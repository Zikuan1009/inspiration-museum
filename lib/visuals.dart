import 'package:flutter/material.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// 希腊神庙标志：黑色剪影，柱廊与台阶留白，无文字。
class TempleMark extends StatelessWidget {
  const TempleMark({super.key, this.width = 104});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 0.8,
      child: const CustomPaint(painter: _TempleMarkPainter()),
    );
  }
}

class _TempleMarkPainter extends CustomPainter {
  const _TempleMarkPainter();

  static const _ink = Color(0xFF111111);

  @override
  void paint(Canvas canvas, Size size) {
    const designW = 160.0;
    const designH = 128.0;
    final unit = size.width / designW < size.height / designH
        ? size.width / designW
        : size.height / designH;
    canvas.save();
    canvas.translate(
      (size.width - designW * unit) / 2,
      (size.height - designH * unit) / 2,
    );
    canvas.scale(unit);

    final fill = Paint()
      ..color = _ink
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    RRect soft(Rect rect, double radius) {
      return RRect.fromRectAndRadius(rect, Radius.circular(radius));
    }

    Path roundPoly(List<Offset> points, double radius) {
      final path = Path();
      final count = points.length;
      for (var i = 0; i < count; i++) {
        final prev = points[(i - 1 + count) % count];
        final curr = points[i];
        final next = points[(i + 1) % count];
        final toPrev = prev - curr;
        final toNext = next - curr;
        final prevLen = toPrev.distance;
        final nextLen = toNext.distance;
        var corner = radius;
        final limit = prevLen < nextLen ? prevLen : nextLen;
        if (corner > limit * 0.42) corner = limit * 0.42;
        final start = curr + toPrev / prevLen * corner;
        final end = curr + toNext / nextLen * corner;
        if (i == 0) {
          path.moveTo(start.dx, start.dy);
        } else {
          path.lineTo(start.dx, start.dy);
        }
        path.quadraticBezierTo(curr.dx, curr.dy, end.dx, end.dy);
      }
      path.close();
      return path;
    }

    canvas.saveLayer(const Rect.fromLTWH(0, 0, designW, designH), Paint());

    canvas.drawRRect(soft(const Rect.fromLTRB(8, 114, 152, 126), 3.2), fill);
    canvas.drawRRect(soft(const Rect.fromLTRB(20, 105, 140, 118), 2.8), fill);
    canvas.drawRRect(soft(const Rect.fromLTRB(32, 97, 128, 110), 2.6), fill);

    const shaftW = 16.0;
    const gap = 9.0;
    const columnCount = 4;
    final row = columnCount * shaftW + (columnCount - 1) * gap;
    final origin = (designW - row) / 2;
    for (var i = 0; i < columnCount; i++) {
      final left = origin + i * (shaftW + gap);
      canvas.drawRRect(soft(Rect.fromLTWH(left, 58, shaftW, 44), 3.4), fill);
      canvas.drawRRect(
        soft(Rect.fromLTWH(left - 3, 52, shaftW + 6, 10), 2.8),
        fill,
      );
    }

    canvas.drawRRect(soft(const Rect.fromLTRB(24, 44, 136, 56), 3.2), fill);
    canvas.drawPath(
      roundPoly(const [Offset(80, 12), Offset(146, 50), Offset(14, 50)], 7),
      fill,
    );
    canvas.drawCircle(
      const Offset(80, 30),
      7,
      Paint()..blendMode = BlendMode.dstOut,
    );

    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TempleMarkPainter oldDelegate) => false;
}

/// 旧的黑白配色。还没迁移的页面在用，迁移一页就换成 CanvasColors，
/// 全部迁完后删除。信封的米色几档仍由信封绘制使用。
abstract final class Palette {
  static const paper = Color(0xFFFFFFFF);
  static const paperLight = Color(0xFFFFFFFF);
  static const paperEdge = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111111);
  static const inkSoft = Color(0xFF111111);
  static const envelope = Color(0xFFE8E5DA);
  static const envelopeInside = Color(0xFFDCD8CB);
  static const envelopeFlapInner = Color(0xFFF1EFE7);
  static const letter = Color(0xFFFDFCF8);
}

const sansFallback = canvasSansFallback;

class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: CanvasColors.background);
  }
}

/// 网络延迟时的占位。名字沿用旧版，外观已是 Living Canvas 的呼吸块。
class BauhausLoadingFrame extends StatelessWidget {
  const BauhausLoadingFrame({super.key, this.width = 48, this.height = 48});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!width.isFinite) {
      return CanvasSkeleton(height: height);
    }
    return Center(
      child: CanvasSkeleton(width: width, height: height),
    );
  }
}
