import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/auth_session.dart';
import 'package:inspiration_museum/chat_tab.dart';
import 'package:inspiration_museum/home_tab.dart';
import 'package:inspiration_museum/inspiration_detail_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/profile_tab.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/chat_message.dart';

/// App 根容器：三个 Tab（首页 / 聊天 / 我的）+ 底部导航。
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.openPostId});

  final String? openPostId;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  int _profileToken = 0;
  AuthSession? _session;
  bool _openedShare = false;
  late final Stream<List<ChatSessionModel>> _chats;

  @override
  void initState() {
    super.initState();
    final me = AuthService.instance.currentUser?.id ?? '';
    _chats = me.isEmpty
        ? Stream<List<ChatSessionModel>>.value(const [])
        : SupabaseDBService.instance.getChatSessionsStream(me);
    final postId = widget.openPostId;
    if (postId == null || postId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openSharedPost(postId);
    });
  }

  Future<void> _openSharedPost(String postId) async {
    if (_openedShare || !mounted) return;
    _openedShare = true;
    final post = await SupabaseDBService.instance.fetchInspiration(postId);
    if (!mounted || post == null) return;
    await Navigator.of(context).push(PostDetailScreen.route(post));
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
    if (!mounted) return;
    if (_session?.isSignedIn != true && _index != 0) {
      setState(() => _index = 0);
    }
  }

  Future<void> _onTap(int i) async {
    if (i == _index) return;
    if (i != 0) {
      final ok = await AuthScreen.require(context);
      if (!ok || !mounted) return;
    }
    setState(() {
      if (i == 2) _profileToken++;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(active: _index == 0, onOpenProfile: () => _onTap(2)),
          const ChatTab(),
          ProfileTab(key: ValueKey('profile-$_profileToken')),
        ],
      ),
      bottomNavigationBar: StreamBuilder<List<ChatSessionModel>>(
        stream: _chats,
        builder: (context, snapshot) {
          final hasUnread = (snapshot.data ?? const <ChatSessionModel>[]).any(
            (session) => session.unreadCount > 0,
          );
          return _MuseumNavBar(
            index: _index,
            onTap: _onTap,
            items: [
              const _NavItem(_Glyph.home, 'Home'),
              _NavItem(_Glyph.chat, 'Chat', alert: hasUnread),
              const _NavItem(_Glyph.profile, 'Profile'),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 底部导航
// ---------------------------------------------------------------------------

enum _Glyph { home, chat, profile }

class _NavItem {
  const _NavItem(this.glyph, this.label, {this.alert = false});

  final _Glyph glyph;
  final String label;
  final bool alert;
}

class _MuseumNavBar extends StatelessWidget {
  const _MuseumNavBar({
    required this.index,
    required this.onTap,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CanvasColors.background,
        border: Border(top: BorderSide(color: CanvasColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    active: i == index,
                    onTap: () {
                      if (i != index) HapticFeedback.selectionClick();
                      onTap(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active ? true : null,
      label: item.alert ? '${item.label}, new messages' : item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: CanvasMotion.standard,
          curve: CanvasMotion.standardCurve,
          builder: (context, t, _) {
            final ink = Color.lerp(
              CanvasColors.textSecondary,
              CanvasColors.text,
              t,
            )!;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 18 * t,
                    height: 1.5,
                    child: const ColoredBox(color: CanvasColors.forest),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: const Size(24, 24),
                        painter: _GlyphPainter(
                          glyph: item.glyph,
                          color: ink,
                          fill: t,
                        ),
                      ),
                      if (item.alert)
                        const Positioned(
                          top: 1,
                          right: -1,
                          child: SizedBox(
                            width: 7,
                            height: 7,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: CanvasColors.terracotta,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.label.toUpperCase(),
                  style: CanvasType.overline.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 1.6,
                    color: ink,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 细线图标。选中时用 [fill] 把内部铺上一层淡淡的森林绿。
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.glyph,
    required this.color,
    required this.fill,
  });

  final _Glyph glyph;
  final Color color;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final wash = Paint()
      ..color = CanvasColors.forest.withValues(alpha: 0.16 * fill);

    switch (glyph) {
      case _Glyph.home:
        // 一张画布：外框，加一道地平线和一轮小太阳。
        final frame = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.16, s * 0.18, s * 0.68, s * 0.64),
          const Radius.circular(2),
        );
        canvas.drawRRect(frame, wash);
        canvas.drawRRect(frame, stroke);
        canvas.drawLine(
          Offset(s * 0.16, s * 0.62),
          Offset(s * 0.84, s * 0.62),
          stroke,
        );
        canvas.drawCircle(Offset(s * 0.62, s * 0.40), s * 0.07, stroke);
      case _Glyph.chat:
        final bubble = Path()
          ..moveTo(s * 0.2, s * 0.22)
          ..lineTo(s * 0.8, s * 0.22)
          ..quadraticBezierTo(s * 0.86, s * 0.22, s * 0.86, s * 0.28)
          ..lineTo(s * 0.86, s * 0.60)
          ..quadraticBezierTo(s * 0.86, s * 0.66, s * 0.8, s * 0.66)
          ..lineTo(s * 0.44, s * 0.66)
          ..lineTo(s * 0.28, s * 0.80)
          ..lineTo(s * 0.28, s * 0.66)
          ..lineTo(s * 0.2, s * 0.66)
          ..quadraticBezierTo(s * 0.14, s * 0.66, s * 0.14, s * 0.60)
          ..lineTo(s * 0.14, s * 0.28)
          ..quadraticBezierTo(s * 0.14, s * 0.22, s * 0.2, s * 0.22)
          ..close();
        canvas.drawPath(bubble, wash);
        canvas.drawPath(bubble, stroke);
      case _Glyph.profile:
        final head = Offset(s * 0.5, s * 0.36);
        canvas.drawCircle(head, s * 0.14, wash);
        canvas.drawCircle(head, s * 0.14, stroke);
        final shoulders = Path()
          ..moveTo(s * 0.22, s * 0.82)
          ..quadraticBezierTo(s * 0.24, s * 0.56, s * 0.5, s * 0.56)
          ..quadraticBezierTo(s * 0.76, s * 0.56, s * 0.78, s * 0.82);
        canvas.drawPath(shoulders, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.fill != fill;
}
