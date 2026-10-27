import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inspiration_museum/community_feed.dart';
import 'package:inspiration_museum/curation_backstage_screen.dart';
import 'package:inspiration_museum/daily_discovery/daily_discovery_screen.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/main.dart' show ArchiveStore;
import 'package:inspiration_museum/other_user_profile_screen.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';

/// 首页：刊物版面（[CommunityFeed]），顶部是每日灵感卡片。
///
/// 点卡片时，全屏的每日灵感页从卡片原位展开（[DailyDiscoveryScreen]），
/// 关闭时收回卡片。每天第一次进入首页时自动展开一次。
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, this.active = true, this.onOpenProfile});

  /// 当前是否正在显示首页。自动展开只在首页可见时发生。
  final bool active;

  /// 刊头头像。切到「我的」分页，由外层决定是否需要先登录。
  final VoidCallback? onOpenProfile;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _searchBusy = false;
  String? _searchNotice;
  Timer? _noticeTimer;
  int _themeEpoch = 0;
  int _feedEpoch = 0;
  String _postQuery = '';
  bool _entryReady = false;
  bool _autoOpenPending = false;
  bool _letterOpen = false;
  late Future<DailyPush> _dailyPush;
  final _letterCardKey = GlobalKey();
  static final _digits = RegExp(r'^\d+$');

  @override
  void initState() {
    super.initState();
    _dailyPush = _loadDailyPush();
    _prepareEntry();
    unawaited(SupabaseDBService.instance.prepareUpcomingLetter());
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _autoOpenIfPending();
  }

  Future<void> _prepareEntry() async {
    final opened = await ArchiveStore.hasOpenedLetterToday();
    if (!mounted) return;
    if (!opened) {
      await ArchiveStore.markLetterOpenedToday();
      if (!mounted) return;
      _autoOpenPending = true;
    }
    setState(() => _entryReady = true);
    if (_autoOpenPending) _autoOpenIfPending();
  }

  /// 今天第一次来：等信准备好、卡片排好版，再从卡片展开。
  Future<void> _autoOpenIfPending() async {
    if (!_autoOpenPending || !widget.active) return;
    final push = await _dailyPush;
    if (!mounted || !_autoOpenPending || !widget.active) return;
    _autoOpenPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openLetter(push);
    });
  }

  Future<DailyPush> _loadDailyPush() {
    final userId = AuthService.instance.currentUser?.id ?? '';
    return SupabaseDBService.instance.fetchDailyPush(userId);
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  /// 卡片此刻在屏幕上的位置。卡片已经滚出屏幕时返回 null，从中央展开。
  Rect? _cardRect() {
    final box = _letterCardKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    if (!rect.overlaps(screen)) return null;
    return rect;
  }

  Future<void> _openLetter(DailyPush push) async {
    if (_letterOpen) return;
    _letterOpen = true;
    final published = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(DailyDiscoveryScreen.route(push: push, origin: _cardRect()));
    _letterOpen = false;
    if (!mounted || published != true) return;
    // 刚发布的那篇要能在版面里看到。
    setState(() => _feedEpoch++);
  }

  /// 整段都是数字时按馆员号找人；否则按内容筛选相关帖子。
  String? _appIdOnly(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (_digits.hasMatch(trimmed)) return trimmed;
    final compact = trimmed.replaceAll(RegExp(r'[\s-]'), '');
    if (compact.isNotEmpty && compact != trimmed && _digits.hasMatch(compact)) {
      return compact;
    }
    return null;
  }

  Future<void> _onSearch(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _noticeTimer?.cancel();
      setState(() {
        _postQuery = '';
        _searchNotice = null;
        _searchBusy = false;
      });
      return;
    }
    final appId = _appIdOnly(trimmed);
    if (appId != null) {
      await _searchByAppId(appId);
      return;
    }
    _noticeTimer?.cancel();
    setState(() {
      _postQuery = trimmed;
      _searchNotice = null;
      _searchBusy = false;
    });
  }

  Future<void> _searchByAppId(String query) async {
    _noticeTimer?.cancel();
    setState(() {
      _searchBusy = true;
      _searchNotice = null;
    });
    try {
      final found = await SupabaseDBService.instance.searchUserByAppId(query);
      if (!mounted) return;
      if (found == null) {
        _flashNotice('Member not found');
        return;
      }
      setState(() => _searchBusy = false);
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push<void>(OtherUserProfileScreen.route(found));
    } catch (_) {
      if (!mounted) return;
      _flashNotice('Member not found');
    }
  }

  Future<void> _openBackstage() async {
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      CurationBackstageScreen.route(
        onSaveThemes: ArchiveStore.completeOnboarding,
      ),
    );
    if (!mounted) return;
    setState(() {
      _feedEpoch++;
      if (changed == true) {
        _themeEpoch++;
        _dailyPush = _loadDailyPush();
      }
    });
  }

  void _flashNotice(String text) {
    setState(() {
      _searchBusy = false;
      _searchNotice = text;
    });
    _noticeTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _searchNotice = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_entryReady) {
      return const ColoredBox(color: CanvasColors.background);
    }
    return CommunityFeed(
      key: ValueKey('feed-$_themeEpoch-$_feedEpoch'),
      onOpenLetter: _openLetter,
      letterCardKey: _letterCardKey,
      onSearchSubmitted: _onSearch,
      postQuery: _postQuery,
      searchNotice: _searchNotice,
      searchBusy: _searchBusy,
      onReselectFields: _openBackstage,
      dailyPush: _dailyPush,
      onOpenProfile: widget.onOpenProfile,
    );
  }
}
