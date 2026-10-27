import 'package:flutter/material.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/inspiration_detail_screen.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/visuals.dart';

/// 站外打开的分享页：先是一张信息卡片，点进去只能看这一篇，不能互动。
class SharedPostScreen extends StatefulWidget {
  const SharedPostScreen({super.key, required this.postId});

  final String postId;

  @override
  State<SharedPostScreen> createState() => _SharedPostScreenState();
}

class _SharedPostScreenState extends State<SharedPostScreen> {
  late final Future<CommunityPost?> _post;

  @override
  void initState() {
    super.initState();
    _post = SupabaseDBService.instance.fetchInspiration(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<CommunityPost?>(
          future: _post,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: BauhausLoadingFrame(width: 72, height: 72),
              );
            }
            final post = snapshot.data;
            if (snapshot.hasError || post == null) {
              return const Center(
                child: Text(
                  'This piece is not public.',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.6,
                    color: Colors.black,
                  ),
                ),
              );
            }
            return _ShareLanding(post: post);
          },
        ),
      ),
    );
  }
}

class _ShareLanding extends StatelessWidget {
  const _ShareLanding({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final title = post.title.trim().isNotEmpty
        ? post.title.trim()
        : (post.theme.trim().isEmpty ? 'INSPIRATION' : post.theme.trim());
    final quote = post.quote.trim();
    final keywords = post.keywords.join('  ×  ');
    final image = post.imagePath?.trim() ?? '';
    final hasImage =
        image.startsWith('http://') || image.startsWith('https://');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'INSPIRATION MUSEUM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 22),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).push(
                    PostDetailScreen.route(post, readOnly: true),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasImage)
                        Image.network(
                          image,
                          height: 210,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 210,
                            child: ColoredBox(color: Color(0xFF3A3A3A)),
                          ),
                        )
                      else
                        const SizedBox(
                          height: 210,
                          child: ColoredBox(color: Color(0xFF3A3A3A)),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                height: 1.3,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                              ),
                            ),
                            if (quote.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                CommunityPost.quotedText(quote),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                            if (keywords.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                keywords,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: Color(0xFF9A9A9A),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 1, color: Colors.black),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Open the piece',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
