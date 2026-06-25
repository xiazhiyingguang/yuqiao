import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

class LocalObjectBox {
  const LocalObjectBox({
    required this.bbox,
    required this.confidence,
    this.label,
  });

  /// Normalized [x1, y1, x2, y2] coordinates in the 0-1000 range.
  final List<double> bbox;
  final double confidence;
  final String? label;

  double get area {
    return math.max(0, bbox[2] - bbox[0]) * math.max(0, bbox[3] - bbox[1]);
  }
}

class LocalObjectLocator {
  ObjectDetector? _detector;

  Future<List<LocalObjectBox>> detect(Uint8List imageBytes) async {
    final decoded = image_lib.decodeImage(imageBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return const [];
    }

    final file = await _writeTempImage(imageBytes);
    try {
      final detector = _detector ??= ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.single,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
      final inputImage = InputImage.fromFilePath(file.path);
      final objects = await detector
          .processImage(inputImage)
          .timeout(const Duration(seconds: 4));
      final boxes = <LocalObjectBox>[];
      for (final object in objects) {
        final rect = object.boundingBox;
        final normalized = _normalizeRect(rect, decoded.width, decoded.height);
        if (normalized == null) continue;
        final confidence = object.labels.isEmpty
            ? 0.55
            : object.labels
                .map((label) => label.confidence)
                .reduce((a, b) => a > b ? a : b);
        final label = object.labels.isEmpty ? null : object.labels.first.text;
        final box = LocalObjectBox(
          bbox: normalized,
          confidence: confidence,
          label: label,
        );
        if (box.area < 900 || box.area > 850000) continue;
        boxes.add(box);
      }
      boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
      return boxes.take(6).toList(growable: false);
    } catch (error) {
      // Keep camera recognition usable on devices where the native detector is
      // unavailable or temporarily fails.
      return const [];
    } finally {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  Future<void> close() async {
    await _detector?.close();
    _detector = null;
  }

  Future<File> _writeTempImage(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'yuqiao_mlkit_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  List<double>? _normalizeRect(Rect rect, int imageWidth, int imageHeight) {
    final left = (rect.left / imageWidth * 1000).clamp(0.0, 1000.0);
    final top = (rect.top / imageHeight * 1000).clamp(0.0, 1000.0);
    final right = (rect.right / imageWidth * 1000).clamp(0.0, 1000.0);
    final bottom = (rect.bottom / imageHeight * 1000).clamp(0.0, 1000.0);
    if (right - left < 8 || bottom - top < 8) return null;
    return [left, top, right, bottom];
  }
}
