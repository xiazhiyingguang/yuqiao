import '../lib/camera_image_processing.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool sameBox(List<double>? actual, List<double> expected) {
  if (actual == null || actual.length != expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if ((actual[index] - expected[index]).abs() > 0.001) return false;
  }
  return true;
}

void main() {
  check(
    sameBox(
      normalizeModelBoundingBox(const [0.1, 0.2, 0.8, 0.9]),
      const [100, 200, 800, 900],
    ),
    '0-1 坐标未正确归一化',
  );
  check(
    sameBox(
      normalizeModelBoundingBox(const [10, 20, 80, 90]),
      const [100, 200, 800, 900],
    ),
    '0-100 坐标未正确归一化',
  );
  check(
    sameBox(
      normalizeModelBoundingBox(const [800, 900, 100, 200]),
      const [100, 200, 800, 900],
    ),
    '反向坐标未正确排序',
  );
  check(
    normalizeModelBoundingBox(const [100, 100, 101, 101]) == null,
    '无效小框应被拒绝',
  );

  print('camera geometry verification passed');
}
