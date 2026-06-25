import '../lib/stuck_expression_flow.dart';

StuckCandidate candidate(StuckExpressionSlot slot, String text) {
  return StuckCandidate(text: text, semanticGroup: '验证', slot: slot);
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final find = StuckExpressionSession(intent: StuckExpressionIntent.find);
  check(find.currentStep?.slot == StuckExpressionSlot.target, '寻找流程首槽位错误');
  find.select(candidate(StuckExpressionSlot.target, '钥匙'));
  check(find.canFinish, '寻找对象确认后应允许成句');
  check(find.currentStep?.slot == StuckExpressionSlot.detail, '寻找流程未继续补充特征');

  final findPerson = StuckExpressionSession(intent: StuckExpressionIntent.find);
  findPerson.select(candidate(StuckExpressionSlot.target, '妈妈'));
  check(
    findPerson.currentStep?.slot == StuckExpressionSlot.place,
    '寻找人物时不应询问物品颜色和大小',
  );

  final request = StuckExpressionSession(intent: StuckExpressionIntent.request);
  request.select(candidate(StuckExpressionSlot.action, '带我去'));
  check(request.currentStep?.slot == StuckExpressionSlot.place, '带我去应切换地点槽位');
  check(!request.canFinish, '缺少目的地时不应成句');
  request.select(candidate(StuckExpressionSlot.place, '公园'));
  check(request.canFinish, '目的地确认后应允许成句');

  final feeling = StuckExpressionSession(intent: StuckExpressionIntent.feeling);
  feeling.select(candidate(StuckExpressionSlot.feeling, '有点害怕'));
  check(feeling.currentStep?.slot == StuckExpressionSlot.degree, '情绪不应强制身体部位');

  final describe =
      StuckExpressionSession(intent: StuckExpressionIntent.describe);
  describe
    ..select(candidate(StuckExpressionSlot.subject, '手机'))
    ..select(candidate(StuckExpressionSlot.action, '找不到了'))
    ..select(candidate(StuckExpressionSlot.object, '家里的东西'));
  describe.clearFrom(StuckExpressionSlot.action);
  check(describe.selections.length == 1, '修改前项时未清除依赖选择');
  check(!describe.canFinish, '描述缺少动作时不应成句');

  check(
    StuckFlowCatalog.isPlausibleCandidate(StuckExpressionSlot.place, '人民公园'),
    '合理地点被错误过滤',
  );
  check(
    !StuckFlowCatalog.isPlausibleCandidate(StuckExpressionSlot.time, '喝水'),
    '动作词不应进入时间槽位',
  );
  check(
    StuckFlowCatalog.isPlausibleCandidate(
      StuckExpressionSlot.communication,
      '帮我找一下',
    ),
    '沟通修复句被错误过滤',
  );

  print('stuck flow verification passed');
}
