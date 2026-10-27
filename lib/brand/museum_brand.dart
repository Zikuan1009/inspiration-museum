import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// Geometry for the approved Inspiration Museum mark.
///
/// The outer frame has three rounded corners and a square bottom-right.
/// A solid pier sits on the left, separated from the frame by an ivory
/// channel. The right court stays ivory and holds a four-point sparkle.
///
/// This painter is the vector source for a later launcher icon, splash,
/// or README mark. It does not load a bitmap.
abstract final class MuseumMarkPaths {
  static double strokeWidth(Size size) {
    return math.max(1.15, size.shortestSide * 0.055);
  }

  static Path frame(Size size) {
    final stroke = strokeWidth(size);
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      math.max(0, size.width - stroke),
      math.max(0, size.height - stroke),
    );
    final radius = math.min(rect.width, rect.height) * 0.28;
    return _threeRoundCorners(rect, radius);
  }

  static Path pier(Size size) {
    final court = _court(size);
    final radius = math.min(court.pier.width, court.pier.height) * 0.34;
    return _leftPier(court.pier, radius);
  }

  static Path sparkle(Size size) {
    final court = _court(size);
    final radius = math.min(court.open.width, court.open.height) * 0.34;
    return _fourPointStar(court.open.center, radius);
  }

  static _Court _court(Size size) {
    final stroke = strokeWidth(size);
    final inner = Rect.fromLTWH(
      stroke,
      stroke,
      math.max(0, size.width - stroke * 2),
      math.max(0, size.height - stroke * 2),
    );
    final channel = size.shortestSide * 0.09;
    final pier = Rect.fromLTRB(
      inner.left + channel,
      inner.top + channel,
      inner.left + inner.width * 0.42,
      inner.bottom - channel,
    );
    final open = Rect.fromLTRB(
      pier.right + channel * 0.55,
      inner.top + channel,
      inner.right - channel,
      inner.bottom - channel,
    );
    return _Court(pier, open);
  }
}

class _Court {
  const _Court(this.pier, this.open);

  final Rect pier;
  final Rect open;
}

/// Rounded on the top-left, top-right, and bottom-left. The bottom-right
/// vertex is a right angle.
Path _threeRoundCorners(Rect rect, double radius) {
  final r = radius.clamp(0.0, math.min(rect.width, rect.height) / 2);
  return Path()
    ..moveTo(rect.left + r, rect.top)
    ..lineTo(rect.right - r, rect.top)
    ..arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r))
    ..lineTo(rect.right, rect.bottom)
    ..lineTo(rect.left + r, rect.bottom)
    ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: Radius.circular(r))
    ..lineTo(rect.left, rect.top + r)
    ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
    ..close();
}

/// Solid left mass. Its left corners follow the frame; its right edge is
/// a straight wall facing the ivory court.
Path _leftPier(Rect rect, double radius) {
  final r = radius.clamp(0.0, math.min(rect.width, rect.height) / 2);
  return Path()
    ..moveTo(rect.left + r, rect.top)
    ..lineTo(rect.right, rect.top)
    ..lineTo(rect.right, rect.bottom)
    ..lineTo(rect.left + r, rect.bottom)
    ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: Radius.circular(r))
    ..lineTo(rect.left, rect.top + r)
    ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
    ..close();
}

Path _fourPointStar(Offset center, double radius) {
  final outer = math.max(radius, 1.1);
  final inner = math.max(outer * 0.22, 0.45);
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final r = i.isEven ? outer : inner;
    final angle = -math.pi / 2 + i * math.pi / 4;
    final point = Offset(
      center.dx + r * math.cos(angle),
      center.dy + r * math.sin(angle),
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();
  return path;
}

/// The architectural mark. Scales from the same paths at any size.
class InspirationMuseumMark extends StatelessWidget {
  const InspirationMuseumMark({
    super.key,
    this.size = 32,
    this.color = CanvasColors.forest,
    this.ground = CanvasColors.background,
    this.decorative = false,
  });

  final double size;
  final Color color;
  final Color ground;

  /// Omit the spoken label when the wordmark beside it already names the brand.
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MuseumMarkPainter(color: color, ground: ground),
        child: const SizedBox.expand(),
      ),
    );
    if (decorative) return mark;
    return Semantics(label: 'Inspiration Museum', image: true, child: mark);
  }
}

class _MuseumMarkPainter extends CustomPainter {
  const _MuseumMarkPainter({required this.color, required this.ground});

  final Color color;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = MuseumMarkPaths.frame(size);
    canvas.drawPath(frame, Paint()..color = ground);
    canvas.drawPath(MuseumMarkPaths.pier(size), Paint()..color = color);
    canvas.drawPath(MuseumMarkPaths.sparkle(size), Paint()..color = color);
    canvas.drawPath(
      frame,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = MuseumMarkPaths.strokeWidth(size)
        ..strokeJoin = StrokeJoin.miter
        ..strokeMiterLimit = 8,
    );
  }

  @override
  bool shouldRepaint(covariant _MuseumMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.ground != ground;
  }
}

/// Serif wordmark. The tagline is optional and stays off compact headers.
class InspirationMuseumWordmark extends StatelessWidget {
  const InspirationMuseumWordmark({
    super.key,
    this.showTagline = false,
    this.color = CanvasColors.text,
    this.taglineColor = CanvasColors.textSecondary,
  });

  static const name = 'Inspiration Museum';
  static const tagline = 'A MUSEUM OF A BRIGHTER YOU';

  final bool showTagline;
  final Color color;
  final Color taglineColor;

  @override
  Widget build(BuildContext context) {
    final nameStyle = CanvasType.section.copyWith(
      fontSize: 21,
      height: 1,
      color: color,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, maxLines: 1, softWrap: false, style: nameStyle),
        if (showTagline) ...[
          const SizedBox(height: 3),
          Text(
            tagline,
            maxLines: 1,
            softWrap: false,
            style: CanvasType.overline.copyWith(
              fontSize: 8.5,
              letterSpacing: 1.05,
              color: taglineColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Logo, wordmark, and whatever actions the screen already owns.
class InspirationMuseumBrandHeader extends StatelessWidget {
  const InspirationMuseumBrandHeader({
    super.key,
    this.markSize = 30,
    this.showTagline = false,
    this.trailing,
  });

  final double markSize;
  final bool showTagline;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InspirationMuseumMark(size: markSize, decorative: true),
        const SizedBox(width: CanvasSpace.sm),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: InspirationMuseumWordmark(showTagline: showTagline),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
