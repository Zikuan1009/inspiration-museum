import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/community_post.dart';

/// 把一篇帖子画成图片。公开图床会按图片打开，不会把网页源码显示出来。
class SharePoster {
  static Future<Uint8List> png(CommunityPost post) async {
    const width = 640.0;
    const pad = 36.0;
    final inner = width - pad * 2;
    final photo = await _photo(post.imagePath);
    final title = post.title.trim().isNotEmpty
        ? post.title.trim()
        : (post.theme.trim().isEmpty ? 'INSPIRATION' : post.theme.trim());
    final quote = post.quote.trim();
    final keys = post.keywords.join('  ×  ');
    final body = post.text.trim();

    final brand = _text('INSPIRATION', 18, FontWeight.w800, letterSpacing: 2);
    final keyLine = _text(keys, 16, FontWeight.w800, letterSpacing: 0.6);
    final quoteLine = _text(
      quote.isEmpty ? '' : CommunityPost.quotedText(quote),
      22,
      FontWeight.w500,
      italic: true,
    );
    final titleLine = _text(title, 32, FontWeight.w800);
    final bodyLine = _text(body, 22, FontWeight.w400, height: 1.55);
    final note = _text('View only', 14, FontWeight.w700, letterSpacing: 1.4);

    for (final painter in [brand, keyLine, quoteLine, titleLine, bodyLine, note]) {
      painter.layout(maxWidth: inner);
    }

    const photoH = 360.0;
    var height = 28.0 + brand.height + 20 + photoH + 18 + titleLine.height + 28 + note.height + 32;
    if (keys.isNotEmpty) height += 24 + keyLine.height;
    if (quote.isNotEmpty) height += 16 + quoteLine.height;
    if (body.isNotEmpty) height += 16 + bodyLine.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(1, 1, width - 2, height - 2),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    var y = 28.0;
    brand.paint(canvas, Offset((width - brand.width) / 2, y));
    y += brand.height + 20;

    final photoRect = Rect.fromLTWH(pad, y, inner, photoH);
    canvas.drawRect(photoRect, Paint()..color = const Color(0xFF3A3A3A));
    if (photo != null) {
      paintImage(
        canvas: canvas,
        rect: photoRect,
        image: photo,
        fit: BoxFit.cover,
      );
    }
    y += photoH;

    if (keys.isNotEmpty) {
      y += 24;
      keyLine.paint(canvas, Offset(pad, y));
      y += keyLine.height;
    }
    if (quote.isNotEmpty) {
      y += 16;
      quoteLine.paint(canvas, Offset(pad, y));
      y += quoteLine.height;
    }
    y += 18;
    titleLine.paint(canvas, Offset(pad, y));
    y += titleLine.height;
    if (body.isNotEmpty) {
      y += 16;
      bodyLine.paint(canvas, Offset(pad, y));
    }
    note.paint(canvas, Offset(pad, height - 32 - note.height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.round(), height.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) {
      throw StateError('The share image was not created.');
    }
    return data.buffer.asUint8List();
  }

  static TextPainter _text(
    String text,
    double size,
    FontWeight weight, {
    double letterSpacing = 0,
    double height = 1.3,
    bool italic = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: size,
          height: height,
          fontWeight: weight,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: letterSpacing,
          fontFamilyFallback: const [
            'PingFang SC',
            'Microsoft YaHei',
            'Noto Sans SC',
            'sans-serif',
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
  }

  static Future<ui.Image?> _photo(String? raw) async {
    final url = raw?.trim() ?? '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    final completer = Completer<ui.Image?>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
  }
}
