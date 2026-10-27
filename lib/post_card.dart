import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/inspiration_editor_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/other_user_profile_screen.dart';
import 'package:inspiration_museum/post_share_sheet.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 瀑布流里的一件作品。按内容分三种版式：
/// 有图的以图为主，长文字以标题和段落为主，短文字以名言为主。
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onOpen,
    this.onComment,
    this.heroTag,
  });

  final CommunityPost post;
  final VoidCallback? onOpen;
  final VoidCallback? onComment;

  /// 有值时，配图和详情页的配图做共享元素过渡。
  final String? heroTag;

  @override
  State<PostCard> createState() => _PostCardState();
}

enum _Layout { image, text, quote }

class _PostCardState extends State<PostCard> {
  static const _empty = <String, dynamic>{
    'likeCount': 0,
    'saveCount': 0,
    'commentCount': 0,
    'repostCount': 0,
    'liked': false,
    'saved': false,
    'reposted': false,
  };

  late final Stream<Map<String, dynamic>> _interactions;
  String? _imageUrl;
  bool _uploading = false;
  bool _deleting = false;
  bool? _liked;
  int? _likeCount;
  bool? _saved;
  int? _saveCount;

  bool get _isAuthor {
    final me = AuthService.instance.currentUser?.id ?? '';
    return me.isNotEmpty && me == widget.post.authorId;
  }

  @override
  void initState() {
    super.initState();
    final me = AuthService.instance.currentUser?.id ?? '';
    _interactions = SupabaseDBService.instance.getPostInteractionsStream(
      widget.post.id,
      me,
    );
    _imageUrl = _networkImageOf(widget.post);
  }

  String? _networkImageOf(CommunityPost post) {
    final saved = SupabaseDBService.instance.latestPostImage(post.id);
    if (saved != null && saved.isNotEmpty) return saved;
    final current = post.imagePath?.trim() ?? '';
    if (current.startsWith('http://') || current.startsWith('https://')) {
      return current;
    }
    return null;
  }

  CommunityPost get _shownPost =>
      SupabaseDBService.instance.withLocalEdits(widget.post);

  _Layout _layoutFor(CommunityPost post, String url) {
    if (url.isNotEmpty) return _Layout.image;
    final quote = CommunityPost.unwrapQuotes(post.quote);
    if (quote.isEmpty) return _Layout.text;
    final body = post.text.trim();
    if (body.length < 90) return _Layout.quote;
    if (CanvasColors.stableHash(post.id) % 4 == 0) return _Layout.quote;
    return _Layout.text;
  }

  Future<void> _editText() async {
    if (!widget.post.isCloudPost) return;
    final post = _shownPost;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => InspirationEditorScreen(
          keywords: post.keywords,
          quote: post.quote,
          postId: post.id,
          initialTitle: post.title,
          initialBody: post.text,
          initialPrivate: post.isPrivate,
          existingImageUrl: _imageUrl,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _imageUrl = _networkImageOf(widget.post));
    }
  }

  Future<bool> _confirmDelete() async {
    final answer = await showDialog<bool>(
      context: context,
      barrierColor: CanvasColors.scrim,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this post?'),
          content: Text(
            'It will leave the museum for everyone.',
            style: CanvasType.bodySmall.copyWith(
              color: CanvasColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: CanvasColors.danger),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return answer == true;
  }

  Future<void> _deletePost() async {
    if (_deleting || !widget.post.isCloudPost) return;
    final confirmed = await _confirmDelete();
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await SupabaseDBService.instance.deletePost(widget.post.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      final raw = error.toString().replaceFirst('Bad state: ', '');
      _toast(raw.isEmpty ? 'The post was not deleted.' : raw);
    }
  }

  Future<void> _changeImage() async {
    if (_uploading || !widget.post.isCloudPost) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final url = await SupabaseDBService.instance.updatePostImage(
        widget.post.id,
        file,
      );
      if (!mounted) return;
      setState(() {
        if (url.isNotEmpty) _imageUrl = url;
        _uploading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _toast(
        'Could not open the album: ${error.message ?? 'permission denied'}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _toast(_imageErrorText(error));
    }
  }

  String _imageErrorText(Object error) {
    final raw = error.toString();
    final state = RegExp(r'StateError: (.*)').firstMatch(raw);
    if (state != null) return state.group(1) ?? 'The image was not replaced.';
    if (raw.contains('42501') || raw.contains('row-level security')) {
      return 'No permission to put the image on this post.';
    }
    return 'The image was not replaced.';
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openOwnerMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        Widget option(String id, IconData icon, String label, {Color? color}) {
          final ink = color ?? CanvasColors.text;
          return ListTile(
            leading: Icon(icon, size: 20, color: ink),
            title: Text(label, style: CanvasType.body.copyWith(color: ink)),
            onTap: () => Navigator.of(sheetContext).pop(id),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: CanvasSpace.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option('edit', Icons.edit_outlined, 'Edit text'),
                option('image', Icons.image_outlined, 'Replace image'),
                option(
                  'delete',
                  Icons.delete_outline,
                  'Delete post',
                  color: CanvasColors.danger,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await _editText();
      case 'image':
        await _changeImage();
      case 'delete':
        await _deletePost();
    }
  }

  int _asCount(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse('$raw') ?? 0;
  }

  ({bool active, int count}) _shown(
    Map<String, dynamic> data,
    String flag,
    String countKey,
    bool? pendingFlag,
    int? pendingCount,
  ) {
    final onServer = data[flag] == true;
    final serverCount = _asCount(data[countKey]);
    if (pendingFlag != null && pendingFlag != onServer) {
      return (active: pendingFlag, count: pendingCount ?? serverCount);
    }
    return (active: onServer, count: serverCount);
  }

  void _likeNow(Map<String, dynamic> data) {
    final me = AuthService.instance.currentUser?.id ?? '';
    if (me.isEmpty || !widget.post.isCloudPost) return;
    final shown = _shown(data, 'liked', 'likeCount', _liked, _likeCount);
    final next = !shown.active;
    HapticFeedback.lightImpact();
    setState(() {
      _liked = next;
      _likeCount = (shown.count + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    SupabaseDBService.instance.toggleLike(widget.post.id, me);
  }

  void _saveNow(Map<String, dynamic> data) {
    final me = AuthService.instance.currentUser?.id ?? '';
    if (me.isEmpty || !widget.post.isCloudPost) return;
    final shown = _shown(data, 'saved', 'saveCount', _saved, _saveCount);
    final next = !shown.active;
    HapticFeedback.lightImpact();
    setState(() {
      _saved = next;
      _saveCount = (shown.count + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    SupabaseDBService.instance.toggleSave(widget.post.id, me);
  }

  void _openAuthor(CommunityPost post) {
    if (post.authorId.isEmpty) return;
    Navigator.of(context).push(
      OtherUserProfileScreen.route(
        UserModel(
          id: post.authorId,
          username: post.author,
          avatarUrl: '',
          bio: '',
          followersCount: 0,
          followingCount: 0,
        ),
      ),
    );
  }

  Widget _metrics({required bool onDark}) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _interactions,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _empty;
        final like = _shown(data, 'liked', 'likeCount', _liked, _likeCount);
        final save = _shown(data, 'saved', 'saveCount', _saved, _saveCount);
        return _MetricRow(
          onDark: onDark,
          liked: like.active,
          likeCount: like.count,
          commentCount: _asCount(data['commentCount']),
          reposted: data['reposted'] == true,
          saved: save.active,
          onLike: () => _likeNow(data),
          onComment: widget.onComment,
          onShare: () => showPostShareSheet(context, post: _shownPost),
          onSave: () => _saveNow(data),
          onMore: _isAuthor && widget.post.isCloudPost ? _openOwnerMenu : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _shownPost;
    final url = _imageUrl?.trim() ?? '';
    final layout = _layoutFor(post, url);
    final Widget body = switch (layout) {
      _Layout.image => _ImageLayout(
        post: post,
        url: url,
        heroTag: widget.heroTag,
        uploading: _uploading,
        onAuthor: () => _openAuthor(post),
        metrics: _metrics(onDark: false),
      ),
      _Layout.text => _TextLayout(
        post: post,
        onAuthor: () => _openAuthor(post),
        metricsFor: (onDark) => _metrics(onDark: onDark),
      ),
      _Layout.quote => _QuoteLayout(
        post: post,
        onAuthor: () => _openAuthor(post),
        metrics: _metrics(onDark: false),
      ),
    };
    return AnimatedOpacity(
      opacity: _deleting ? 0.4 : 1,
      duration: CanvasMotion.standard,
      child: Pressable(onTap: widget.onOpen, scale: 0.98, child: body),
    );
  }
}

// ---------------------------------------------------------------------------
// 三种版式
// ---------------------------------------------------------------------------

class _ImageLayout extends StatelessWidget {
  const _ImageLayout({
    required this.post,
    required this.url,
    required this.heroTag,
    required this.uploading,
    required this.onAuthor,
    required this.metrics,
  });

  final CommunityPost post;
  final String url;
  final String? heroTag;
  final bool uploading;
  final VoidCallback onAuthor;
  final Widget metrics;

  @override
  Widget build(BuildContext context) {
    Widget image = ClipRRect(
      borderRadius: CanvasRadius.imageAll,
      child: ColoredBox(
        color: CanvasColors.sunken,
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: CanvasMotion.emphasized,
              curve: CanvasMotion.enter,
              child: child,
            );
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const AspectRatio(
              aspectRatio: 0.8,
              child: SizedBox.expand(),
            );
          },
          errorBuilder: (_, _, _) => const AspectRatio(
            aspectRatio: 1,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: CanvasColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    final tag = heroTag;
    if (tag != null) {
      image = Hero(
        tag: tag,
        placeholderBuilder: (context, size, child) =>
            SizedBox(width: size.width, height: size.height),
        child: image,
      );
    }

    final title = post.title.trim();
    final quote = CommunityPost.unwrapQuotes(post.quote);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            image,
            if (uploading)
              const Positioned(
                top: 10,
                right: 10,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: CanvasColors.textOnInk,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AccentLabel(
          text: CommunityPost.themeLabel(post.theme),
          accent: CanvasColors.accentFor(post.theme),
        ),
        const SizedBox(height: 7),
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: CanvasType.collectionTitle,
          )
        else if (quote.isNotEmpty)
          Text(
            '“$quote”',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: CanvasType.quote.copyWith(fontSize: 16),
          ),
        const SizedBox(height: 8),
        _Byline(
          author: post.author,
          onTap: post.authorId.isEmpty ? null : onAuthor,
        ),
        const SizedBox(height: 6),
        metrics,
      ],
    );
  }
}

class _TextLayout extends StatelessWidget {
  const _TextLayout({
    required this.post,
    required this.onAuthor,
    required this.metricsFor,
  });

  final CommunityPost post;
  final VoidCallback onAuthor;
  final Widget Function(bool onDark) metricsFor;

  @override
  Widget build(BuildContext context) {
    final hash = CanvasColors.stableHash(post.id);
    final solid = hash % 5 == 0;
    final accent = CanvasColors.accentFor(post.theme);
    final fill = solid ? _solidFor(hash) : CanvasColors.surface;
    final ink = solid ? CanvasColors.textOnInk : CanvasColors.text;
    final soft = solid
        ? CanvasColors.textOnInk.withValues(alpha: 0.72)
        : CanvasColors.textSecondary;
    final title = post.title.trim();
    final body = post.text.trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: CanvasRadius.cardAll,
        border: solid ? null : Border.all(color: CanvasColors.divider),
      ),
      child: Stack(
        children: [
          if (solid) const Positioned.fill(child: GrainTexture(opacity: 0.045)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccentLabel(
                  text: CommunityPost.themeLabel(post.theme),
                  accent: solid ? CanvasColors.goldLight : accent,
                  color: soft,
                ),
                const SizedBox(height: 12),
                if (title.isNotEmpty) ...[
                  Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.collectionTitle.copyWith(
                      fontSize: 20,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (body.isNotEmpty)
                  Text(
                    body,
                    maxLines: title.isEmpty ? 9 : 6,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.bodySmall.copyWith(
                      color: solid ? ink.withValues(alpha: 0.88) : ink,
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 1,
                  child: ColoredBox(
                    color: solid
                        ? CanvasColors.textOnInk.withValues(alpha: 0.18)
                        : CanvasColors.divider,
                  ),
                ),
                const SizedBox(height: 10),
                _Byline(
                  author: post.author,
                  onTap: post.authorId.isEmpty ? null : onAuthor,
                  color: ink,
                  soft: soft,
                ),
                const SizedBox(height: 4),
                metricsFor(solid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _solidFor(int hash) {
    const fills = [CanvasColors.forest, Color(0xFF4F6A7D), Color(0xFF8F5843)];
    return fills[(hash ~/ 5) % fills.length];
  }
}

class _QuoteLayout extends StatelessWidget {
  const _QuoteLayout({
    required this.post,
    required this.onAuthor,
    required this.metrics,
  });

  final CommunityPost post;
  final VoidCallback onAuthor;
  final Widget metrics;

  @override
  Widget build(BuildContext context) {
    final accent = CanvasColors.accentFor(post.theme);
    final quote = CommunityPost.unwrapQuotes(post.quote);
    final quoteAuthor = post.quoteAuthor.trim();
    final title = post.title.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CanvasColors.tint(accent, 0.09),
        borderRadius: CanvasRadius.cardAll,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '“',
              style: CanvasType.display.copyWith(
                fontSize: 56,
                height: 1,
                color: accent.withValues(alpha: 0.85),
              ),
            ),
            Text(
              quote,
              maxLines: 7,
              overflow: TextOverflow.ellipsis,
              style: CanvasType.quote.copyWith(fontSize: 19, height: 1.38),
            ),
            if (quoteAuthor.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '— $quoteAuthor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CanvasType.caption,
              ),
            ],
            const SizedBox(height: 16),
            AccentLabel(
              text: CommunityPost.themeLabel(post.theme),
              accent: accent,
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CanvasType.titleSmall.copyWith(fontSize: 14),
              ),
            ],
            const SizedBox(height: 8),
            _Byline(
              author: post.author,
              onTap: post.authorId.isEmpty ? null : onAuthor,
            ),
            const SizedBox(height: 4),
            metrics,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 署名与互动
// ---------------------------------------------------------------------------

class _Byline extends StatelessWidget {
  const _Byline({
    required this.author,
    required this.onTap,
    this.color = CanvasColors.text,
    this.soft = CanvasColors.textSecondary,
  });

  final String author;
  final VoidCallback? onTap;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'by ',
              style: CanvasType.caption.copyWith(color: soft),
            ),
            TextSpan(
              text: author,
              style: CanvasType.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.onDark,
    required this.liked,
    required this.likeCount,
    required this.commentCount,
    required this.reposted,
    required this.saved,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onMore,
  });

  final bool onDark;
  final bool liked;
  final int likeCount;
  final int commentCount;
  final bool reposted;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback? onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final base = onDark
        ? CanvasColors.textOnInk.withValues(alpha: 0.82)
        : CanvasColors.textSecondary;
    final likeColor = onDark ? CanvasColors.goldLight : CanvasColors.terracotta;
    final saveColor = onDark ? CanvasColors.goldLight : CanvasColors.forest;
    return Row(
      children: [
        _Metric(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          color: liked ? likeColor : base,
          count: likeCount,
          label: liked ? 'Unlike' : 'Like',
          onTap: onLike,
        ),
        _Metric(
          icon: Icons.mode_comment_outlined,
          color: base,
          count: commentCount,
          label: 'Comment',
          onTap: onComment,
        ),
        _Metric(
          icon: Icons.repeat,
          color: reposted ? saveColor : base,
          label: 'Share',
          onTap: onShare,
        ),
        const Spacer(),
        if (onMore != null)
          _Metric(
            icon: Icons.more_horiz,
            color: base,
            label: 'Manage post',
            onTap: onMore,
          ),
        _Metric(
          icon: saved ? Icons.bookmark : Icons.bookmark_border,
          color: saved ? saveColor : base,
          label: saved ? 'Unsave' : 'Save',
          onTap: onSave,
          last: true,
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.count,
    this.last = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final int? count;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final value = count ?? 0;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 6, last ? 0 : 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: CanvasMotion.quick,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.7, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: CanvasMotion.enter,
                    ),
                  ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(icon, key: ValueKey(icon), size: 16, color: color),
              ),
              if (value > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$value',
                  style: CanvasType.caption.copyWith(
                    fontSize: 11,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
