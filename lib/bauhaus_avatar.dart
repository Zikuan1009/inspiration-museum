import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 有云端照片则显示照片，否则回退几何头像。
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({
    super.key,
    required this.seed,
    this.imageUrl,
    this.size = 72,
    this.border = true,
  });

  final String seed;
  final String? imageUrl;
  final double size;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return BauhausAvatar(seed: seed, size: size, border: border);
    }
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: border ? Border.all(color: Colors.black, width: 1) : null,
        ),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              BauhausAvatar(seed: seed, size: size, border: false),
        ),
      ),
    );
  }
}

/// 方形几何头像：用 id 作种子画黑白构成，无照片时的包豪斯占位。
class BauhausAvatar extends StatelessWidget {
  const BauhausAvatar({
    super.key,
    required this.seed,
    this.size = 40,
    this.border = true,
  });

  final String seed;
  final double size;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: border ? Border.all(color: Colors.black, width: 1) : null,
        ),
        child: CustomPaint(painter: _AvatarPainter(seed.hashCode)),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  const _AvatarPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final w = size.width;
    final h = size.height;
    final ink = Paint()..color = const Color(0xFF111111);
    final line = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    if (rng.nextBool()) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w * (0.35 + rng.nextDouble() * 0.4), h),
        Paint()..color = const Color(0xFFE8E8E8),
      );
    }

    final r = math.min(w, h) * (0.14 + rng.nextDouble() * 0.18);
    canvas.drawCircle(
      Offset(r + rng.nextDouble() * (w - 2 * r), r + rng.nextDouble() * (h - 2 * r)),
      r,
      rng.nextBool() ? ink : line,
    );

    canvas.drawRect(
      Rect.fromLTWH(
        rng.nextDouble() * w * 0.5,
        rng.nextDouble() * h * 0.5,
        w * (0.2 + rng.nextDouble() * 0.35),
        h * (0.12 + rng.nextDouble() * 0.3),
      ),
      ink,
    );

    if (rng.nextBool()) {
      canvas.drawLine(Offset(0, h * rng.nextDouble()), Offset(w, h * rng.nextDouble()), line);
    } else {
      canvas.drawLine(Offset(w * rng.nextDouble(), 0), Offset(w * rng.nextDouble(), h), line);
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) => oldDelegate.seed != seed;
}
