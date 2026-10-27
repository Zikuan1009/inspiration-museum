import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'local_image_io.dart'
    if (dart.library.html) 'local_image_web.dart' as impl;

Widget localFileImage(String path, {BoxFit fit = BoxFit.fitWidth}) {
  return impl.localFileImage(path, fit: fit);
}

Future<String?> persistPickedImage(XFile file) {
  return impl.persistPickedImage(file);
}
