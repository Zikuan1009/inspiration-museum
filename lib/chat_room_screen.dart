import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/chat_message.dart';
import 'package:inspiration_museum/chat_tab.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/inspiration_detail_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/other_user_profile_screen.dart';
import 'package:inspiration_museum/peer_remark.dart';
import 'package:inspiration_museum/post_share.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 会话详情。发送、已读和贴底逻辑不变，只换气泡、顶栏和输入区的呈现。
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.currentUserId,
    required this.peerId,
    this.peerName = '',
    this.peer,
  });

  final String currentUserId;
  final String peerId;
  final String peerName;
  final UserModel? peer;

  static Route<void> route({
    UserModel? peer,
    String? currentUserId,
    String? peerId,
    String? peerName,
  }) {
    final me = currentUserId ?? AuthService.instance.currentUser?.id ?? '';
    final other = peerId ?? peer?.id ?? '';
    final name = peerName ?? peer?.username ?? '';
    return _ChatRoomRoute(
      pageBuilder: (context, animation, secondary) => ChatRoomScreen(
        currentUserId: me,
        peerId: other,
        peerName: name,
        peer: peer,
      ),
    );
  }

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  late final Stream<List<Map<String, dynamic>>> _messagesStream;
  final List<ChatMessage> _pending = [];
  int _lastCount = -1;
  bool _sending = false;
  bool _pinBottom = true;
  UserModel? _peer;
  String _remark = '';

  @override
  void initState() {
    super.initState();
    _peer = widget.peer;
    _messagesStream = SupabaseDBService.instance.getMessagesStream(
      widget.currentUserId,
      widget.peerId,
    );
    _markRead();
    _loadPeer();
    _loadRemark();
  }

  Future<void> _loadRemark() async {
    final notes = await PeerRemarks.load();
    if (!mounted) return;
    setState(() => _remark = notes[widget.peerId] ?? '');
  }

  Future<void> _loadPeer() async {
    if (widget.peerId.isEmpty) return;
    try {
      final latest = await SupabaseDBService.instance.fetchProfile(
        widget.peerId,
      );
      if (!mounted || latest == null) return;
      setState(() => _peer = latest);
    } catch (_) {}
  }

  void _openPeerProfile() {
    final id = _peer?.id ?? widget.peerId;
    if (id.isEmpty) return;
    final named = _peer?.username.trim() ?? '';
    final fallback = widget.peerName.trim();
    final user =
        _peer ??
        UserModel(
          id: id,
          username: named.isNotEmpty
              ? named
              : (fallback.isNotEmpty ? fallback : 'ANON'),
          avatarUrl: '',
          bio: '',
          followersCount: 0,
          followingCount: 0,
        );
    Navigator.of(context).push(OtherUserProfileScreen.route(user));
  }

  String get _peerTitle {
    final remark = _remark.trim();
    if (remark.isNotEmpty) return remark;
    final name = _peer?.username.trim() ?? '';
    if (name.isNotEmpty && name != 'ANON') return name;
    final fallback = widget.peerName.trim();
    if (fallback.isNotEmpty) return fallback;
    return 'MESSAGE';
  }

  Future<void> _editRemark() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CanvasColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: CanvasRadius.sheetTop),
      builder: (context) => _RemarkSheet(initial: _remark),
    );
    if (saved == null || !mounted) return;
    await PeerRemarks.save(widget.peerId, saved);
    if (!mounted) return;
    setState(() => _remark = saved.trim());
  }

  void _markRead() {
    if (widget.currentUserId.isEmpty || widget.peerId.isEmpty) return;
    unawaited(
      SupabaseDBService.instance.markMessagesAsRead(
        widget.currentUserId,
        widget.peerId,
      ),
    );
  }

  @override
  void dispose() {
    _markRead();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ChatMessage> _visibleMessages(List<ChatMessage> remote) {
    _pending.removeWhere(
      (local) => remote.any(
        (item) =>
            item.id == local.id ||
            (item.text == local.text &&
                item.senderId == local.senderId &&
                item.timestamp.difference(local.timestamp).inSeconds.abs() < 8),
      ),
    );
    final seen = <String>{};
    final merged = <ChatMessage>[...remote, ..._pending]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final unique = <ChatMessage>[];
    for (final item in merged) {
      final key = item.id.isNotEmpty
          ? item.id
          : '${item.senderId}-${item.timestamp.millisecondsSinceEpoch}-${item.text}';
      if (!seen.add(key)) continue;
      unique.add(item);
    }
    return unique;
  }

  void _maybeMarkRead(List<ChatMessage> remote) {
    final hasIncomingUnread = remote.any(
      (item) =>
          item.senderId == widget.peerId &&
          item.receiverId == widget.currentUserId &&
          item.isRead == false,
    );
    if (hasIncomingUnread) _markRead();
  }

  void _stickToBottom(int count) {
    if (count == 0 || count == _lastCount) return;
    final pin = _pinBottom || _lastCount < 0;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // reverse 列表的 0 是视觉底部。打开时、自己发送时、以及本来就停在底部时贴底。
      final nearBottom = _scroll.position.pixels <= 48;
      if (!pin && !nearBottom) return;
      _pinBottom = false;
      _scroll.jumpTo(0);
    });
  }

  void _keepKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (widget.currentUserId.isEmpty || widget.peerId.isEmpty) return;
    final keepKeyboard = _inputFocus.hasFocus;
    _input.clear();
    _pinBottom = true;
    final local = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderId: widget.currentUserId,
      receiverId: widget.peerId,
      text: text,
      timestamp: DateTime.now(),
      isRead: true,
    );
    setState(() {
      _pending.add(local);
      _sending = true;
    });
    if (keepKeyboard) _keepKeyboard();
    try {
      await SupabaseDBService.instance.sendMessage(
        widget.currentUserId,
        widget.peerId,
        text,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _pending.remove(local));
      }
      if (!mounted) return;
      _input.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: CanvasColors.forest,
          content: Text(
            'The message was not sent.',
            style: CanvasType.bodySmall.copyWith(color: CanvasColors.textOnInk),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
      if (keepKeyboard) _keepKeyboard();
    }
  }

  static bool _sameGroup(ChatMessage older, ChatMessage newer) {
    if (older.senderId != newer.senderId) return false;
    return newer.timestamp.difference(older.timestamp).inMinutes.abs() <= 8;
  }

  @override
  Widget build(BuildContext context) {
    final title = _peerTitle == 'MESSAGE' ? 'Conversation' : _peerTitle;
    return Scaffold(
      backgroundColor: CanvasColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 22,
                      color: CanvasColors.text,
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openPeerProfile,
                    child: ProfilePhoto(
                      seed: widget.peerId,
                      imageUrl: _peer?.avatarUrl,
                      size: 32,
                      border: false,
                    ),
                  ),
                  const SizedBox(width: CanvasSpace.sm),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openPeerProfile,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.titleSmall,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Private note',
                    onPressed: _editRemark,
                    icon: const Icon(
                      Icons.more_horiz,
                      color: CanvasColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _messagesStream,
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
                  if (snapshot.hasData) {
                    final remote = [
                      for (final row in snapshot.data!)
                        ChatMessage.fromSupabase(row),
                    ];
                    _maybeMarkRead(remote);
                    final messages = _visibleMessages(remote);
                    _stickToBottom(messages.length);
                    if (messages.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(CanvasSpace.xxl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'No messages yet.',
                                textAlign: TextAlign.center,
                                style: CanvasType.collectionTitle,
                              ),
                              const SizedBox(height: CanvasSpace.sm),
                              Text(
                                'Type a message to start.',
                                textAlign: TextAlign.center,
                                style: CanvasType.body.copyWith(
                                  color: CanvasColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        CanvasSpace.page,
                        CanvasSpace.md,
                        CanvasSpace.page,
                        CanvasSpace.lg,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final index = messages.length - 1 - i;
                        final msg = messages[index];
                        final older = index > 0 ? messages[index - 1] : null;
                        final newer = index < messages.length - 1
                            ? messages[index + 1]
                            : null;
                        final joinAbove =
                            older != null && _sameGroup(older, msg);
                        final joinBelow =
                            newer != null && _sameGroup(msg, newer);
                        final mine = msg.senderId == widget.currentUserId;
                        final postId = PostShareLink.postIdOf(msg.text);
                        final child = postId != null
                            ? _MiniPostMessage(
                                postId: postId,
                                mine: mine,
                                time: ChatTab.formatStamp(msg.timestamp),
                                peerId: widget.peerId,
                                avatarUrl: _peer?.avatarUrl ?? '',
                                onAvatarTap: _openPeerProfile,
                                joinBelow: joinBelow,
                              )
                            : _Bubble(
                                message: msg,
                                mine: mine,
                                peerId: widget.peerId,
                                avatarUrl: _peer?.avatarUrl ?? '',
                                onAvatarTap: _openPeerProfile,
                                joinAbove: joinAbove,
                                joinBelow: joinBelow,
                              );
                        final slot = msg.id.isNotEmpty
                            ? msg.id
                            : '${msg.senderId}-${msg.timestamp.microsecondsSinceEpoch}';
                        final keyed = KeyedSubtree(
                          key: ValueKey(slot),
                          child: child,
                        );
                        if (!msg.id.startsWith('local-')) return keyed;
                        return _SentMessage(key: ValueKey(slot), child: child);
                      },
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(CanvasSpace.page),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CanvasSkeleton(width: 180, height: 36),
                        ),
                        SizedBox(height: CanvasSpace.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: CanvasSkeleton(width: 140, height: 36),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            _Composer(
              controller: _input,
              focusNode: _inputFocus,
              onSend: _send,
              enabled: !_sending,
            ),
          ],
        ),
      ),
    );
  }
}

class _SentMessage extends StatefulWidget {
  const _SentMessage({super.key, required this.child});

  final Widget child;

  @override
  State<_SentMessage> createState() => _SentMessageState();
}

class _SentMessageState extends State<_SentMessage> {
  var _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _visible) return;
      if (MediaQuery.disableAnimationsOf(context)) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final shown = reduce || _visible;
    return AnimatedSlide(
      offset: shown ? Offset.zero : const Offset(0.03, 0.2),
      duration: reduce ? Duration.zero : CanvasMotion.quick,
      curve: CanvasMotion.enter,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: reduce ? Duration.zero : CanvasMotion.quick,
        curve: CanvasMotion.enter,
        child: widget.child,
      ),
    );
  }
}

class _MessageFrame extends StatelessWidget {
  const _MessageFrame({
    required this.mine,
    required this.joinBelow,
    required this.time,
    required this.peerId,
    required this.avatarUrl,
    required this.onAvatarTap,
    required this.child,
  });

  final bool mine;
  final bool joinBelow;
  final String time;
  final String peerId;
  final String avatarUrl;
  final VoidCallback onAvatarTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showAvatar = !mine && !joinBelow;
    return Padding(
      padding: EdgeInsets.only(bottom: joinBelow ? 2 : 10),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: showAvatar
                      ? _PeerAvatar(
                          peerId: peerId,
                          avatarUrl: avatarUrl,
                          onTap: onAvatarTap,
                        )
                      : null,
                ),
                const SizedBox(width: CanvasSpace.sm),
              ],
              Flexible(child: child),
            ],
          ),
          if (!joinBelow)
            Padding(
              padding: EdgeInsets.only(top: 4, left: mine ? 0 : 40),
              child: Text(time, style: CanvasType.caption),
            ),
        ],
      ),
    );
  }
}

BorderRadius _bubbleRadius({
  required bool mine,
  required bool joinAbove,
  required bool joinBelow,
}) {
  const wide = Radius.circular(CanvasRadius.card);
  const tight = Radius.circular(3);
  if (mine) {
    return BorderRadius.only(
      topLeft: wide,
      bottomLeft: wide,
      topRight: joinAbove ? tight : wide,
      bottomRight: joinBelow ? tight : wide,
    );
  }
  return BorderRadius.only(
    topRight: wide,
    bottomRight: wide,
    topLeft: joinAbove ? tight : wide,
    bottomLeft: joinBelow ? tight : wide,
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.peerId,
    required this.avatarUrl,
    required this.onAvatarTap,
    required this.joinAbove,
    required this.joinBelow,
  });

  final ChatMessage message;
  final bool mine;
  final String peerId;
  final String avatarUrl;
  final VoidCallback onAvatarTap;
  final bool joinAbove;
  final bool joinBelow;

  @override
  Widget build(BuildContext context) {
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mine ? CanvasColors.forest : CanvasColors.sunken,
          borderRadius: _bubbleRadius(
            mine: mine,
            joinAbove: joinAbove,
            joinBelow: joinBelow,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CanvasSpace.md,
            vertical: CanvasSpace.sm,
          ),
          child: SelectableText(
            message.text,
            style: CanvasType.body.copyWith(
              height: 1.45,
              color: mine ? CanvasColors.textOnInk : CanvasColors.text,
            ),
          ),
        ),
      ),
    );

    return _MessageFrame(
      mine: mine,
      joinBelow: joinBelow,
      time: ChatTab.formatStamp(message.timestamp),
      peerId: peerId,
      avatarUrl: avatarUrl,
      onAvatarTap: onAvatarTap,
      child: bubble,
    );
  }
}

class _MiniPostMessage extends StatefulWidget {
  const _MiniPostMessage({
    required this.postId,
    required this.mine,
    required this.time,
    required this.peerId,
    required this.avatarUrl,
    required this.onAvatarTap,
    required this.joinBelow,
  });

  final String postId;
  final bool mine;
  final String time;
  final String peerId;
  final String avatarUrl;
  final VoidCallback onAvatarTap;
  final bool joinBelow;

  @override
  State<_MiniPostMessage> createState() => _MiniPostMessageState();
}

class _MiniPostMessageState extends State<_MiniPostMessage> {
  late final Future<CommunityPost?> _post;

  @override
  void initState() {
    super.initState();
    _post = SupabaseDBService.instance.fetchInspiration(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: FutureBuilder<CommunityPost?>(
        future: _post,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CanvasSkeleton(width: 220, height: 96);
          }
          final post = snapshot.data;
          if (post == null) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: CanvasColors.surface,
                borderRadius: CanvasRadius.cardAll,
                border: Border.all(color: CanvasColors.divider),
              ),
              child: Padding(
                padding: const EdgeInsets.all(CanvasSpace.md),
                child: Text(
                  'This piece could not be opened.',
                  style: CanvasType.bodySmall,
                ),
              ),
            );
          }
          final image = post.imagePath?.trim() ?? '';
          final hasImage =
              image.startsWith('http://') || image.startsWith('https://');
          final quote = post.quote.trim();
          final keywords = post.keywords
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .join(' · ');
          final title = post.title.trim();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.of(context).push(PostDetailScreen.route(post));
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CanvasColors.surface,
                borderRadius: CanvasRadius.cardAll,
                border: Border.all(color: CanvasColors.divider),
              ),
              child: ClipRRect(
                borderRadius: CanvasRadius.cardAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasImage)
                      Image.network(
                        image,
                        height: 112,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 72,
                          child: ColoredBox(color: CanvasColors.sunken),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CanvasSpace.md,
                        CanvasSpace.sm,
                        CanvasSpace.md,
                        CanvasSpace.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (keywords.isNotEmpty)
                            Text(
                              keywords.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CanvasType.overline,
                            ),
                          if (quote.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              CommunityPost.quotedText(quote),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: CanvasType.bodySmall.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          if (title.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CanvasType.titleSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    return _MessageFrame(
      mine: widget.mine,
      joinBelow: widget.joinBelow,
      time: widget.time,
      peerId: widget.peerId,
      avatarUrl: widget.avatarUrl,
      onAvatarTap: widget.onAvatarTap,
      child: card,
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool enabled;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  var _hasText = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    _focused = widget.focusNode.hasFocus;
    widget.controller.addListener(_onText);
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _onText();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
      _onFocus();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next == _hasText) return;
    setState(() => _hasText = next);
  }

  void _onFocus() {
    final next = widget.focusNode.hasFocus;
    if (next == _focused) return;
    setState(() => _focused = next);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final ready = widget.enabled && _hasText;
    final motion = reduce ? Duration.zero : CanvasMotion.quick;
    return AnimatedSize(
      duration: motion,
      curve: CanvasMotion.standardCurve,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CanvasSpace.page,
          CanvasSpace.sm,
          CanvasSpace.md,
          CanvasSpace.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: motion,
                curve: CanvasMotion.standardCurve,
                decoration: BoxDecoration(
                  color: CanvasColors.sunken,
                  borderRadius: CanvasRadius.inputAll,
                  border: Border.all(
                    color: _focused ? CanvasColors.forest : Colors.transparent,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.md),
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  cursorColor: CanvasColors.forest,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onEditingComplete: () {
                    widget.onSend();
                    widget.focusNode.requestFocus();
                  },
                  style: CanvasType.body.copyWith(height: 1.4),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Type a message',
                    hintStyle: CanvasType.body.copyWith(
                      color: CanvasColors.textSecondary,
                      height: 1.4,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: CanvasSpace.md,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: CanvasSpace.sm),
            Semantics(
              button: true,
              label: 'Send',
              enabled: ready,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: ready ? widget.onSend : null,
                child: AnimatedContainer(
                  duration: motion,
                  curve: CanvasMotion.standardCurve,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ready ? CanvasColors.forest : CanvasColors.sunken,
                    borderRadius: CanvasRadius.buttonAll,
                  ),
                  child: Text(
                    'Send',
                    style: CanvasType.label.copyWith(
                      color: ready
                          ? CanvasColors.textOnInk
                          : CanvasColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({
    required this.peerId,
    required this.avatarUrl,
    required this.onTap,
  });

  final String peerId;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ProfilePhoto(
        seed: peerId,
        imageUrl: avatarUrl,
        size: 32,
        border: false,
      ),
    );
  }
}

class _RemarkSheet extends StatefulWidget {
  const _RemarkSheet({required this.initial});

  final String initial;

  @override
  State<_RemarkSheet> createState() => _RemarkSheetState();
}

class _RemarkSheetState extends State<_RemarkSheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CanvasSpace.page,
        CanvasSpace.lg,
        CanvasSpace.page,
        CanvasSpace.lg + inset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PRIVATE NOTE', style: CanvasType.overline),
          const SizedBox(height: 2),
          Text('Private note', style: CanvasType.title),
          const SizedBox(height: CanvasSpace.lg),
          TextField(
            controller: _field,
            autofocus: true,
            maxLength: 24,
            cursorColor: CanvasColors.forest,
            style: CanvasType.titleSmall,
            decoration: InputDecoration(
              counterText: '',
              hintText: 'A private note about this person',
              hintStyle: CanvasType.body.copyWith(
                color: CanvasColors.textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: CanvasColors.divider),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: CanvasColors.forest, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: CanvasSpace.lg),
          Align(
            alignment: Alignment.centerRight,
            child: CanvasButton(
              label: 'Save',
              onPressed: () => Navigator.of(context).pop(_field.text.trim()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRoomRoute extends PageRouteBuilder<void> {
  _ChatRoomRoute({required super.pageBuilder})
    : super(
        transitionDuration: CanvasMotion.standard,
        reverseTransitionDuration: CanvasMotion.quick,
      );

  @override
  Duration get transitionDuration => _motion(super.transitionDuration);

  @override
  Duration get reverseTransitionDuration =>
      _motion(super.reverseTransitionDuration);

  Duration _motion(Duration fallback) {
    final ctx = navigator?.context;
    if (ctx != null && MediaQuery.disableAnimationsOf(ctx)) {
      return Duration.zero;
    }
    return fallback;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: CanvasMotion.enter,
      reverseCurve: CanvasMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
