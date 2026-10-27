import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:inspiration_museum/brand/museum_brand.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_letter_card.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/inspiration_detail_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/next_letter_test_screen.dart';
import 'package:inspiration_museum/post_card.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// Puts ranked ids first and drops any id that is not already in [posts].
/// Unknown, private, or invented ids cannot add a card. Everyone else stays
/// in the original order.
List<CommunityPost> placeRankedFirst(
  List<CommunityPost> posts,
  List<String> ids,
) {
  final byId = {for (final post in posts) post.id: post};
  final used = <String>{};
  final ordered = <CommunityPost>[];
  for (final id in ids) {
    final post = byId[id];
    if (post == null || !used.add(post.id)) continue;
    ordered.add(post);
  }
  for (final post in posts) {
    if (used.contains(post.id)) continue;
    ordered.add(post);
  }
  return ordered;
}

/// 首页的刊物版面：刊头、每日灵感、栏目切换、作品瀑布流。
class CommunityFeed extends StatefulWidget {
  const CommunityFeed({
    super.key,
    this.onOpenLetter,
    this.posts,
    this.onSearchSubmitted,
    this.postQuery = '',
    this.searchNotice,
    this.searchBusy = false,
    this.onReselectFields,
    this.dailyPush,
    this.letterCardKey,
    this.onOpenProfile,
  });

  /// 点每日灵感卡片。信还在加载时卡片不可点。
  final ValueChanged<DailyPush>? onOpenLetter;
  final List<CommunityPost>? posts;
  final ValueChanged<String>? onSearchSubmitted;
  final String postQuery;
  final String? searchNotice;
  final bool searchBusy;
  final VoidCallback? onReselectFields;

  /// 今天的信。为空时不显示每日来信卡片。
  final Future<DailyPush>? dailyPush;

  /// 挂在每日灵感卡片上，首页据此让全屏页从卡片原位展开。
  final GlobalKey? letterCardKey;
  final VoidCallback? onOpenProfile;

  static const double toolbarHeight = 64;

  @override
  State<CommunityFeed> createState() => _CommunityFeedState();
}

enum _Shelf { forYou, following, images, words }

class _CommunityFeedState extends State<CommunityFeed> {
  late Future<List<CommunityPost>> _future;
  int _reloadToken = 0;
  _Shelf _shelf = _Shelf.forYou;
  Future<Set<String>>? _followingIds;
  UserModel? _me;
  bool _searching = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  String get _myId => AuthService.instance.currentUser?.id ?? '';

  List<_Shelf> get _shelves => [
    _Shelf.forYou,
    if (_myId.isNotEmpty) _Shelf.following,
    _Shelf.images,
    _Shelf.words,
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadPosts();
    _searching = widget.postQuery.trim().isNotEmpty;
    _searchController.text = widget.postQuery;
    _loadMe();
  }

  @override
  void didUpdateWidget(covariant CommunityFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.posts, widget.posts) && widget.posts != null) {
      _future = Future<List<CommunityPost>>.value(widget.posts);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    if (_myId.isEmpty) return;
    try {
      final me = await SupabaseDBService.instance.getCurrentUserProfile();
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  Future<List<CommunityPost>> _loadPosts() async {
    if (widget.posts != null) return widget.posts!;
    final db = SupabaseDBService.instance;
    final all = await db.fetchPublicInspirations();
    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) return all;
    try {
      final ids = await db.rankHomeFeed(_todayKey());
      if (ids.isNotEmpty) return _placeFirst(all, ids);
    } catch (error) {
      debugPrint('rank home feed: $error');
    }
    return _bySelectedThemes(all, userId, db);
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  List<CommunityPost> _placeFirst(List<CommunityPost> posts, List<String> ids) {
    return placeRankedFirst(posts, ids);
  }

  Future<List<CommunityPost>> _bySelectedThemes(
    List<CommunityPost> all,
    String userId,
    SupabaseDBService db,
  ) async {
    final selectedIds = await db.fetchUserSelectedThemes(userId);
    if (selectedIds.isEmpty) return all;
    final catalog = await db.fetchAvailableThemes();
    final themes = [
      for (final theme in catalog)
        if (selectedIds.contains(theme.id)) theme.name,
    ];
    if (themes.isEmpty) return all;
    final selected = themes.toSet();
    final filtered = all
        .where(
          (post) =>
              selected.contains(post.theme) ||
              post.keywords.any(selected.contains),
        )
        .toList(growable: false);
    return filtered.isEmpty ? all : filtered;
  }

  Future<void> _reloadPosts() {
    if (widget.posts != null) return Future<void>.value();
    final next = _loadPosts();
    setState(() {
      _future = next;
      _reloadToken++;
      _followingIds = null;
    });
    return next;
  }

  Future<Set<String>> _loadFollowing() async {
    final people = await SupabaseDBService.instance.fetchFollowing(_myId);
    return {for (final person in people) person.id};
  }

  void _selectShelf(_Shelf shelf) {
    setState(() {
      _shelf = shelf;
      if (shelf == _Shelf.following) _followingIds ??= _loadFollowing();
    });
  }

  static String _shelfLabel(_Shelf shelf) => switch (shelf) {
    _Shelf.forYou => 'For you',
    _Shelf.following => 'Following',
    _Shelf.images => 'Images',
    _Shelf.words => 'Words',
  };

  static bool _hasImage(CommunityPost post) {
    final saved = SupabaseDBService.instance.latestPostImage(post.id);
    if (saved != null && saved.trim().isNotEmpty) return true;
    return post.hasNetworkImage;
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _searching = false);
    if (widget.postQuery.trim().isNotEmpty) {
      widget.onSearchSubmitted?.call('');
    }
  }

  void _submitSearch(String value) {
    _searchFocus.unfocus();
    widget.onSearchSubmitted?.call(value.trim());
  }

  // ---------------------------------------------------------------------------
  // 版面
  // ---------------------------------------------------------------------------

  Widget _masthead() {
    return SliverAppBar(
      pinned: false,
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: CanvasColors.background,
      automaticallyImplyLeading: false,
      toolbarHeight: CommunityFeed.toolbarHeight,
      titleSpacing: CanvasSpace.page,
      title: AnimatedSwitcher(
        duration: CanvasMotion.standard,
        switchInCurve: CanvasMotion.enter,
        switchOutCurve: CanvasMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _searching ? _searchRow() : _brandRow(),
      ),
    );
  }

  Widget _brandRow() {
    final me = _me;
    return InspirationMuseumBrandHeader(
      key: const ValueKey('brand'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HeaderAction(
            icon: Icons.search,
            label: 'Search',
            onTap: widget.onSearchSubmitted == null ? null : _openSearch,
          ),
          if (widget.onReselectFields != null)
            _HeaderAction(
              icon: Icons.tune,
              label: 'Backstage',
              onTap: widget.onReselectFields,
            ),
          if (me != null && widget.onOpenProfile != null) ...[
            const SizedBox(width: CanvasSpace.xs),
            _MastheadAvatar(user: me, onTap: widget.onOpenProfile!),
          ],
        ],
      ),
    );
  }

  Widget _searchRow() {
    final notice = widget.searchNotice;
    return Row(
      key: const ValueKey('search'),
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              style: CanvasType.body.copyWith(fontSize: 14),
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                hintText: widget.searchBusy
                    ? 'Searching…'
                    : 'Search collections or a member number',
                hintStyle: CanvasType.bodySmall.copyWith(
                  color: CanvasColors.textSecondary,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: CanvasColors.textSecondary,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                suffixIcon: notice == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: CanvasSpace.md),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            notice,
                            style: CanvasType.caption.copyWith(
                              color: CanvasColors.danger,
                            ),
                          ),
                        ),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: CanvasSpace.xs),
        _HeaderAction(
          icon: Icons.close,
          label: 'Close search',
          onTap: _closeSearch,
        ),
      ],
    );
  }

  Widget _letterCard() {
    final future = widget.dailyPush;
    if (future == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CanvasSpace.page,
          CanvasSpace.sm,
          CanvasSpace.page,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RevealIn(
              distance: 16,
              child: FutureBuilder<DailyPush>(
                future: future,
                builder: (context, snapshot) {
                  final ready =
                      snapshot.connectionState == ConnectionState.done;
                  final push = ready
                      ? (snapshot.data ?? DailyPush.fallback)
                      : null;
                  final open = widget.onOpenLetter;
                  return DailyLetterCard(
                    key: widget.letterCardKey,
                    push: push,
                    onOpen: push != null && open != null
                        ? () => open(push)
                        : null,
                  );
                },
              ),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(top: CanvasSpace.sm),
                child: _QuietTestLink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CanvasSpace.page,
          CanvasSpace.lg,
          CanvasSpace.page,
          CanvasSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FROM THE COMMUNITY', style: CanvasType.overline),
            const SizedBox(height: 6),
            Text('Collections', style: CanvasType.section),
          ],
        ),
      ),
    );
  }

  Widget _shelfBar() {
    final shelves = _shelves;
    final selected = math.max(0, shelves.indexOf(_shelf));
    return SliverPersistentHeader(
      pinned: true,
      delegate: _ShelfBarDelegate(
        child: EditorialTabs(
          labels: [for (final shelf in shelves) _shelfLabel(shelf)],
          selected: selected,
          onSelected: (index) => _selectShelf(shelves[index]),
        ),
        signature: '${shelves.length}-$selected',
      ),
    );
  }

  List<CommunityPost> _shelved(
    List<CommunityPost> posts,
    Set<String>? following,
  ) {
    return switch (_shelf) {
      _Shelf.forYou => posts,
      _Shelf.following => [
        for (final post in posts)
          if (following?.contains(post.authorId) ?? false) post,
      ],
      _Shelf.images => [
        for (final post in posts)
          if (_hasImage(post)) post,
      ],
      _Shelf.words => [
        for (final post in posts)
          if (!_hasImage(post)) post,
      ],
    };
  }

  Widget _postsSliver(AsyncSnapshot<List<CommunityPost>> snapshot) {
    if (snapshot.hasError) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _QuietMessage(
          title: 'The collections did not load.',
          detail: 'Pull down to try again.',
        ),
      );
    }
    if (!snapshot.hasData) return const _FeedSkeleton();
    if (_shelf == _Shelf.following) {
      return FutureBuilder<Set<String>>(
        future: _followingIds,
        builder: (context, following) {
          if (following.connectionState != ConnectionState.done) {
            return const _FeedSkeleton();
          }
          return _matchedSliver(snapshot.data!, following.data ?? const {});
        },
      );
    }
    return _matchedSliver(snapshot.data!, null);
  }

  Widget _matchedSliver(List<CommunityPost> all, Set<String>? following) {
    final query = widget.postQuery.trim();
    final searched = query.isEmpty ? all : _relatedPosts(all, query);
    final matched = _shelved(searched, following);
    if (matched.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _QuietMessage(
          title: query.isNotEmpty
              ? 'Nothing matches “$query”.'
              : switch (_shelf) {
                  _Shelf.following =>
                    'No collections from people you follow yet.',
                  _Shelf.images => 'No image collections yet.',
                  _Shelf.words => 'No written collections yet.',
                  _Shelf.forYou => 'No collections yet.',
                },
          detail: query.isNotEmpty
              ? 'Try another word, or close the search.'
              : null,
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        if (query.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CanvasSpace.page,
                CanvasSpace.lg,
                CanvasSpace.page,
                0,
              ),
              child: Text(
                'RELATED TO “${query.toUpperCase()}”  ·  ${matched.length}',
                style: CanvasType.overline,
              ),
            ),
          ),
        CommunityMasonrySliver(
          posts: matched,
          reloadToken: _reloadToken,
          heroScope: 'home',
          animateEntrance: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CommunityPost>>(
      future: _future,
      builder: (context, snapshot) {
        return ColoredBox(
          color: CanvasColors.background,
          child: RefreshIndicator(
            color: CanvasColors.forest,
            backgroundColor: CanvasColors.surface,
            displacement: 72,
            onRefresh: _reloadPosts,
            child: ScrollConfiguration(
              behavior: const _QuietScrollBehavior(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  _masthead(),
                  _letterCard(),
                  _sectionHeading(),
                  _shelfBar(),
                  _postsSliver(snapshot),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: CanvasSpace.xxl),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuietScrollBehavior extends MaterialScrollBehavior {
  const _QuietScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _ShelfBarDelegate extends SliverPersistentHeaderDelegate {
  const _ShelfBarDelegate({required this.child, required this.signature});

  final Widget child;
  final String signature;

  static const double _height = 48;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CanvasColors.background,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent || shrinkOffset > 0
                ? CanvasColors.divider
                : CanvasColors.divider.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _ShelfBarDelegate oldDelegate) =>
      oldDelegate.signature != signature || oldDelegate.child != child;
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null ? CanvasColors.divider : CanvasColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _MastheadAvatar extends StatelessWidget {
  const _MastheadAvatar({required this.user, required this.onTap});

  final UserModel user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl.trim();
    final initial = user.username.trim().isEmpty
        ? '·'
        : user.username.trim().characters.first.toUpperCase();
    return Semantics(
      button: true,
      label: 'Open your profile',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CanvasColors.forest,
            border: Border.all(color: CanvasColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: url.isEmpty
              ? Text(
                  initial,
                  style: CanvasType.brand.copyWith(
                    fontSize: 15,
                    color: CanvasColors.textOnInk,
                    letterSpacing: 0,
                  ),
                )
              : ProfilePhoto(
                  seed: user.id,
                  imageUrl: url,
                  size: 32,
                  border: false,
                ),
        ),
      ),
    );
  }
}

/// 开发测试入口的安静版本。正式版和 NextLetterTestButton 一起删除。
class _QuietTestLink extends StatelessWidget {
  const _QuietTestLink();

  @override
  Widget build(BuildContext context) {
    return const Opacity(opacity: 0.55, child: NextLetterTestButton());
  }
}

class _QuietMessage extends StatelessWidget {
  const _QuietMessage({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: CanvasType.section.copyWith(
              fontSize: 19,
              color: CanvasColors.text,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: CanvasSpace.sm),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: CanvasType.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        CanvasSpace.page,
        CanvasSpace.lg,
        CanvasSpace.page,
        CanvasSpace.md,
      ),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: CanvasSpace.gridRow,
        crossAxisSpacing: CanvasSpace.gridColumn,
        childCount: 4,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CanvasSkeleton(height: index.isEven ? 200 : 150),
            const SizedBox(height: 10),
            const CanvasSkeleton(width: 70, height: 9),
            const SizedBox(height: 8),
            const CanvasSkeleton(height: 14),
          ],
        ),
      ),
    );
  }
}

List<CommunityPost> _relatedPosts(List<CommunityPost> posts, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return posts;
  final tokens = needle
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  final ranked = <({int score, int index, CommunityPost post})>[];
  for (var i = 0; i < posts.length; i++) {
    final post = posts[i];
    final blob = _searchBlob(post);
    final phrase = blob.contains(needle);
    final tokensHit = tokens.isNotEmpty && tokens.every(blob.contains);
    if (!phrase && !tokensHit) continue;
    final keys = phrase ? [needle] : tokens;
    var score = phrase ? 2 : 0;
    for (final key in keys) {
      if (post.title.toLowerCase().contains(key)) score += 5;
      if (post.keywords.any((word) => word.toLowerCase().contains(key))) {
        score += 4;
      }
      if (post.quote.toLowerCase().contains(key)) score += 3;
      if (post.theme.toLowerCase().contains(key)) score += 2;
      if (post.text.toLowerCase().contains(key)) score += 1;
      if (post.author.toLowerCase().contains(key)) score += 1;
    }
    ranked.add((score: score, index: i, post: post));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.index.compareTo(b.index);
  });
  return [for (final row in ranked) row.post];
}

String _searchBlob(CommunityPost post) {
  return [
    post.title,
    post.text,
    post.quote,
    post.quoteAuthor,
    post.theme,
    post.author,
    ...post.keywords,
  ].join('\n').toLowerCase();
}

/// 可复用的社区瀑布流 sliver（首页、个人主页 POSTS / SAVED 共用）。
class CommunityMasonrySliver extends StatefulWidget {
  const CommunityMasonrySliver({
    super.key,
    required this.posts,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(
      CanvasSpace.page,
      CanvasSpace.lg,
      CanvasSpace.page,
      CanvasSpace.md,
    ),
    this.reloadToken = 0,
    this.heroScope,
    this.animateEntrance = false,
  });

  final List<CommunityPost> posts;
  final Widget? leading;
  final EdgeInsets padding;
  final int reloadToken;

  /// 有值时，卡片配图与详情页做共享元素过渡。同一页面里每个瀑布流用不同的值。
  final String? heroScope;

  /// 首屏的前几件依次淡入。已经出现过的作品滚回来时不再重播。
  final bool animateEntrance;

  static const int _entranceCount = 6;

  static int columnCountFor(double width) {
    if (width < 720) return 2;
    return math.min(4, width ~/ 280);
  }

  @override
  State<CommunityMasonrySliver> createState() => _CommunityMasonrySliverState();
}

class _CommunityMasonrySliverState extends State<CommunityMasonrySliver> {
  final _shown = <String>{};

  @override
  void initState() {
    super.initState();
    SupabaseDBService.instance.deletedPosts.addListener(_onDeleted);
  }

  @override
  void dispose() {
    SupabaseDBService.instance.deletedPosts.removeListener(_onDeleted);
    super.dispose();
  }

  void _onDeleted() {
    if (mounted) setState(() {});
  }

  Widget _entrance(String id, int index, Widget child) {
    final first = _shown.add(id);
    return RevealIn(
      key: ValueKey('reveal-$id'),
      enabled:
          widget.animateEntrance &&
          first &&
          index < CommunityMasonrySliver._entranceCount,
      index: index + 1,
      distance: 18,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = [
      for (final post in widget.posts)
        if (!SupabaseDBService.instance.isPostDeleted(post.id)) post,
    ];
    final leading = widget.leading;
    if (posts.isEmpty && leading == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _QuietMessage(title: 'Nothing here yet.'),
      );
    }

    final offset = leading == null ? 0 : 1;
    return SliverPadding(
      padding: widget.padding,
      sliver: SliverMasonryGrid.count(
        crossAxisCount: CommunityMasonrySliver.columnCountFor(
          MediaQuery.sizeOf(context).width,
        ),
        mainAxisSpacing: CanvasSpace.gridRow,
        crossAxisSpacing: CanvasSpace.gridColumn,
        childCount: posts.length + offset,
        itemBuilder: (context, index) {
          if (leading != null && index == 0) return leading;
          final post = SupabaseDBService.instance.withLocalEdits(
            posts[index - offset],
          );
          final scope = widget.heroScope;
          final heroTag = scope == null ? null : '$scope-post-image-${post.id}';
          return _entrance(
            '${post.id}-${widget.reloadToken}',
            index - offset,
            PostCard(
              key: ValueKey('${post.id}-${widget.reloadToken}'),
              post: post,
              heroTag: heroTag,
              onOpen: () => Navigator.of(context)
                  .push(InspirationDetailScreen.route(post, heroTag: heroTag)),
              onComment: () => Navigator.of(context).push(
                InspirationDetailScreen.route(
                  post,
                  openComments: true,
                  heroTag: heroTag,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
