import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/living_canvas/tokens.dart';
import 'package:inspiration_museum/living_canvas/typography.dart';

bool _reduceMotion(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// 按下时轻微缩小，松开回弹。给任何可点的块用，不改变点击行为。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = CanvasMotion.pressScale,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _down && !_reduceMotion(context) ? widget.scale : 1,
        duration: CanvasMotion.quick,
        curve: CanvasMotion.standardCurve,
        child: widget.child,
      ),
    );
  }
}

enum CanvasButtonVariant {
  /// 墨色实心。一屏一个主要动作。
  primary,

  /// 纸面底加细边。
  secondary,

  /// 只有文字。
  quiet,

  /// 森林绿实心，只给每日来信等需要被注意的动作。
  accent,
}

class CanvasButton extends StatelessWidget {
  const CanvasButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = CanvasButtonVariant.primary,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CanvasButtonVariant variant;
  final IconData? icon;
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final (Color fill, Color ink, Color? edge) = switch (variant) {
      CanvasButtonVariant.primary => (
        CanvasColors.text,
        CanvasColors.textOnInk,
        null,
      ),
      CanvasButtonVariant.secondary => (
        CanvasColors.surface,
        CanvasColors.text,
        CanvasColors.divider,
      ),
      CanvasButtonVariant.quiet => (
        Colors.transparent,
        CanvasColors.text,
        null,
      ),
      CanvasButtonVariant.accent => (
        CanvasColors.forest,
        CanvasColors.textOnInk,
        null,
      ),
    };
    final shownFill = enabled || variant == CanvasButtonVariant.quiet
        ? fill
        : CanvasColors.divider;
    final shownInk = enabled ? ink : CanvasColors.textSecondary;

    final content = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: shownInk),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: shownInk),
                const SizedBox(width: CanvasSpace.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CanvasType.label.copyWith(color: shownInk),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: CanvasMotion.standard,
          curve: CanvasMotion.standardCurve,
          height: 48,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: variant == CanvasButtonVariant.quiet
                ? CanvasSpace.md
                : CanvasSpace.xl,
          ),
          decoration: BoxDecoration(
            color: shownFill,
            borderRadius: CanvasRadius.buttonAll,
            border: edge == null ? null : Border.all(color: edge),
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

/// 纸面卡片。默认细边无阴影；[elevated] 用于浮在内容上方的卡片。
class CanvasCard extends StatelessWidget {
  const CanvasCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(CanvasSpace.lg),
    this.elevated = false,
    this.color = CanvasColors.surface,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: CanvasRadius.cardAll,
        border: elevated ? null : Border.all(color: CanvasColors.divider),
        boxShadow: elevated ? CanvasShadow.raised : CanvasShadow.none,
      ),
      child: ClipRRect(
        borderRadius: CanvasRadius.cardAll,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

/// 小标签：话题、内容种类、状态。传入 [accent] 时用该强调色的浅底。
class CanvasTag extends StatelessWidget {
  const CanvasTag({
    super.key,
    required this.label,
    this.accent,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final Color? accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color ink;
    final Color? edge;
    if (selected) {
      fill = CanvasColors.text;
      ink = CanvasColors.textOnInk;
      edge = null;
    } else if (accent != null) {
      fill = CanvasColors.tint(accent!);
      ink = CanvasColors.text;
      edge = null;
    } else {
      fill = CanvasColors.surface;
      ink = CanvasColors.text;
      edge = CanvasColors.divider;
    }
    final tag = AnimatedContainer(
      duration: CanvasMotion.quick,
      curve: CanvasMotion.standardCurve,
      padding: const EdgeInsets.symmetric(
        horizontal: CanvasSpace.sm + CanvasSpace.xxs,
        vertical: CanvasSpace.xs + 1,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: CanvasRadius.tagAll,
        border: edge == null ? null : Border.all(color: edge),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: CanvasType.caption.copyWith(
          color: ink,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    if (onTap == null) return tag;
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(onTap: onTap, child: tag),
    );
  }
}

/// 编辑排版的栏目头：小号眉题加衬线标题。
class EditorialHeading extends StatelessWidget {
  const EditorialHeading({
    super.key,
    required this.title,
    this.kicker,
    this.trailing,
    this.expressive = false,
  });

  final String title;
  final String? kicker;
  final Widget? trailing;
  final bool expressive;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kicker != null && kicker!.isNotEmpty) ...[
                Text(kicker!.toUpperCase(), style: CanvasType.overline),
                const SizedBox(height: CanvasSpace.xs + 2),
              ],
              Text(
                title,
                style: expressive ? CanvasType.expressive : CanvasType.headline,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: CanvasSpace.md),
          trailing!,
        ],
      ],
    );
  }
}

/// 缓慢漂移的渐变底。三团柔光沿不同周期移动，
/// 只用于每日来信和沉浸场景。系统要求减少动效时保持静止。
class GradientWash extends StatefulWidget {
  const GradientWash({
    super.key,
    this.colors = const [
      CanvasColors.forest,
      CanvasColors.mineral,
      CanvasColors.gold,
    ],
    this.base = CanvasColors.background,
    this.intensity = 0.55,
    this.borderRadius,
    this.child,
  });

  final List<Color> colors;
  final Color base;

  /// 0 到 1。越大颜色越浓。压文字时保持在 0.6 以下。
  final double intensity;
  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  State<GradientWash> createState() => _GradientWashState();
}

class _GradientWashState extends State<GradientWash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(vsync: this, duration: CanvasMotion.ambient);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wash = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _drift,
        builder: (context, child) => CustomPaint(
          painter: _WashPainter(
            phase: _drift.value,
            colors: widget.colors,
            base: widget.base,
            intensity: widget.intensity.clamp(0.0, 1.0),
          ),
          child: child,
        ),
        child: widget.child,
      ),
    );
    final radius = widget.borderRadius;
    if (radius == null) return wash;
    return ClipRRect(borderRadius: radius, child: wash);
  }
}

class _WashPainter extends CustomPainter {
  const _WashPainter({
    required this.phase,
    required this.colors,
    required this.base,
    required this.intensity,
  });

  final double phase;
  final List<Color> colors;
  final Color base;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    if (colors.isEmpty) return;
    final turn = phase * 2 * math.pi;
    final span = math.max(size.width, size.height);
    for (var i = 0; i < colors.length; i++) {
      final offset = i * 2.1;
      final center = Offset(
        size.width * (0.5 + 0.38 * math.sin(turn + offset)),
        size.height *
            (0.5 + 0.34 * math.cos(turn * (i.isEven ? 1 : -1) + offset * 1.3)),
      );
      final radius = span * (0.62 + 0.08 * math.sin(turn * 2 + i));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors[i].withValues(alpha: intensity),
              colors[i].withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WashPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.intensity != intensity ||
        oldDelegate.base != base ||
        !_sameColors(oldDelegate.colors, colors);
  }

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 进入时淡入并上移一点。列表里用 [index] 做依次进入。
class RevealIn extends StatefulWidget {
  const RevealIn({
    super.key,
    required this.child,
    this.index = 0,
    this.distance = 12,
    this.duration = CanvasMotion.emphasized,
    this.enabled = true,
  });

  final Widget child;
  final int index;
  final double distance;
  final Duration duration;

  /// 只在第一次插入时读取。为 false 时直接显示，用于已经出现过的内容。
  final bool enabled;

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _controller, curve: CanvasMotion.enter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || _reduceMotion(context)) {
      _controller.value = 1;
      return;
    }
    final steps = widget.index.clamp(0, 8);
    Future<void>.delayed(CanvasMotion.stagger * steps, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.distance * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// 加载占位：纸面略深一档的块，缓慢明暗呼吸。
class CanvasSkeleton extends StatefulWidget {
  const CanvasSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = CanvasRadius.imageAll,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<CanvasSkeleton> createState() => _CanvasSkeletonState();
}

class _CanvasSkeletonState extends State<CanvasSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            CanvasColors.sunken,
            CanvasColors.divider,
            CanvasMotion.drift.transform(_pulse.value),
          ),
          borderRadius: widget.borderRadius,
        ),
      ),
    );
  }
}
