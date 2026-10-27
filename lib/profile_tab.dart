import 'package:flutter/material.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/auth_session.dart';
import 'package:inspiration_museum/app_id_label.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/edit_profile_screen.dart';
import 'package:inspiration_museum/follow_list_screen.dart';
import 'package:inspiration_museum/community_feed.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/letter_drafts_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 个人主页：方形头像、签名、数字统计、POSTS / SAVED 双向展厅。
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _savedTab = false;
  bool _profileLoading = true;
  bool _statsLoading = true;
  UserModel? _cloudUser;
  List<CommunityPost> _ownPosts = const [];
  List<CommunityPost> _savedPosts = const [];
  List<LetterDraft> _drafts = const [];
  int? _posts;
  int? _likes;
  int? _followers;
  int? _following;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _loadCloudProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthScope.of(context);
    if (!identical(_session, session)) {
      _session?.removeListener(_onAuth);
      _session = session;
      _session!.addListener(_onAuth);
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    _loadCloudProfile();
  }

  Future<void> _loadCloudProfile() async {
    if (mounted && !_profileLoading) {
      setState(() => _profileLoading = true);
    }
    try {
      final db = SupabaseDBService.instance;
      final profile = await db.fetchCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _cloudUser = profile;
        _profileLoading = false;
        _statsLoading = profile != null;
      });
      if (profile == null) return;

      try {
        final stats = await db.fetchUserStats(profile.id);
        if (!mounted) return;
        setState(() {
          _posts = stats.posts;
          _likes = stats.likes;
          _followers = stats.followers;
          _following = stats.following;
          _statsLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _posts = 0;
          _likes = 0;
          _followers = 0;
          _following = 0;
          _statsLoading = false;
        });
      }

      try {
        final own = await db.fetchUserInspirations(profile.id);
        if (mounted) setState(() => _ownPosts = own);
      } catch (_) {}
      try {
        final saved = await db.fetchSavedInspirations(profile.id);
        if (mounted) setState(() => _savedPosts = saved);
      } catch (_) {}
      try {
        final drafts = await db.fetchLetterDrafts();
        if (mounted) setState(() => _drafts = drafts);
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cloudUser = null;
        _profileLoading = false;
        _statsLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await AuthScope.of(context).signOut();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      _SettingsScreen.route(
        onSignOut: _signOut,
        onUpgrade: AuthService.instance.isAnonymous
            ? () => AuthScreen.present(context)
            : null,
      ),
    );
  }

  void _openFollowList(String userId, {required bool followers}) {
    Navigator.of(context)
        .push(FollowListScreen.route(userId: userId, followers: followers));
  }

  Future<void> _editProfile(UserModel user) async {
    final changed = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(EditProfileScreen.route(user));
    if (changed == true && mounted) {
      await _loadCloudProfile();
    }
  }

  void _previewAvatar(UserModel user) {
    showDialog<void>(
      context: context,
      barrierColor: CanvasColors.scrim,
      builder: (ctx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: Hero(
              tag: 'self-avatar',
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(ctx).width * 0.88,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
                ),
                child: user.avatarUrl.trim().isNotEmpty
                    ? Image.network(
                        user.avatarUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => BauhausAvatar(
                          seed: user.id,
                          size: 220,
                          border: true,
                        ),
                      )
                    : BauhausAvatar(seed: user.id, size: 220, border: true),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_profileLoading) {
      return const Scaffold(
        backgroundColor: CanvasColors.background,
        body: SafeArea(child: _ProfileLoading()),
      );
    }

    final userModel = _cloudUser;
    if (userModel == null) {
      return Scaffold(
        backgroundColor: CanvasColors.background,
        body: SafeArea(
          child: Center(
            child: CanvasButton(
              label: 'Sign out',
              variant: CanvasButtonVariant.secondary,
              onPressed: _signOut,
            ),
          ),
        ),
      );
    }
    final user = userModel;

    final posts = _savedTab ? _savedPosts : _ownPosts;

    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _ProfileHeader(
                user: user,
                appId: user.appId,
                appIdLoading: _profileLoading,
                likes: _statsLoading ? null : _likes,
                followers: _statsLoading ? null : _followers,
                following: _statsLoading ? null : _following,
                onSettings: _openSettings,
                onEdit: () => _editProfile(user),
                onAvatarTap: () => _previewAvatar(user),
                onFollowers: () => _openFollowList(user.id, followers: true),
                onFollowing: () => _openFollowList(user.id, followers: false),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabStripDelegate(
                saved: _savedTab,
                count: _statsLoading ? null : _posts,
                onSelect: (saved) {
                  if (saved == _savedTab) return;
                  setState(() => _savedTab = saved);
                },
              ),
            ),
            CommunityMasonrySliver(
              posts: posts,
              heroScope: _savedTab ? 'saved' : 'gallery',
              leading: _savedTab
                  ? null
                  : _DraftBox(
                      count: _drafts.length,
                      onTap: () =>
                          Navigator.of(context)
                              .push(LetterDraftsScreen.route()),
                    ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(CanvasSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: CanvasSkeleton(width: 72, height: 16),
          ),
          const SizedBox(height: CanvasSpace.xl),
          Row(
            children: [
              CanvasSkeleton(
                width: 64,
                height: 64,
                borderRadius: BorderRadius.circular(32),
              ),
              SizedBox(width: CanvasSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CanvasSkeleton(width: 160, height: 22),
                    SizedBox(height: CanvasSpace.sm),
                    CanvasSkeleton(width: 96, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CanvasSpace.xl),
          const CanvasSkeleton(height: 14),
          const SizedBox(height: CanvasSpace.sm),
          const CanvasSkeleton(width: 220, height: 14),
        ],
      ),
    );
  }
}

class _DraftBox extends StatelessWidget {
  const _DraftBox({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Drafts, $count saved letters',
        excludeSemantics: true,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(CanvasSpace.md),
          decoration: BoxDecoration(
            color: CanvasColors.sunken,
            borderRadius: CanvasRadius.cardAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DRAFTS',
                style: CanvasType.overline.copyWith(color: CanvasColors.forest),
              ),
              const SizedBox(height: CanvasSpace.sm),
              Text(
                '$count',
                style: CanvasType.title.copyWith(color: CanvasColors.text),
              ),
              const SizedBox(height: CanvasSpace.xs),
              Text(
                count == 1 ? 'Saved letter' : 'Saved letters',
                style: CanvasType.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.appId,
    required this.appIdLoading,
    required this.likes,
    required this.followers,
    required this.following,
    required this.onSettings,
    required this.onEdit,
    required this.onAvatarTap,
    required this.onFollowers,
    required this.onFollowing,
  });

  final UserModel user;
  final String? appId;
  final bool appIdLoading;
  final int? likes;
  final int? followers;
  final int? following;
  final VoidCallback onSettings;
  final VoidCallback onEdit;
  final VoidCallback onAvatarTap;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;

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
        CanvasSpace.md,
        CanvasSpace.page,
        CanvasSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                button: true,
                label: 'Profile photo',
                child: Pressable(
                  onTap: onAvatarTap,
                  child: Hero(
                    tag: 'self-avatar',
                    child: ProfilePhoto(
                      seed: user.id,
                      imageUrl: user.avatarUrl,
                      size: 56,
                      border: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CanvasSpace.md),
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
                    AppIdCopyRow(appId: appId, loading: appIdLoading),
                  ],
                ),
              ),
              CanvasButton(
                label: 'Settings',
                variant: CanvasButtonVariant.quiet,
                onPressed: onSettings,
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
                  _MetaLine(label: item.label, value: item.value),
              ],
            ),
          ],
          const SizedBox(height: CanvasSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: CanvasButton(
              label: 'Edit profile',
              variant: CanvasButtonVariant.secondary,
              onPressed: onEdit,
            ),
          ),
          const SizedBox(height: CanvasSpace.md),
          Row(
            children: [
              _Stat(value: likes, label: 'Likes'),
              _Stat(value: followers, label: 'Followers', onTap: onFollowers),
              _Stat(value: following, label: 'Following', onTap: onFollowing),
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

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: CanvasType.overline),
          const SizedBox(height: CanvasSpace.xs),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: CanvasType.bodySmall.copyWith(color: CanvasColors.text),
          ),
        ],
      ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.onSignOut, this.onUpgrade});

  final VoidCallback onSignOut;
  final VoidCallback? onUpgrade;

  static Route<void> route({
    required VoidCallback onSignOut,
    VoidCallback? onUpgrade,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: CanvasMotion.standard,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) =>
          _SettingsScreen(onSignOut: onSignOut, onUpgrade: onUpgrade),
      transitionsBuilder: (context, animation, secondary, child) {
        final reduce = MediaQuery.disableAnimationsOf(context);
        if (reduce) return child;
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: CanvasMotion.standardCurve,
          ),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CanvasSpace.xs,
                CanvasSpace.xs,
                CanvasSpace.page,
                CanvasSpace.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: CanvasColors.text,
                    ),
                  ),
                  Expanded(
                    child: Text('Settings', style: CanvasType.collectionTitle),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            if (onUpgrade != null)
              _SettingsRow(
                label: 'Register email',
                onTap: () {
                  Navigator.of(context).maybePop();
                  onUpgrade!();
                },
              ),
            _SettingsRow(
              label: 'Sign out',
              onTap: () {
                Navigator.of(context).maybePop();
                onSignOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.page),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CanvasColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: CanvasType.titleSmall)),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: CanvasColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final int? value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = value == null ? '—' : '$value';
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shown, style: CanvasType.title),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: CanvasType.overline),
      ],
    );
    return Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: onTap == null
            ? child
            : Pressable(
                onTap: onTap,
                child: Semantics(
                  button: true,
                  label: '$label $shown',
                  excludeSemantics: true,
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: child,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TabStripDelegate extends SliverPersistentHeaderDelegate {
  _TabStripDelegate({
    required this.saved,
    required this.count,
    required this.onSelect,
  });

  final bool saved;
  final int? count;
  final ValueChanged<bool> onSelect;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collections = count == null ? 'Collections' : 'Collections · $count';
    return ColoredBox(
      color: CanvasColors.background,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CanvasColors.divider)),
        ),
        child: Row(
          children: [
            _Tab(
              label: collections,
              selected: !saved,
              onTap: () => onSelect(false),
            ),
            _Tab(label: 'Saved', selected: saved, onTap: () => onSelect(true)),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabStripDelegate oldDelegate) =>
      oldDelegate.saved != saved || oldDelegate.count != count;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.label.copyWith(
                      color: selected
                          ? CanvasColors.text
                          : CanvasColors.textSecondary,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: CanvasMotion.standard,
                curve: CanvasMotion.standardCurve,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: CanvasSpace.lg),
                color: selected ? CanvasColors.forest : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
