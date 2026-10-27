import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_discovery/discovery_backdrop.dart';
import 'package:inspiration_museum/daily_discovery/discovery_palette.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/local_image.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/curation_service.dart';
import 'package:inspiration_museum/services/db_service.dart';

/// 与 [CurationService.curate] 同签名，测试里可以换掉。
typedef CurateCall = Future<CurationResult> Function({
  required String title,
  required String text,
  required bool deep,
});

/// What Publish would store. Tests replace the network call with this.
class EditorPublishRequest {
  const EditorPublishRequest({
    required this.title,
    required this.body,
    required this.quote,
    required this.keywords,
    required this.isPrivate,
    required this.generatedImageUrl,
    required this.editing,
  });

  final String title;
  final String body;
  final String quote;
  final List<String> keywords;
  final bool isPrivate;

  /// The generated URL passed to [SupabaseDBService.createPost] or
  /// [SupabaseDBService.attachUploadedImage]. Null when the user picked a
  /// local file, or when generation did not return an image.
  final String? generatedImageUrl;
  final bool editing;
}

typedef EditorPublish = Future<void> Function(EditorPublishRequest request);

class InspirationEditorScreen extends StatefulWidget {
  const InspirationEditorScreen({
    super.key,
    required this.keywords,
    required this.quote,
    this.postId,
    this.initialTitle = '',
    this.initialBody = '',
    this.initialPrivate = false,
    this.existingImageUrl,
    this.atmosphere,
    @visibleForTesting this.curate,
    @visibleForTesting this.publish,
  });

  final List<String> keywords;
  final String quote;

  /// 有值时改原来的帖子，不再新建一篇。
  final String? postId;
  final String initialTitle;
  final String initialBody;
  final bool initialPrivate;
  final String? existingImageUrl;

  /// 从每日灵感进来时沿用那一页的色调。其他入口用象牙墨色。
  final DiscoveryPalette? atmosphere;

  final CurateCall? curate;
  final EditorPublish? publish;

  @override
  State<InspirationEditorScreen> createState() =>
      _InspirationEditorScreenState();
}

/// 发布成功后的确认页停留多久再返回。
const _confirmationHold = Duration(milliseconds: 1300);

/// 生成超过这个时间，文字从「读」换成「画」，和后台的两步对应。
const _paintingStageAfter = Duration(seconds: 4);

class _InspirationEditorScreenState extends State<InspirationEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _text = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _textFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _visualKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  XFile? _imageFile;
  bool _isPrivate = false;
  bool _saving = false;
  bool _curating = false;
  bool _curatingDeep = false;
  late List<String> _keywords;
  late String _quote;
  String _caption = '';
  String? _generatedImageUrl;

  /// 生成失败的原因，显示在画面区域里，而不是一闪而过的提示条。
  String? _visualError;

  /// 没写字就点生成时的提示，开始输入后消失。
  String? _studioHint;
  bool _painting = false;
  bool _curated = false;
  bool _usedUltra = false;
  bool _scrolled = false;
  Timer? _stageTimer;

  /// 只有服务器确认保存后才为 true，用来显示确认页。
  bool _confirmed = false;
  bool _confirmedPrivate = false;

  bool get _editing =>
      widget.postId != null && widget.postId!.trim().isNotEmpty;

  DiscoveryPalette get _palette =>
      widget.atmosphere ?? DiscoveryPalette.inkAndIvory;

  CurateCall get _curator => widget.curate ?? CurationService.instance.curate;

  bool get _hasGenerated => (_generatedImageUrl?.trim() ?? '').isNotEmpty;
  bool get _hasPicked => _imagePath != null && _imagePath!.isNotEmpty;
  bool get _hasExisting => (widget.existingImageUrl?.trim() ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title.text = widget.initialTitle;
    _text.text = widget.initialBody;
    _isPrivate = widget.initialPrivate;
    _keywords = List<String>.from(widget.keywords);
    _quote = widget.quote;
    _titleFocus.addListener(_onFocus);
    _textFocus.addListener(_onFocus);
    _title.addListener(_onTyping);
    _text.addListener(_onTyping);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _titleFocus.removeListener(_onFocus);
    _textFocus.removeListener(_onFocus);
    _title.removeListener(_onTyping);
    _text.removeListener(_onTyping);
    _scroll.removeListener(_onScroll);
    _titleFocus.dispose();
    _textFocus.dispose();
    _title.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _onTyping() {
    if (!mounted) return;
    setState(() {
      if (_studioHint != null &&
          (_title.text.trim().isNotEmpty || _text.text.trim().isNotEmpty)) {
        _studioHint = null;
      }
    });
  }

  void _onScroll() {
    final scrolled = _scroll.hasClients && _scroll.offset > 4;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null) return;
      final saved = await persistPickedImage(file);
      if (!mounted) return;
      setState(() {
        _imageFile = file;
        _imagePath = saved;
      });
    } catch (_) {
      if (!mounted) return;
      _snack('Could not read the image.');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    final body = _text.text.trim();
    final existing = widget.existingImageUrl?.trim() ?? '';
    final generated = _generatedImageUrl?.trim() ?? '';
    final hasImage =
        _imageFile != null ||
        (_imagePath != null && _imagePath!.isNotEmpty) ||
        existing.isNotEmpty ||
        generated.isNotEmpty;
    if (title.isEmpty && body.isEmpty && !hasImage) {
      _snack('Write a title or some text, or choose an image.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final quote = _quoteForSave();
      final storedImage = _imageFile == null ? _generatedImageUrl : null;
      if (widget.publish != null) {
        await widget.publish!(
          EditorPublishRequest(
            title: title,
            body: body,
            quote: quote,
            keywords: List<String>.from(_keywords),
            isPrivate: _isPrivate,
            generatedImageUrl: storedImage,
            editing: _editing,
          ),
        );
        if (!mounted) return;
        await _confirmAndClose();
        return;
      }
      final authorId = AuthService.instance.currentUser?.id ?? '';
      if (authorId.isEmpty) {
        if (mounted) {
          setState(() => _saving = false);
          _snack('Sign in before publishing.');
        }
        return;
      }
      if (_editing) {
        await SupabaseDBService.instance.updatePostText(
          postId: widget.postId!,
          title: title,
          body: body,
          isPrivate: _isPrivate,
          keywords: List<String>.from(_keywords),
          quote: quote,
        );
        if (_imageFile != null) {
          await SupabaseDBService.instance.updatePostImage(
            widget.postId!,
            _imageFile!,
          );
        } else if ((storedImage ?? '').isNotEmpty) {
          await SupabaseDBService.instance.attachUploadedImage(
            widget.postId!,
            storedImage!,
          );
        }
      } else {
        await SupabaseDBService.instance.createPost(
          authorId,
          body,
          _imageFile,
          title: title,
          quote: quote,
          keywords: List<String>.from(_keywords),
          isPrivate: _isPrivate,
          imageUrl: storedImage,
        );
      }
      if (!mounted) return;
      await _confirmAndClose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Not published: $error');
    }
  }

  /// 保存已经成功：先给一个清楚的确认，再带着 true 返回。
  Future<void> _confirmAndClose() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _confirmed = true;
      _confirmedPrivate = _isPrivate;
    });
    await Future<void>.delayed(_confirmationHold);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _quoteForSave() {
    final quote = _quote.trim();
    final caption = _caption.trim();
    if (caption.isEmpty) return quote;
    if (quote.isEmpty) return caption;
    return '$quote\n$caption';
  }

  Future<void> _curate({required bool deep}) async {
    if (_curating || _saving) return;
    final title = _title.text.trim();
    final body = _text.text.trim();
    if (title.isEmpty && body.isEmpty) {
      setState(() => _studioHint = 'Write a title or a few lines first.');
      return;
    }
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _curating = true;
      _curatingDeep = deep;
      _painting = false;
      _visualError = null;
      _studioHint = null;
    });
    _stageTimer?.cancel();
    _stageTimer = Timer(_paintingStageAfter, () {
      if (mounted && _curating) setState(() => _painting = true);
    });
    _revealVisual();
    try {
      final result = await _curator(title: title, text: body, deep: deep);
      if (!mounted) return;
      setState(() {
        _keywords = result.keywords;
        _quote = result.quote;
        _caption = result.caption;
        _usedUltra = result.usedUltra;
        _curated = true;
        if ((result.imageUrl ?? '').isNotEmpty) {
          _generatedImageUrl = result.imageUrl;
          _imageFile = null;
          _imagePath = null;
        } else {
          _visualError =
              result.imageError ??
              'No image came back. Try again, or choose your own image.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _visualError = CurationService.messageOf(error));
    } finally {
      _stageTimer?.cancel();
      if (mounted) {
        setState(() {
          _curating = false;
          _curatingDeep = false;
          _painting = false;
        });
      }
    }
  }

  /// 点了生成之后把画面区域滚进视野，加载态不会藏在键盘或屏幕下方。
  void _revealVisual() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _visualKey.currentContext;
      if (target == null || !mounted) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      Scrollable.ensureVisible(
        target,
        alignment: 0.35,
        duration: reduce ? Duration.zero : CanvasMotion.emphasized,
        curve: CanvasMotion.standardCurve,
      );
    });
  }

  void _removeImage() {
    setState(() {
      if (_hasPicked || _imageFile != null) {
        _imageFile = null;
        _imagePath = null;
      } else {
        _generatedImageUrl = null;
      }
      _visualError = null;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _curating || _confirmed;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _confirmed && !_palette.isLight
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: !_confirmed,
        child: Scaffold(
          backgroundColor: CanvasColors.surface,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EditorTopBar(
                      title: _editing
                          ? 'Edit Reflection'
                          : 'Write a Reflection',
                      overline: widget.atmosphere != null
                          ? 'DAILY INSPIRATION'
                          : 'COLLECTION',
                      divided: _scrolled,
                      onBack: busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(child: _content(busy)),
                    _PublishBar(
                      busy: busy,
                      saving: _saving,
                      editing: _editing,
                      isPrivate: _isPrivate,
                      onPickImage: _pickImage,
                      onTogglePrivate: (value) =>
                          setState(() => _isPrivate = value),
                      onPublish: _save,
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_confirmed,
                  child: AnimatedSwitcher(
                    duration: reduce ? Duration.zero : CanvasMotion.emphasized,
                    switchInCurve: CanvasMotion.enter,
                    child: _confirmed
                        ? _PublishedConfirmation(
                            key: const ValueKey('confirmed'),
                            palette: _palette,
                            editing: _editing,
                            isPrivate: _confirmedPrivate,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(bool busy) {
    final showVisual =
        _curating ||
        _visualError != null ||
        _hasGenerated ||
        _hasPicked ||
        _hasExisting;
    return SingleChildScrollView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        CanvasSpace.page,
        CanvasSpace.sm,
        CanvasSpace.page,
        CanvasSpace.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ContextCard(
            palette: _palette,
            keywords: _keywords,
            quote: _quote,
            caption: _caption,
            curatedBy: _curated
                ? (_usedUltra ? 'Refined by Ultra' : 'Curated by Nano')
                : null,
          ),
          const SizedBox(height: CanvasSpace.lg),
          _writingArea(),
          const SizedBox(height: CanvasSpace.lg),
          _StudioPanel(
            curating: _curating,
            curatingDeep: _curatingDeep,
            enabled: !busy,
            hint: _studioHint,
            onCurate: (deep) => _curate(deep: deep),
          ),
          AnimatedSize(
            key: _visualKey,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : CanvasMotion.emphasized,
            curve: CanvasMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: showVisual
                ? Padding(
                    padding: const EdgeInsets.only(top: CanvasSpace.xl),
                    child: _visualSection(busy),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _visualSection(bool busy) {
    final String label;
    final Widget body;
    final List<_VisualAction> actions;
    String? note;

    if (_curating) {
      label = 'GENERATED VISUAL';
      body = _PaintingPlaceholder(
        key: const ValueKey('painting'),
        palette: _palette,
        message: _painting
            ? 'Painting the visual…'
            : 'Reading your reflection…',
      );
      actions = const [];
    } else if (_hasPicked) {
      label = 'YOUR IMAGE';
      body = _FramedImage(
        key: ValueKey(_imagePath),
        child: _FramedImage.limit(
          context,
          localFileImage(_imagePath!, fit: BoxFit.contain),
        ),
      );
      note = 'This image will be published with your reflection.';
      actions = [
        _VisualAction('Replace', Icons.photo_library_outlined, _pickImage),
        _VisualAction('Remove', Icons.close, _removeImage),
      ];
    } else if (_hasGenerated) {
      label = 'GENERATED VISUAL';
      body = _FramedImage(
        key: ValueKey(_generatedImageUrl),
        child: _NetworkVisual(
          url: _generatedImageUrl!,
          palette: _palette,
          onRetry: () => _curate(deep: false),
        ),
      );
      note =
          'Painted from your words. It will be published with your reflection.';
      actions = [
        _VisualAction('Regenerate', Icons.refresh, () => _curate(deep: false)),
        _VisualAction('Remove', Icons.close, _removeImage),
      ];
    } else if (_hasExisting) {
      label = 'CURRENT IMAGE';
      body = _FramedImage(
        key: ValueKey(widget.existingImageUrl),
        child: _NetworkVisual(
          url: widget.existingImageUrl!,
          palette: _palette,
          onRetry: null,
        ),
      );
      actions = [
        _VisualAction('Replace', Icons.photo_library_outlined, _pickImage),
      ];
    } else {
      label = 'GENERATED VISUAL';
      body = _VisualError(
        key: const ValueKey('error'),
        message: _visualError ?? '',
        onRetry: busy ? null : () => _curate(deep: false),
        onChoose: busy ? null : _pickImage,
      );
      actions = const [];
    }

    final inlineError =
        !_curating && _visualError != null && body is! _VisualError
        ? _visualError
        : null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label),
        const SizedBox(height: CanvasSpace.md),
        AnimatedSwitcher(
          duration: reduce ? Duration.zero : CanvasMotion.reveal,
          switchInCurve: CanvasMotion.enter,
          switchOutCurve: CanvasMotion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: body,
        ),
        if (inlineError != null) ...[
          const SizedBox(height: CanvasSpace.sm),
          Text(
            inlineError,
            style: CanvasType.bodySmall.copyWith(color: CanvasColors.danger),
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: CanvasSpace.md),
          Text(
            note,
            style: CanvasType.caption.copyWith(
              color: CanvasColors.textSecondary,
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: CanvasSpace.xs),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              for (final action in actions)
                _QuietIconAction(
                  label: action.label,
                  icon: action.icon,
                  onTap: busy ? null : action.onTap,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _writingArea() {
    final titleActive = _titleFocus.hasFocus;
    final textActive = _textFocus.hasFocus;
    final words = RegExp(r'\S+').allMatches(_text.text).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('REFLECTION TITLE', active: titleActive),
        const SizedBox(height: CanvasSpace.sm),
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          maxLines: 3,
          minLines: 1,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _textFocus.requestFocus(),
          cursorColor: CanvasColors.forest,
          style: CanvasType.headline.copyWith(fontSize: 28, height: 1.2),
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            hintText: 'Give it a title',
            hintStyle: CanvasType.headline.copyWith(
              fontSize: 28,
              height: 1.2,
              color: CanvasColors.textSecondary.withValues(alpha: 0.55),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        const SizedBox(height: CanvasSpace.md),
        _FocusRule(active: titleActive),
        const SizedBox(height: CanvasSpace.xl),
        _SectionLabel('YOUR REFLECTION', active: textActive),
        const SizedBox(height: CanvasSpace.sm),
        AnimatedContainer(
          duration: CanvasMotion.standard,
          curve: CanvasMotion.standardCurve,
          padding: const EdgeInsets.only(left: CanvasSpace.md),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: textActive ? CanvasColors.forest : CanvasColors.divider,
              ),
            ),
          ),
          child: TextField(
            controller: _text,
            focusNode: _textFocus,
            minLines: 4,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            cursorColor: CanvasColors.forest,
            style: CanvasType.body.copyWith(fontSize: 16.5, height: 1.75),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              hintText:
                  'What did today\'s inspiration open up for you? '
                  'A memory, a place, a question…',
              hintMaxLines: 4,
              hintStyle: CanvasType.body.copyWith(
                fontSize: 16.5,
                height: 1.75,
                color: CanvasColors.textSecondary.withValues(alpha: 0.7),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: CanvasSpace.sm),
        Align(
          alignment: Alignment.centerRight,
          child: AnimatedOpacity(
            duration: CanvasMotion.standard,
            opacity: words > 0 ? 1 : 0,
            child: Text(
              words == 1 ? '1 word' : '$words words',
              style: CanvasType.caption.copyWith(
                color: CanvasColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 顶栏
// ---------------------------------------------------------------------------

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.title,
    required this.overline,
    required this.divided,
    required this.onBack,
  });

  final String title;
  final String overline;
  final bool divided;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: CanvasMotion.standard,
      decoration: BoxDecoration(
        color: CanvasColors.surface,
        border: Border(
          bottom: BorderSide(
            color: divided ? CanvasColors.divider : Colors.transparent,
          ),
        ),
      ),
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: CanvasColors.text),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  overline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CanvasType.overline.copyWith(
                    fontSize: 9.5,
                    color: CanvasColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CanvasType.collectionTitle.copyWith(
                    color: CanvasColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 灵感卡：用户正在回应的那一条
// ---------------------------------------------------------------------------

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.palette,
    required this.keywords,
    required this.quote,
    required this.caption,
    required this.curatedBy,
  });

  final DiscoveryPalette palette;
  final List<String> keywords;
  final String quote;
  final String caption;
  final String? curatedBy;

  @override
  Widget build(BuildContext context) {
    final words = keywords.where((k) => k.trim().isNotEmpty).join('  ·  ');
    final quoteText = quote.trim();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ClipRRect(
      borderRadius: CanvasRadius.cardAll,
      child: Stack(
        children: [
          Positioned.fill(
            child: DiscoveryBackdrop(
              palette: palette,
              seed: CanvasColors.stableHash(words),
              grain: false,
              quiet: true,
            ),
          ),
          AnimatedSize(
            duration: CanvasMotion.emphasized,
            curve: CanvasMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : CanvasMotion.emphasized,
              switchInCurve: CanvasMotion.enter,
              child: Padding(
                key: ValueKey('$words|$quoteText|$caption'),
                padding: const EdgeInsets.fromLTRB(
                  CanvasSpace.xl,
                  CanvasSpace.xl,
                  CanvasSpace.xl,
                  CanvasSpace.lg + 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'REFLECTING ON',
                      style: CanvasType.overline.copyWith(
                        fontSize: 9.5,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(height: CanvasSpace.sm),
                    Text(
                      words.isEmpty ? 'Your own idea' : words,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CanvasType.hero.copyWith(
                        fontSize: 28,
                        color: palette.ink,
                      ),
                    ),
                    if (quoteText.isNotEmpty) ...[
                      const SizedBox(height: CanvasSpace.md),
                      Text(
                        CommunityPost.quotedText(quoteText),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.quote.copyWith(
                          fontSize: 16,
                          height: 1.5,
                          color: palette.ink.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                    if (caption.trim().isNotEmpty) ...[
                      const SizedBox(height: CanvasSpace.sm),
                      Text(
                        caption.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.bodySmall.copyWith(
                          color: palette.muted,
                        ),
                      ),
                    ],
                    if (curatedBy != null) ...[
                      const SizedBox(height: CanvasSpace.md),
                      Row(
                        children: [
                          Container(
                            width: 18,
                            height: 1,
                            color: palette.accent,
                          ),
                          const SizedBox(width: CanvasSpace.sm),
                          Flexible(
                            child: Text(
                              curatedBy!.toUpperCase(),
                              style: CanvasType.overline.copyWith(
                                fontSize: 9,
                                color: palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 写作区的小件
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.active = false});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: CanvasMotion.standard,
      style: CanvasType.overline.copyWith(
        fontSize: 9.5,
        color: active ? CanvasColors.forest : CanvasColors.textSecondary,
      ),
      child: Text(text),
    );
  }
}

class _FocusRule extends StatelessWidget {
  const _FocusRule({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(height: 1, color: CanvasColors.divider),
        AnimatedFractionallySizedBox(
          duration: CanvasMotion.emphasized,
          curve: CanvasMotion.standardCurve,
          widthFactor: active ? 1 : 0,
          child: Container(height: 1.5, color: CanvasColors.forest),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// AI 工作台：Generate Image / Go Deeper
// ---------------------------------------------------------------------------

class _StudioPanel extends StatelessWidget {
  const _StudioPanel({
    required this.curating,
    required this.curatingDeep,
    required this.enabled,
    required this.hint,
    required this.onCurate,
  });

  final bool curating;
  final bool curatingDeep;
  final bool enabled;
  final String? hint;
  final ValueChanged<bool> onCurate;

  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(16) > 20 ||
        MediaQuery.sizeOf(context).width < 340;
    final generate = _StudioButton(
      label: curating && !curatingDeep ? 'Generating…' : 'Generate Image',
      icon: Icons.auto_awesome_outlined,
      filled: true,
      busy: curating && !curatingDeep,
      onTap: enabled ? () => onCurate(false) : null,
    );
    final deeper = _StudioButton(
      label: curating && curatingDeep ? 'Refining…' : 'Go Deeper',
      icon: Icons.layers_outlined,
      filled: false,
      busy: curating && curatingDeep,
      onTap: enabled ? () => onCurate(true) : null,
    );
    return Container(
      padding: const EdgeInsets.all(CanvasSpace.lg + 2),
      decoration: BoxDecoration(
        color: CanvasColors.background,
        borderRadius: CanvasRadius.cardAll,
        border: Border.all(color: CanvasColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: CanvasColors.forest,
              ),
              const SizedBox(width: CanvasSpace.sm),
              Expanded(
                child: Text(
                  'AI STUDIO',
                  style: CanvasType.overline.copyWith(
                    fontSize: 9.5,
                    color: CanvasColors.forest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CanvasSpace.sm),
          Text(
            'Turn your words into a curated quote and an original visual.',
            style: CanvasType.bodySmall.copyWith(color: CanvasColors.text),
          ),
          const SizedBox(height: CanvasSpace.lg),
          if (stacked) ...[
            generate,
            const SizedBox(height: CanvasSpace.sm),
            deeper,
          ] else
            Row(
              children: [
                Expanded(flex: 6, child: generate),
                const SizedBox(width: CanvasSpace.sm),
                Expanded(flex: 5, child: deeper),
              ],
            ),
          const SizedBox(height: CanvasSpace.md),
          AnimatedSwitcher(
            duration: CanvasMotion.standard,
            child: hint != null
                ? Text(
                    hint!,
                    key: const ValueKey('hint'),
                    style: CanvasType.bodySmall.copyWith(
                      color: CanvasColors.danger,
                    ),
                  )
                : Text(
                    'Go Deeper asks Nemotron Ultra to refine the scene. '
                    'It takes a little longer.',
                    key: const ValueKey('help'),
                    style: CanvasType.caption.copyWith(
                      color: CanvasColors.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StudioButton extends StatelessWidget {
  const _StudioButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = filled ? CanvasColors.textOnInk : CanvasColors.text;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: CanvasMotion.quick,
          opacity: enabled || busy ? 1 : 0.45,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.md),
            decoration: BoxDecoration(
              color: filled ? CanvasColors.text : CanvasColors.surface,
              borderRadius: CanvasRadius.buttonAll,
              border: filled
                  ? null
                  : Border.all(color: CanvasColors.text.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: busy
                      ? CircularProgressIndicator(strokeWidth: 1.5, color: ink)
                      : Icon(icon, size: 16, color: ink),
                ),
                const SizedBox(width: CanvasSpace.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.label.copyWith(
                      fontSize: 13.5,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 画面区域：生成中 / 图片 / 失败
// ---------------------------------------------------------------------------

class _VisualAction {
  const _VisualAction(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// 画面外框：细边、小圆角、浅底。图片按原比例完整显示，不裁切。
class _FramedImage extends StatelessWidget {
  const _FramedImage({super.key, required this.child});

  final Widget child;

  /// 只限制图片本身的高度；加载失败的说明按内容撑开。
  static Widget limit(BuildContext context, Widget image) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(240.0, 520.0)),
      child: Center(heightFactor: 1, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CanvasColors.sunken,
        borderRadius: CanvasRadius.imageAll,
        boxShadow: CanvasShadow.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _NetworkVisual extends StatelessWidget {
  const _NetworkVisual({
    required this.url,
    required this.palette,
    required this.onRetry,
  });

  final String url;
  final DiscoveryPalette palette;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Image.network(
      url,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: 'Generated visual',
      frameBuilder: (context, child, frame, wasSync) {
        final limited = _FramedImage.limit(context, child);
        if (wasSync || reduce) return limited;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: CanvasMotion.reveal,
          curve: CanvasMotion.enter,
          child: AnimatedScale(
            scale: frame == null ? 1.03 : 1,
            duration: CanvasMotion.reveal,
            curve: CanvasMotion.enter,
            child: limited,
          ),
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _PaintingPlaceholder(
                palette: palette,
                message: 'Loading the visual…',
                framed: false,
              ),
            ),
            Positioned.fill(child: child),
          ],
        );
      },
      errorBuilder: (context, _, _) => _VisualError(
        message: 'The visual was created but could not be loaded.',
        onRetry: onRetry,
        onChoose: null,
        framed: false,
      ),
    );
  }
}

/// 生成中的占位：沿用当天色调，一道很慢的光扫过，配合当前步骤的文字。
class _PaintingPlaceholder extends StatefulWidget {
  const _PaintingPlaceholder({
    super.key,
    required this.palette,
    required this.message,
    this.framed = true,
  });

  final DiscoveryPalette palette;
  final String message;
  final bool framed;

  @override
  State<_PaintingPlaceholder> createState() => _PaintingPlaceholderState();
}

class _PaintingPlaceholderState extends State<_PaintingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final content = AnimatedBuilder(
      animation: _sweep,
      builder: (context, child) {
        final t = CanvasMotion.drift.transform(_sweep.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, -1),
              end: Alignment(-0.6 + 3.2 * t, 1),
              colors: [
                palette.mid,
                Color.lerp(palette.mid, palette.glow, 0.55)!,
                palette.mid,
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
          child: child,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const GrainTexture(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(CanvasSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: CanvasRadius.tagAll,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: palette.ink,
                        backgroundColor: palette.ink.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  const SizedBox(height: CanvasSpace.lg),
                  AnimatedSwitcher(
                    duration: CanvasMotion.emphasized,
                    child: Text(
                      widget.message,
                      key: ValueKey(widget.message),
                      textAlign: TextAlign.center,
                      style: CanvasType.quote.copyWith(
                        fontSize: 17,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final semantic = Semantics(
      liveRegion: true,
      label: widget.message,
      child: ExcludeSemantics(child: content),
    );
    if (!widget.framed) return semantic;
    return ClipRRect(
      borderRadius: CanvasRadius.imageAll,
      child: AspectRatio(aspectRatio: 1.25, child: semantic),
    );
  }
}

class _VisualError extends StatelessWidget {
  const _VisualError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onChoose,
    this.framed = true,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onChoose;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(CanvasSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            size: 22,
            color: CanvasColors.danger,
          ),
          const SizedBox(height: CanvasSpace.md),
          Text(
            'The visual could not be generated.',
            style: CanvasType.collectionTitle.copyWith(
              color: CanvasColors.text,
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.xs),
            Text(
              message,
              style: CanvasType.bodySmall.copyWith(
                color: CanvasColors.textSecondary,
              ),
            ),
          ],
          if (onRetry != null || onChoose != null) ...[
            const SizedBox(height: CanvasSpace.lg),
            Wrap(
              spacing: CanvasSpace.sm,
              runSpacing: CanvasSpace.sm,
              children: [
                if (onRetry != null)
                  CanvasButton(
                    label: 'Try Again',
                    icon: Icons.refresh,
                    variant: CanvasButtonVariant.secondary,
                    onPressed: onRetry,
                  ),
                if (onChoose != null)
                  CanvasButton(
                    label: 'Choose an Image',
                    variant: CanvasButtonVariant.quiet,
                    onPressed: onChoose,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    if (!framed) return content;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CanvasColors.background,
        borderRadius: CanvasRadius.imageAll,
        border: Border.all(color: CanvasColors.divider),
      ),
      child: content,
    );
  }
}

class _QuietIconAction extends StatelessWidget {
  const _QuietIconAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: CanvasMotion.quick,
          opacity: enabled ? 1 : 0.4,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: CanvasColors.text),
                const SizedBox(width: CanvasSpace.xs),
                Text(label, style: CanvasType.label.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 底部发布栏
// ---------------------------------------------------------------------------

class _PublishBar extends StatelessWidget {
  const _PublishBar({
    required this.busy,
    required this.saving,
    required this.editing,
    required this.isPrivate,
    required this.onPickImage,
    required this.onTogglePrivate,
    required this.onPublish,
  });

  final bool busy;
  final bool saving;
  final bool editing;
  final bool isPrivate;
  final VoidCallback onPickImage;
  final ValueChanged<bool> onTogglePrivate;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final publishLabel = saving
        ? (editing ? 'Saving…' : 'Publishing…')
        : (editing ? 'Save' : 'Publish');
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: CanvasColors.surface,
          border: Border(top: BorderSide(color: CanvasColors.divider)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A22231F),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CanvasSpace.md,
              CanvasSpace.sm + 2,
              CanvasSpace.page,
              CanvasSpace.sm + 2,
            ),
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  _RoundTool(
                    icon: Icons.add_photo_alternate_outlined,
                    label: 'Choose an image',
                    onTap: busy ? null : onPickImage,
                  ),
                  const SizedBox(width: CanvasSpace.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _VisibilityToggle(
                        isPrivate: isPrivate,
                        onChanged: busy ? null : onTogglePrivate,
                      ),
                    ),
                  ),
                  const SizedBox(width: CanvasSpace.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.46),
                    child: CanvasButton(
                      label: publishLabel,
                      icon: editing ? null : Icons.north_east,
                      busy: saving,
                      variant: CanvasButtonVariant.accent,
                      onPressed: busy ? null : onPublish,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundTool extends StatelessWidget {
  const _RoundTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Pressable(
          onTap: onTap,
          child: AnimatedOpacity(
            duration: CanvasMotion.quick,
            opacity: enabled ? 1 : 0.4,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CanvasColors.divider),
              ),
              child: Icon(icon, size: 20, color: CanvasColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// 公开 / 私密。一个按钮切换，图标和文字一起变。
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.isPrivate, required this.onChanged});

  final bool isPrivate;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final onTap = enabled ? () => onChanged!(!isPrivate) : null;
    return Semantics(
      toggled: !isPrivate,
      enabled: enabled,
      label: 'Public',
      hint: isPrivate ? 'Only you can see this reflection' : null,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: CanvasMotion.quick,
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: CanvasMotion.standard,
            curve: CanvasMotion.standardCurve,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.md),
            decoration: BoxDecoration(
              color: isPrivate
                  ? CanvasColors.sunken
                  : CanvasColors.tint(CanvasColors.forest),
              borderRadius: CanvasRadius.buttonAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: CanvasMotion.quick,
                  child: Icon(
                    isPrivate ? Icons.lock_outline : Icons.public,
                    key: ValueKey(isPrivate),
                    size: 16,
                    color: isPrivate ? CanvasColors.text : CanvasColors.forest,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isPrivate ? 'Private' : 'Public',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.label.copyWith(
                      fontSize: 13,
                      color: isPrivate
                          ? CanvasColors.text
                          : CanvasColors.forest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 发布成功
// ---------------------------------------------------------------------------

/// 只在保存成功之后出现。文字根据实际结果写：公开发布、私密保存或修改已存。
class _PublishedConfirmation extends StatelessWidget {
  const _PublishedConfirmation({
    super.key,
    required this.palette,
    required this.editing,
    required this.isPrivate,
  });

  final DiscoveryPalette palette;
  final bool editing;
  final bool isPrivate;

  @override
  Widget build(BuildContext context) {
    final headline = editing
        ? 'Changes saved'
        : (isPrivate ? 'Saved privately' : 'Published');
    final detail = editing
        ? 'Your reflection is up to date.'
        : (isPrivate
              ? 'Added to your Collections. Only you can see it.'
              : 'Added to your Collections.');
    return Semantics(
      liveRegion: true,
      label: '$headline. $detail',
      child: Stack(
        fit: StackFit.expand,
        children: [
          DiscoveryBackdrop(palette: palette, seed: 11),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(CanvasSpace.xxl),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 720),
                curve: CanvasMotion.enter,
                builder: (context, t, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size(64, 64),
                      painter: _CheckPainter(progress: t, color: palette.ink),
                    ),
                    const SizedBox(height: CanvasSpace.xl),
                    Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - t)),
                        child: Column(
                          children: [
                            Text(
                              headline,
                              textAlign: TextAlign.center,
                              style: CanvasType.display.copyWith(
                                fontSize: 36,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: CanvasSpace.sm),
                            Text(
                              detail,
                              textAlign: TextAlign.center,
                              style: CanvasType.body.copyWith(
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(1),
      -1.5708,
      6.2832 * progress.clamp(0.0, 1.0),
      false,
      stroke,
    );
    final tick = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
    if (tick <= 0) return;
    final s = size.width;
    final path = Path()
      ..moveTo(s * 0.3, s * 0.52)
      ..lineTo(s * 0.44, s * 0.66)
      ..lineTo(s * 0.72, s * 0.38);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * tick), stroke);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
