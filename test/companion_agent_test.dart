import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuqiao_app/companion_agent.dart';
import 'package:yuqiao_app/location_recommendation.dart';

class _MemoryLocationStore implements LocationDataStore {
  bool enabled = false;
  String? data;

  @override
  Future<void> clearLocationRecommendationData() async {
    data = null;
  }

  @override
  Future<String?> loadLocationRecommendationData() async => data;

  @override
  Future<bool> loadLocationRecommendationEnabled() async => enabled;

  @override
  Future<void> saveLocationRecommendationData(String data) async {
    this.data = data;
  }

  @override
  Future<void> saveLocationRecommendationEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanionAgentController', () {
    late CompanionAgentController agent;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await CompanionFeedbackStore().clearAll();
      agent = CompanionAgentController(
        locationController: LocationRecommendationController(
          store: _MemoryLocationStore(),
        ),
      );
      agent.updateMemory(
        recentExpressions: const [],
        favoriteExpressions: const [],
        expressionHabits: const [],
        personalObjects: const [],
        conversationTerms: const [],
      );
    });

    test('uses local feedback to rerank similar-context candidates', () async {
      await agent.recordInteraction(
        text: '喝水',
        feature: 'stuck',
        action: CompanionFeedbackAction.accepted,
        prompt: '我想喝点东西',
        slot: RecommendationSlot.actionOrObject,
      );

      final ranked = await agent.rankExpressions(
        const ['休息', '喝水'],
        feature: 'stuck',
        prompt: '我想喝一点',
        slot: RecommendationSlot.actionOrObject,
        includeContextWords: false,
        allowContextExpansion: false,
      );

      expect(ranked.first, '喝水');
    });

    test('adds learned feedback to personalized model hints', () async {
      await agent.recordInteraction(
        text: '等我一下',
        feature: 'conversation',
        action: CompanionFeedbackAction.spoken,
        prompt: '我想说但是说不出来',
        slot: RecommendationSlot.sentence,
      );

      final hints = await agent.personalizedPromptHints(
        feature: 'conversation',
        prompt: '我想说',
        slot: RecommendationSlot.sentence,
      );

      expect(hints.join('\n'), contains('等我一下'));
      expect(hints.join('\n'), contains('智能体学习'));
      expect(hints.join('\n'), contains('智能体行动计划'));
    });

    test('chooses action plans from conversation intent', () {
      agent.updateConversationContext(
        transcript: '医生说今天下午要做检查',
        latestUserFragment: '什么意思',
        userSpeakerLabel: '说话者1',
      );

      final explain = agent.evaluateConversation(userRequested: true);
      expect(explain.actionPlan.type, CompanionActionType.explain);

      agent.updateConversationContext(
        transcript: '我想说不是这个',
        latestUserFragment: '不是这个',
        userSpeakerLabel: '说话者1',
      );

      final clarify = agent.evaluateConversation(userRequested: true);
      expect(clarify.actionPlan.type, CompanionActionType.clarify);

      agent.updateConversationContext(
        transcript: '我想',
        latestUserFragment: '我想',
        userSpeakerLabel: '说话者1',
      );

      final expression = agent.evaluateConversation(userRequested: true);
      expect(expression.actionPlan.type, CompanionActionType.recommendSentence);
      expect(expression.likelyStuck, isTrue);
    });

    test('uses action feedback to adapt future plans', () async {
      agent.updateConversationContext(
        transcript: '我想',
        latestUserFragment: '我想',
        userSpeakerLabel: '说话者1',
      );

      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendSentence,
        feature: 'conversation',
        action: CompanionFeedbackAction.rejected,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendSentence,
        feature: 'conversation',
        action: CompanionFeedbackAction.rejected,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.clarify,
        feature: 'conversation',
        action: CompanionFeedbackAction.accepted,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.clarify,
        feature: 'conversation',
        action: CompanionFeedbackAction.accepted,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.clarify,
        feature: 'conversation',
        action: CompanionFeedbackAction.accepted,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );

      final plan = await agent.adaptivePlanFor(
        feature: 'conversation',
        prompt: '我想',
        slot: RecommendationSlot.sentence,
        userRequested: true,
      );

      expect(plan.type, CompanionActionType.clarify);
      expect(plan.evidence.join('\n'), contains('相似语境更常接受'));
    });

    test('uses long-term profile to adapt plans across contexts', () async {
      for (var i = 0; i < 3; i++) {
        await agent.recordActionPlanFeedback(
          type: CompanionActionType.clarify,
          feature: 'conversation',
          action: CompanionFeedbackAction.accepted,
          prompt: '之前不确定',
          slot: RecommendationSlot.sentence,
        );
      }

      agent.updateConversationContext(
        transcript: '我想',
        latestUserFragment: '我想',
        userSpeakerLabel: '说话者1',
      );

      final plan = await agent.adaptivePlanFor(
        feature: 'conversation',
        prompt: '全新的片段',
        slot: RecommendationSlot.sentence,
        userRequested: true,
      );

      expect(plan.type, CompanionActionType.clarify);
      expect(plan.evidence.join('\n'), contains('长期画像更常接受'));
    });

    test('debug snapshot exposes long-term profile decision evidence',
        () async {
      await agent.recordInteraction(
        text: '请等我一下',
        feature: 'conversation',
        action: CompanionFeedbackAction.saved,
        prompt: '我说不出来',
        slot: RecommendationSlot.sentence,
      );
      for (var i = 0; i < 3; i++) {
        await agent.recordActionPlanFeedback(
          type: CompanionActionType.clarify,
          feature: 'conversation',
          action: CompanionFeedbackAction.accepted,
          prompt: '之前不确定',
          slot: RecommendationSlot.sentence,
        );
      }

      final snapshot = await agent.debugSnapshot(
        feature: 'conversation',
        prompt: '全新的片段',
        baseWords: const ['请等我一下', '我想喝水'],
        slot: RecommendationSlot.sentence,
      );

      expect(snapshot.preferenceProfileSummary.join('\n'), contains('常用表达'));
      expect(snapshot.preferenceProfileSummary.join('\n'), contains('帮助方式'));
      expect(snapshot.learningLoopSummary.join('\n'), contains('学习闭环'));
      expect(snapshot.adaptiveActionPlan.type, CompanionActionType.clarify);
      expect(
        snapshot.adaptiveActionPlan.evidence.join('\n'),
        contains('长期画像更常接受'),
      );
      expect(snapshot.rankedExplanations.first.scoreSummary, contains('profile'));
    });

    test('downgrades repeated skipped auto prompts to observe', () async {
      agent.updateConversationContext(
        transcript: '我想',
        latestUserFragment: '我想',
        userSpeakerLabel: '说话者1',
      );

      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendSentence,
        feature: 'conversation',
        action: CompanionFeedbackAction.skipped,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendSentence,
        feature: 'conversation',
        action: CompanionFeedbackAction.skipped,
        prompt: '我想',
        slot: RecommendationSlot.sentence,
      );

      final plan = await agent.adaptivePlanFor(
        feature: 'conversation',
        prompt: '我想',
        slot: RecommendationSlot.sentence,
        userRequested: false,
        autoDetectionEnabled: true,
      );

      expect(plan.type, CompanionActionType.observe);
      expect(plan.evidence.join('\n'), contains('自动辅助降级为观察'));
    });

    test('adapts stuck-flow action plans from action feedback', () async {
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendWord,
        feature: 'stuck',
        action: CompanionFeedbackAction.accepted,
        prompt: '我要 找东西 当前问题',
        slot: RecommendationSlot.actionOrObject,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendWord,
        feature: 'stuck',
        action: CompanionFeedbackAction.accepted,
        prompt: '我要 找东西 当前问题',
        slot: RecommendationSlot.actionOrObject,
      );
      await agent.recordActionPlanFeedback(
        type: CompanionActionType.recommendWord,
        feature: 'stuck',
        action: CompanionFeedbackAction.accepted,
        prompt: '我要 找东西 当前问题',
        slot: RecommendationSlot.actionOrObject,
      );

      final plan = await agent.adaptivePlanFor(
        feature: 'stuck',
        prompt: '我要 找东西 当前问题',
        slot: RecommendationSlot.actionOrObject,
        userRequested: true,
      );

      expect(plan.type, CompanionActionType.recommendWord);
      expect(plan.evidence.join('\n'), contains('相似语境更常接受'));
    });

    test('explains candidate ranking with user feedback reason', () async {
      await agent.recordInteraction(
        text: '请等我一下',
        feature: 'conversation',
        action: CompanionFeedbackAction.accepted,
        prompt: '我想说但是卡住了',
        slot: RecommendationSlot.sentence,
      );

      final explanations = await agent.explainCandidates(
        const ['请等我一下'],
        feature: 'conversation',
        prompt: '我想说但是卡住了',
        slot: RecommendationSlot.sentence,
      );

      final key = LocationRecommendationController.normalizeText('请等我一下');
      expect(explanations[key]?.reason, contains('类似场景常确认'));
    });

    test('uses saved expressions as soft long-term preference', () async {
      await agent.recordInteraction(
        text: '请等我一下',
        feature: 'conversation',
        action: CompanionFeedbackAction.saved,
        prompt: '我说不出来',
        slot: RecommendationSlot.sentence,
      );

      final ranked = await agent.rankExpressions(
        const ['我想喝水', '请等我一下'],
        feature: 'conversation',
        prompt: '刚才没听清',
        slot: RecommendationSlot.sentence,
        includeContextWords: false,
        allowContextExpansion: false,
      );

      expect(ranked.first, '请等我一下');
      final explanations = await agent.explainCandidates(
        const ['请等我一下'],
        feature: 'conversation',
        prompt: '刚才没听清',
        slot: RecommendationSlot.sentence,
      );
      final key = LocationRecommendationController.normalizeText('请等我一下');
      expect(explanations[key]?.reason, contains('长期偏好'));
    });

    test('does not apply saved sentence preference to a different slot',
        () async {
      await agent.recordInteraction(
        text: '请等我一下',
        feature: 'conversation',
        action: CompanionFeedbackAction.saved,
        prompt: '我说不出来',
        slot: RecommendationSlot.sentence,
      );

      final ranked = await agent.rankExpressions(
        const ['喝水', '请等我一下'],
        feature: 'conversation',
        prompt: '想要什么',
        slot: RecommendationSlot.actionOrObject,
        includeContextWords: false,
        allowContextExpansion: false,
      );

      expect(ranked.first, '喝水');
    });
  });
}
