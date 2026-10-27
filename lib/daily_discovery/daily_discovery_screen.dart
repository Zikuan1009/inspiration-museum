import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_discovery/discovery_backdrop.dart';
import 'package:inspiration_museum/daily_discovery/discovery_motion.dart';
import 'package:inspiration_museum/daily_discovery/discovery_palette.dart';
import 'package:inspiration_museum/daily_discovery/discovery_route.dart';
import 'package:inspiration_museum/daily_letter_card.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/inspiration_editor_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/db_service.dart';

/// 今天这封信以哪种方式做封面。三种都会完整展示关键词和名言，
/// 只是谁当主角不同。
enum DiscoveryMode { keyword, quote, image }

DiscoveryMode discoveryModeOf(DailyPush push) {
  if (push.imageUrl.trim().startsWith('http')) return DiscoveryMode.image;
  final keyword = push.keyword.trim();
  final quote = push.quote.trim();
  if (keyword.isEmpty && quote.isNotEmpty) return DiscoveryMode.quote;
  if (quote.isEmpty) return DiscoveryMode.keyword;
  return CanvasColors.stableHash(keyword).isEven
      ? DiscoveryMode.keyword
      : DiscoveryMode.quote;
}

/// 全屏的每日灵感。返回 true 表示用户写下并发布了一篇。
class DailyDiscoveryScreen extends StatefulWidget {
  const DailyDiscoveryScreen({super.key, required this.push});

  final DailyPush push;

  static Route<bool> route({required DailyPush push, Rect? origin}) {
    return DiscoveryRoute<bool>(
      push: push,
      origin: origin,
      builder: (_) => DailyDiscoveryScreen(push: push),
    );
  }

  @override
  State<DailyDiscoveryScreen> createState() => _DailyDiscoveryScreenState();
}

class _DailyDiscoveryScreenState extends State<DailyDiscoveryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: CanvasMotion.ambient,
  );
  final ScrollController _scroll = ScrollController();
  Animation<double>? _routeAnimation;
  bool _scrolled = false;
  bool _savingDraft = false;
  bool _leaving = false;

  DailyPush get _push => widget.push;
  late final DiscoveryPalette _palette = DiscoveryPalette.of(_push);
  late final DiscoveryMode _mode = discoveryModeOf(_push);
  late final int _seed = CanvasColors.stableHash(_push.keyword);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) _startAmbient();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _routeAnimation) return;
    _routeAnimation?.removeListener(_onRouteProgress);
    _routeAnimation = animation;
    if (discoveryReduceMotion(context)) {
      _reveal.value = 1;
      return;
    }
    if (animation == null || animation.isCompleted) {
      _reveal.forward();
    } else {
      animation.addListener(_onRouteProgress);
    }
  }

  /// 卡片展开到六成多时开始揭示内容，两段动作相互衔接。
  void _onRouteProgress() {
    final animation = _routeAnimation;
    if (animation == null || !_reveal.isDismissed) return;
    if (animation.status == AnimationStatus.forward && animation.value > 0.6 ||
        animation.isCompleted) {
      _reveal.forward();
      animation.removeListener(_onRouteProgress);
    }
  }

  void _startAmbient() {
    if (discoveryReduceMotion(context) || _ambient.isAnimating) return;
    _ambient.repeat();
  }

  void _onScroll() {
    final scrolled = _scroll.hasClients && _scroll.offset > 24;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  void dispose() {
    _routeAnimation?.removeListener(_onRouteProgress);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _reveal.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _close([bool published = false]) {
    if (_leaving) return;
    _leaving = true;
    _ambient.stop();
    Navigator.of(context).pop(published);
  }

  void _exploreMore() {
    if (!_scroll.hasClients) return;
    final target = math.min(
      MediaQuery.sizeOf(context).height * 0.86,
      _scroll.position.maxScrollExtent,
    );
    if (discoveryReduceMotion(context)) {
      _scroll.jumpTo(target);
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 720),
      curve: CanvasMotion.standardCurve,
    );
  }

  /// 原来信封上的「WRITE」：带着今天的关键词和名言去写，发布成功后合上这一页。
  Future<void> _writeReflection() async {
    if (_leaving) return;
    HapticFeedback.lightImpact();
    final published = await Navigator.of(context).push<bool>(
      ReflectionRoute<bool>(
        builder: (_) => InspirationEditorScreen(
          keywords: _push.keywords,
          quote: _push.quote,
          atmosphere: _palette,
        ),
      ),
    );
    if (!mounted || published != true) return;
    _close(true);
  }

  /// 原来信封上的「SAVE」：需要登录，存进草稿箱后合上这一页。
  Future<void> _saveDraft() async {
    if (_savingDraft || _leaving) return;
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    setState(() => _savingDraft = true);
    final saved = await SupabaseDBService.instance.saveLetterDraft(_push);
    if (!mounted) return;
    setState(() => _savingDraft = false);
    final messenger = ScaffoldMessenger.of(context);
    if (!saved) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save this letter.')),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Saved to your Drafts.')),
    );
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final palette = _palette;
    final viewport = media.size.height;
    final reduce = discoveryReduceMotion(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Material(
        color: palette.deep,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景不随内容滚动；往下读时淡出装饰竖条等元素，免得压在正文上。
            DiscoveryBackdrop(
              palette: palette,
              seed: _seed,
              drift: reduce ? null : _ambient,
              quiet: true,
            ),
            if (_mode != DiscoveryMode.image)
              AnimatedOpacity(
                opacity: _scrolled ? 0 : 1,
                duration: CanvasMotion.standard,
                child: DiscoveryBackdrop(
                  palette: palette,
                  seed: _seed,
                  drift: reduce || _scrolled ? null : _ambient,
                ),
              ),
            Scrollbar(
              controller: _scroll,
              child: CustomScrollView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: viewport),
                      child: IntrinsicHeight(child: _cover(media)),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      CanvasSpace.page,
                      CanvasSpace.lg,
                      CanvasSpace.page,
                      media.padding.bottom + 120,
                    ),
                    sliver: SliverList.list(children: _spread(media)),
                  ),
                ],
              ),
            ),
            _TopBar(
              palette: palette,
              scrolled: _scrolled,
              reveal: _reveal,
              onClose: _close,
            ),
            _FloatingAction(
              palette: palette,
              reveal: discoveryInterval(_reveal, 0.55, 1),
              onTap: _writeReflection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(MediaQueryData media) {
    final common = (
      push: _push,
      palette: _palette,
      reveal: _reveal,
      onExplore: _exploreMore,
      topInset: media.padding.top + 76,
      // 给底部悬浮的 Write a Reflection 按钮留出位置。
      bottomInset:
          media.padding.bottom +
          CanvasSpace.lg +
          _FloatingAction.height +
          CanvasSpace.lg,
    );
    return switch (_mode) {
      DiscoveryMode.keyword => _KeywordCover(data: common),
      DiscoveryMode.quote => _QuoteCover(data: common),
      DiscoveryMode.image => _ImageCover(data: common, scroll: _scroll),
    };
  }

  List<Widget> _spread(MediaQueryData media) {
    final push = _push;
    final palette = _palette;
    final keyword = push.keyword.trim();
    final quote = push.quote.trim();
    final pieceLabel = DailyLetterFace.pieceLabel(push);
    final why = push.whyToday.trim();
    final path = _themePath(push);
    final sections = <Widget>[];
    var number = 0;

    void add(String label, Widget body) {
      number++;
      sections.add(
        _Section(
          number: number,
          label: label,
          palette: palette,
          indent: number.isEven,
          child: body,
        ),
      );
    }

    if (_mode != DiscoveryMode.quote && quote.isNotEmpty) {
      add('THE QUOTE', _QuoteBlock(push: push, palette: palette, size: 26));
    }
    if (_mode == DiscoveryMode.quote && keyword.isNotEmpty) {
      add(
        'THE WORD',
        Text(
          keyword,
          style: CanvasType.display.copyWith(
            fontSize: 48,
            height: 1.02,
            color: palette.ink,
          ),
        ),
      );
    }
    if (pieceLabel.isNotEmpty && push.pieceTitle.isNotEmpty) {
      add(
        pieceLabel,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              push.pieceTitle,
              style: CanvasType.headline.copyWith(
                fontSize: 32,
                height: 1.1,
                color: palette.ink,
              ),
            ),
            if (push.pieceDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                push.pieceDetail,
                style: CanvasType.body.copyWith(color: palette.muted),
              ),
            ],
          ],
        ),
      );
    }
    if (why.isNotEmpty) {
      add(
        'WHY TODAY',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              why,
              style: CanvasType.body.copyWith(
                fontSize: 16,
                height: 1.65,
                color: palette.ink.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Drafted by Nano  ·  Read by Ultra',
              style: CanvasType.caption.copyWith(color: palette.muted),
            ),
          ],
        ),
      );
    }
    if (path.isNotEmpty) {
      add(
        'FILED UNDER',
        Text(
          path,
          style: CanvasType.titleSmall.copyWith(
            color: palette.ink,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return [
      ...sections,
      const SizedBox(height: CanvasSpace.xxl),
      RevealOnScroll(
        builder: (context, progress) => WipeReveal(
          progress: progress,
          child: _ClosingActions(
            palette: palette,
            savingDraft: _savingDraft,
            onSaveDraft: _saveDraft,
            onDone: _close,
          ),
        ),
      ),
    ];
  }
}

String _themePath(DailyPush push) {
  final theme = push.themeName.trim();
  final sub = push.subThemeName.trim();
  return [
    if (theme.isNotEmpty) CommunityPost.themeLabel(theme),
    if (sub.isNotEmpty) CommunityPost.themeLabel(sub),
  ].join('  /  ');
}

typedef _CoverData = ({
  DailyPush push,
  DiscoveryPalette palette,
  AnimationController reveal,
  VoidCallback onExplore,
  double topInset,
  double bottomInset,
});

// ---------------------------------------------------------------------------
// 封面一：关键词
// ---------------------------------------------------------------------------

class _KeywordCover extends StatelessWidget {
  const _KeywordCover({required this.data});

  final _CoverData data;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final reveal = data.reveal;
    final size = MediaQuery.sizeOf(context);
    final width = size.width - CanvasSpace.page * 2;
    final words = _words(data.push.keyword.trim());
    final indent = words.length > 1 ? width * 0.14 : 0.0;
    final style = CanvasType.display.copyWith(
      height: 0.98,
      letterSpacing: -1.2,
      color: palette.ink,
    );
    final fontSize = _fitDisplay(
      words,
      style,
      width - indent,
      maxSize: math.min(140, size.height * 0.15),
    );
    final quote = data.push.quote.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        CanvasSpace.page,
        data.topInset,
        CanvasSpace.page,
        data.bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Masthead(push: data.push, palette: palette, reveal: reveal),
          const Spacer(),
          for (var i = 0; i < words.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i.isOdd ? indent : 0),
              child: MaskRise(
                progress: discoveryInterval(
                  reveal,
                  0.08 + i * 0.09,
                  0.58 + i * 0.09,
                ),
                scaleFrom: 1.08,
                child: Text(
                  words[i],
                  textScaler: TextScaler.noScaling,
                  style: style.copyWith(fontSize: fontSize),
                ),
              ),
            ),
          const SizedBox(height: CanvasSpace.xl),
          _GrowingRule(
            progress: discoveryInterval(reveal, 0.4, 0.85),
            color: palette.accent,
            width: 72,
          ),
          if (quote.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.lg),
            Padding(
              padding: EdgeInsets.only(left: indent),
              child: WipeReveal(
                progress: discoveryInterval(reveal, 0.5, 0.95),
                child: Text(
                  quote,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: CanvasType.quote.copyWith(
                    fontSize: 17,
                    height: 1.45,
                    color: palette.ink.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          _ExploreCue(
            palette: palette,
            progress: discoveryInterval(reveal, 0.7, 1),
            onTap: data.onExplore,
          ),
        ],
      ),
    );
  }

  static List<String> _words(String keyword) {
    if (keyword.isEmpty) return const [''];
    final parts = keyword.split(RegExp(r'\s+'));
    if (parts.length <= 3) return parts;
    // 太多词时两两并成一行，避免一屏都是字。
    final lines = <String>[];
    for (var i = 0; i < parts.length; i += 2) {
      lines.add(parts.skip(i).take(2).join(' '));
    }
    return lines;
  }

  /// 让最长的那一行恰好放进宽度，留一点余量给尚未加载完的字体。
  static double _fitDisplay(
    List<String> lines,
    TextStyle style,
    double width, {
    required double maxSize,
    double minSize = 40,
  }) {
    var size = maxSize;
    for (final line in lines) {
      if (line.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: line, style: style.copyWith(fontSize: 100)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final measured = painter.width;
      painter.dispose();
      if (measured > 0) size = math.min(size, 100 * width * 0.94 / measured);
    }
    return size.clamp(minSize, math.max(minSize, maxSize));
  }
}

// ---------------------------------------------------------------------------
// 封面二：名言
// ---------------------------------------------------------------------------

class _QuoteCover extends StatelessWidget {
  const _QuoteCover({required this.data});

  final _CoverData data;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final reveal = data.reveal;
    final keyword = data.push.keyword.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CanvasSpace.page,
        data.topInset,
        CanvasSpace.page + 8,
        data.bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Masthead(push: data.push, palette: palette, reveal: reveal),
          const Spacer(),
          MaskRise(
            progress: discoveryInterval(reveal, 0.04, 0.4),
            scaleFrom: 1.25,
            child: Text(
              '“',
              textScaler: TextScaler.noScaling,
              style: CanvasType.display.copyWith(
                fontSize: 120,
                height: 0.9,
                color: palette.accent,
              ),
            ),
          ),
          _QuoteBlock(
            push: data.push,
            palette: palette,
            size: null,
            progress: discoveryInterval(reveal, 0.14, 0.82),
            attributionProgress: discoveryInterval(reveal, 0.55, 1),
          ),
          if (keyword.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.xxl),
            MaskRise(
              progress: discoveryInterval(reveal, 0.62, 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    "TODAY'S WORD",
                    style: CanvasType.overline.copyWith(color: palette.accent),
                  ),
                  const SizedBox(width: CanvasSpace.md),
                  Flexible(
                    child: Text(
                      keyword,
                      style: CanvasType.section.copyWith(
                        fontSize: 24,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          _ExploreCue(
            palette: palette,
            progress: discoveryInterval(reveal, 0.72, 1),
            onTap: data.onExplore,
          ),
        ],
      ),
    );
  }
}

/// 名言正文和出处。[size] 为空时按长度选字号：越长越小，长段落仍然舒适。
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({
    required this.push,
    required this.palette,
    required this.size,
    this.progress,
    this.attributionProgress,
  });

  final DailyPush push;
  final DiscoveryPalette palette;
  final double? size;
  final Animation<double>? progress;
  final Animation<double>? attributionProgress;

  static double sizeFor(String quote) {
    final length = quote.runes.length;
    if (length <= 60) return 34;
    if (length <= 120) return 29;
    if (length <= 220) return 25;
    return 22;
  }

  @override
  Widget build(BuildContext context) {
    final quote = push.quote.trim();
    final author = push.quoteAuthor.trim();
    final fontSize = size ?? sizeFor(quote);
    Widget body = Text(
      quote,
      style: CanvasType.quote.copyWith(
        fontSize: fontSize,
        height: 1.3,
        color: palette.ink,
      ),
    );
    final progress = this.progress;
    if (progress != null) body = WipeReveal(progress: progress, child: body);

    Widget? attribution;
    if (author.isNotEmpty) {
      final line = Row(
        children: [
          _GrowingRule(
            progress: attributionProgress ?? kAlwaysCompleteAnimation,
            color: palette.accent,
            width: 28,
          ),
          const SizedBox(width: CanvasSpace.md),
          Flexible(
            child: Text(
              author.toUpperCase(),
              style: CanvasType.overline.copyWith(
                fontSize: 11.5,
                color: palette.ink.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      );
      final reveal = attributionProgress;
      attribution = reveal == null
          ? line
          : MaskRise(progress: reveal, child: line);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        if (attribution != null) ...[
          const SizedBox(height: CanvasSpace.lg + 2),
          attribution,
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 封面三：图片
// ---------------------------------------------------------------------------

class _ImageCover extends StatelessWidget {
  const _ImageCover({required this.data, required this.scroll});

  final _CoverData data;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final palette = data.palette;
    final reveal = data.reveal;
    final size = MediaQuery.sizeOf(context);
    final keyword = data.push.keyword.trim();
    final path = _themePath(data.push);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CanvasSpace.page,
        data.topInset,
        CanvasSpace.page,
        data.bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Masthead(push: data.push, palette: palette, reveal: reveal),
          const SizedBox(height: CanvasSpace.xl),
          Center(
            child: _CinematicImage(
              url: data.push.imageUrl.trim(),
              palette: palette,
              progress: discoveryInterval(reveal, 0.02, 0.7),
              scroll: scroll,
              maxHeight: size.height * 0.52,
            ),
          ),
          const Spacer(),
          const SizedBox(height: CanvasSpace.xl),
          MaskRise(
            progress: discoveryInterval(reveal, 0.38, 0.8),
            child: Text(
              "TODAY'S IMAGE",
              style: CanvasType.overline.copyWith(color: palette.accent),
            ),
          ),
          if (keyword.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.sm),
            MaskRise(
              progress: discoveryInterval(reveal, 0.44, 0.9),
              scaleFrom: 1.05,
              child: Text(
                keyword,
                style: CanvasType.display.copyWith(
                  fontSize: 44,
                  height: 1.02,
                  color: palette.ink,
                ),
              ),
            ),
          ],
          if (path.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.sm),
            WipeReveal(
              progress: discoveryInterval(reveal, 0.55, 0.95),
              child: Text(
                path,
                style: CanvasType.caption.copyWith(color: palette.muted),
              ),
            ),
          ],
          const SizedBox(height: CanvasSpace.xl),
          _ExploreCue(
            palette: palette,
            progress: discoveryInterval(reveal, 0.72, 1),
            onTap: data.onExplore,
          ),
        ],
      ),
    );
  }
}

/// 图片按原比例完整显示，不裁切。入场时像银幕上下黑边打开，
/// 同时从略大的比例回落；滚动时比文字走得慢一点。
class _CinematicImage extends StatelessWidget {
  const _CinematicImage({
    required this.url,
    required this.palette,
    required this.progress,
    required this.scroll,
    required this.maxHeight,
  });

  final String url;
  final DiscoveryPalette palette;
  final Animation<double> progress;
  final ScrollController scroll;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final reduce = discoveryReduceMotion(context);
    final image = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: CanvasRadius.imageAll,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: "Today's image",
          frameBuilder: (context, child, frame, sync) {
            if (sync || frame != null) return child;
            return Container(
              height: maxHeight * 0.8,
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.ink.withValues(alpha: 0.06),
                borderRadius: CanvasRadius.imageAll,
              ),
            );
          },
          errorBuilder: (_, _, _) => Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: CanvasRadius.imageAll,
              border: Border.all(color: palette.ink.withValues(alpha: 0.2)),
            ),
            child: Text(
              'Image unavailable',
              style: CanvasType.caption.copyWith(color: palette.muted),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: reduce ? progress : Listenable.merge([progress, scroll]),
      child: DecoratedBox(
        decoration: const BoxDecoration(boxShadow: CanvasShadow.floating),
        child: image,
      ),
      builder: (context, child) {
        final t = progress.value;
        final offset = !reduce && scroll.hasClients
            ? math.max(0.0, scroll.offset)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, offset * 0.22),
          child: ClipRect(
            clipper: _LetterboxClipper((1 - t) * 0.5),
            child: Transform.scale(scale: 1.06 - 0.06 * t, child: child),
          ),
        );
      },
    );
  }
}

class _LetterboxClipper extends CustomClipper<Rect> {
  const _LetterboxClipper(this.inset);

  /// 上下各收起高度的这个比例。0 为完全打开。
  final double inset;

  @override
  Rect getClip(Size size) {
    final dy = size.height * inset.clamp(0.0, 0.5);
    return Rect.fromLTRB(0, dy, size.width, size.height - dy);
  }

  @override
  bool shouldReclip(covariant _LetterboxClipper oldClipper) =>
      oldClipper.inset != inset;
}

// ---------------------------------------------------------------------------
// 共用零件
// ---------------------------------------------------------------------------

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.push,
    required this.palette,
    required this.reveal,
  });

  final DailyPush push;
  final DiscoveryPalette palette;
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context) {
    return MaskRise(
      progress: discoveryInterval(reveal, 0, 0.42),
      child: Text(
        DailyLetterFace.discoveryLabel(push, DateTime.now()),
        style: CanvasType.overline.copyWith(color: palette.accent),
      ),
    );
  }
}

class _GrowingRule extends StatelessWidget {
  const _GrowingRule({
    required this.progress,
    required this.color,
    required this.width,
  });

  final Animation<double> progress;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Transform.scale(
        scaleX: progress.value,
        scaleY: 1,
        alignment: Alignment.centerLeft,
        child: child,
      ),
      child: SizedBox(
        width: width,
        height: 1.5,
        child: ColoredBox(color: color),
      ),
    );
  }
}

class _ExploreCue extends StatelessWidget {
  const _ExploreCue({
    required this.palette,
    required this.progress,
    required this.onTap,
  });

  final DiscoveryPalette palette;
  final Animation<double> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: progress,
      child: Semantics(
        button: true,
        label: 'Discover more',
        excludeSemantics: true,
        onTap: onTap,
        child: Pressable(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Discover more',
                    style: CanvasType.label.copyWith(color: palette.ink),
                  ),
                ),
                const SizedBox(width: CanvasSpace.sm),
                Icon(Icons.south, size: 16, color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面之后的编排段落。偶数段向右缩进，形成不对称的版式。
class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.label,
    required this.palette,
    required this.indent,
    required this.child,
  });

  final int number;
  final String label;
  final DiscoveryPalette palette;
  final bool indent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.only(
        left: indent ? math.min(64.0, width * 0.12) : 0,
        bottom: CanvasSpace.xxl + 8,
      ),
      child: RevealOnScroll(
        builder: (context, progress) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MaskRise(
              progress: discoveryInterval(progress, 0, 0.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    number.toString().padLeft(2, '0'),
                    style: CanvasType.section.copyWith(
                      fontSize: 18,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: CanvasSpace.md),
                  Flexible(
                    child: Text(
                      label,
                      style: CanvasType.overline.copyWith(color: palette.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CanvasSpace.sm),
            _GrowingRule(
              progress: discoveryInterval(progress, 0.1, 0.6),
              color: palette.ink.withValues(alpha: 0.22),
              width: width,
            ),
            const SizedBox(height: CanvasSpace.lg),
            WipeReveal(
              progress: discoveryInterval(progress, 0.2, 1),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosingActions extends StatelessWidget {
  const _ClosingActions({
    required this.palette,
    required this.savingDraft,
    required this.onSaveDraft,
    required this.onDone,
  });

  final DiscoveryPalette palette;
  final bool savingDraft;
  final VoidCallback onSaveDraft;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Keep it for later, or make something of it.',
          style: CanvasType.section.copyWith(color: palette.ink),
        ),
        const SizedBox(height: CanvasSpace.xl),
        _OutlineAction(
          palette: palette,
          icon: Icons.bookmark_border,
          label: savingDraft ? 'Saving…' : 'Save to Drafts',
          onTap: savingDraft ? null : onSaveDraft,
        ),
        const SizedBox(height: CanvasSpace.md),
        _OutlineAction(
          palette: palette,
          icon: Icons.west,
          label: 'Back to Home',
          quiet: true,
          onTap: onDone,
        ),
      ],
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.quiet = false,
  });

  final DiscoveryPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool quiet;

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
          opacity: enabled ? 1 : 0.55,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.lg),
            decoration: BoxDecoration(
              borderRadius: CanvasRadius.buttonAll,
              border: quiet
                  ? null
                  : Border.all(color: palette.ink.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: palette.ink),
                const SizedBox(width: CanvasSpace.md),
                Expanded(
                  child: Text(
                    label,
                    style: CanvasType.label.copyWith(color: palette.ink),
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.palette,
    required this.scrolled,
    required this.reveal,
    required this.onClose,
  });

  final DiscoveryPalette palette;
  final bool scrolled;
  final Animation<double> reveal;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: scrolled ? 1 : 0,
                duration: CanvasMotion.standard,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.deep.withValues(alpha: 0.92),
                        palette.deep.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              CanvasSpace.lg,
              top + CanvasSpace.sm,
              CanvasSpace.page,
              CanvasSpace.xl,
            ),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Close Daily Inspiration',
                  excludeSemantics: true,
                  onTap: onClose,
                  child: Pressable(
                    onTap: onClose,
                    scale: 0.9,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.ink.withValues(alpha: 0.1),
                        border: Border.all(
                          color: palette.ink.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(Icons.close, size: 20, color: palette.ink),
                    ),
                  ),
                ),
                const SizedBox(width: CanvasSpace.lg),
                Expanded(
                  child: FadeTransition(
                    opacity: discoveryInterval(reveal, 0.2, 0.7),
                    child: Text(
                      'DAILY INSPIRATION',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CanvasType.overline.copyWith(color: palette.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingAction extends StatelessWidget {
  const _FloatingAction({
    required this.palette,
    required this.reveal,
    required this.onTap,
  });

  static const double height = 54;

  final DiscoveryPalette palette;
  final Animation<double> reveal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: CanvasSpace.page,
      right: CanvasSpace.page,
      bottom: bottom + CanvasSpace.lg,
      child: Center(
        child: AnimatedBuilder(
          animation: reveal,
          builder: (context, child) => Opacity(
            opacity: reveal.value,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - reveal.value)),
              child: child,
            ),
          ),
          child: Semantics(
            button: true,
            label: 'Write a Reflection',
            excludeSemantics: true,
            onTap: onTap,
            child: Pressable(
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: height),
                padding: const EdgeInsets.symmetric(horizontal: 26),
                decoration: BoxDecoration(
                  color: palette.actionFill,
                  borderRadius: BorderRadius.circular(27),
                  boxShadow: CanvasShadow.floating,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: palette.actionText,
                    ),
                    const SizedBox(width: CanvasSpace.sm + 2),
                    Flexible(
                      child: Text(
                        'Write a Reflection',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.label.copyWith(
                          fontSize: 15,
                          color: palette.actionText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 进入写作页：从下方轻轻升起，每日灵感页在下面后退。
class ReflectionRoute<T> extends PageRouteBuilder<T> {
  ReflectionRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 460),
        reverseTransitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) {
          if (discoveryReduceMotion(context)) {
            return FadeTransition(opacity: animation, child: child);
          }
          return FadeTransition(
            opacity: discoveryInterval(animation, 0, 0.5, Curves.easeOut),
            child: SlideTransition(
              position: animation.drive(
                Tween(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).chain(CurveTween(curve: CanvasMotion.enter)),
              ),
              child: child,
            ),
          );
        },
      );
}
