// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// capture_emoji_icon.dart
// Renders the 🌊 emoji using Flutter's text engine (identical to the app bar)
// and exports it as PNG files for waveform browser and PWA icons.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Run: flutter run -d linux tool/capture_emoji_icon.dart

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const EmojiCaptureApp());
}

class EmojiCaptureApp extends StatelessWidget {
  const EmojiCaptureApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: EmojiCapturePage());
}

class EmojiCapturePage extends StatefulWidget {
  const EmojiCapturePage({super.key});

  @override
  State<EmojiCapturePage> createState() => _EmojicapturePageState();
}

class _EmojicapturePageState extends State<EmojiCapturePage> {
  final GlobalKey _emojiKey = GlobalKey();
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    // Wait for the emoji to be rendered, then capture it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_captureEmoji());
    });
  }

  Future<void> _captureEmoji() async {
    try {
      final boundary = _emojiKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      // Capture at 4x for high resolution (renders at ~512px)
      final image = await boundary.toImage(pixelRatio: 4);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('ERROR: Failed to get byte data');
        exit(1);
      }

      final pngBytes = byteData.buffer.asUint8List();

      // Save the raw captured emoji
      final rawFile = File('web/emoji_captured.png');
      await rawFile.writeAsBytes(pngBytes);
      debugPrint('Saved raw capture: ${image.width}x${image.height}');

      // Now scale to each target size with light blue circle background
      for (final entry in {
        32: 'web/waveform.png',
        192: 'web/icons/waveform-192.png',
        512: 'web/icons/waveform-512.png',
      }.entries) {
        await _createIcon(pngBytes, entry.key, entry.value);
        // Also maskable
        if (entry.key > 32) {
          await _createIcon(
            pngBytes,
            entry.key,
            'web/icons/waveform-maskable-${entry.key}.png',
          );
        }
      }

      debugPrint('All icons generated! You can close the app.');
      setState(() => _captured = true);
    } on Object catch (e) {
      debugPrint('ERROR: $e');
    }
  }

  Future<void> _createIcon(
    Uint8List srcPng,
    int size,
    String outputPath,
  ) async {
    // Decode the source PNG
    final codec = await ui.instantiateImageCodec(
      srcPng,
      targetWidth: size,
      targetHeight: size,
    );
    final frame = await codec.getNextFrame();
    final scaledImage = frame.image;

    // Create a picture with light blue circle + scaled emoji
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw light blue circle background
    final bgPaint = Paint()..color = const Color(0xFFB3E5FC);
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, bgPaint);

    // Draw the scaled emoji centered
    final pad = size * 0.08;
    final inner = size - 2 * pad;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      scaledImage.width.toDouble(),
      scaledImage.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(pad, pad, inner, inner);
    canvas.drawImageRect(scaledImage, srcRect, dstRect, Paint());

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(size, size);
    final finalBytes = await finalImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (finalBytes != null) {
      final file = File(outputPath);
      await file.writeAsBytes(finalBytes.buffer.asUint8List());
      debugPrint('  $outputPath (${size}x$size)');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RepaintBoundary(
                key: _emojiKey,
                child: const Text('🌊', style: TextStyle(fontSize: 128)),
              ),
              const SizedBox(height: 20),
              Text(
                _captured ? 'Icons captured! Close app.' : 'Capturing...',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
}
