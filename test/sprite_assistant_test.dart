import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuqiao_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteAssistantIntent', () {
    test('uses a local confirmation built from sanitized parameters', () {
      final intent = SpriteAssistantIntent.fromJson(
        {
          'actionId': SpriteAssistantActionIds.setImageScale,
          'parameters': {'imageScale': 1.5},
          'confidence': 0.92,
          'title': '模型自定义标题',
          'confirmation': '模型自定义确认文案',
          'reason': '用户希望图片更大',
        },
        rawText: '图片调大一点',
      );

      expect(intent.isSupported, isTrue);
      expect(intent.parameters['imageScale'], 1.55);
      expect(intent.title, '调整图片大小');
      expect(intent.confirmation, contains('最大'));
      expect(intent.confirmation, isNot(contains('模型自定义')));
    });

    test('requires missing setting parameters instead of guessing defaults',
        () {
      final countIntent = SpriteAssistantIntent.fromJson(
        {
          'actionId': SpriteAssistantActionIds.setCandidateCount,
          'parameters': <String, dynamic>{},
          'confidence': 0.9,
        },
        rawText: '调整候选数量',
      );
      final toggleIntent = SpriteAssistantIntent.fromJson(
        {
          'actionId': SpriteAssistantActionIds.togglePersonalizedLearning,
          'parameters': <String, dynamic>{},
          'confidence': 0.9,
        },
        rawText: '调整学习记忆',
      );

      expect(countIntent.isSupported, isFalse);
      expect(countIntent.needsTextFollowUp, isTrue);
      expect(countIntent.validationMessage, contains('两项'));
      expect(toggleIntent.isSupported, isFalse);
      expect(toggleIntent.needsTextFollowUp, isTrue);
      expect(toggleIntent.validationMessage, contains('开启还是关闭'));
    });

    test('rejects unknown actions and overlong stored text', () {
      final unknown = SpriteAssistantIntent.fromJson(
        {
          'actionId': 'delete_everything',
          'parameters': <String, dynamic>{},
          'confidence': 1,
        },
        rawText: '删除全部内容',
      );
      final overlong = SpriteAssistantIntent.fromJson(
        {
          'actionId': SpriteAssistantActionIds.addVocabularyEntry,
          'parameters': {'text': '这是一个明显超过十二个字限制的超长词条'},
          'confidence': 0.9,
        },
        rawText: '添加一个很长的词条',
      );

      expect(unknown.isSupported, isFalse);
      expect(unknown.actionId, SpriteAssistantActionIds.unsupported);
      expect(overlong.isSupported, isFalse);
      expect(overlong.validationMessage, contains('12 个字'));
    });
  });

  test('assistant operation memory stays separate and favors completed tasks',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SpriteAssistantUsageStore();
    await store.clear();
    await store.record(
      SpriteAssistantActionIds.setImageScale,
      outcome: 'completed',
    );
    await store.record(
      SpriteAssistantActionIds.setImageScale,
      outcome: 'completed',
    );
    await store.record(
      SpriteAssistantActionIds.openTraining,
      outcome: 'cancelled',
    );

    final hints = await store.promptHints();

    expect(hints.join('\n'), contains('调整图片大小'));
    expect(hints.join('\n'), isNot(contains('打开词语花园')));
  });
}
