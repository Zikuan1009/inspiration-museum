import 'package:flutter/material.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/chat_message.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/share_page.dart';
import 'package:share_plus/share_plus.dart';

String postShareLabel(CommunityPost post) {
  final text = post.text.trim();
  if (text.isNotEmpty) {
    final line = text.split('\n').first.trim();
    if (line.isEmpty) {
      return post.theme.trim().isEmpty ? 'INSPIRATION' : post.theme.trim();
    }
    return line.length > 40 ? '${line.substring(0, 40)}…' : line;
  }
  final theme = post.theme.trim();
  return theme.isEmpty ? 'INSPIRATION' : theme;
}

/// 与详情页相同的转发：站内好友，或生成图片分享到其他 App。
Future<void> showPostShareSheet(
  BuildContext context, {
  required CommunityPost post,
}) async {
  if (!post.isCloudPost) return;
  final ok = await AuthScreen.require(context);
  if (!ok || !context.mounted) return;
  final me = AuthService.instance.currentUser?.id ?? '';
  if (me.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: CanvasColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: CanvasRadius.sheetTop),
    builder: (sheetContext) {
      return _ShareSheet(
        post: post,
        currentUserId: me,
        shareText: postShareLabel(post),
        onSent: () {
          Navigator.of(sheetContext).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: CanvasColors.forest,
              content: Text(
                'Sent',
                style: CanvasType.bodySmall.copyWith(
                  color: CanvasColors.textOnInk,
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.post,
    required this.currentUserId,
    required this.shareText,
    required this.onSent,
  });

  final CommunityPost post;
  final String currentUserId;
  final String shareText;
  final VoidCallback onSent;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final Stream<List<ChatSessionModel>> _sessions;
  bool _friendsOpen = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _sessions = SupabaseDBService.instance.getChatSessionsStream(
      widget.currentUserId,
    );
  }

  Future<void> _sendTo(String receiverId) async {
    if (_sending || receiverId.isEmpty) return;
    setState(() => _sending = true);
    final ok = await SupabaseDBService.instance.sharePostToFriend(
      widget.post.id,
      widget.currentUserId,
      receiverId,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) return;
    widget.onSent();
  }

  Future<void> _shareOutside() async {
    await SupabaseDBService.instance.recordRepost(
      widget.post.id,
      widget.currentUserId,
    );
    final post = widget.post;
    final title = post.title.trim().isNotEmpty
        ? post.title.trim()
        : widget.shareText;
    final quote = post.quote.trim();
    try {
      final url = await SupabaseDBService.instance.publishSharePage(
        post.id,
        SharePage.bytes(post),
      );
      final text = [
        title,
        if (quote.isNotEmpty) CommunityPost.quotedText(quote),
        url,
      ].join('\n');
      await Share.share(text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: CanvasColors.forest,
          content: Text(
            'The link was not created: $error',
            style: CanvasType.bodySmall.copyWith(color: CanvasColors.textOnInk),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CanvasSpace.page,
          CanvasSpace.lg,
          CanvasSpace.page,
          CanvasSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SHARE', style: CanvasType.overline),
            const SizedBox(height: 2),
            Text('Share', style: CanvasType.title),
            const SizedBox(height: CanvasSpace.lg),
            _ShareAction(
              label: 'Send to a member',
              onTap: () => setState(() => _friendsOpen = !_friendsOpen),
            ),
            if (_friendsOpen) ...[
              const SizedBox(height: CanvasSpace.md),
              SizedBox(
                height: 88,
                child: StreamBuilder<List<ChatSessionModel>>(
                  stream: _sessions,
                  builder: (context, snapshot) {
                    final sessions = snapshot.data ?? const [];
                    if (snapshot.hasError) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Contacts could not be loaded.',
                          style: CanvasType.bodySmall,
                        ),
                      );
                    }
                    if (sessions.isEmpty) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No recent contacts',
                          style: CanvasType.bodySmall.copyWith(
                            color: CanvasColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: CanvasSpace.md),
                      itemBuilder: (context, index) {
                        final peer = sessions[index].peer;
                        return Pressable(
                          onTap: _sending ? null : () => _sendTo(peer.id),
                          child: SizedBox(
                            width: 64,
                            child: Column(
                              children: [
                                ProfilePhoto(
                                  seed: peer.id,
                                  imageUrl: peer.avatarUrl,
                                  size: 48,
                                  border: false,
                                ),
                                const SizedBox(height: CanvasSpace.xs),
                                Text(
                                  peer.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: CanvasType.caption.copyWith(
                                    color: CanvasColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: CanvasSpace.sm),
            _ShareAction(label: 'Share to another app', onTap: _shareOutside),
          ],
        ),
      ),
    );
  }
}

class _ShareAction extends StatelessWidget {
  const _ShareAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CanvasSpace.md),
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
    );
  }
}
