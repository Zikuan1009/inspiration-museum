import 'package:flutter/material.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// 每日信件。数据只来自 [DailyPush]（`fetchDailyPush` / RPC）。
///
/// 这不是 `inspirations` 帖子，没有 UUID，禁止查询 likes / saves / comments。
class DailyPushCard extends StatelessWidget {
  const DailyPushCard({super.key, required this.push});

  final DailyPush push;

  @override
  Widget build(BuildContext context) {
    final theme = push.themeName.trim();
    final subTheme = push.subThemeName.trim();
    final path = [
      if (theme.isNotEmpty) CommunityPost.themeLabel(theme),
      if (subTheme.isNotEmpty) CommunityPost.themeLabel(subTheme),
    ].join(' / ');

    final quote = push.quote.trim();
    final spoken = push.quoteAuthor.trim().isEmpty
        ? quote
        : '$quote  ——  ${push.quoteAuthor.trim()}';
    final imageUrl = push.imageUrl.trim();
    final pieces = <({String label, String title, String detail})>[
      if (push.musicTitle.trim().isNotEmpty)
        (
          label: "TODAY'S SONG",
          title: push.musicTitle.trim(),
          detail: push.musicArtist.trim(),
        ),
      if (push.cityName.trim().isNotEmpty)
        (
          label: "TODAY'S CITY",
          title: push.cityName.trim(),
          detail: push.cityCountry.trim(),
        ),
      if (push.buildingName.trim().isNotEmpty)
        (
          label: "TODAY'S BUILDING",
          title: push.buildingName.trim(),
          detail: push.buildingCity.trim(),
        ),
      if (push.filmTitle.trim().isNotEmpty)
        (
          label: "TODAY'S FILM",
          title: push.filmTitle.trim(),
          detail: push.filmDirector.trim(),
        ),
      if (push.bookTitle.trim().isNotEmpty)
        (
          label: "TODAY'S BOOK",
          title: push.bookTitle.trim(),
          detail: push.bookAuthor.trim(),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageUrl.startsWith('http')) ...[
          ClipRRect(
            borderRadius: CanvasRadius.imageAll,
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: CanvasColors.sunken),
              ),
            ),
          ),
          const SizedBox(height: CanvasSpace.xl),
        ],
        if (path.isNotEmpty) ...[
          Text(
            path.toUpperCase(),
            textAlign: TextAlign.center,
            style: CanvasType.overline,
          ),
          const SizedBox(height: CanvasSpace.lg),
        ],
        if (push.keyword.trim().isNotEmpty) ...[
          Text(
            push.keyword.trim(),
            textAlign: TextAlign.center,
            style: CanvasType.headline,
          ),
          const SizedBox(height: CanvasSpace.lg),
        ],
        if (quote.isNotEmpty) ...[
          Text(spoken, textAlign: TextAlign.center, style: CanvasType.quote),
          const SizedBox(height: CanvasSpace.lg),
        ],
        for (final piece in pieces) ...[
          _LetterPiece(
            label: piece.label,
            title: piece.title,
            detail: piece.detail,
          ),
          const SizedBox(height: CanvasSpace.lg),
        ],
        if (push.whyToday.trim().isNotEmpty) ...[
          Text(
            push.whyToday.trim(),
            textAlign: TextAlign.center,
            style: CanvasType.bodySmall.copyWith(
              color: CanvasColors.textSecondary,
            ),
          ),
          const SizedBox(height: CanvasSpace.md),
          Text(
            'Drafted by Nano  ·  Read by Ultra',
            textAlign: TextAlign.center,
            style: CanvasType.caption,
          ),
        ],
      ],
    );
  }
}

class _LetterPiece extends StatelessWidget {
  const _LetterPiece({
    required this.label,
    required this.title,
    required this.detail,
  });

  final String label;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, textAlign: TextAlign.center, style: CanvasType.overline),
        const SizedBox(height: CanvasSpace.sm),
        Text(title, textAlign: TextAlign.center, style: CanvasType.title),
        if (detail.trim().isNotEmpty) ...[
          const SizedBox(height: CanvasSpace.xs),
          Text(
            detail.trim(),
            textAlign: TextAlign.center,
            style: CanvasType.bodySmall.copyWith(
              color: CanvasColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
