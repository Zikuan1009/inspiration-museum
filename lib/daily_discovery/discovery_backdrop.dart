import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/daily_discovery/discovery_palette.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// 每日灵感的背景：色调渐变上的一组抽象构成（一块色面、一圈细环、
/// 一道竖条、几根目录线）。位置由 [seed] 决定，同一封信在卡片和全屏页里
/// 构图一致。[drift] 给出时，色面和细环会极慢地漂移。
class DiscoveryBackdrop extends StatelessWidget {
  const DiscoveryBackdrop({
    super.key,
    required this.palette,
    required this.seed,
    this.drift,
    this.grain = true,
    this.quiet = false,
  });

  final DiscoveryPalette palette;
  final int seed;
  final Animation<double>? drift;
  final bool grain;

  /// 图片当主角时只留渐变和很淡的构成，不和图片抢。
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final drift = this.drift;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: palette.gradient)),
        RepaintBoundary(
          child: CustomPaint(
            painter: DiscoveryCompositionPainter(
              palette: palette,
              seed: seed,
              drift: drift,
              quiet: quiet,
            ),
          ),
        ),
        if (grain)
          GrainTexture(opacity: palette.isLight ? 0.035 : 0.05, seed: seed),
      ],
    );
  }
}

class DiscoveryCompositionPainter extends CustomPainter {
  DiscoveryCompositionPainter({
    required this.palette,
    required this.seed,
    this.drift,
    this.quiet = false,
  }) : super(repaint: drift);

  final DiscoveryPalette palette;
  final int seed;
  final Animation<double>? drift;
  final bool quiet;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rng = math.Random(seed);
    final w = size.width;
    final h = size.height;
    final unit = math.min(w, h);
    final phase = (drift?.value ?? 0) * 2 * math.pi;
    final sway = Offset(math.sin(phase), math.cos(phase)) * unit * 0.025;
    final strength = quiet ? 0.45 : 1.0;
    final light = palette.isLight;

    final discCenter =
        Offset(
          w * (0.62 + rng.nextDouble() * 0.26),
          h * (0.56 + rng.nextDouble() * 0.28),
        ) +
        sway;
    final discRadius = unit * (0.62 + rng.nextDouble() * 0.22);
    canvas.drawCircle(
      discCenter,
      discRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.shape.withValues(alpha: (light ? 0.42 : 0.5) * strength),
            palette.shape.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: discCenter, radius: discRadius)),
    );

    final ringCenter =
        Offset(
          w * (0.70 + rng.nextDouble() * 0.16),
          h * (0.12 + rng.nextDouble() * 0.18),
        ) -
        sway * 0.6;
    final ringRadius = unit * (0.42 + rng.nextDouble() * 0.14);
    final ringColor = light ? palette.ink : palette.accent;
    canvas.drawCircle(
      ringCenter,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ringColor.withValues(alpha: (light ? 0.16 : 0.42) * strength),
    );
    canvas.drawCircle(
      ringCenter,
      ringRadius * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = ringColor.withValues(alpha: (light ? 0.1 : 0.22) * strength),
    );

    if (!quiet) {
      // 竖条只放在右上方的留白里，避免穿过标题文字。
      final barX = w * (0.88 + rng.nextDouble() * 0.04);
      canvas.drawRect(
        Rect.fromLTWH(barX, h * 0.13, 3, h * (0.10 + rng.nextDouble() * 0.08)),
        Paint()..color = palette.bar.withValues(alpha: 0.85),
      );
    }

    final rule = Paint()
      ..color = (light ? palette.ink : palette.accent).withValues(
        alpha: (light ? 0.1 : 0.16) * strength,
      )
      ..strokeWidth = 0.6;
    for (var i = 0; i < 4; i++) {
      final y = h * (0.64 + i * 0.03);
      canvas.drawLine(Offset(w * 0.6, y), Offset(w, y), rule);
    }
  }

  @override
  bool shouldRepaint(covariant DiscoveryCompositionPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.seed != seed ||
      oldDelegate.quiet != quiet ||
      oldDelegate.drift != drift;
}
