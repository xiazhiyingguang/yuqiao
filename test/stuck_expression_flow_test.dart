import 'package:flutter_test/flutter_test.dart';
import 'package:yuqiao_app/stuck_expression_flow.dart';

void main() {
  group('StuckFlowCatalog helper slot filtering', () {
    test('accepts people but rejects action sentences', () {
      expect(
        StuckFlowCatalog.isPlausibleCandidate(
          StuckExpressionSlot.helper,
          '家人',
        ),
        isTrue,
      );
      expect(
        StuckFlowCatalog.isPlausibleCandidate(
          StuckExpressionSlot.helper,
          '身边的人',
        ),
        isTrue,
      );
      expect(
        StuckFlowCatalog.isPlausibleCandidate(
          StuckExpressionSlot.helper,
          '请帮我拿水',
        ),
        isFalse,
      );
      expect(
        StuckFlowCatalog.isPlausibleCandidate(
          StuckExpressionSlot.helper,
          '我想喝水',
        ),
        isFalse,
      );
    });
  });
}
