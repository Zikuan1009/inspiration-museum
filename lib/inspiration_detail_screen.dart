import 'package:flutter/material.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/chat_room_screen.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/local_image.dart';
import 'package:inspiration_museum/other_user_profile_screen.dart';
import 'package:inspiration_museum/post_share_sheet.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 帖子详情：拍立得黑框、右对齐互动、评论输入、实时评论流。
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.post,
    this.openComments = false,
    this.readOnly = false,
    this.heroTag,
  });

  final CommunityPost post;
  final bool openComments;
  final bool readOnly;

  /// 与来源卡片配图相同的 Hero 标签。为空时不做共享元素过渡。
  final String? heroTag;

  static Route<void> route(
    CommunityPost post, {
    bool openComments = false,
    bool readOnly = false,
    String? heroTag,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 480),
      reverseTransitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (context, animation, secondary) => PostDetailScreen(
        post: post,
        openComments: openComments,
        readOnly: readOnly,
        heroTag: heroTag,
      ),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.15, 1, curve: CanvasMotion.enter),
          reverseCurve: CanvasMotion.exit,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

typedef InspirationDetailScreen = PostDetailScreen;

class _PostDetailScreenState extends State<PostDetailScreen> {
  static const _emptyInteractions = <String, dynamic>{
    'likeCount': 0,
    'saveCount': 0,
    'commentCount': 0,
    'repostCount': 0,
    'liked': false,
    'saved': false,
    'reposted': false,
  };

  final _commentInput = TextEditingController();
  final _commentFocus = FocusNode();
  late final Stream<Map<String, dynamic>> _interactions;
  late final Stream<List<Map<String, dynamic>>> _commentsStream;
  bool _sending = false;
  bool? _liked;
  int? _likeCount;
  bool? _saved;
  int? _saveCount;
  String? replyingToCommentId;
  String? replyingToUsername;
  final Set<String> _openReplyThreads = {};

  CommunityPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    final me = AuthService.instance.currentUser?.id ?? '';
    _interactions = SupabaseDBService.instance.getPostInteractionsStream(
      post.id,
      me,
    );
    _commentsStream = SupabaseDBService.instance.getCommentsWithProfilesStream(
      post.id,
    );
    if (widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _commentInput.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _openChat() async {
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    final me = AuthService.instance.currentUser?.id ?? '';
    if (me.isEmpty || post.authorId.isEmpty || me == post.authorId) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      ChatRoomScreen.route(
        currentUserId: me,
        peerId: post.authorId,
        peerName: post.author,
      ),
    );
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

  void _toggleLike(Map<String, dynamic> data) {
    final me = AuthService.instance.currentUser?.id ?? '';
    if (me.isEmpty || !post.isCloudPost) return;
    final shown = _shown(data, 'liked', 'likeCount', _liked, _likeCount);
    final next = !shown.active;
    setState(() {
      _liked = next;
      _likeCount = (shown.count + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    SupabaseDBService.instance.toggleLike(post.id, me);
  }

  void _toggleSave(Map<String, dynamic> data) {
    final me = AuthService.instance.currentUser?.id ?? '';
    if (me.isEmpty || !post.isCloudPost) return;
    final shown = _shown(data, 'saved', 'saveCount', _saved, _saveCount);
    final next = !shown.active;
    setState(() {
      _saved = next;
      _saveCount = (shown.count + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    SupabaseDBService.instance.toggleSave(post.id, me);
  }

  Future<void> _sendComment() async {
    final text = _commentInput.text.trim();
    if (text.isEmpty || _sending) return;
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    final me = AuthService.instance.currentUser?.id ?? '';
    if (!post.isCloudPost || me.isEmpty) {
      _toast('The comment was not sent.');
      return;
    }
    setState(() => _sending = true);
    try {
      await SupabaseDBService.instance.addComment(
        post.id,
        me,
        text,
        parentId: replyingToCommentId,
      );
      if (!mounted) return;
      _commentInput.clear();
      setState(() {
        replyingToCommentId = null;
        replyingToUsername = null;
      });
      FocusScope.of(context).unfocus();
    } catch (_) {
      if (!mounted) return;
      _toast('The comment was not sent.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Map<String, dynamic>? _commentProfile(Map<String, dynamic> row) {
    final raw = row['profiles'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String _commentName(Map<String, dynamic> row) {
    final name = _commentProfile(row)?['username']?.toString().trim() ?? '';
    return name.isEmpty ? 'ANON' : name;
  }

  List<_CommentThread> _commentThreads(List<Map<String, dynamic>> rows) {
    final byId = <String, Map<String, dynamic>>{
      for (final row in rows)
        if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
    };
    final children = <String, List<Map<String, dynamic>>>{};
    final roots = <Map<String, dynamic>>[];
    for (final row in rows) {
      final parentId = row['parent_id']?.toString() ?? '';
      if (parentId.isEmpty || !byId.containsKey(parentId)) {
        roots.add(row);
      } else {
        children.putIfAbsent(parentId, () => []).add(row);
      }
    }

    List<_ReplyNode> collect(String parentId, int depth) {
      final nodes = <_ReplyNode>[];
      for (final child in children[parentId] ?? const []) {
        final id = child['id']?.toString() ?? '';
        nodes.add(_ReplyNode(child, depth));
        if (id.isNotEmpty) nodes.addAll(collect(id, depth + 1));
      }
      return nodes;
    }

    return [
      for (final root in roots)
        _CommentThread(root, collect(root['id']?.toString() ?? '', 1)),
    ];
  }

  Widget _commentTile(
    Map<String, dynamic> row,
    Map<String, String> names,
    String me,
  ) {
    final commentId = row['id']?.toString() ?? '';
    final parentId = row['parent_id']?.toString() ?? '';
    final likes = _commentLikeIds(row);
    final profile = _commentProfile(row);
    final username = _commentName(row);
    return CommentTile(
      seed:
          profile?['id']?.toString() ?? row['user_id']?.toString() ?? commentId,
      username: username,
      avatarUrl: profile?['avatar_url']?.toString() ?? '',
      content: row['content']?.toString() ?? '',
      replyToName: parentId.isEmpty ? null : names[parentId],
      liked: me.isNotEmpty && likes.contains(me),
      likeCount: likes.length,
      onOpenAuthor: () => _openCommentAuthor(
        profile?['id']?.toString() ?? row['user_id']?.toString() ?? '',
        username,
        profile?['avatar_url']?.toString() ?? '',
      ),
      onLike: () => _toggleCommentLike(commentId),
      onReply: () => _startReply(commentId, username),
    );
  }

  List<String> _commentLikeIds(Map<String, dynamic> row) {
    final raw = row['comment_likes'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map &&
            (item['user_id']?.toString().trim().isNotEmpty ?? false))
          item['user_id'].toString(),
    ];
  }

  void _startReply(String commentId, String username) {
    setState(() {
      replyingToCommentId = commentId;
      replyingToUsername = username;
    });
    _commentFocus.requestFocus();
  }

  Future<void> _toggleCommentLike(String commentId) async {
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    final me = AuthService.instance.currentUser?.id ?? '';
    await SupabaseDBService.instance.toggleCommentLike(commentId, me);
  }

  void _openCommentAuthor(String userId, String username, String avatarUrl) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      OtherUserProfileScreen.route(
        UserModel(
          id: userId,
          username: username,
          avatarUrl: avatarUrl,
          bio: '',
          followersCount: 0,
          followingCount: 0,
        ),
      ),
    );
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CanvasColors.forest,
        content: Text(
          text,
          style: CanvasType.bodySmall.copyWith(color: CanvasColors.textOnInk),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.currentUser?.id ?? '';
    final readOnly = widget.readOnly;
    final canMessage =
        !readOnly &&
        post.authorId.isNotEmpty &&
        (me.isEmpty || me != post.authorId);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: CanvasColors.background,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: _DetailTopBar(
              onClose: () => Navigator.of(context).maybePop(),
              isPrivate: post.isPrivate,
            ),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                CanvasSpace.page,
                CanvasSpace.sm,
                CanvasSpace.page,
                readOnly ? bottom + CanvasSpace.xxl : CanvasSpace.xl,
              ),
              children: [
                _Exhibit(post: post, heroTag: widget.heroTag),
                const SizedBox(height: CanvasSpace.xl),
                _DetailCopy(
                  post: post,
                  canMessage: canMessage,
                  onAuthor: post.authorId.isEmpty
                      ? null
                      : () {
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
                        },
                  onMessage: _openChat,
                ),
                if (!readOnly) ...[
                  const SizedBox(height: CanvasSpace.xl),
                  StreamBuilder<Map<String, dynamic>>(
                    stream: _interactions,
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? _emptyInteractions;
                      final like = _shown(
                        data,
                        'liked',
                        'likeCount',
                        _liked,
                        _likeCount,
                      );
                      final save = _shown(
                        data,
                        'saved',
                        'saveCount',
                        _saved,
                        _saveCount,
                      );
                      return _DetailActions(
                        liked: like.active,
                        likeCount: like.count,
                        commentCount: _asCount(data['commentCount']),
                        saved: save.active,
                        saveCount: save.count,
                        onLike: () => _toggleLike(data),
                        onComment: () => _commentFocus.requestFocus(),
                        onShare: () => showPostShareSheet(context, post: post),
                        onSave: () => _toggleSave(data),
                      );
                    },
                  ),
                  const SizedBox(height: CanvasSpace.xxl),
                  Text('COMMENTS', style: CanvasType.overline),
                  const SizedBox(height: CanvasSpace.lg),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _commentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                          'Comments could not be loaded.',
                          style: CanvasType.bodySmall,
                        );
                      }
                      final rows = snapshot.data;
                      if (rows == null) {
                        return const CanvasSkeleton(height: 72);
                      }
                      if (rows.isEmpty) {
                        return Text(
                          'No comments yet.',
                          style: CanvasType.body.copyWith(
                            color: CanvasColors.textSecondary,
                          ),
                        );
                      }
                      final names = <String, String>{
                        for (final row in rows)
                          row['id']?.toString() ?? '': _commentName(row),
                      };
                      final threads = _commentThreads(rows);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0; index < threads.length; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 ? 0 : CanvasSpace.xl,
                              ),
                              child: _thread(threads[index], names, me),
                            ),
                        ],
                      );
                    },
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: CanvasSpace.xl),
                    child: Text('View only', style: CanvasType.caption),
                  ),
              ],
            ),
          ),
          if (!readOnly)
            _CommentComposer(
              controller: _commentInput,
              focusNode: _commentFocus,
              sending: _sending,
              replyingTo: replyingToUsername,
              onCancelReply: () {
                setState(() {
                  replyingToCommentId = null;
                  replyingToUsername = null;
                });
              },
              onSend: _sendComment,
            ),
        ],
      ),
    );
  }

  Widget _thread(_CommentThread thread, Map<String, String> names, String me) {
    final rootId = thread.root['id']?.toString() ?? '';
    final expanded = _openReplyThreads.contains(rootId);
    final replies = thread.replies;
    final visible = replies.length <= 3 || expanded
        ? replies
        : replies.take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _commentTile(thread.root, names, me),
        for (final reply in visible)
          Padding(
            padding: EdgeInsets.only(
              left: 36 + ((reply.depth - 1).clamp(0, 2)) * 18,
              top: CanvasSpace.lg,
            ),
            child: _commentTile(reply.row, names, me),
          ),
        if (replies.length > 3)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: CanvasSpace.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CanvasButton(
                label: expanded ? 'Show less' : 'Show more',
                variant: CanvasButtonVariant.quiet,
                onPressed: () {
                  setState(() {
                    if (expanded) {
                      _openReplyThreads.remove(rootId);
                    } else {
                      _openReplyThreads.add(rootId);
                    }
                  });
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.onClose, required this.isPrivate});

  final VoidCallback onClose;
  final bool isPrivate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.xs),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close, color: CanvasColors.text),
            ),
            Expanded(
              child: Text(
                'COLLECTION',
                textAlign: TextAlign.center,
                style: CanvasType.overline.copyWith(color: CanvasColors.text),
              ),
            ),
            SizedBox(
              width: 72,
              child: isPrivate
                  ? Text(
                      'PRIVATE',
                      textAlign: TextAlign.right,
                      style: CanvasType.overline.copyWith(
                        color: CanvasColors.forest,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Exhibit extends StatelessWidget {
  const _Exhibit({required this.post, this.heroTag});

  final CommunityPost post;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final saved = SupabaseDBService.instance.latestPostImage(post.id);
    final url = (saved != null && saved.isNotEmpty)
        ? saved
        : (post.imagePath?.trim() ?? '');
    if (url.startsWith('http')) {
      Widget image = ClipRRect(
        borderRadius: CanvasRadius.imageAll,
        child: ColoredBox(
          color: CanvasColors.sunken,
          child: Image.network(
            url,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
            semanticLabel: 'Collection image',
            errorBuilder: (_, _, _) => const AspectRatio(
              aspectRatio: 1.4,
              child: Center(
                child: Text(
                  'Image unavailable',
                  style: TextStyle(color: CanvasColors.textSecondary),
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
      return image;
    }
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: CanvasRadius.imageAll,
        child: localFileImage(url, fit: BoxFit.fitWidth),
      );
    }
    final title = post.title.trim();
    final quote = CommunityPost.unwrapQuotes(post.quote);
    final lead = title.isNotEmpty ? title : quote;
    if (lead.isEmpty) return const SizedBox.shrink();
    return Text(lead, style: CanvasType.display.copyWith(fontSize: 36));
  }
}

class _DetailCopy extends StatelessWidget {
  const _DetailCopy({
    required this.post,
    required this.canMessage,
    required this.onAuthor,
    required this.onMessage,
  });

  final CommunityPost post;
  final bool canMessage;
  final VoidCallback? onAuthor;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final theme = post.theme.trim();
    final title = post.title.trim();
    final body = post.text.trim();
    final quote = CommunityPost.unwrapQuotes(post.quote);
    final quoteBy = post.quoteAuthor.trim();
    final words = post.keywords.where((k) => k.trim().isNotEmpty).join('  ·  ');
    final hasImage = () {
      final saved = SupabaseDBService.instance.latestPostImage(post.id);
      final url = (saved != null && saved.isNotEmpty)
          ? saved
          : (post.imagePath?.trim() ?? '');
      return url.isNotEmpty;
    }();
    final quoteAlreadyShown = !hasImage && title.isEmpty && quote.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (theme.isNotEmpty)
          AccentLabel(
            text: CommunityPost.themeLabel(theme),
            accent: CanvasColors.accentFor(theme),
          ),
        if (hasImage && title.isNotEmpty) ...[
          const SizedBox(height: CanvasSpace.md),
          Text(title, style: CanvasType.headline),
        ],
        const SizedBox(height: CanvasSpace.md),
        Row(
          children: [
            if (post.author.trim().isNotEmpty)
              Expanded(
                child: Pressable(
                  onTap: onAuthor,
                  child: Text(
                    post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.label,
                  ),
                ),
              )
            else
              const Spacer(),
            if (canMessage)
              CanvasButton(
                label: 'Message',
                variant: CanvasButtonVariant.quiet,
                onPressed: onMessage,
              ),
          ],
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: CanvasSpace.sm),
          Text(words, style: CanvasType.caption),
        ],
        if (body.isNotEmpty) ...[
          const SizedBox(height: CanvasSpace.lg),
          Text(
            body,
            style: CanvasType.body.copyWith(fontSize: 16.5, height: 1.7),
          ),
        ],
        if (quote.isNotEmpty && !quoteAlreadyShown) ...[
          const SizedBox(height: CanvasSpace.xl),
          Container(
            padding: const EdgeInsets.only(left: CanvasSpace.md),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: CanvasColors.gold, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CommunityPost.quotedText(quote),
                  style: CanvasType.quote.copyWith(fontSize: 20),
                ),
                if (quoteBy.isNotEmpty) ...[
                  const SizedBox(height: CanvasSpace.sm),
                  Text(quoteBy, style: CanvasType.caption),
                ],
              ],
            ),
          ),
        ] else if (quoteBy.isNotEmpty && quoteAlreadyShown) ...[
          const SizedBox(height: CanvasSpace.sm),
          Text(quoteBy, style: CanvasType.caption),
        ],
      ],
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.liked,
    required this.likeCount,
    required this.commentCount,
    required this.saved,
    required this.saveCount,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
  });

  final bool liked;
  final int likeCount;
  final int commentCount;
  final bool saved;
  final int saveCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CanvasColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: CanvasSpace.sm),
        child: Row(
          children: [
            _Action(
              icon: liked ? Icons.favorite : Icons.favorite_border,
              label: liked ? 'Unlike' : 'Like',
              count: likeCount,
              active: liked,
              onTap: onLike,
            ),
            _Action(
              icon: Icons.mode_comment_outlined,
              label: 'Comments',
              count: commentCount,
              onTap: onComment,
            ),
            _Action(icon: Icons.ios_share, label: 'Share', onTap: onShare),
            const Spacer(),
            _Action(
              icon: saved ? Icons.bookmark : Icons.bookmark_border,
              label: saved ? 'Unsave' : 'Save',
              count: saveCount,
              active: saved,
              onTap: onSave,
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? CanvasColors.forest : CanvasColors.text;
    final spoken = count == null ? label : '$label $count';
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                if (count != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: CanvasType.caption.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final reply = replyingTo?.trim() ?? '';
    return Material(
      color: CanvasColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CanvasColors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CanvasSpace.page,
              CanvasSpace.sm,
              CanvasSpace.sm,
              CanvasSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reply.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to $reply',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CanvasType.caption,
                        ),
                      ),
                      CanvasButton(
                        label: 'Cancel',
                        variant: CanvasButtonVariant.quiet,
                        onPressed: sending ? null : onCancelReply,
                      ),
                    ],
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !sending,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        cursorColor: CanvasColors.forest,
                        style: CanvasType.body,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: reply.isEmpty
                              ? 'Write a comment'
                              : 'Reply to $reply',
                          hintStyle: CanvasType.body.copyWith(
                            color: CanvasColors.textSecondary,
                          ),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                    CanvasButton(
                      label: sending ? 'Sending…' : 'Send',
                      variant: CanvasButtonVariant.quiet,
                      onPressed: sending ? null : onSend,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyNode {
  const _ReplyNode(this.row, this.depth);

  final Map<String, dynamic> row;
  final int depth;
}

class _CommentThread {
  const _CommentThread(this.root, this.replies);

  final Map<String, dynamic> root;
  final List<_ReplyNode> replies;
}

class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.seed,
    required this.username,
    required this.avatarUrl,
    required this.content,
    required this.liked,
    required this.likeCount,
    required this.onOpenAuthor,
    required this.onLike,
    required this.onReply,
    this.replyToName,
  });

  final String seed;
  final String username;
  final String avatarUrl;
  final String content;
  final String? replyToName;
  final bool liked;
  final int likeCount;
  final VoidCallback onOpenAuthor;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final reply = replyToName?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pressable(
          onTap: onOpenAuthor,
          child: Row(
            children: [
              ProfilePhoto(seed: seed, imageUrl: avatarUrl, size: 28),
              const SizedBox(width: CanvasSpace.sm),
              Expanded(
                child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CanvasType.label.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CanvasSpace.xs),
        Text.rich(
          TextSpan(
            style: CanvasType.bodySmall.copyWith(color: CanvasColors.text),
            children: [
              if (reply.isNotEmpty)
                TextSpan(
                  text: '@$reply ',
                  style: CanvasType.bodySmall.copyWith(
                    color: CanvasColors.forest,
                  ),
                ),
              TextSpan(text: content),
            ],
          ),
        ),
        Row(
          children: [
            CanvasButton(
              label: liked ? 'Unlike' : 'Like',
              variant: CanvasButtonVariant.quiet,
              onPressed: onLike,
            ),
            if (likeCount > 0) Text('$likeCount', style: CanvasType.caption),
            CanvasButton(
              label: 'Reply',
              variant: CanvasButtonVariant.quiet,
              onPressed: onReply,
            ),
          ],
        ),
      ],
    );
  }
}
