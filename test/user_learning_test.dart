import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuqiao_app/companion_agent.dart';
import 'package:yuqiao_app/location_recommendation.dart';
import 'package:yuqiao_app/user_learning.dart';

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

  test('builds a compact profile from unified learning events', () {
    final now = DateTime(2026, 7, 5, 10);
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'accepted',
        text: 'check time',
        normalizedText: 'checktime',
        intentTag: 'ask_time',
        objectTag: '',
        placeType: 'hospital',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now,
      ),
      UserLearningEvent(
        feature: 'conversation',
        action: 'spoken',
        text: 'check time',
        normalizedText: 'checktime',
        intentTag: 'ask_time',
        objectTag: '',
        placeType: 'hospital',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now.add(const Duration(minutes: 1)),
      ),
      UserLearningEvent(
        feature: 'conversation',
        action: 'rejected',
        text: 'small talk',
        normalizedText: 'smalltalk',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'hospital',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now.add(const Duration(minutes: 2)),
      ),
    ]);

    expect(profile.topExpressions.first.latestText, 'check time');
    expect(profile.rejectedExpressions.first.latestText, 'small talk');
    expect(profile.placeIntentPatterns.first.key, contains('hospital'));
    expect(profile.placeIntentPatterns.first.key, contains('ask_time'));
    expect(profile.updatedAt, now.add(const Duration(minutes: 2)));
    expect(profile.stats.eventCount, 3);
    expect(profile.stats.positiveCount, 2);
    expect(profile.stats.negativeCount, 1);
    expect(profile.stats.displayLines().join('\n'), contains('学习闭环'));
    expect(profile.stats.displayLines().join('\n'), contains('画像阶段'));
    expect(profile.stats.compactStatusLabel, contains('画像正在形成'));
    expect(profile.stats.displayLines().join('\n'), contains('对话辅助'));
    expect(profile.promptHints().join('\n'),
        contains('Long-term preferred expression'));
    expect(profile.summaryLines().join('\n'),
        contains('Long-term preferred expression'));
    expect(profile.displaySummaryLines().join('\n'), contains('常用表达'));
    expect(profile.displaySummaryLines().join('\n'), contains('询问时间'));
    expect(profile.semanticPreferences.first.label, contains('time'));
    expect(profile.portrait.hasSignal, isTrue);
    expect(profile.portrait.displayLines().join('\n'), contains('画像摘要'));
    expect(profile.promptHints().join('\n'), contains('User portrait summary'));
  });

  test('portrait context score generalizes frequent scene intents', () {
    final now = DateTime(2026, 7, 5, 10);
    final profile = const UserPreferenceProfileBuilder().build([
      for (var i = 0; i < 4; i++)
        UserLearningEvent(
          feature: 'conversation',
          action: 'accepted',
          text: 'what time is it',
          normalizedText: 'whattimeisit',
          intentTag: 'ask_time',
          objectTag: '',
          placeType: 'hospital',
          timeBucket: 'morning',
          slotName: 'sentence',
          createdAt: now.add(Duration(minutes: i)),
        ),
    ]);

    final hospitalScore = profile.contextualScoreFor(
      'when is the appointment',
      feature: 'conversation',
      placeType: 'hospital',
      slotName: 'sentence',
    );
    final unrelatedTextScore = profile.contextualScoreFor(
      'play music',
      feature: 'conversation',
      placeType: 'hospital',
      slotName: 'sentence',
    );
    final otherPlaceScore = profile.contextualScoreFor(
      'when is the appointment',
      feature: 'conversation',
      placeType: 'home',
      slotName: 'sentence',
    );

    expect(profile.portrait.summary, contains('医院'));
    expect(hospitalScore, greaterThan(unrelatedTextScore));
    expect(hospitalScore, greaterThan(otherPlaceScore));
  });

  test('semantic preference helps similar expressions without exact text match',
      () {
    final now = DateTime(2026, 7, 5, 10);
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'accepted',
        text: 'ask doctor',
        normalizedText: 'askdoctor',
        intentTag: 'request_help',
        objectTag: '',
        placeType: 'hospital',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now,
      ),
      UserLearningEvent(
        feature: 'conversation',
        action: 'spoken',
        text: 'ask doctor',
        normalizedText: 'askdoctor',
        intentTag: 'request_help',
        objectTag: '',
        placeType: 'hospital',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now.add(const Duration(minutes: 1)),
      ),
    ]);

    expect(profile.expressionScore('call doctor'), greaterThan(0));
    expect(profile.promptHints().join('\n'), contains('Semantic preference'));
  });

  test('builds expression length style preference from repeated choices', () {
    final now = DateTime(2026, 7, 5, 10);
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'accepted',
        text: 'yes',
        normalizedText: 'yes',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now,
      ),
      UserLearningEvent(
        feature: 'conversation',
        action: 'spoken',
        text: 'ok',
        normalizedText: 'ok',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now.add(const Duration(minutes: 1)),
      ),
      UserLearningEvent(
        feature: 'conversation',
        action: 'saved',
        text: 'wait',
        normalizedText: 'wait',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now.add(const Duration(minutes: 2)),
      ),
      UserLearningEvent(
        feature: 'conversation',
        action: 'rejected',
        text: 'please wait for a few minutes before leaving',
        normalizedText: 'pleasewaitforafewminutesbeforeleaving',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: now.add(const Duration(minutes: 3)),
      ),
    ]);

    expect(profile.expressionStyle.summary, contains('shorter candidates'));
    expect(
      profile.expressionScore('yes'),
      greaterThan(profile.expressionScore('please wait for a few minutes')),
    );
    expect(profile.promptHints().join('\n'), contains('Expression style'));
    expect(profile.displaySummaryLines().join('\n'), contains('更常选择短句候选'));
  });

  test('unknown text does not create noisy semantic profile', () {
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'accepted',
        text: 'custom phrase alpha',
        normalizedText: 'customphrasealpha',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: DateTime(2026, 7, 5, 10),
      ),
    ]);

    expect(profile.topExpressions, isNotEmpty);
    expect(profile.semanticPreferences, isEmpty);
  });

  test('refreshed feedback is treated as a negative learning event', () {
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'refreshed',
        text: 'wrong suggestion',
        normalizedText: 'wrongsuggestion',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: DateTime(2026, 7, 5, 10),
      ),
    ]);

    expect(profile.rejectedExpressions.first.latestText, 'wrong suggestion');
    expect(profile.expressionScore('wrong suggestion'), lessThan(0));
  });

  test('exact expression preference stays within its learned slot', () {
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'saved',
        text: 'wait for me',
        normalizedText: 'waitforme',
        intentTag: 'say_sentence',
        objectTag: '',
        placeType: 'home',
        timeBucket: 'morning',
        slotName: 'sentence',
        createdAt: DateTime(2026, 7, 5, 10),
      ),
    ]);

    expect(
      profile.expressionScore('wait for me', slotName: 'sentence'),
      greaterThan(0),
    );
    expect(
      profile.expressionScore('wait for me', slotName: 'actionOrObject'),
      0,
    );
  });

  test('companion writes unified events into personalized prompt hints',
      () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    await agent.recordInteraction(
      text: 'wait for me',
      feature: 'conversation',
      action: CompanionFeedbackAction.accepted,
      prompt: 'i want to say',
      slot: RecommendationSlot.sentence,
    );

    final hints = await agent.personalizedPromptHints(
      feature: 'conversation',
      prompt: 'i want to say',
      slot: RecommendationSlot.sentence,
    );

    expect(hints.join('\n'), contains('Long-term preferred expression'));
    expect(hints.join('\n'), contains('wait for me'));
  });

  test('companion notifies when the long-term profile changes', () async {
    SharedPreferences.setMockInitialValues({});
    final notifiedProfiles = <UserPreferenceProfile>[];
    final agent = CompanionAgentController(
      locationController: LocationRecommendationController(
        store: _MemoryLocationStore(),
      ),
      onPreferenceProfileChanged: notifiedProfiles.add,
    );
    agent.updateMemory(
      recentExpressions: const [],
      favoriteExpressions: const [],
      expressionHabits: const [],
      personalObjects: const [],
      conversationTerms: const [],
    );

    await agent.recordInteraction(
      text: 'wait for me',
      feature: 'conversation',
      action: CompanionFeedbackAction.accepted,
      prompt: 'i want to say',
      slot: RecommendationSlot.sentence,
    );
    await agent.recordActionPlanFeedback(
      type: CompanionActionType.clarify,
      feature: 'conversation',
      action: CompanionFeedbackAction.accepted,
      prompt: 'not sure',
      slot: RecommendationSlot.sentence,
    );

    expect(notifiedProfiles, hasLength(2));
    expect(notifiedProfiles.last.stats.eventCount, 2);
    expect(
        notifiedProfiles.last.actionPlanPreferences['clarify'], greaterThan(0));
  });

  test('repeated confirmation moves a similar candidate upward', () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    for (var i = 0; i < 3; i++) {
      await agent.recordInteraction(
        text: 'ask doctor',
        feature: 'conversation',
        action: CompanionFeedbackAction.accepted,
        prompt: 'need help',
        slot: RecommendationSlot.sentence,
      );
    }
    await agent.recordInteraction(
      text: 'play music',
      feature: 'conversation',
      action: CompanionFeedbackAction.rejected,
      prompt: 'need help',
      slot: RecommendationSlot.sentence,
    );

    final ranked = await agent.rankExpressions(
      const ['play music', 'ask doctor'],
      feature: 'conversation',
      prompt: 'need help',
      slot: RecommendationSlot.sentence,
      includeContextWords: false,
      allowContextExpansion: false,
      preserveInputOrder: true,
    );

    expect(ranked.first, 'ask doctor');
  });

  test('fixed scenario ranking improves after repeated use', () async {
    Future<int> rankAfterLearning({
      required int uses,
      required String acceptedText,
      required String targetCandidate,
      required List<String> candidates,
      required String prompt,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final agent = CompanionAgentController(
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

      for (var i = 0; i < uses; i++) {
        await agent.recordInteraction(
          text: acceptedText,
          feature: 'conversation',
          action: CompanionFeedbackAction.accepted,
          prompt: prompt,
          slot: RecommendationSlot.sentence,
        );
      }

      final ranked = await agent.rankExpressions(
        candidates,
        feature: 'conversation',
        prompt: prompt,
        slot: RecommendationSlot.sentence,
        includeContextWords: false,
        allowContextExpansion: false,
        preserveInputOrder: true,
      );
      return ranked.indexOf(targetCandidate);
    }

    final scenarios = [
      (
        name: 'hospital doctor help',
        acceptedText: 'ask doctor',
        targetCandidate: 'call doctor',
        candidates: const ['open window', 'call doctor', 'play music'],
        prompt: 'need help',
      ),
      (
        name: 'home water need',
        acceptedText: 'drink water',
        targetCandidate: 'need water',
        candidates: const ['watch tv', 'need water', 'open door'],
        prompt: 'thirsty',
      ),
    ];

    for (final scenario in scenarios) {
      final firstUse = await rankAfterLearning(
        uses: 1,
        acceptedText: scenario.acceptedText,
        targetCandidate: scenario.targetCandidate,
        candidates: scenario.candidates,
        prompt: scenario.prompt,
      );
      final thirdUse = await rankAfterLearning(
        uses: 3,
        acceptedText: scenario.acceptedText,
        targetCandidate: scenario.targetCandidate,
        candidates: scenario.candidates,
        prompt: scenario.prompt,
      );
      final fifthUse = await rankAfterLearning(
        uses: 5,
        acceptedText: scenario.acceptedText,
        targetCandidate: scenario.targetCandidate,
        candidates: scenario.candidates,
        prompt: scenario.prompt,
      );

      expect(
        thirdUse,
        lessThanOrEqualTo(firstUse),
        reason: '${scenario.name}: use 3 should not rank worse than use 1',
      );
      expect(
        fifthUse,
        lessThanOrEqualTo(thirdUse),
        reason: '${scenario.name}: use 5 should not rank worse than use 3',
      );
      expect(
        fifthUse,
        0,
        reason: '${scenario.name}: target candidate should be first by use 5',
      );
    }
  });

  test('candidate explanation shows long-term profile reason', () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    for (var i = 0; i < 3; i++) {
      await agent.recordInteraction(
        text: 'ask doctor',
        feature: 'conversation',
        action: CompanionFeedbackAction.accepted,
        prompt: 'need help',
        slot: RecommendationSlot.sentence,
      );
    }

    final explanations = await agent.explainCandidates(
      const ['call doctor'],
      feature: 'conversation',
      prompt: 'need help',
      slot: RecommendationSlot.sentence,
    );
    final key = LocationRecommendationController.normalizeText('call doctor');

    expect(explanations[key]?.reason, contains('long-term user profile'));
  });

  test('action plan feedback becomes unified profile signal', () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    await agent.recordActionPlanFeedback(
      type: CompanionActionType.clarify,
      feature: 'conversation',
      action: CompanionFeedbackAction.accepted,
      prompt: 'not sure',
      slot: RecommendationSlot.sentence,
    );

    final hints = await agent.personalizedPromptHints(
      feature: 'conversation',
      prompt: 'not sure',
      slot: RecommendationSlot.sentence,
    );
    final profile = await UserLearningStore().loadProfile();

    expect(hints.join('\n'), contains('prefers clarify assistance'));
    expect(
      hints.join('\n'),
      isNot(contains('Long-term preferred expression: action:')),
    );
    expect(profile.actionPlanPreferences['clarify'], greaterThan(0));
    expect(profile.displaySummaryLines().join('\n'), contains('帮助方式'));
    expect(
        profile.displaySummaryLines().join('\n'), isNot(contains('action:')));
  });

  test('vocabulary saved and deleted feedback updates long-term profile',
      () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    await agent.recordInteraction(
      text: 'blue cup',
      feature: 'vocabulary',
      action: CompanionFeedbackAction.saved,
      prompt: 'objects',
      slot: RecommendationSlot.actionOrObject,
    );
    await agent.recordInteraction(
      text: 'old word',
      feature: 'vocabulary',
      action: CompanionFeedbackAction.deleted,
      prompt: 'objects',
      slot: RecommendationSlot.actionOrObject,
    );

    final profile = await UserLearningStore().loadProfile();

    expect(profile.stats.featureCounts['vocabulary'], 2);
    expect(profile.topExpressions.first.latestText, 'blue cup');
    expect(profile.rejectedExpressions.first.latestText, 'old word');
    expect(profile.expressionScore('blue cup'), greaterThan(0));
    expect(profile.expressionScore('old word'), lessThan(0));
  });

  test('deleted vocabulary feedback lowers candidate rank in real agent',
      () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    await agent.recordInteraction(
      text: 'old word',
      feature: 'vocabulary',
      action: CompanionFeedbackAction.deleted,
      prompt: 'objects',
      slot: RecommendationSlot.actionOrObject,
    );
    await agent.recordInteraction(
      text: 'blue cup',
      feature: 'vocabulary',
      action: CompanionFeedbackAction.saved,
      prompt: 'objects',
      slot: RecommendationSlot.actionOrObject,
    );

    final ranked = await agent.rankExpressions(
      const ['old word', 'blue cup'],
      feature: 'vocabulary',
      prompt: 'objects',
      slot: RecommendationSlot.actionOrObject,
      includeContextWords: false,
      allowContextExpansion: false,
      preserveInputOrder: true,
    );

    expect(ranked.first, 'blue cup');
    expect(ranked.last, 'old word');
  });

  test('personal object feedback can carry an explicit object tag', () async {
    SharedPreferences.setMockInitialValues({});
    final agent = CompanionAgentController(
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

    await agent.recordInteraction(
      text: 'bring my blue cup',
      feature: 'personalObject',
      action: CompanionFeedbackAction.saved,
      prompt: 'my blue cup',
      slot: RecommendationSlot.sentence,
      objectTag: 'my blue cup',
    );

    final profile = await UserLearningStore().loadProfile();

    expect(profile.stats.featureCounts['personalObject'], 1);
    expect(profile.objectPatterns, isNotEmpty);
    expect(profile.objectPatterns.first.key, contains('mybluecup'));
    expect(profile.displaySummaryLines().join('\n'), contains('物品相关'));
  });

  test('rehabilitation events do not change communication preferences', () {
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'training',
        action: 'accepted',
        text: '喝水',
        normalizedText: '喝水',
        intentTag: 'training_correct',
        objectTag: '',
        placeType: 'unknown',
        timeBucket: 'training',
        slotName: 'topic',
        createdAt: DateTime(2026, 7, 10, 10),
      ),
    ]);

    expect(profile.stats.featureCounts['training'], 1);
    expect(profile.topExpressions, isEmpty);
    expect(profile.semanticPreferences, isEmpty);
    expect(profile.intentPatterns, isEmpty);
    expect(profile.expressionScore('我想喝水'), 0);
  });
}
