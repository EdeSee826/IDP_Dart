import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class WebCameraCaptureResult {
  final XFile xfile;
  final Uint8List bytes;

  const WebCameraCaptureResult({required this.xfile, required this.bytes});
}

Future<WebCameraCaptureResult?> openWebCameraDialog(BuildContext context) async {
  return null;
}