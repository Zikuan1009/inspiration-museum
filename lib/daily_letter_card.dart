import 'package:flutter/material.dart';
import 'package:inspiration_museum/daily_discovery/discovery_backdrop.dart';
import 'package:inspiration_museum/daily_discovery/discovery_palette.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// 首页顶部的每日灵感卡片。内容来自已经准备好的那封信，
/// 点击后从卡片原位展开成全屏的每日灵感页。
class DailyLetterCard extends StatelessWidget {
  const DailyLetterCard({super.key, required this.push, required this.onOpen});

  /// 还在加载时为 null，卡片只显示骨架，不显示任何临时文字。
  final DailyPush? push;
  final VoidCallback? onOpen;

  /// 大字号设置下卡片跟着长高一些，文字不必挤在原来的高度里。
  static double heightFor(
    double width, [
    TextScaler scaler = TextScaler.noScaling,
  ]) {
    final base = (width * 0.74).clamp(248.0, 340.0);
    final grow = (scaler.scale(16) / 16).clamp(1.0, 1.5);
    return base * grow;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      button: onOpen != null,
      label: 'Open Daily Inspiration',
      onTap: onOpen,
      excludeSemantics: push == null,
      child: Pressable(
        onTap: onOpen,
        scale: 0.975,
        child: LayoutBuilder(
          builder: (context, box) {
            return Container(
              height: heightFor(box.maxWidth, scaler),
              decoration: const BoxDecoration(
                borderRadius: CanvasRadius.cardAll,
                boxShadow: CanvasShadow.raised,
              ),
              child: ClipRRect(
                borderRadius: CanvasRadius.cardAll,
                child: DailyLetterFace(push: push),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 卡片的画面本身，不含点击和阴影。展开动画开始时用它画出一模一样的卡片。
class DailyLetterFace extends StatelessWidget {
  const DailyLetterFace({super.key, required this.push, this.textOpacity = 1});

  final DailyPush? push;
  final double textOpacity;

  /// Stock fallback is a starting prompt, not a prepared letter.
  static String discoveryLabel(DailyPush? push, DateTime now) {
    final kind = push != null && push.isStockFallback
        ? 'STARTING PROMPT'
        : "TODAY'S DISCOVERY";
    return '$kind  ·  ${dateLabel(now)}';
  }

  static String dateLabel(DateTime now) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[now.month - 1]} ${now.day}';
  }

  static String pieceLabel(DailyPush push) {
    if (push.musicTitle.trim().isNotEmpty) return "TODAY'S SONG";
    if (push.cityName.trim().isNotEmpty) return "TODAY'S CITY";
    if (push.buildingName.trim().isNotEmpty) return "TODAY'S BUILDING";
    if (push.filmTitle.trim().isNotEmpty) return "TODAY'S FILM";
    if (push.bookTitle.trim().isNotEmpty) return "TODAY'S BOOK";
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final letter = push;
    final palette = letter == null
        ? DiscoveryPalette.deepForest
        : DiscoveryPalette.of(letter);
    final imageUrl = letter?.imageUrl.trim() ?? '';
    final seed = CanvasColors.stableHash(letter?.keyword ?? '');
    final hasImage = imageUrl.startsWith('http');
    return Stack(
      fit: StackFit.expand,
      children: [
        DiscoveryBackdrop(palette: palette, seed: seed, quiet: hasImage),
        if (hasImage) _LetterImage(url: imageUrl, palette: palette),
        if (textOpacity > 0)
          Opacity(
            opacity: textOpacity.clamp(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 20, 18),
              child: letter == null
                  ? _LetterSkeleton(palette: palette)
                  : _LetterText(
                      push: letter,
                      palette: palette,
                      pieceLabel: pieceLabel(letter),
                    ),
            ),
          ),
      ],
    );
  }
}

class _LetterText extends StatelessWidget {
  const _LetterText({
    required this.push,
    required this.palette,
    required this.pieceLabel,
  });

  final DailyPush push;
  final DiscoveryPalette palette;
  final String pieceLabel;

  @override
  Widget build(BuildContext context) {
    final keyword = push.keyword.trim();
    final quote = push.quote.trim();
    final piece = push.pieceTitle;
    final detail = push.pieceDetail;
    final ink = palette.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Inspiration',
          style: CanvasType.brand.copyWith(fontSize: 22, color: ink),
        ),
        const SizedBox(height: 6),
        Text(
          DailyLetterFace.discoveryLabel(push, DateTime.now()),
          style: CanvasType.overline.copyWith(color: palette.accent),
        ),
        // 关键词和名言贴着下沿排；高度不够时从上方裁掉，不会溢出卡片。
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (keyword.isNotEmpty)
                  Text(
                    keyword,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.hero.copyWith(color: ink),
                  ),
                if (quote.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '“$quote”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CanvasType.quote.copyWith(
                      fontSize: 15.5,
                      height: 1.45,
                      color: ink.withValues(alpha: 0.86),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: pieceLabel.isEmpty || piece.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pieceLabel,
                          style: CanvasType.overline.copyWith(
                            color: palette.accent,
                            fontSize: 9.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detail.isEmpty ? piece : '$piece — $detail',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CanvasType.caption.copyWith(
                            color: ink.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: CanvasSpace.md),
            Flexible(child: _OpenAffordance(palette: palette)),
          ],
        ),
      ],
    );
  }
}

class _OpenAffordance extends StatelessWidget {
  const _OpenAffordance({required this.palette});

  final DiscoveryPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.ink.withValues(alpha: 0.08),
        borderRadius: CanvasRadius.buttonAll,
        border: Border.all(color: palette.accent.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Explore',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CanvasType.label.copyWith(
                fontSize: 12.5,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward, size: 15, color: palette.ink),
        ],
      ),
    );
  }
}

class _LetterSkeleton extends StatelessWidget {
  const _LetterSkeleton({required this.palette});

  final DiscoveryPalette palette;

  @override
  Widget build(BuildContext context) {
    final bar = palette.ink.withValues(alpha: 0.14);
    Widget line(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: bar, borderRadius: CanvasRadius.tagAll),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Inspiration',
          style: CanvasType.brand.copyWith(fontSize: 22, color: palette.ink),
        ),
        const SizedBox(height: 8),
        line(110, 9),
        const Spacer(),
        line(180, 26),
        const SizedBox(height: 12),
        line(double.infinity, 12),
        const SizedBox(height: 8),
        line(160, 12),
        const SizedBox(height: 22),
      ],
    );
  }
}

class _LetterImage extends StatelessWidget {
  const _LetterImage({required this.url, required this.palette});

  final String url;
  final DiscoveryPalette palette;

  @override
  Widget build(BuildContext context) {
    final deep = palette.deep;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: CanvasMotion.reveal,
              curve: CanvasMotion.enter,
              child: child,
            );
          },
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                deep.withValues(alpha: 0.4),
                deep.withValues(alpha: 0.2),
                deep.withValues(alpha: 0.9),
              ],
              stops: const [0, 0.4, 1],
            ),
          ),
        ),
      ],
    );
  }
}
