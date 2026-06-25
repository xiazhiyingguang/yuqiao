import 'package:flutter_test/flutter_test.dart';
import 'package:yuqiao_app/stuck_expression_flow.dart';

StuckCandidate candidate(
  StuckExpressionSlot slot,
  String text, {
  String group = '测试',
}) {
  return StuckCandidate(text: text, semanticGroup: group, slot: slot);
}

void main() {
  group('StuckExpressionSession', () {
    test('寻找流程确认对象后即可成句，但仍可继续补充', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.find,
      );

      expect(session.currentStep?.slot, StuckExpressionSlot.target);
      expect(session.canFinish, isFalse);

      session.select(candidate(StuckExpressionSlot.target, '钥匙'));

      expect(session.canFinish, isTrue);
      expect(session.currentStep?.slot, StuckExpressionSlot.detail);
    });

    test('寻找人物时跳过物品颜色和大小特征', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.find,
      );

      session.select(candidate(
        StuckExpressionSlot.target,
        '妈妈',
        group: '人物',
      ));

      expect(session.currentStep?.slot, StuckExpressionSlot.place);
    });

    test('带我去会动态切换到地点槽位', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.request,
      );
      session.select(candidate(StuckExpressionSlot.action, '带我去'));

      expect(session.currentStep?.slot, StuckExpressionSlot.place);
      expect(session.canFinish, isFalse);

      session.select(candidate(StuckExpressionSlot.place, '公园'));
      expect(session.canFinish, isTrue);
    });

    test('自包含请求不强制补充对象', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.request,
      );
      session.select(candidate(StuckExpressionSlot.action, '陪陪我'));

      expect(session.canFinish, isTrue);
      expect(session.currentStep?.slot, StuckExpressionSlot.detail);
    });

    test('情绪感受跳过身体部位', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.feeling,
      );
      session.select(candidate(StuckExpressionSlot.feeling, '有点害怕'));

      expect(session.currentStep?.slot, StuckExpressionSlot.degree);
      expect(session.canFinish, isTrue);
    });

    test('修改前一步会清除依赖它的后续选择', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.describe,
      );
      session
        ..select(candidate(StuckExpressionSlot.subject, '手机'))
        ..select(candidate(StuckExpressionSlot.action, '找不到了'))
        ..select(candidate(StuckExpressionSlot.object, '家里的东西'));

      expect(session.selections, hasLength(3));
      session.clearFrom(StuckExpressionSlot.action);

      expect(session.selections, hasLength(1));
      expect(session.currentStep?.slot, StuckExpressionSlot.action);
      expect(session.canFinish, isFalse);
    });

    test('描述流程至少需要主体和动作', () {
      final session = StuckExpressionSession(
        intent: StuckExpressionIntent.describe,
      );
      session.select(candidate(StuckExpressionSlot.subject, '这件事'));
      expect(session.canFinish, isFalse);

      session.select(candidate(StuckExpressionSlot.action, '已经完成了'));
      expect(session.canFinish, isTrue);
    });
  });
}
