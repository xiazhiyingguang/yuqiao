import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;

Uint8List normalizeCameraImage(Uint8List bytes) {
  var image = image_lib.decodeImage(bytes);
  if (image == null) return bytes;
  image = image_lib.bakeOrientation(image);
  const maxSide = 1600;
  if (image.width > maxSide || image.height > maxSide) {
    image = image_lib.copyResize(
      image,
      width: image.width >= image.height ? maxSide : null,
      height: image.height > image.width ? maxSide : null,
      interpolation: image_lib.Interpolation.average,
    );
  }
  return Uint8List.fromList(image_lib.encodeJpg(image, quality: 84));
}

List<double>? normalizeModelBoundingBox(Object? rawBbox) {
  if (rawBbox is! List || rawBbox.length != 4) return null;
  final rawValues =
      rawBbox.whereType<num>().map((value) => value.toDouble()).toList();
  if (rawValues.length != 4 || rawValues.any((value) => !value.isFinite)) {
    return null;
  }
  final maxValue = rawValues.reduce((a, b) => a > b ? a : b);
  final scale = maxValue <= 1.5
      ? 1000.0
      : maxValue <= 100.0
          ? 10.0
          : 1.0;
  final values = rawValues
      .map((value) => (value * scale).clamp(0.0, 1000.0).toDouble())
      .toList(growable: false);
  final left = values[0] < values[2] ? values[0] : values[2];
  final top = values[1] < values[3] ? values[1] : values[3];
  final right = values[0] > values[2] ? values[0] : values[2];
  final bottom = values[1] > values[3] ? values[1] : values[3];
  if (right - left < 4 || bottom - top < 4) return null;
  return [left, top, right, bottom];
}
