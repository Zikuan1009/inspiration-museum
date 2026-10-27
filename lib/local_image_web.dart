import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Widget localFileImage(String path, {BoxFit fit = BoxFit.fitWidth}) {
  if (path.startsWith('data:')) {
    final comma = path.indexOf(',');
    if (comma < 0) return const SizedBox.shrink();
    try {
      final bytes = base64Decode(path.substring(comma + 1));
      return Image.memory(
        bytes,
        width: double.infinity,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
  return Image.network(
    path,
    width: double.infinity,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  );
}

Future<String?> persistPickedImage(XFile file) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}
