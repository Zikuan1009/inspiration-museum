import 'package:flutter/material.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/daily_push_card.dart';
import 'package:inspiration_museum/envelope_stage.dart';
import 'package:inspiration_museum/inspiration_editor_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/db_service.dart';

String _storedDate(String raw) {
  final text = raw.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (match == null) return text;
  return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
}

/// 草稿箱：选出一封存过的信，用它的关键词和名言开始写。
class LetterDraftsScreen extends StatefulWidget {
  const LetterDraftsScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      transitionDuration: CanvasMotion.standard,
      reverseTransitionDuration: CanvasMotion.quick,
      pageBuilder: (context, animation, secondary) =>
          const LetterDraftsScreen(),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: CanvasMotion.enter,
            reverseCurve: CanvasMotion.exit,
          ),
          child: child,
        );
      },
    );
  }

  @override
  State<LetterDraftsScreen> createState() => _LetterDraftsScreenState();
}

class _LetterDraftsScreenState extends State<LetterDraftsScreen> {
  late final Future<List<LetterDraft>> _drafts = SupabaseDBService.instance
      .fetchLetterDrafts();

  Future<void> _open(LetterDraft draft) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: CanvasMotion.emphasized,
        reverseTransitionDuration: CanvasMotion.standard,
        pageBuilder: (context, animation, secondary) =>
            _StoredLetterScreen(draft: draft),
        transitionsBuilder: (context, animation, secondary, child) {
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
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
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
            const _DraftBar(title: 'Drafts'),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: FutureBuilder<List<LetterDraft>>(
                future: _drafts,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CanvasSpace.xl),
                        child: Text(
                          'Drafts could not be loaded.',
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
                          CanvasSkeleton(height: 180),
                          SizedBox(height: CanvasSpace.lg),
                          CanvasSkeleton(height: 18, width: 120),
                        ],
                      ),
                    );
                  }
                  final drafts = snapshot.data!;
                  if (drafts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(CanvasSpace.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'No drafts yet.',
                            textAlign: TextAlign.center,
                            style: CanvasType.collectionTitle,
                          ),
                          const SizedBox(height: CanvasSpace.sm),
                          Text(
                            'Letters you save appear here.',
                            textAlign: TextAlign.center,
                            style: CanvasType.body.copyWith(
                              color: CanvasColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      CanvasSpace.page,
                      CanvasSpace.xl,
                      CanvasSpace.page,
                      CanvasSpace.xxxl,
                    ),
                    itemCount: drafts.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CanvasSpace.xxl),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      final keyword = draft.push.keyword.trim();
                      final storedOn = _storedDate(draft.letterDate);
                      return Pressable(
                        onTap: () => _open(draft),
                        child: Column(
                          children: [
                            AspectRatio(
                              aspectRatio:
                                  1 / ClosedEnvelopeGraphic.aspectRatio,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // 右下折线从底角收到中点。日期贴着底边时，
                                  // 这条线离右缘的距离不随信封宽度变化。
                                  const bottom = 16.0;
                                  const textHeight = 16.0;
                                  const flap = 0.56;
                                  final height =
                                      constraints.maxWidth *
                                      ClosedEnvelopeGraphic.aspectRatio;
                                  if (height <= 0) {
                                    return const ClosedEnvelopeGraphic();
                                  }
                                  final creaseFromRight =
                                      (constraints.maxWidth / 2) *
                                      ((bottom + textHeight) / (height * flap));
                                  return Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      const ClosedEnvelopeGraphic(),
                                      if (storedOn.isNotEmpty)
                                        Positioned(
                                          right: creaseFromRight + 18,
                                          bottom: bottom,
                                          child: Text(
                                            storedOn,
                                            style: CanvasType.caption.copyWith(
                                              fontSize: 11,
                                              height: 1,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.6,
                                              color: CanvasColors.text,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: CanvasSpace.md),
                            Text(
                              keyword,
                              textAlign: TextAlign.center,
                              style: CanvasType.collectionTitle,
                            ),
                          ],
                        ),
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

class _StoredLetterScreen extends StatelessWidget {
  const _StoredLetterScreen({required this.draft});

  final LetterDraft draft;

  Future<void> _write(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        pageBuilder: (context, animation, secondary) => InspirationEditorScreen(
          keywords: draft.push.creationKeywords,
          quote: draft.push.quote,
        ),
        transitionsBuilder: (context, animation, secondary, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: CanvasMotion.enter,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storedOn = _storedDate(draft.letterDate);
    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _DraftBar(title: storedOn.isEmpty ? 'Draft' : storedOn),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  CanvasSpace.page,
                  CanvasSpace.xl,
                  CanvasSpace.page,
                  CanvasSpace.xxxl,
                ),
                children: [
                  DailyPushCard(push: draft.push),
                  const SizedBox(height: CanvasSpace.xl),
                  Center(
                    child: CanvasButton(
                      label: 'Write a reflection',
                      variant: CanvasButtonVariant.secondary,
                      onPressed: () => _write(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftBar extends StatelessWidget {
  const _DraftBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CanvasSpace.page,
        CanvasSpace.md,
        CanvasSpace.page,
        CanvasSpace.md,
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Back', style: CanvasType.label),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CanvasType.collectionTitle,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}
