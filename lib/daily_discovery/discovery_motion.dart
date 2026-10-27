import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

bool discoveryReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 在 [parent] 的 [begin]–[end] 区间里走完 0→1。
/// 用 drive 而不是 CurvedAnimation：重建时反复创建也不会在父动画上留下监听。
Animation<double> discoveryInterval(
  Animation<double> parent,
  double begin,
  double end, [
  Curve curve = CanvasMotion.enter,
]) {
  return parent.drive(
    CurveTween(
      curve: Interval(begin.clamp(0.0, 1.0), end.clamp(0.0, 1.0), curve: curve),
    ),
  );
}

/// 文字从一道看不见的下沿里升上来：外层裁切，内层按自身高度平移。
/// 结束时没有任何变换，最终文字和普通 Text 完全一样。
class MaskRise extends StatelessWidget {
  const MaskRise({
    super.key,
    required this.progress,
    required this.child,
    this.scaleFrom = 1,
  });

  final Animation<double> progress;
  final Widget child;

  /// 升起时从这个比例缩回 1，给大字一点重量感。
  final double scaleFrom;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: progress,
        child: child,
        builder: (context, child) {
          final t = progress.value;
          if (t >= 1) return child!;
          final scale = scaleFrom + (1 - scaleFrom) * t;
          return FractionalTranslation(
            translation: Offset(0, 1 - t),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomLeft,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// 自上而下的显影：一条柔和的边从段落顶部扫到底部，同时轻轻上移。
/// 不拆字，中文、英文、长段落都一样可用。
class WipeReveal extends StatelessWidget {
  const WipeReveal({
    super.key,
    required this.progress,
    required this.child,
    this.rise = 14,
  });

  final Animation<double> progress;
  final Widget child;
  final double rise;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = progress.value;
        if (t >= 1) return child!;
        if (t <= 0) return Opacity(opacity: 0, child: child);
        const soft = 0.18;
        final edge = -soft + t * (1 + soft);
        return Transform.translate(
          offset: Offset(0, rise * (1 - t)),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.white, Color(0x00FFFFFF)],
              stops: [edge.clamp(0.0, 1.0), (edge + soft).clamp(0.0, 1.0)],
            ).createShader(bounds),
            child: child,
          ),
        );
      },
    );
  }
}

/// 只做一次的入场：第一次滚进视口时开始自己的动画，之后不再重播。
/// 减少动态效果时直接显示。
class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 820),
    this.trigger = 0.88,
  });

  final Widget Function(BuildContext context, Animation<double> progress)
  builder;
  final Duration duration;

  /// 顶边进入视口高度的这个比例以内时开始。
  final double trigger;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (discoveryReduceMotion(context)) {
      _controller.value = 1;
      _detach();
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _detach();
      _position = position;
      _position?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _detach() {
    _position?.removeListener(_check);
    _position = null;
  }

  void _check() {
    if (!mounted || _controller.status != AnimationStatus.dismissed) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final height = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;
    if (viewport == null || top < height * widget.trigger) {
      _controller.forward();
      _detach();
    }
  }

  @override
  void dispose() {
    _detach();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
