import 'package:flutter/material.dart';
import 'package:inspiration_museum/visuals.dart';

// 每日来信原先的信封舞台已由全屏的每日灵感页替代（daily_discovery/）。
// 这里只保留其他页面仍在用的两件：启动时的加载印章，和草稿箱里的闭合信封。

// ---------------------------------------------------------------------------
// 加载
// ---------------------------------------------------------------------------

class ArchiveLoading extends StatelessWidget {
  const ArchiveLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: _BreathingSeal(caption: 'ARRANGING'));
  }
}

class _BreathingSeal extends StatefulWidget {
  const _BreathingSeal({required this.caption});

  final String caption;

  @override
  State<_BreathingSeal> createState() => _BreathingSealState();
}

class _BreathingSealState extends State<_BreathingSeal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Opacity(
          opacity: 0.45 + 0.55 * t,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: CustomPaint(
                  size: const Size(28, 28),
                  painter: _SealPainter(progress: t),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                widget.caption,
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 6,
                  color: Palette.inkSoft,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Palette.ink.withValues(alpha: 0.55)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, 10, paint);
    canvas.drawCircle(c, 5.5 + progress * 1.4, paint);
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ---------------------------------------------------------------------------
// 闭合的信封
// ---------------------------------------------------------------------------

/// 一枚合上的信封，可在任意尺寸下绘制（草稿箱里的信）。
/// 内部按 300×186 的参考尺寸绘制后整体缩放，保证封印、折线比例一致。
class ClosedEnvelopeGraphic extends StatelessWidget {
  const ClosedEnvelopeGraphic({super.key});

  static const double aspectRatio = 0.62;

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _ClosedEnvelopePainter());
  }
}

class _ClosedEnvelopePainter extends CustomPainter {
  const _ClosedEnvelopePainter();

  static const _ref = Size(300, 186);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / _ref.width, size.height / _ref.height);

    final back = RRect.fromRectAndRadius(
      Offset.zero & _ref,
      const Radius.circular(3),
    );
    if (size.width > 120) {
      canvas.drawShadow(
        Path()..addRRect(back),
        Palette.ink.withValues(alpha: 0.35),
        10,
        false,
      );
    }
    canvas.drawRRect(back, Paint()..color = Palette.envelopeInside);
    // 很小的时候加 1px 黑描边，避免米色信封融进浅底。
    if (size.width < 48) {
      canvas.drawRRect(
        back,
        Paint()
          ..color = const Color(0xFF111111)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ref.width / size.width,
      );
    }

    canvas.save();
    const _PocketPainter().paint(canvas, _ref);
    canvas.restore();

    const _FlapPainter().paint(canvas, Size(_ref.width, _ref.height * 0.52));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClosedEnvelopePainter oldDelegate) => false;
}

class _PocketPainter extends CustomPainter {
  const _PocketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.clipRRect(rrect);

    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.envelope);

    final apex = Offset(w / 2, h * 0.44);
    final bottomFlap = Path()
      ..moveTo(0, h)
      ..lineTo(apex.dx, apex.dy)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      bottomFlap,
      Paint()..color = Color.lerp(Palette.envelope, Colors.white, 0.28)!,
    );

    final crease = Paint()
      ..color = Palette.ink.withValues(alpha: 0.09)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, h), apex, crease);
    canvas.drawLine(Offset(w, h), apex, crease);
    canvas.drawLine(
      Offset(0, 0),
      apex,
      crease..color = Palette.ink.withValues(alpha: 0.05),
    );
    canvas.drawLine(Offset(w, 0), apex, crease);
  }

  @override
  bool shouldRepaint(covariant _PocketPainter oldDelegate) => false;
}

/// 闭合的封舌：带阴影和封印圆点。
class _FlapPainter extends CustomPainter {
  const _FlapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w / 2, h)
      ..close();

    canvas.drawShadow(path, Palette.ink.withValues(alpha: 0.5), 4, false);
    canvas.drawPath(
      path,
      Paint()..color = Color.lerp(Palette.envelope, Palette.ink, 0.05)!,
    );

    final edge = Paint()
      ..color = Palette.ink.withValues(alpha: 0.10)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, 0), Offset(w / 2, h), edge);
    canvas.drawLine(Offset(w, 0), Offset(w / 2, h), edge);

    canvas.drawCircle(
      Offset(w / 2, h - 14),
      4,
      Paint()
        ..color = Palette.ink.withValues(alpha: 0.45)
        ..strokeWidth = 0.9
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _FlapPainter oldDelegate) => false;
}
