import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/chat_list_prefs.dart';
import 'package:inspiration_museum/chat_message.dart';
import 'package:inspiration_museum/chat_room_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/peer_remark.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';

/// 会话列表。数据、排序、未读和置顶隐藏都沿用原来的逻辑，只换呈现。
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  static String formatStamp(DateTime time, {DateTime? now}) {
    final local = time.toLocal();
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final month = local.month.toString().padLeft(2, '0');
    final date = local.day.toString().padLeft(2, '0');
    return '$month/$date';
  }

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  late final Stream<List<ChatSessionModel>> _chatStream;
  final Map<String, DateTime> _openedAt = <String, DateTime>{};
  final Map<String, String> _remarks = <String, String>{};
  final Set<String> _pins = <String>{};
  final Map<String, int> _hiddenAt = <String, int>{};
  String? _activePeerId;
  String? _revealedPeerId;

  @override
  void initState() {
    super.initState();
    final me = AuthService.instance.currentUser?.id ?? '';
    _chatStream = me.isEmpty
        ? Stream<List<ChatSessionModel>>.value(const [])
        : SupabaseDBService.instance.getChatSessionsStream(me);
    _loadRemarks();
    _loadListPrefs();
  }

  Future<void> _loadListPrefs() async {
    final pins = await ChatListPrefs.pins();
    final hidden = await ChatListPrefs.hidden();
    if (!mounted) return;
    setState(() {
      _pins
        ..clear()
        ..addAll(pins);
      _hiddenAt
        ..clear()
        ..addAll(hidden);
    });
  }

  bool _isHidden(ChatSessionModel session) {
    final mark = _hiddenAt[session.peer.id];
    if (mark == null) return false;
    return session.lastAt.microsecondsSinceEpoch <= mark;
  }

  Future<void> _togglePin(ChatSessionModel session) async {
    final peerId = session.peer.id;
    final next = !_pins.contains(peerId);
    setState(() {
      if (next) {
        _pins.add(peerId);
      } else {
        _pins.remove(peerId);
      }
      _revealedPeerId = null;
    });
    await ChatListPrefs.setPinned(peerId, next);
  }

  Future<void> _hideSession(ChatSessionModel session) async {
    final peerId = session.peer.id;
    setState(() {
      _hiddenAt[peerId] = session.lastAt.microsecondsSinceEpoch;
      _pins.remove(peerId);
      _revealedPeerId = null;
    });
    await ChatListPrefs.hide(peerId, session.lastAt);
    await ChatListPrefs.setPinned(peerId, false);
  }

  Future<void> _loadRemarks() async {
    final notes = await PeerRemarks.load();
    if (!mounted) return;
    setState(() {
      _remarks
        ..clear()
        ..addAll(notes);
    });
  }

  DateTime _markOpened(String peerId, {DateTime? lastAt}) {
    final now = DateTime.now();
    final stamp = lastAt != null && lastAt.isAfter(now) ? lastAt : now;
    _openedAt[peerId] = stamp;
    _activePeerId = peerId;
    return stamp;
  }

  int _visibleUnread(ChatSessionModel session) {
    final peerId = session.peer.id;
    if (session.unreadCount <= 0 || session.lastUnreadAt == null) return 0;
    if (_activePeerId == peerId) return 0;
    final opened = _openedAt[peerId];
    if (opened != null && !session.lastUnreadAt!.isAfter(opened)) return 0;
    return session.unreadCount;
  }

  Future<void> _openSession(ChatSessionModel session) async {
    final peerId = session.peer.id;
    final me = AuthService.instance.currentUser?.id ?? '';
    setState(() => _markOpened(peerId, lastAt: session.lastAt));
    if (me.isNotEmpty) {
      unawaited(SupabaseDBService.instance.markMessagesAsRead(me, peerId));
    }
    if (!mounted) return;
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(ChatRoomScreen.route(peer: session.peer));
    if (me.isNotEmpty) {
      await SupabaseDBService.instance.markMessagesAsRead(me, peerId);
    }
    if (!mounted) return;
    await _loadRemarks();
    if (!mounted) return;
    setState(() {
      _markOpened(peerId);
      _activePeerId = null;
    });
  }

  Widget _sessionRow(ChatSessionModel session) {
    final peerId = session.peer.id;
    final revealed = _revealedPeerId == peerId;
    return _SwipeRow(
      key: ValueKey(peerId),
      revealed: revealed,
      onRevealed: (open) {
        setState(() {
          if (open) {
            _revealedPeerId = peerId;
          } else if (_revealedPeerId == peerId) {
            _revealedPeerId = null;
          }
        });
      },
      pinned: _pins.contains(peerId),
      onPin: () => _togglePin(session),
      onDelete: () => _hideSession(session),
      child: _SessionTile(
        session: session,
        unreadOverride: _visibleUnread(session),
        remark: _remarks[peerId] ?? '',
        pinned: _pins.contains(peerId),
        onOpen: () {
          if (_revealedPeerId == peerId) {
            setState(() => _revealedPeerId = null);
            return;
          }
          _openSession(session);
        },
      ),
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
                CanvasSpace.page,
                CanvasSpace.lg,
                CanvasSpace.page,
                CanvasSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MESSAGES', style: CanvasType.overline),
                  const SizedBox(height: 2),
                  Text('Messages', style: CanvasType.section),
                ],
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: StreamBuilder<List<ChatSessionModel>>(
                stream: _chatStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CanvasSpace.xl),
                        child: Text(
                          'Messages could not be loaded.',
                          textAlign: TextAlign.center,
                          style: CanvasType.body,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(CanvasSpace.page),
                      child: Column(
                        children: [
                          CanvasSkeleton(height: 64),
                          SizedBox(height: CanvasSpace.md),
                          CanvasSkeleton(height: 64),
                          SizedBox(height: CanvasSpace.md),
                          CanvasSkeleton(height: 64),
                        ],
                      ),
                    );
                  }
                  final sessions = [...snapshot.data!]
                    ..sort((a, b) => b.lastAt.compareTo(a.lastAt));
                  final visible = sessions
                      .where((session) => !_isHidden(session))
                      .toList();
                  if (visible.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(CanvasSpace.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'No conversations yet.',
                            textAlign: TextAlign.center,
                            style: CanvasType.collectionTitle,
                          ),
                          const SizedBox(height: CanvasSpace.sm),
                          Text(
                            'Open a profile, then send a message.',
                            textAlign: TextAlign.center,
                            style: CanvasType.body.copyWith(
                              color: CanvasColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  int byRecent(ChatSessionModel a, ChatSessionModel b) =>
                      b.lastAt.compareTo(a.lastAt);
                  final pinned =
                      visible
                          .where((session) => _pins.contains(session.peer.id))
                          .toList()
                        ..sort(byRecent);
                  final rest =
                      visible
                          .where((session) => !_pins.contains(session.peer.id))
                          .toList()
                        ..sort(byRecent);
                  final rows = <ChatSessionModel>[...pinned, ...rest];
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: CanvasSpace.lg),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final session = rows[index];
                      final showPinned = index == 0 && pinned.isNotEmpty;
                      final showOthers =
                          pinned.isNotEmpty && index == pinned.length;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showPinned) const _ListLabel('Pinned'),
                          if (showOthers) const _ListLabel('All messages'),
                          _sessionRow(session),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListLabel extends StatelessWidget {
  const _ListLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CanvasSpace.page,
        CanvasSpace.lg,
        CanvasSpace.page,
        CanvasSpace.xs,
      ),
      child: Text(text.toUpperCase(), style: CanvasType.overline),
    );
  }
}

class _SwipeRow extends StatefulWidget {
  const _SwipeRow({
    super.key,
    required this.revealed,
    required this.onRevealed,
    required this.pinned,
    required this.onPin,
    required this.onDelete,
    required this.child,
  });

  final bool revealed;
  final ValueChanged<bool> onRevealed;
  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<_SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<_SwipeRow> {
  static const _reveal = 148.0;
  double _offset = 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant _SwipeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.revealed && !_dragging) _offset = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_reveal, 0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity < -500 || (velocity <= 500 && _offset < -_reveal / 2);
    setState(() {
      _dragging = false;
      _offset = open ? -_reveal : 0;
    });
    widget.onRevealed(open);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final closed = _offset == 0 && !widget.revealed;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: closed,
              child: ExcludeSemantics(
                excluding: closed,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SwipeAction(
                      label: widget.pinned ? 'Unpin' : 'Pin',
                      filled: false,
                      onTap: widget.onPin,
                    ),
                    _SwipeAction(
                      label: 'Hide',
                      filled: true,
                      onTap: widget.onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: _dragging || reduce ? Duration.zero : CanvasMotion.quick,
            curve: CanvasMotion.standardCurve,
            transform: Matrix4.translationValues(_offset, 0, 0),
            color: CanvasColors.background,
            child: SizedBox(
              width: double.infinity,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: () {
                  setState(() {
                    _dragging = false;
                    _offset = widget.revealed ? -_reveal : 0;
                  });
                },
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: filled ? CanvasColors.forest : CanvasColors.sunken,
          child: SizedBox(
            width: 74,
            child: Center(
              child: Text(
                label,
                style: CanvasType.label.copyWith(
                  color: filled ? CanvasColors.textOnInk : CanvasColors.text,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.onOpen,
    this.unreadOverride,
    this.remark = '',
    this.pinned = false,
  });

  final ChatSessionModel session;
  final VoidCallback onOpen;
  final int? unreadOverride;
  final String remark;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final peer = session.peer;
    final unread = unreadOverride ?? session.unreadCount;
    final hasUnread = unread > 0;
    final noted = remark.trim();
    final name = noted.isEmpty ? peer.username : noted;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Pressable(
      onTap: onOpen,
      child: Semantics(
        button: true,
        label: hasUnread ? '$name, $unread unread' : name,
        excludeSemantics: true,
        onTap: onOpen,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CanvasColors.divider)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CanvasSpace.page,
              CanvasSpace.md,
              CanvasSpace.page,
              CanvasSpace.md,
            ),
            child: Row(
              children: [
                ProfilePhoto(seed: peer.id, imageUrl: peer.avatarUrl, size: 44),
                const SizedBox(width: CanvasSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (pinned) ...[
                            const Icon(
                              Icons.push_pin_outlined,
                              size: 14,
                              color: CanvasColors.forest,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CanvasType.titleSmall.copyWith(
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        session.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.bodySmall.copyWith(
                          color: hasUnread
                              ? CanvasColors.text
                              : CanvasColors.textSecondary,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CanvasSpace.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ChatTab.formatStamp(session.lastAt),
                      style: CanvasType.caption,
                    ),
                    const SizedBox(height: 6),
                    AnimatedOpacity(
                      duration: reduce ? Duration.zero : CanvasMotion.quick,
                      opacity: hasUnread ? 1 : 0,
                      child: AnimatedContainer(
                        duration: reduce ? Duration.zero : CanvasMotion.quick,
                        curve: CanvasMotion.standardCurve,
                        height: 18,
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hasUnread
                              ? CanvasColors.forest
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: CanvasType.caption.copyWith(
                            fontSize: 11,
                            color: CanvasColors.textOnInk,
                            height: 1,
                          ),
                        ),
                      ),
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
