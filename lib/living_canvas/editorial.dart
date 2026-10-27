import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/living_canvas/tokens.dart';
import 'package:inspiration_museum/living_canvas/typography.dart';

/// 细颗粒的材质感，叠在深色卡片或大块色面上。画面固定，只绘制一次。
class GrainTexture extends StatelessWidget {
  const GrainTexture({super.key, this.opacity = 0.06, this.seed = 7});

  final double opacity;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GrainPainter(opacity: opacity, seed: seed),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.opacity, required this.seed});

  final double opacity;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rng = math.Random(seed);
    final count = math.min(5000, (size.width * size.height / 55).round());
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final point = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      (i.isEven ? light : dark).add(point);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..strokeWidth = 1,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: opacity * 0.9)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.seed != seed;
}

/// 编辑排版的横向栏目切换。大写字距标签，选中时文字变深，
/// 下方细线从左展开。不使用胶囊按钮。
class EditorialTabs extends StatelessWidget {
  const EditorialTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: CanvasSpace.page),
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: labels.length,
      separatorBuilder: (_, _) => const SizedBox(width: CanvasSpace.xl),
      itemBuilder: (context, index) {
        final active = index == selected;
        void select() {
          if (active) return;
          HapticFeedback.selectionClick();
          onSelected(index);
        }

        return Semantics(
          button: true,
          selected: active ? true : null,
          label: labels[index],
          excludeSemantics: true,
          onTap: select,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: select,
            child: Center(
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: CanvasMotion.standard,
                      curve: CanvasMotion.standardCurve,
                      style: CanvasType.overline.copyWith(
                        fontSize: 11.5,
                        letterSpacing: 1.6,
                        color: active
                            ? CanvasColors.text
                            : CanvasColors.textSecondary,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: Text(labels[index].toUpperCase()),
                    ),
                    const SizedBox(height: 7),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: active ? 1 : 0),
                      duration: CanvasMotion.emphasized,
                      curve: CanvasMotion.enter,
                      builder: (context, value, child) => Transform.scale(
                        scaleX: value,
                        scaleY: 1,
                        alignment: Alignment.centerLeft,
                        child: child,
                      ),
                      child: const SizedBox(
                        height: 1.5,
                        child: ColoredBox(color: CanvasColors.forest),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 小方块色标加大写眉题，用于作品的领域标签。
class AccentLabel extends StatelessWidget {
  const AccentLabel({
    super.key,
    required this.text,
    required this.accent,
    this.color = CanvasColors.textSecondary,
  });

  final String text;
  final Color accent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 6, height: 6, child: ColoredBox(color: accent)),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CanvasType.overline.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
