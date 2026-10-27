import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

Widget localFileImage(String path, {BoxFit fit = BoxFit.fitWidth}) {
  return Image.file(
    File(path),
    width: double.infinity,
    fit: fit,
    filterQuality: FilterQuality.medium,
    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  );
}

Future<String?> persistPickedImage(XFile file) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final dir = await getApplicationDocumentsDirectory();
    final original = file.name;
    final dot = original.lastIndexOf('.');
    final ext = dot >= 0 ? original.substring(dot) : '.jpg';
    final dest = File(
      '${dir.path}/insp_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  } catch (_) {
    return null;
  }
}
