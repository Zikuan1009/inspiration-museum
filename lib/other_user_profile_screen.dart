import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inspiration_museum/app_id_label.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/chat_room_screen.dart';
import 'package:inspiration_museum/community_feed.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';
import 'package:inspiration_museum/user_stats_model.dart';

/// 他人主页：头像、馆员号、关注 / 私信，以及公开灵感瀑布流。
class OtherUserProfileScreen extends StatefulWidget {
  const OtherUserProfileScreen({super.key, required this.user});

  final UserModel user;

  static Route<void> route(UserModel user) {
    return PageRouteBuilder<void>(
      transitionDuration: CanvasMotion.standard,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) =>
          OtherUserProfileScreen(user: user),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: CanvasMotion.standardCurve,
          reverseCurve: CanvasMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  static const _followDebounce = Duration(milliseconds: 280);

  late UserModel _profile;
  late final Stream<UserStatsModel> _statsStream;
  StreamSubscription<UserStatsModel>? _statsSub;
  bool _relationLoading = true;
  bool _followBusy = false;
  bool _following = false;
  DateTime? _lastFollowTap;
  int _likes = 0;
  int _followers = 0;
  int _followingCount = 0;
  late final Future<List<CommunityPost>> _postsFuture;
  List<CommunityPost>? _posts;
  Object? _postsError;

  bool get _isSelf {
    final me = AuthService.instance.currentUser?.id;
    return me != null && me == _profile.id;
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.user;
    _postsFuture = SupabaseDBService.instance.fetchUserInspirations(
      widget.user.id,
    );
    _postsFuture
        .then((posts) {
          if (!mounted) return;
          setState(() => _posts = posts);
        })
        .catchError((Object error) {
          // 数据库拒绝时必须打到终端，不能再静默。
          // ignore: avoid_print
          print('===========> 拉取主页帖子彻底失败: $error');
          if (!mounted) return;
          setState(() => _postsError = error);
        });
    _statsStream = SupabaseDBService.instance.watchUserStats(widget.user.id);
    _statsSub = _statsStream.listen((stats) {
      if (!mounted) return;
      setState(() {
        _likes = stats.likes;
        _followers = stats.followers;
        _followingCount = stats.following;
      });
    });
    _load();
    SupabaseDBService.instance.deletedPosts.addListener(_onPostDeleted);
  }

  void _onPostDeleted() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SupabaseDBService.instance.deletedPosts.removeListener(_onPostDeleted);
    _statsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _relationLoading = true);
    final db = SupabaseDBService.instance;
    try {
      final latest = await db.fetchProfile(widget.user.id);
      if (latest != null && mounted) {
        setState(() => _profile = latest);
      }
      final following = await db.checkIsFollowing(_profile.id);
      if (!mounted) return;
      setState(() {
        _following = following;
        _relationLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _relationLoading = false);
    }
  }

  CommunityPost _asPost(CommunityPost post) {
    final name = _profile.username.trim();
    return CommunityPost(
      id: post.id,
      author: name.isEmpty ? post.author : name,
      authorId: _profile.id.isEmpty ? post.authorId : _profile.id,
      theme: post.theme,
      themeEn: post.themeEn,
      keywords: post.keywords,
      title: post.title,
      text: post.text,
      quote: post.quote,
      quoteAuthor: post.quoteAuthor,
      artworkSeed: post.artworkSeed,
      aspectRatio: post.aspectRatio,
      imagePath: post.imagePath,
    );
  }

  List<Widget> _gallerySlivers() {
    final error = _postsError;
    if (error != null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(CanvasSpace.xl),
            child: Text(
              'This gallery could not be loaded.',
              style: TextStyle(color: CanvasColors.text),
            ),
          ),
        ),
      ];
    }
    final loaded = _posts;
    if (loaded == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              CanvasSpace.page,
              CanvasSpace.lg,
              CanvasSpace.page,
              CanvasSpace.xl,
            ),
            child: CanvasSkeleton(height: 220),
          ),
        ),
      ];
    }
    final posts = [
      for (final post in loaded)
        if (!SupabaseDBService.instance.isPostDeleted(post.id)) _asPost(post),
    ];
    return [
      CommunityMasonrySliver(posts: posts, heroScope: 'profile-${_profile.id}'),
    ];
  }

  Future<void> _toggleFollow() async {
    if (_followBusy || _isSelf || _relationLoading) return;
    if (_lastFollowTap != null &&
        DateTime.now().difference(_lastFollowTap!) < _followDebounce) {
      return;
    }
    _lastFollowTap = DateTime.now();
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    setState(() => _followBusy = true);
    final db = SupabaseDBService.instance;
    try {
      final live = await db.checkIsFollowing(_profile.id);
      if (!mounted) return;
      if (live != _following) {
        setState(() => _following = live);
      }
      if (live) {
        await db.unfollowUser(_profile.id);
        if (!mounted) return;
        setState(() => _following = false);
      } else {
        await db.followUser(_profile.id);
        if (!mounted) return;
        setState(() => _following = true);
      }
      final stats = await db.fetchUserStats(_profile.id);
      if (!mounted) return;
      setState(() {
        _likes = stats.likes;
        _followers = stats.followers;
        _followingCount = stats.following;
      });
    } catch (_) {
      if (!mounted) return;
      final synced = await db.checkIsFollowing(_profile.id);
      if (!mounted) return;
      setState(() => _following = synced);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _openChat() async {
    if (!_following) return;
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    final me = AuthService.instance.currentUser?.id ?? '';
    if (me.isEmpty || me == _profile.id) return;
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(ChatRoomScreen.route(peer: _profile, currentUserId: me));
  }

  void _previewAvatar() {
    final user = _profile;
    showDialog<void>(
      context: context,
      barrierColor: CanvasColors.scrim,
      builder: (ctx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(ctx).width * 0.88,
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
              ),
              child: user.avatarUrl.trim().isNotEmpty
                  ? Image.network(
                      user.avatarUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          BauhausAvatar(seed: user.id, size: 220, border: true),
                    )
                  : BauhausAvatar(seed: user.id, size: 220, border: true),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _profile;
    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _OtherHeader(
                user: user,
                likes: _likes,
                followers: _followers,
                followingCount: _followingCount,
                following: _following,
                followBusy: _followBusy,
                relationLoading: _relationLoading,
                isSelf: _isSelf,
                onBack: () => Navigator.of(context).maybePop(),
                onFollow: _toggleFollow,
                onMessage: _openChat,
                onAvatarTap: _previewAvatar,
              ),
            ),
            ..._gallerySlivers(),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

class _OtherHeader extends StatelessWidget {
  const _OtherHeader({
    required this.user,
    required this.likes,
    required this.followers,
    required this.followingCount,
    required this.following,
    required this.followBusy,
    required this.relationLoading,
    required this.isSelf,
    required this.onBack,
    required this.onFollow,
    required this.onMessage,
    required this.onAvatarTap,
  });

  final UserModel user;
  final int likes;
  final int followers;
  final int followingCount;
  final bool following;
  final bool followBusy;
  final bool relationLoading;
  final bool isSelf;
  final VoidCallback onBack;
  final VoidCallback onFollow;
  final VoidCallback onMessage;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final meta = <({String label, String value})>[
      if (user.age != null) (label: 'Age', value: '${user.age}'),
      if (user.gender.trim().isNotEmpty)
        (label: 'Gender', value: _shownGender(user.gender)),
      if (user.location.trim().isNotEmpty)
        (label: 'Location', value: user.location.trim()),
      if (user.school.trim().isNotEmpty)
        (label: 'School', value: user.school.trim()),
    ];
    final bio = user.bio.trim();
    final name = user.username.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CanvasSpace.page,
        CanvasSpace.xs,
        CanvasSpace.page,
        CanvasSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: CanvasColors.text),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Pressable(
                onTap: onAvatarTap,
                child: ProfilePhoto(
                  seed: user.id,
                  imageUrl: user.avatarUrl,
                  size: 56,
                  border: false,
                ),
              ),
              const SizedBox(width: CanvasSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.collectionTitle,
                      ),
                    const SizedBox(height: CanvasSpace.xs),
                    AppIdCopyRow(appId: user.appId),
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.md),
            Text(
              bio,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: CanvasType.bodySmall,
            ),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: CanvasSpace.md),
            Wrap(
              spacing: CanvasSpace.xl,
              runSpacing: CanvasSpace.md,
              children: [
                for (final item in meta)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label.toUpperCase(),
                        style: CanvasType.overline,
                      ),
                      const SizedBox(height: CanvasSpace.xs),
                      Text(item.value, style: CanvasType.bodySmall),
                    ],
                  ),
              ],
            ),
          ],
          if (!isSelf) ...[
            const SizedBox(height: CanvasSpace.lg),
            if (relationLoading)
              const Align(
                alignment: Alignment.centerLeft,
                child: CanvasSkeleton(width: 120, height: 40),
              )
            else
              Wrap(
                spacing: CanvasSpace.sm,
                runSpacing: CanvasSpace.sm,
                children: [
                  CanvasButton(
                    label: followBusy
                        ? 'Working…'
                        : (following ? 'Following' : 'Follow'),
                    busy: followBusy,
                    variant: following
                        ? CanvasButtonVariant.secondary
                        : CanvasButtonVariant.primary,
                    onPressed: followBusy ? null : onFollow,
                  ),
                  if (following)
                    CanvasButton(
                      label: 'Message',
                      variant: CanvasButtonVariant.secondary,
                      onPressed: onMessage,
                    ),
                ],
              ),
          ],
          const SizedBox(height: CanvasSpace.xl),
          Row(
            children: [
              _Stat(value: likes, label: 'Likes'),
              _Stat(value: followers, label: 'Followers'),
              _Stat(value: followingCount, label: 'Following'),
            ],
          ),
        ],
      ),
    );
  }
}

String _shownGender(String raw) {
  return switch (raw.trim()) {
    '女' => 'Female',
    '男' => 'Male',
    final other => other,
  };
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: CanvasType.title),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: CanvasType.overline),
        ],
      ),
    );
  }
}
