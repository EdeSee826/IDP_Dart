import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class WebCameraCaptureResult {
  final XFile xfile;
  final Uint8List bytes;

  const WebCameraCaptureResult({required this.xfile, required this.bytes});
}

Future<WebCameraCaptureResult?> openWebCameraDialog(BuildContext context) {
  return showDialog<WebCameraCaptureResult?>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const _WebCameraDialog(),
  );
}

class _WebCameraDialog extends StatefulWidget {
  const _WebCameraDialog();

  @override
  State<_WebCameraDialog> createState() => _WebCameraDialogState();
}

class _WebCameraDialogState extends State<_WebCameraDialog> {
  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  String? _viewType;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewType = 'web-camera-${DateTime.now().microsecondsSinceEpoch}';
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..controls = false
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..setAttribute('playsinline', 'true');

      ui_web.platformViewRegistry.registerViewFactory(
        _viewType!,
        (int viewId) => video,
      );

      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'facingMode': {'ideal': 'environment'},
        },
        'audio': false,
      });

      video.srcObject = stream;
      await video.play();

      if (!mounted) {
        _stopStream(stream);
        return;
      }

      setState(() {
        _videoElement = video;
        _stream = stream;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera could not be opened: $e';
        _initializing = false;
      });
    }
  }

  void _stopStream([html.MediaStream? stream]) {
    final activeStream = stream ?? _stream;
    if (activeStream == null) return;
    for (final track in activeStream.getTracks()) {
      track.stop();
    }
  }

  Future<WebCameraCaptureResult?> _captureFrame() async {
    final video = _videoElement;
    if (video == null) return null;

    final width = video.videoWidth > 0 ? video.videoWidth : 1280;
    final height = video.videoHeight > 0 ? video.videoHeight : 720;

    final canvas = html.CanvasElement(width: width, height: height);
    final ctx = canvas.context2D;
    ctx.drawImageScaled(video, 0, 0, width, height);

    final bytes = _canvasToBytes(canvas);
    final xfile = XFile.fromData(
      bytes,
      name: 'capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: 'image/jpeg',
    );

    return WebCameraCaptureResult(xfile: xfile, bytes: bytes);
  }

  Uint8List _canvasToBytes(html.CanvasElement canvas) {
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
    final base64Part = dataUrl.split(',').last;
    return Uint8List.fromList(base64Decode(base64Part));
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Camera',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black,
                    child: _initializing
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : HtmlElementView(viewType: _viewType!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _stopStream();
                      Navigator.of(context).pop(null);
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _initializing || _error != null
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            final result = await _captureFrame();
                            _stopStream();
                            if (!mounted) return;
                            navigator.pop(result);
                          },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Shutter'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}