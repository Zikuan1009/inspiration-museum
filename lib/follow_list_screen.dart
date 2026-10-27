import 'package:flutter/material.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/other_user_profile_screen.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 粉丝或关注名单。点进用户只打开他人主页，不能编辑对方资料。
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.followers,
  });

  final String userId;
  final bool followers;

  static Route<void> route({required String userId, required bool followers}) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) =>
          FollowListScreen(userId: userId, followers: followers),
      transitionsBuilder: (context, animation, secondary, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late final Future<List<UserModel>> _future;

  @override
  void initState() {
    super.initState();
    final db = SupabaseDBService.instance;
    _future = widget.followers
        ? db.fetchFollowers(widget.userId)
        : db.fetchFollowing(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.followers ? 'Followers' : 'Following';

    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Text('Back', style: CanvasType.label),
                  ),
                  const Spacer(),
                  Text(title, style: CanvasType.collectionTitle),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: FutureBuilder<List<UserModel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'The list did not load.',
                        style: CanvasType.body,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return Center(
                      child: Text('Loading…', style: CanvasType.caption),
                    );
                  }
                  final people = snapshot.data!;
                  if (people.isEmpty) {
                    return Center(
                      child: Text(
                        widget.followers
                            ? 'No followers yet'
                            : 'Not following anyone',
                        style: CanvasType.body.copyWith(
                          color: CanvasColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: people.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: CanvasColors.divider,
                    ),
                    itemBuilder: (context, index) {
                      final person = people[index];
                      return _PersonRow(
                        person: person,
                        onTap: () {
                          Navigator.of(context)
                              .push(OtherUserProfileScreen.route(person));
                        },
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});

  final UserModel person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appId = person.appId?.trim() ?? '';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              ProfilePhoto(
                seed: person.id,
                imageUrl: person.avatarUrl,
                size: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CanvasType.titleSmall,
                    ),
                    if (appId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        appId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CanvasType.caption,
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
  }
}
