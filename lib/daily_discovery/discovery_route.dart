import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/daily_discovery/discovery_motion.dart';
import 'package:inspiration_museum/daily_letter_card.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// 从首页卡片原位展开成全屏的路由，返回时沿原路收回卡片。
///
/// 展开过程中先画一张和首页一模一样的卡片，随矩形长大逐渐交给全屏页；
/// 矩形始终包住原卡片的位置，所以首页上的卡片不必隐藏。
class DiscoveryRoute<T> extends PageRoute<T> {
  DiscoveryRoute({
    required this.push,
    required this.origin,
    required this.builder,
    super.settings,
  });

  final DailyPush push;

  /// 卡片在屏幕上的位置。为 null 时从屏幕中央一张卡片大小处展开。
  final Rect? origin;
  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 580);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 440);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final covered = _RecedeBehind(animation: secondaryAnimation, child: child);
    if (discoveryReduceMotion(context)) {
      return FadeTransition(opacity: animation, child: covered);
    }
    return _CardExpansion(
      animation: animation,
      origin: origin,
      push: push,
      child: covered,
    );
  }
}

class _CardExpansion extends StatefulWidget {
  const _CardExpansion({
    required this.animation,
    required this.origin,
    required this.push,
    required this.child,
  });

  final Animation<double> animation;
  final Rect? origin;
  final DailyPush push;
  final Widget child;

  @override
  State<_CardExpansion> createState() => _CardExpansionState();
}

class _CardExpansionState extends State<_CardExpansion> {
  static const _emphasized = Cubic(0.2, 0, 0, 1);

  late CurvedAnimation _curve = _build();

  CurvedAnimation _build() => CurvedAnimation(
    parent: widget.animation,
    curve: _emphasized,
    reverseCurve: _emphasized.flipped,
  );

  @override
  void didUpdateWidget(covariant _CardExpansion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curve.dispose();
      _curve = _build();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  static double _span(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    // 路由浮层挂在 MaterialApp 的兜底文字样式下，那是一条黄色双下划线。
    // 展开中的卡片不在 Material 里，文字会把这条线继承下来，直到飞行结束。
    // 先把装饰收成 none，再画这些字。
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: LayoutBuilder(
        builder: (context, box) {
          final full = Offset.zero & box.biggest;
          final start = _startRect(full);
          return AnimatedBuilder(
            animation: _curve,
            child: widget.child,
            builder: (context, child) {
              final t = _curve.value;
              final settled = t >= 1;
              final rect = Rect.lerp(start, full, t)!;
              final radius = ui.lerpDouble(CanvasRadius.card, 0, t)!;
              final pageOpacity = Curves.easeOut.transform(
                _span(t, 0.18, 0.62),
              );
              final cardText = 1 - _span(t, 0, 0.28);
              final lift = 1 - _span(t, 0.5, 1);
              // 页面始终在同一个带 key 的位置上，展开结束前后不会被重建。
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (!settled)
                    Positioned.fromRect(
                      key: const ValueKey('card-face'),
                      rect: rect,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(34, 35, 31, 0.22 * lift),
                              blurRadius: 40,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: DailyLetterFace(
                            push: widget.push,
                            textOpacity: cardText,
                          ),
                        ),
                      ),
                    ),
                  ClipPath(
                    key: const ValueKey('page'),
                    clipper: _RectClipper(rect, radius),
                    clipBehavior: settled ? Clip.none : Clip.antiAlias,
                    child: Opacity(opacity: pageOpacity, child: child),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Rect _startRect(Rect full) {
    final origin = widget.origin;
    if (origin != null && origin.overlaps(full) && !origin.isEmpty) {
      return origin;
    }
    final width = full.width - CanvasSpace.page * 2;
    return Rect.fromCenter(
      center: full.center,
      width: width,
      height: DailyLetterCard.heightFor(width),
    );
  }
}

class _RectClipper extends CustomClipper<Path> {
  const _RectClipper(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  bool shouldReclip(covariant _RectClipper oldClipper) =>
      oldClipper.rect != rect || oldClipper.radius != radius;
}

/// 写作页盖上来时，每日灵感页稍稍后退并压暗，像被推到纸面下方。
class _RecedeBehind extends StatelessWidget {
  const _RecedeBehind({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final s = CanvasMotion.standardCurve.transform(animation.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(scale: 1 - 0.05 * s, child: child),
            if (s > 0)
              IgnorePointer(
                child: ColoredBox(color: Color.fromRGBO(18, 20, 18, 0.35 * s)),
              ),
          ],
        );
      },
    );
  }
}
