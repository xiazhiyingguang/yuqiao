import '../lib/personal_object_match_policy.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  check(
    PersonalObjectMatchPolicy.kindsCompatible('水杯', '我的蓝色杯子'),
    '同类杯子未进入核验阶段',
  );
  check(
    !PersonalObjectMatchPolicy.kindsCompatible('钥匙', '我的水杯'),
    '不同品类不应进入个人物品核验',
  );
  check(
    !PersonalObjectMatchPolicy.acceptsMatch(
      samePhysicalObject: true,
      confidence: 0.99,
      matchingEvidence: const ['都是蓝色', '都是杯子'],
      conflictingEvidence: const [],
    ),
    '只有品类和颜色相同不应认作同一件物品',
  );
  check(
    PersonalObjectMatchPolicy.acceptsMatch(
      samePhysicalObject: true,
      confidence: 0.98,
      matchingEvidence: const ['杯身有相同星形贴纸', '杯盖边缘有相同划痕'],
      conflictingEvidence: const [],
    ),
    '高置信度且有独特证据的匹配应通过',
  );
  check(
    !PersonalObjectMatchPolicy.acceptsMatch(
      samePhysicalObject: true,
      confidence: 0.98,
      matchingEvidence: const ['相同星形贴纸', '相同杯盖划痕'],
      conflictingEvidence: const ['把手方向明显不同'],
    ),
    '存在冲突证据时必须拒绝匹配',
  );

  print('personal object match verification passed');
}
