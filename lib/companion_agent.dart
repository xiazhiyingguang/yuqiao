import 'dart:convert';
import 'dart:math' as math;

import 'conversation_terms.dart';
import 'expression_habits.dart';
import 'location_recommendation.dart';
import 'personal_objects.dart';
import 'sensitive_local_store.dart';
import 'user_learning.dart';

enum CompanionFeedbackAction {
  accepted,
  rejected,
  skipped,
  refreshed,
  spoken,
  saved,
  deleted,
}

enum CompanionAssistMode {
  none,
  expression,
  comprehension,
  clarification,
}

enum CompanionActionType {
  observe,
  recommendWord,
  recommendPhrase,
  recommendSentence,
  explain,
  clarify,
}

extension CompanionActionTypeLabel on CompanionActionType {
  String get label {
    return switch (this) {
      CompanionActionType.observe => '继续观察',
      CompanionActionType.recommendWord => '推荐关键词',
      CompanionActionType.recommendPhrase => '推荐短语',
      CompanionActionType.recommendSentence => '整理表达',
      CompanionActionType.explain => '帮我理解',
      CompanionActionType.clarify => '澄清确认',
    };
  }
}

class CompanionActionPlan {
  const CompanionActionPlan({
    required this.type,
    required this.title,
    required this.uiPrompt,
    required this.modelInstruction,
    required this.requiresConfirmation,
    required this.priority,
    required this.evidence,
  });

  final CompanionActionType type;
  final String title;
  final String uiPrompt;
  final String modelInstruction;
  final bool requiresConfirmation;
  final int priority;
  final List<String> evidence;

  String get summary {
    final confirmation = requiresConfirmation ? '需要用户确认' : '只展示不播报';
    return '$title；$confirmation；${evidence.join('、')}';
  }

  CompanionActionPlan copyWith({
    CompanionActionType? type,
    String? title,
    String? uiPrompt,
    String? modelInstruction,
    bool? requiresConfirmation,
    int? priority,
    List<String>? evidence,
  }) {
    return CompanionActionPlan(
      type: type ?? this.type,
      title: title ?? this.title,
      uiPrompt: uiPrompt ?? this.uiPrompt,
      modelInstruction: modelInstruction ?? this.modelInstruction,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      priority: priority ?? this.priority,
      evidence: evidence ?? this.evidence,
    );
  }
}

class CompanionAgentDecision {
  const CompanionAgentDecision({
    required this.speakerLabel,
    required this.topic,
    required this.likelyStuck,
    required this.shouldPrompt,
    required this.mode,
    required this.actionPlan,
    required this.reasons,
  });

  final String speakerLabel;
  final String topic;
  final bool likelyStuck;
  final bool shouldPrompt;
  final CompanionAssistMode mode;
  final CompanionActionPlan actionPlan;
  final List<String> reasons;

  String get brief {
    final action = switch (mode) {
      CompanionAssistMode.expression => '建议表达辅助',
      CompanionAssistMode.comprehension => '建议理解辅助',
      CompanionAssistMode.clarification => '建议确认澄清',
      CompanionAssistMode.none => '继续观察',
    };
    return '$action；${actionPlan.title}；话题：$topic；${reasons.join('、')}';
  }
}

class CompanionActionBias {
  const CompanionActionBias({
    required this.accepted,
    required this.rejected,
  });

  final Map<CompanionActionType, int> accepted;
  final Map<CompanionActionType, int> rejected;

  bool get hasSignal => accepted.isNotEmpty || rejected.isNotEmpty;

  double scoreFor(CompanionActionType type) {
    return (accepted[type] ?? 0) - (rejected[type] ?? 0) * 1.5;
  }

  CompanionActionType? get preferredType {
    final types = {...accepted.keys, ...rejected.keys};
    if (types.isEmpty) return null;
    final sorted = types.toList()
      ..sort((a, b) => scoreFor(b).compareTo(scoreFor(a)));
    final best = sorted.first;
    return scoreFor(best) > 0 ? best : null;
  }

  String summaryFor(CompanionActionType type) {
    final acceptedCount = accepted[type] ?? 0;
    final rejectedCount = rejected[type] ?? 0;
    if (acceptedCount == 0 && rejectedCount == 0) return '';
    return '行动反馈：${type.label} 确认 $acceptedCount 次，跳过 $rejectedCount 次';
  }
}

class CompanionAgentDebugSnapshot {
  const CompanionAgentDebugSnapshot({
    required this.context,
    required this.decision,
    required this.contextKey,
    required this.feedbackContextKeys,
    required this.learningEnabled,
    required this.memorySignals,
    required this.rankedPreview,
    required this.rankedExplanations,
    required this.preferenceProfileSummary,
    required this.learningLoopSummary,
    required this.adaptiveActionPlan,
    required this.feedbackProfile,
    required this.globalFeedbackProfile,
    required this.actionBias,
    required this.recentFeedbackEvents,
  });

  final UserContextModel context;
  final CompanionAgentDecision? decision;
  final String contextKey;
  final List<String> feedbackContextKeys;
  final bool learningEnabled;
  final List<String> memorySignals;
  final List<String> rankedPreview;
  final List<CompanionRankedExplanation> rankedExplanations;
  final List<String> preferenceProfileSummary;
  final List<String> learningLoopSummary;
  final CompanionActionPlan adaptiveActionPlan;
  final CompanionFeedbackProfile feedbackProfile;
  final CompanionFeedbackProfile globalFeedbackProfile;
  final CompanionActionBias actionBias;
  final List<String> recentFeedbackEvents;
}

class CompanionRankedExplanation {
  const CompanionRankedExplanation({
    required this.text,
    required this.totalScore,
    required this.baseScore,
    required this.memoryScore,
    required this.preferenceScore,
    required this.feedbackScore,
    this.reason = '',
  });

  final String text;
  final double totalScore;
  final double baseScore;
  final double memoryScore;
  final double preferenceScore;
  final double feedbackScore;
  final String reason;

  String get scoreSummary {
    String fmt(double value) => value.toStringAsFixed(0);
    if (preferenceScore.isFinite) {
      final profileReasonText = reason.isEmpty ? '' : '; reason $reason';
      return 'total ${fmt(totalScore)}; base ${fmt(baseScore)}; memory ${fmt(memoryScore)}; profile ${fmt(preferenceScore)}; feedback ${fmt(feedbackScore)}$profileReasonText';
    }
    final reasonText = reason.isEmpty ? '' : '；$reason';
    return '总分 ${fmt(totalScore)}；基础 ${fmt(baseScore)}；记忆 ${fmt(memoryScore)}；反馈 ${fmt(feedbackScore)}$reasonText';
  }
}

class CompanionCandidateExplanation {
  const CompanionCandidateExplanation({
    required this.text,
    required this.reason,
  });

  final String text;
  final String reason;
}

class UserContextModel {
  const UserContextModel({
    required this.capturedAt,
    required this.feature,
    required this.timeBucket,
    required this.timeLabel,
    required this.placeType,
    required this.placeLabel,
    required this.userSpeakerLabel,
    required this.recentTranscript,
    required this.latestUserFragment,
    required this.recentExpressions,
    required this.favoriteExpressions,
    required this.expressionHabits,
    required this.personalObjects,
    required this.conversationTerms,
    required this.placeWords,
    required this.supportProfileHints,
  });

  final DateTime capturedAt;
  final String feature;
  final String timeBucket;
  final String timeLabel;
  final String placeType;
  final String placeLabel;
  final String userSpeakerLabel;
  final String recentTranscript;
  final String latestUserFragment;
  final List<String> recentExpressions;
  final List<String> favoriteExpressions;
  final List<ExpressionHabit> expressionHabits;
  final List<PersonalObject> personalObjects;
  final List<ConversationTerm> conversationTerms;
  final List<PlaceWordUsage> placeWords;
  final List<String> supportProfileHints;

  List<ConversationTerm> termsOfType(String type) {
    final normalizedType = normalizeConversationTermType(type);
    return conversationTerms
        .where((term) => term.type == normalizedType)
        .toList(growable: false);
  }

  List<String> get keyPeople =>
      termsOfType('person').map((term) => term.text).toList(growable: false);

  List<String> get keyPlaces =>
      termsOfType('place').map((term) => term.text).toList(growable: false);

  List<String> get objectNames => personalObjects
      .map((object) => object.displayName)
      .where((text) => text.trim().isNotEmpty)
      .toList(growable: false);

  String get compactKey {
    final prompt = LocationRecommendationController.normalizeText(
      latestUserFragment,
    );
    final fragment = prompt.length <= 10 ? prompt : prompt.substring(0, 10);
    final person = keyPeople.take(2).join(',');
    return [
      feature,
      timeBucket,
      placeType,
      userSpeakerLabel,
      person,
      fragment,
    ].where((item) => item.trim().isNotEmpty).join('|');
  }

  String modelBrief({int maxTranscriptChars = 180}) {
    final recent = recentTranscript.trim();
    final summaryLines = recent
        .split('\n')
        .where((line) => line.startsWith('对话摘要：') || line.startsWith('较早对话：'))
        .toList(growable: false);
    final tail = recent.length <= maxTranscriptChars
        ? recent
        : recent.substring(recent.length - maxTranscriptChars);
    final compactTranscript = [
      ...summaryLines.take(1),
      tail,
    ].where((line) => line.trim().isNotEmpty).join('\n');
    final lines = <String>[
      '时间：$timeLabel',
      '地点：$placeLabel',
      if (userSpeakerLabel.trim().isNotEmpty) '用户说话者：$userSpeakerLabel',
      if (keyPeople.isNotEmpty) '对话人物：${keyPeople.take(4).join('、')}',
      if (keyPlaces.isNotEmpty) '对话地点：${keyPlaces.take(3).join('、')}',
      if (objectNames.isNotEmpty) '个人物品：${objectNames.take(5).join('、')}',
      if (favoriteExpressions.isNotEmpty)
        '收藏表达：${favoriteExpressions.take(4).join('、')}',
      ...supportProfileHints.take(4),
      if (compactTranscript.isNotEmpty) '最近对话：$compactTranscript',
      if (latestUserFragment.trim().isNotEmpty) '用户最后片段：$latestUserFragment',
    ];
    return lines.join('\n');
  }
}

class CompanionAgentController {
  CompanionAgentController({
    required LocationRecommendationController locationController,
    CompanionFeedbackStore? feedbackStore,
    UserLearningStore? userLearningStore,
    void Function(UserPreferenceProfile profile)? onPreferenceProfileChanged,
  })  : _locationController = locationController,
        _feedbackStore = feedbackStore ?? CompanionFeedbackStore(),
        _userLearningStore = userLearningStore ?? UserLearningStore(),
        _onPreferenceProfileChanged = onPreferenceProfileChanged;

  final LocationRecommendationController _locationController;
  final CompanionFeedbackStore _feedbackStore;
  final UserLearningStore _userLearningStore;
  final void Function(UserPreferenceProfile profile)?
      _onPreferenceProfileChanged;

  List<String> _recentExpressions = const [];
  List<String> _favoriteExpressions = const [];
  List<ExpressionHabit> _expressionHabits = const [];
  List<PersonalObject> _personalObjects = const [];
  List<ConversationTerm> _conversationTerms = const [];
  List<String> _supportProfileHints = const [];
  String _recentTranscript = '';
  String _latestUserFragment = '';
  String _userSpeakerLabel = '';
  bool _learningEnabled = true;
  UserPreferenceProfile _preferenceProfile = UserPreferenceProfile.empty;

  void updateMemory({
    required List<String> recentExpressions,
    required List<String> favoriteExpressions,
    required List<ExpressionHabit> expressionHabits,
    required List<PersonalObject> personalObjects,
    required List<ConversationTerm> conversationTerms,
    List<String> supportProfileHints = const [],
    bool learningEnabled = true,
  }) {
    _recentExpressions = List.unmodifiable(recentExpressions);
    _favoriteExpressions = List.unmodifiable(favoriteExpressions);
    _expressionHabits = List.unmodifiable(expressionHabits);
    _personalObjects = List.unmodifiable(personalObjects);
    _conversationTerms = List.unmodifiable(conversationTerms);
    _supportProfileHints = List.unmodifiable(supportProfileHints);
    _learningEnabled = learningEnabled;
  }

  void updateConversationContext({
    required String transcript,
    required String latestUserFragment,
    required String userSpeakerLabel,
    List<ConversationTerm>? conversationTerms,
  }) {
    _recentTranscript = transcript;
    _latestUserFragment = latestUserFragment;
    _userSpeakerLabel = userSpeakerLabel;
    if (conversationTerms != null) {
      _conversationTerms = List.unmodifiable(conversationTerms);
    }
  }

  UserContextModel contextFor({
    required String feature,
    String latestUserFragment = '',
    String prompt = '',
  }) {
    final now = DateTime.now();
    final place = _locationController.currentPlace;
    final semantic = _locationController.currentSemantic;
    final placeType = place?.normalizedType ??
        PlaceTypeCatalog.normalize(semantic?.type ?? PlaceTypeCatalog.unknown);
    final placeLabel = place?.name ??
        (semantic == null
            ? PlaceTypeCatalog.labelOf(placeType)
            : semantic.displayName);
    return UserContextModel(
      capturedAt: now,
      feature: feature,
      timeBucket: ExpressionHabitStore.bucketFor(now),
      timeLabel: _timeLabel(now),
      placeType: placeType,
      placeLabel: placeLabel,
      userSpeakerLabel: _userSpeakerLabel,
      recentTranscript: _recentTranscript,
      latestUserFragment: latestUserFragment.trim().isNotEmpty
          ? latestUserFragment.trim()
          : prompt.trim().isNotEmpty
              ? prompt.trim()
              : _latestUserFragment,
      recentExpressions: _recentExpressions,
      favoriteExpressions: _favoriteExpressions,
      expressionHabits: _expressionHabits,
      personalObjects: _personalObjects,
      conversationTerms: _conversationTerms,
      placeWords: place == null
          ? const []
          : _locationController.wordsForPlace(place.id),
      supportProfileHints: _supportProfileHints,
    );
  }

  Future<List<String>> rankExpressions(
    List<String> baseWords, {
    required String feature,
    String? category,
    String prompt = '',
    List<String> selectedWords = const [],
    RecommendationSlot? slot,
    bool includeContextWords = true,
    bool allowContextExpansion = true,
    bool preserveInputOrder = false,
    int limit = 12,
  }) async {
    final scored = await _rankExpressionsWithScores(
      baseWords,
      feature: feature,
      category: category,
      prompt: prompt,
      selectedWords: selectedWords,
      slot: slot,
      includeContextWords: includeContextWords,
      allowContextExpansion: allowContextExpansion,
      preserveInputOrder: preserveInputOrder,
    );
    return scored.take(limit).map((item) => item.text).toList(growable: false);
  }

  Future<Map<String, CompanionCandidateExplanation>> explainCandidates(
    List<String> candidates, {
    required String feature,
    String? category,
    String prompt = '',
    List<String> selectedWords = const [],
    RecommendationSlot? slot,
    bool includeContextWords = false,
    bool allowContextExpansion = false,
  }) async {
    if (candidates.isEmpty) return const {};
    final scored = await _rankExpressionsWithScores(
      candidates,
      feature: feature,
      category: category,
      prompt: prompt,
      selectedWords: selectedWords,
      slot: slot,
      includeContextWords: includeContextWords,
      allowContextExpansion: allowContextExpansion,
    );
    final byNormalized = <String, CompanionCandidateExplanation>{};
    for (final item in scored) {
      final normalized = LocationRecommendationController.normalizeText(
        item.text,
      );
      byNormalized[normalized] = CompanionCandidateExplanation(
        text: item.text,
        reason: item.reason,
      );
    }
    return byNormalized;
  }

  Future<List<_CompanionScoredText>> _rankExpressionsWithScores(
    List<String> baseWords, {
    required String feature,
    String? category,
    String prompt = '',
    List<String> selectedWords = const [],
    RecommendationSlot? slot,
    bool includeContextWords = true,
    bool allowContextExpansion = true,
    bool preserveInputOrder = false,
  }) async {
    final context = contextFor(
      feature: feature,
      latestUserFragment: prompt,
      prompt: prompt,
    );
    final inferredSlot = slot ?? RecommendationContext.inferSlot(prompt);
    final locationRanked = preserveInputOrder
        ? List<String>.of(baseWords)
        : _locationController.recommendWords(
            baseWords,
            category: category ?? feature,
            includeContextWords: includeContextWords,
            context: RecommendationContext(
              feature: feature,
              intent: prompt,
              prompt: prompt,
              slot: inferredSlot,
              selectedWords: selectedWords,
              allowContextExpansion: allowContextExpansion,
            ),
          );
    final feedback = _learningEnabled
        ? await _feedbackStore.profileForContextKeys(
            feedbackContextKeys(context, slot: inferredSlot),
          )
        : const CompanionFeedbackProfile(accepted: {}, rejected: {});
    final globalFeedback = _learningEnabled
        ? await _feedbackStore.profileForGlobalSignals(
            feature: feature,
            slot: inferredSlot,
          )
        : const CompanionFeedbackProfile(accepted: {}, rejected: {});
    final preferenceProfile = _learningEnabled
        ? await _currentPreferenceProfile()
        : UserPreferenceProfile.empty;
    final candidates = <String>[
      ...locationRanked,
      if (includeContextWords && allowContextExpansion)
        ..._contextSupplements(context, inferredSlot),
    ];
    final baseRank = <String, int>{
      for (var index = 0; index < locationRanked.length; index++)
        LocationRecommendationController.normalizeText(locationRanked[index]):
            index,
    };
    final seen = <String>{};
    final scored = <_CompanionScoredText>[];
    for (final candidate in candidates) {
      final clean = candidate.trim();
      final normalized = LocationRecommendationController.normalizeText(clean);
      if (clean.isEmpty || normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      final baseIndex = baseRank[normalized] ?? 120;
      final baseScore = preserveInputOrder
          ? math.max(0, 5000 - baseIndex * 350).toDouble()
          : math.max(0, 1200 - baseIndex * 8).toDouble();
      final memoryScore = _memoryScore(
        clean,
        context,
        category: category ?? feature,
        slot: inferredSlot,
      );
      final preferenceScore = _preferenceScore(
        clean,
        context,
        slot: inferredSlot,
        profile: preferenceProfile,
      );
      final contextFeedbackScore = feedback.scoreFor(clean);
      final globalFeedbackScore = _softGlobalFeedbackScore(
        globalFeedback.scoreFor(clean),
        context,
        clean,
        inferredSlot,
      );
      final feedbackScore = contextFeedbackScore + globalFeedbackScore;
      scored.add(_CompanionScoredText(
        text: clean,
        score: baseScore + memoryScore + preferenceScore + feedbackScore,
        baseScore: baseScore,
        memoryScore: memoryScore,
        preferenceScore: preferenceScore,
        feedbackScore: feedbackScore,
        reason: _candidateReason(
          clean,
          context,
          slot: inferredSlot,
          memoryScore: memoryScore,
          preferenceScore: preferenceScore,
          contextFeedbackScore: contextFeedbackScore,
          globalFeedbackScore: globalFeedbackScore,
        ),
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  Future<CompanionAgentDebugSnapshot> debugSnapshot({
    required String feature,
    String prompt = '',
    List<String> baseWords = const [],
    RecommendationSlot? slot,
    bool autoDetectionEnabled = false,
  }) async {
    final context = contextFor(feature: feature, prompt: prompt);
    final inferredSlot = slot ?? RecommendationContext.inferSlot(prompt);
    final key = contextKey(context, slot: inferredSlot);
    final keys = feedbackContextKeys(context, slot: inferredSlot);
    final feedback = _learningEnabled
        ? await _feedbackStore.profileForContextKeys(keys)
        : const CompanionFeedbackProfile(accepted: {}, rejected: {});
    final globalFeedback = _learningEnabled
        ? await _feedbackStore.profileForGlobalSignals(
            feature: feature,
            slot: inferredSlot,
          )
        : const CompanionFeedbackProfile(accepted: {}, rejected: {});
    final actionBias = _learningEnabled
        ? await _feedbackStore.actionBiasForContextKeys(keys)
        : const CompanionActionBias(accepted: {}, rejected: {});
    final recentFeedbackEvents = _learningEnabled
        ? await _feedbackStore.recentEventsForContextKeys(keys)
        : <String>[];
    final preferenceProfile = _learningEnabled
        ? await _currentPreferenceProfile()
        : UserPreferenceProfile.empty;
    final adaptiveActionPlan = await adaptivePlanFor(
      feature: feature,
      prompt: prompt,
      slot: inferredSlot,
      userRequested: feature == 'conversation' || feature == 'stuck',
      autoDetectionEnabled: autoDetectionEnabled,
    );
    final memorySignals = personalWordsForPrompt(
      feature: feature,
      prompt: prompt,
      limit: 14,
    );
    final previewSeeds = _unique([
      ...baseWords,
      ..._contextSupplements(context, inferredSlot),
      ...context.recentExpressions,
      ...context.favoriteExpressions,
    ]);
    final rankedWithScores = await _rankExpressionsWithScores(
      previewSeeds,
      feature: feature,
      prompt: prompt,
      slot: inferredSlot,
      includeContextWords: true,
      allowContextExpansion: true,
    );
    final rankedPreview = rankedWithScores
        .take(8)
        .map((item) => item.text)
        .toList(growable: false);
    final rankedExplanations = rankedWithScores
        .take(8)
        .map((item) => CompanionRankedExplanation(
              text: item.text,
              totalScore: item.score,
              baseScore: item.baseScore,
              memoryScore: item.memoryScore,
              preferenceScore: item.preferenceScore,
              feedbackScore: item.feedbackScore,
              reason: item.reason,
            ))
        .toList(growable: false);
    return CompanionAgentDebugSnapshot(
      context: context,
      decision: feature == 'conversation'
          ? evaluateConversation(
              userRequested: true,
              autoDetectionEnabled: autoDetectionEnabled,
            )
          : null,
      contextKey: key,
      feedbackContextKeys: keys,
      learningEnabled: _learningEnabled,
      memorySignals: memorySignals,
      rankedPreview: rankedPreview,
      rankedExplanations: rankedExplanations,
      preferenceProfileSummary: preferenceProfile.displaySummaryLines(limit: 8),
      learningLoopSummary: preferenceProfile.stats.displayLines(limit: 5),
      adaptiveActionPlan: adaptiveActionPlan,
      feedbackProfile: feedback,
      globalFeedbackProfile: globalFeedback,
      actionBias: actionBias,
      recentFeedbackEvents: recentFeedbackEvents,
    );
  }

  CompanionActionPlan planFor({
    required String feature,
    String prompt = '',
    RecommendationSlot? slot,
    bool userRequested = false,
    bool autoDetectionEnabled = false,
  }) {
    final context = contextFor(feature: feature, prompt: prompt);
    return _actionPlanFor(
      context,
      slot: slot ?? RecommendationContext.inferSlot(prompt),
      userRequested: userRequested,
      autoDetectionEnabled: autoDetectionEnabled,
    );
  }

  Future<CompanionActionPlan> adaptivePlanFor({
    required String feature,
    String prompt = '',
    RecommendationSlot? slot,
    bool userRequested = false,
    bool autoDetectionEnabled = false,
  }) async {
    final context = contextFor(feature: feature, prompt: prompt);
    final inferredSlot = slot ?? RecommendationContext.inferSlot(prompt);
    final base = _actionPlanFor(
      context,
      slot: inferredSlot,
      userRequested: userRequested,
      autoDetectionEnabled: autoDetectionEnabled,
    );
    if (!_learningEnabled) return base;
    final bias = await _feedbackStore.actionBiasForContextKeys(
      feedbackContextKeys(context, slot: inferredSlot),
    );
    final profile = await _currentPreferenceProfile();
    final locallyAdapted = _adaptPlanWithActionBias(
      base,
      context,
      slot: inferredSlot,
      bias: bias,
      userRequested: userRequested,
    );
    return _adaptPlanWithPreferenceProfile(
      locallyAdapted,
      context,
      slot: inferredSlot,
      profile: profile,
      userRequested: userRequested,
    );
  }

  CompanionAgentDecision evaluateConversation({
    bool userRequested = false,
    bool autoDetectionEnabled = false,
  }) {
    final context = contextFor(feature: 'conversation');
    final latest = context.latestUserFragment.trim();
    final transcript = context.recentTranscript.trim();
    final reasons = <String>[];

    final likelyStuck = _looksLikeStuck(latest, transcript);
    if (likelyStuck) reasons.add('检测到停顿、重复或未完成表达');
    if (context.keyPeople.isNotEmpty) {
      reasons.add('识别到对话人物 ${context.keyPeople.take(2).join('、')}');
    }
    if (context.keyPlaces.isNotEmpty) {
      reasons.add('识别到地点 ${context.keyPlaces.take(2).join('、')}');
    }
    if (context.placeType != PlaceTypeCatalog.unknown) {
      reasons.add('当前地点 ${context.placeLabel}');
    }

    final mode = _assistModeFor(context, likelyStuck);
    final actionPlan = _actionPlanFor(
      context,
      slot: RecommendationSlot.sentence,
      userRequested: userRequested,
      autoDetectionEnabled: autoDetectionEnabled,
      likelyStuck: likelyStuck,
      mode: userRequested || likelyStuck ? mode : CompanionAssistMode.none,
    );
    return CompanionAgentDecision(
      speakerLabel: context.userSpeakerLabel.trim().isEmpty
          ? '未确认'
          : context.userSpeakerLabel,
      topic: _topicFor(context),
      likelyStuck: likelyStuck,
      shouldPrompt: userRequested || (autoDetectionEnabled && likelyStuck),
      mode: userRequested || likelyStuck ? mode : CompanionAssistMode.none,
      actionPlan: actionPlan,
      reasons: reasons.isEmpty ? const ['语境仍在积累'] : reasons,
    );
  }

  List<String> personalWordsForPrompt({
    required String feature,
    String prompt = '',
    int limit = 24,
  }) {
    final context = contextFor(feature: feature, prompt: prompt);
    final decision = feature == 'conversation'
        ? evaluateConversation(userRequested: true)
        : null;
    final rankedHabits = ExpressionHabitStore.rank(
      _expressionHabits,
      category: feature,
      timeBucket: context.timeBucket,
      placeType: context.placeType,
      limit: 10,
    );
    return _unique([
      if (decision != null) '伴身智能体判断：${decision.brief}',
      '伴身语境：${context.modelBrief(maxTranscriptChars: 130)}',
      ...rankedHabits.map((habit) => '常用${habit.count}次：${habit.text}'),
      ...context.placeWords.take(6).map(
            (usage) => '当前地点常用${usage.count}次：${usage.wordText}',
          ),
      ...context.conversationTerms.take(8).map(
            (term) =>
                '${conversationTermTypeLabel(term.type)}：${term.text}（${term.count}次）',
          ),
      ...context.personalObjects.take(8).expand(
            (object) => [
              '个人物品：${object.displayName}',
              ...object.commonExpressions.map(
                (phrase) => '${object.displayName}相关表达：$phrase',
              ),
            ],
          ),
      ...context.favoriteExpressions.map((text) => '收藏：$text'),
    ]).take(limit).toList(growable: false);
  }

  Future<List<String>> personalizedPromptHints({
    required String feature,
    String prompt = '',
    RecommendationSlot? slot,
    int limit = 24,
  }) async {
    final context = contextFor(feature: feature, prompt: prompt);
    final inferredSlot = slot ?? RecommendationContext.inferSlot(prompt);
    final plan = await adaptivePlanFor(
      feature: feature,
      prompt: prompt,
      slot: inferredSlot,
      userRequested: feature == 'conversation' || feature == 'stuck',
    );
    final baseHints = personalWordsForPrompt(
      feature: feature,
      prompt: prompt,
      limit: limit,
    );
    if (!_learningEnabled) {
      return _unique([
        '智能体行动计划：${plan.modelInstruction}',
        ...baseHints,
      ]).take(limit).toList(growable: false);
    }

    final feedback = await _feedbackStore.profileForContextKeys(
      feedbackContextKeys(context, slot: inferredSlot),
    );
    final learnedExpressions = await _feedbackStore.topLearnedExpressions(
      feature: feature,
      limit: 6,
    );
    final preferenceProfile = await _currentPreferenceProfile();
    final hints = <String>[
      '智能体行动计划：${plan.modelInstruction}',
      ...baseHints,
      ...preferenceProfile.promptHints(limit: 8),
      if (feedback.topAccepted.isNotEmpty)
        '类似语境中用户更常确认：${feedback.topAccepted.join('、')}',
      if (feedback.topRejected.isNotEmpty)
        '类似语境中用户多次跳过：${feedback.topRejected.join('、')}；生成时不要优先使用这些表达',
      ...learnedExpressions.map(
        (item) => '智能体学习：${item.text}（确认/播报/保存 ${item.acceptedCount} 次）',
      ),
    ];
    return _unique(hints).take(limit).toList(growable: false);
  }

  Future<void> recordInteraction({
    required String text,
    required String feature,
    required CompanionFeedbackAction action,
    String prompt = '',
    RecommendationSlot? slot,
    String? objectTag,
  }) async {
    if (!_learningEnabled) return;
    final context = contextFor(feature: feature, prompt: prompt);
    final inferredSlot = slot ?? RecommendationContext.inferSlot(prompt);
    await _feedbackStore.record(
      contextKey: contextKey(
        context,
        slot: inferredSlot,
      ),
      text: text,
      feature: feature,
      action: action,
    );
    await _recordLearningEvent(
      text: text,
      feature: feature,
      action: action,
      context: context,
      slot: inferredSlot,
      objectTagOverride: objectTag,
    );
  }

  Future<void> recordActionPlanFeedback({
    required CompanionActionType type,
    required String feature,
    required CompanionFeedbackAction action,
    String prompt = '',
    RecommendationSlot? slot,
  }) async {
    if (!_learningEnabled) return;
    final context = contextFor(feature: feature, prompt: prompt);
    final inferredSlot = slot ?? RecommendationContext.inferSlot(prompt);
    await _feedbackStore.recordActionPlan(
      contextKey: contextKey(
        context,
        slot: inferredSlot,
      ),
      type: type,
      feature: feature,
      action: action,
    );
    await _recordActionPlanLearningEvent(
      type: type,
      feature: feature,
      action: action,
      context: context,
      slot: inferredSlot,
    );
  }

  Future<UserPreferenceProfile> _currentPreferenceProfile() async {
    _preferenceProfile = await _userLearningStore.loadProfile();
    return _preferenceProfile;
  }

  Future<void> _recordLearningEvent({
    required String text,
    required String feature,
    required CompanionFeedbackAction action,
    required UserContextModel context,
    required RecommendationSlot slot,
    String? objectTagOverride,
  }) async {
    final clean = text.trim();
    final normalized = LocationRecommendationController.normalizeText(clean);
    if (clean.isEmpty || normalized.isEmpty) return;
    final event = UserLearningEvent(
      feature: feature,
      action: action.name,
      text: clean,
      normalizedText: normalized,
      intentTag: _intentTagFor(clean, context, slot),
      objectTag: _normalizedObjectTag(objectTagOverride) ??
          _objectTagFor(clean, context),
      placeType: context.placeType,
      timeBucket: context.timeBucket,
      slotName: slot.name,
      createdAt: DateTime.now(),
    );
    await _userLearningStore.record(event);
    _preferenceProfile = await _userLearningStore.loadProfile();
    _onPreferenceProfileChanged?.call(_preferenceProfile);
  }

  String? _normalizedObjectTag(String? value) {
    final normalized = LocationRecommendationController.normalizeText(
      value?.trim() ?? '',
    );
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _recordActionPlanLearningEvent({
    required CompanionActionType type,
    required String feature,
    required CompanionFeedbackAction action,
    required UserContextModel context,
    required RecommendationSlot slot,
  }) async {
    final text = 'action:${type.name}';
    final event = UserLearningEvent(
      feature: feature,
      action: action.name,
      text: text,
      normalizedText: text,
      intentTag: 'action_plan_${type.name}',
      objectTag: '',
      placeType: context.placeType,
      timeBucket: context.timeBucket,
      slotName: slot.name,
      createdAt: DateTime.now(),
    );
    await _userLearningStore.record(event);
    _preferenceProfile = await _userLearningStore.loadProfile();
    _onPreferenceProfileChanged?.call(_preferenceProfile);
  }

  String _intentTagFor(
    String text,
    UserContextModel context,
    RecommendationSlot slot,
  ) {
    final combined = '${context.latestUserFragment} $text';
    if (RegExp(r'什么时候|几点|多久|时间|现在|今天|明天').hasMatch(combined)) {
      return 'ask_time';
    }
    if (RegExp(r'哪里|在哪|找|寻找|拿|递|给我').hasMatch(combined)) {
      return 'find_or_get';
    }
    if (RegExp(r'疼|痛|难受|不舒服|累|害怕|紧张').hasMatch(combined)) {
      return 'discomfort';
    }
    if (RegExp(r'再说|慢一点|什么意思|听不懂|不明白').hasMatch(combined)) {
      return 'understand';
    }
    if (RegExp(r'不是|说错|是不是|对吗|确认').hasMatch(combined)) {
      return 'clarify';
    }
    if (RegExp(r'帮我|能不能|可以|请').hasMatch(combined)) {
      return 'request_help';
    }
    return slot == RecommendationSlot.sentence ? 'say_sentence' : slot.name;
  }

  String _objectTagFor(String text, UserContextModel context) {
    final normalized = LocationRecommendationController.normalizeText(text);
    for (final object in context.personalObjects) {
      final objectName =
          LocationRecommendationController.normalizeText(object.displayName);
      if (objectName.isNotEmpty &&
          (normalized.contains(objectName) ||
              objectName.contains(normalized))) {
        return objectName;
      }
      for (final phrase in object.commonExpressions) {
        final normalizedPhrase =
            LocationRecommendationController.normalizeText(phrase);
        if (normalizedPhrase.isNotEmpty && normalized == normalizedPhrase) {
          return objectName;
        }
      }
    }
    return '';
  }

  Future<void> recordRejectedBatch({
    required List<String> texts,
    required String feature,
    required CompanionFeedbackAction action,
    String prompt = '',
    RecommendationSlot? slot,
  }) async {
    for (final text in texts) {
      await recordInteraction(
        text: text,
        feature: feature,
        action: action,
        prompt: prompt,
        slot: slot,
      );
    }
  }

  String contextKey(UserContextModel context, {RecommendationSlot? slot}) {
    final normalizedPrompt = LocationRecommendationController.normalizeText(
      context.latestUserFragment,
    );
    final promptTail = normalizedPrompt.length <= 10
        ? normalizedPrompt
        : normalizedPrompt.substring(normalizedPrompt.length - 10);
    final people = context.keyPeople.take(2).join(',');
    return [
      context.feature,
      (slot ?? RecommendationContext.inferSlot(context.latestUserFragment))
          .name,
      context.placeType,
      context.timeBucket,
      people,
      promptTail,
    ].where((part) => part.trim().isNotEmpty).join('|');
  }

  List<String> feedbackContextKeys(
    UserContextModel context, {
    RecommendationSlot? slot,
  }) {
    final effectiveSlot =
        (slot ?? RecommendationContext.inferSlot(context.latestUserFragment))
            .name;
    final people = context.keyPeople.take(2).join(',');
    final precise = contextKey(context, slot: slot);
    final hasPlace = context.placeType != PlaceTypeCatalog.unknown;
    final hasPeople = people.trim().isNotEmpty;
    return _unique([
      precise,
      if (hasPeople)
        [
          context.feature,
          effectiveSlot,
          context.placeType,
          context.timeBucket,
          people
        ].where((part) => part.trim().isNotEmpty).join('|'),
      if (hasPlace)
        [
          context.feature,
          effectiveSlot,
          context.placeType,
          context.timeBucket,
        ].join('|'),
      if (hasPlace)
        [context.feature, effectiveSlot, context.placeType].join('|'),
      if (hasPeople) [context.feature, effectiveSlot, people].join('|'),
    ]);
  }

  CompanionActionPlan _adaptPlanWithActionBias(
    CompanionActionPlan base,
    UserContextModel context, {
    required RecommendationSlot slot,
    required CompanionActionBias bias,
    required bool userRequested,
  }) {
    if (!bias.hasSignal) return base;
    final baseScore = bias.scoreFor(base.type);
    final preferred = bias.preferredType;
    final preferredScore =
        preferred == null ? double.negativeInfinity : bias.scoreFor(preferred);
    final evidence = <String>[
      ...base.evidence,
      if (bias.summaryFor(base.type).isNotEmpty) bias.summaryFor(base.type),
      if (preferred != null && preferred != base.type)
        '相似语境更常接受：${preferred.label}',
    ];

    if (!userRequested &&
        baseScore <= -2 &&
        (preferred == null || preferredScore <= 0)) {
      return _planFromActionType(
        CompanionActionType.observe,
        context,
        slot: slot,
        priority: math.max(15, base.priority - 24),
        evidence: [
          ...evidence,
          '相似语境中用户多次跳过该类提示，自动辅助降级为观察',
        ],
      );
    }

    if (preferred != null &&
        preferred != base.type &&
        preferredScore >= baseScore + 2) {
      return _planFromActionType(
        preferred,
        context,
        slot: slot,
        priority: math.min(96, base.priority + 8),
        evidence: evidence,
      );
    }

    if (evidence.length == base.evidence.length) return base;
    return base.copyWith(
      priority: (base.priority + baseScore.round()).clamp(10, 96),
      evidence: evidence,
    );
  }

  CompanionActionPlan _adaptPlanWithPreferenceProfile(
    CompanionActionPlan base,
    UserContextModel context, {
    required RecommendationSlot slot,
    required UserPreferenceProfile profile,
    required bool userRequested,
  }) {
    if (profile.actionPlanPreferences.isEmpty) return base;
    final baseScore = profile.actionPlanPreferences[base.type.name] ?? 0;
    final preferredEntry = profile.actionPlanPreferences.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final preferred = preferredEntry.isEmpty
        ? null
        : _actionTypeFromName(preferredEntry.first.key);
    final preferredScore = preferred == null
        ? double.negativeInfinity
        : preferredEntry.first.value;
    final evidence = <String>[
      ...base.evidence,
      if (baseScore != 0)
        '长期画像对${base.type.label}的反馈强度 ${baseScore.toStringAsFixed(1)}',
      if (preferred != null && preferred != base.type)
        '长期画像更常接受：${preferred.label}',
    ];

    if (!userRequested &&
        baseScore <= -2 &&
        (preferred == null || preferredScore <= 0)) {
      return _planFromActionType(
        CompanionActionType.observe,
        context,
        slot: slot,
        priority: math.max(15, base.priority - 18),
        evidence: [
          ...evidence,
          '长期画像显示用户较少接受该类自动辅助，先继续观察',
        ],
      );
    }

    if (preferred != null &&
        preferred != base.type &&
        preferredScore >= math.max(2.0, baseScore + 2.0)) {
      return _planFromActionType(
        preferred,
        context,
        slot: slot,
        priority: math.min(96, base.priority + 6),
        evidence: evidence,
      );
    }

    if (evidence.length == base.evidence.length) return base;
    return base.copyWith(
      priority: (base.priority + baseScore.round()).clamp(10, 96),
      evidence: evidence,
    );
  }

  CompanionActionType? _actionTypeFromName(String value) {
    for (final type in CompanionActionType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  CompanionActionPlan _planFromActionType(
    CompanionActionType type,
    UserContextModel context, {
    required RecommendationSlot slot,
    required int priority,
    required List<String> evidence,
  }) {
    return switch (type) {
      CompanionActionType.explain => CompanionActionPlan(
          type: CompanionActionType.explain,
          title: '帮用户理解对方内容',
          uiPrompt: '把对方的话拆成重点',
          modelInstruction: '优先做理解辅助：保留原话，把人物、地点、动作和请求拆开解释；不要替用户生成新事实。',
          requiresConfirmation: false,
          priority: priority,
          evidence: evidence,
        ),
      CompanionActionType.clarify => CompanionActionPlan(
          type: CompanionActionType.clarify,
          title: '生成确认澄清句',
          uiPrompt: '帮用户确认是不是这个意思',
          modelInstruction: '优先生成确认或澄清表达，例如“你是说……吗？”；不要把不确定内容写成确定事实。',
          requiresConfirmation: true,
          priority: priority,
          evidence: evidence,
        ),
      CompanionActionType.recommendWord => CompanionActionPlan(
          type: CompanionActionType.recommendWord,
          title: '推荐下一步关键词',
          uiPrompt: '先帮用户缩小选择范围',
          modelInstruction: '优先生成当前槽位的短关键词，每项尽量 2 到 6 个汉字；不要提前替用户组成完整句。',
          requiresConfirmation: true,
          priority: priority,
          evidence: evidence,
        ),
      CompanionActionType.recommendPhrase => CompanionActionPlan(
          type: CompanionActionType.recommendPhrase,
          title: '推荐短语或动作',
          uiPrompt: '给出不同方向的短语',
          modelInstruction: '优先生成不同语义方向的短语或动作表达，每项不超过 18 个汉字；避免只给同义词。',
          requiresConfirmation: true,
          priority: priority,
          evidence: evidence,
        ),
      CompanionActionType.recommendSentence => CompanionActionPlan(
          type: CompanionActionType.recommendSentence,
          title: '整理成可播报句子',
          uiPrompt: '给出一句可以确认后播报的话',
          modelInstruction:
              '优先生成完整、短、可直接播报的中文句子；必须基于当前对话和用户记忆，新增信息要写成请求、询问或可能性。',
          requiresConfirmation: true,
          priority: priority,
          evidence: evidence,
        ),
      CompanionActionType.observe => CompanionActionPlan(
          type: CompanionActionType.observe,
          title: '继续积累上下文',
          uiPrompt: '继续听取和记录上下文',
          modelInstruction: '上下文不足时先保持保守，优先给通用、安全、可撤回的表达。',
          requiresConfirmation: false,
          priority: priority,
          evidence: evidence.isEmpty ? const ['暂无足够上下文'] : evidence,
        ),
    };
  }

  List<String> _contextSupplements(
    UserContextModel context,
    RecommendationSlot slot,
  ) {
    final supplements = <String>[
      ...context.placeWords.map((usage) => usage.wordText),
      ...context.conversationTerms.map((term) => term.text),
      ...context.personalObjects.expand((object) => [
            object.displayName,
            ...object.commonExpressions,
          ]),
      ...context.favoriteExpressions,
      ...context.recentExpressions,
    ];
    return _unique(supplements)
        .where((text) => _fitsSlot(text, slot))
        .take(24)
        .toList(growable: false);
  }

  double _memoryScore(
    String text,
    UserContextModel context, {
    required String category,
    required RecommendationSlot slot,
  }) {
    final normalized = LocationRecommendationController.normalizeText(text);
    var score = 0.0;
    for (final habit in context.expressionHabits) {
      if (habit.normalizedText == normalized) {
        score += habit.scoreFor(
              category: category,
              timeBucket: context.timeBucket,
              placeType: context.placeType,
            ) /
            2.8;
      }
    }
    for (final usage in context.placeWords) {
      if (usage.normalizedText == normalized) {
        score += 360 + math.min(usage.count, 20) * 42;
      }
    }
    for (final term in context.conversationTerms) {
      if (term.normalizedText == normalized) {
        score += 280 + math.min(term.count, 12) * 36;
      }
    }
    for (final object in context.personalObjects) {
      final objectName =
          LocationRecommendationController.normalizeText(object.displayName);
      final expressionHit = object.commonExpressions.any(
        (phrase) =>
            LocationRecommendationController.normalizeText(phrase) ==
            normalized,
      );
      if (objectName == normalized || expressionHit) {
        score += 260 + math.min(object.usageCount, 12) * 32;
      }
    }
    if (context.favoriteExpressions.any((item) =>
        LocationRecommendationController.normalizeText(item) == normalized)) {
      score += 220;
    }
    if (!_fitsSlot(text, slot)) score -= 900;
    return score;
  }

  double _preferenceScore(
    String text,
    UserContextModel context, {
    required RecommendationSlot slot,
    required UserPreferenceProfile profile,
  }) {
    if (!profile.hasSignal || !_fitsSlot(text, slot)) return 0;
    var score =
        profile.hasExpressionSlotMismatch(text, slot.name) ? -520.0 : 0.0;
    score += profile.expressionScore(text, slotName: slot.name);
    score += profile.contextualScoreFor(
      text,
      feature: context.feature,
      placeType: context.placeType,
      slotName: slot.name,
    );
    final normalized = LocationRecommendationController.normalizeText(text);
    final objectMatches = profile.objectPatterns.where((signal) {
      return signal.key.contains(normalized) ||
          signal.latestText.contains(text) ||
          text.contains(signal.latestText);
    }).length;
    if (objectMatches > 0) score += math.min(objectMatches, 2) * 46.0;
    return score.clamp(-900.0, 900.0).toDouble();
  }

  double _softGlobalFeedbackScore(
    double rawScore,
    UserContextModel context,
    String text,
    RecommendationSlot slot,
  ) {
    if (rawScore == 0 || !_fitsSlot(text, slot)) return 0;
    final normalized = LocationRecommendationController.normalizeText(text);
    var multiplier = 0.16;
    if (context.favoriteExpressions.any((item) =>
        LocationRecommendationController.normalizeText(item) == normalized)) {
      multiplier += 0.10;
    }
    if (context.expressionHabits.any(
        (habit) => habit.normalizedText == normalized && habit.count >= 2)) {
      multiplier += 0.10;
    }
    if (context.placeWords.any((usage) => usage.normalizedText == normalized)) {
      multiplier += 0.08;
    }
    final capped = rawScore.clamp(-180.0, 180.0);
    return capped * multiplier.clamp(0.12, 0.34);
  }

  String _candidateReason(
    String text,
    UserContextModel context, {
    required RecommendationSlot slot,
    required double memoryScore,
    required double preferenceScore,
    required double contextFeedbackScore,
    required double globalFeedbackScore,
  }) {
    final normalized = LocationRecommendationController.normalizeText(text);
    final reasons = <String>[];
    if (preferenceScore > 0) {
      reasons.add('long-term user profile');
    }
    if (preferenceScore < 0) {
      reasons.add('long-term low preference');
    }
    if (contextFeedbackScore > 0) reasons.add('类似场景常确认');
    if (contextFeedbackScore < 0) reasons.add('曾被跳过，已降低优先级');
    if (contextFeedbackScore == 0 && globalFeedbackScore > 0) {
      reasons.add('长期偏好');
    }
    if (contextFeedbackScore == 0 && globalFeedbackScore < 0) {
      reasons.add('长期少选，已轻微降权');
    }
    if (context.placeWords.any((usage) => usage.normalizedText == normalized)) {
      reasons.add('当前地点常用');
    }
    if (context.expressionHabits.any(
        (habit) => habit.normalizedText == normalized && habit.count >= 2)) {
      reasons.add('你的常用表达');
    }
    if (context.conversationTerms.any((term) =>
        term.normalizedText == normalized || text.contains(term.text))) {
      reasons.add('来自当前对话');
    }
    if (context.personalObjects.any((object) {
      final objectName =
          LocationRecommendationController.normalizeText(object.displayName);
      return objectName == normalized ||
          object.commonExpressions.any(
            (phrase) =>
                LocationRecommendationController.normalizeText(phrase) ==
                normalized,
          );
    })) {
      reasons.add('关联个人物品');
    }
    if (reasons.isEmpty && memoryScore > 0) reasons.add('符合个人记忆');
    if (reasons.isEmpty && _fitsSlot(text, slot)) reasons.add('贴合当前步骤');
    return _unique(reasons).take(2).join(' · ');
  }

  bool _fitsSlot(String text, RecommendationSlot slot) {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    switch (slot) {
      case RecommendationSlot.any:
      case RecommendationSlot.topic:
      case RecommendationSlot.sentence:
        return true;
      case RecommendationSlot.person:
        return _conversationTerms.any((term) =>
                term.type == 'person' &&
                term.normalizedText ==
                    LocationRecommendationController.normalizeText(clean)) ||
            RegExp(r'妈妈|爸爸|家人|朋友|医生|护士|老师|同学|同事|工作人员').hasMatch(clean);
      case RecommendationSlot.place:
        return _conversationTerms.any((term) =>
                term.type == 'place' &&
                term.normalizedText ==
                    LocationRecommendationController.normalizeText(clean)) ||
            RegExp(r'家|医院|超市|学校|公园|药店|餐厅|公司|小区|车站|地铁|厕所|这里').hasMatch(clean);
      case RecommendationSlot.time:
        return RegExp(r'现在|刚才|今天|明天|昨天|早上|中午|下午|晚上|一会儿|最近').hasMatch(clean);
      case RecommendationSlot.bodyPart:
        return RegExp(r'头|手|脚|腿|胳膊|胸|肚子|腰|背|喉咙|牙|眼睛').hasMatch(clean);
      case RecommendationSlot.feeling:
        return RegExp(r'疼|痛|累|晕|冷|热|难受|舒服|害怕|着急|恶心').hasMatch(clean);
      case RecommendationSlot.actionOrObject:
        return clean.length <= 14;
    }
  }

  bool _looksLikeStuck(String latest, String transcript) {
    final clean = latest.trim();
    if (clean.isEmpty && transcript.isNotEmpty) return true;
    if (RegExp(r'嗯|啊|那个|就是|我想|等一下|怎么说|说不出来').hasMatch(clean)) {
      return true;
    }
    final normalized = LocationRecommendationController.normalizeText(clean);
    if (normalized.length <= 2 && transcript.length > 12) return true;
    final repeated = RegExp(r'(.{1,3})\1{2,}').hasMatch(normalized);
    if (repeated) return true;
    return RegExp(r'(我想|我要|能不能|帮我|是不是|在哪里)$').hasMatch(clean);
  }

  CompanionActionPlan _actionPlanFor(
    UserContextModel context, {
    required RecommendationSlot slot,
    bool userRequested = false,
    bool autoDetectionEnabled = false,
    bool? likelyStuck,
    CompanionAssistMode? mode,
  }) {
    final effectiveMode = mode ??
        _assistModeFor(
          context,
          likelyStuck ??
              _looksLikeStuck(
                context.latestUserFragment,
                context.recentTranscript,
              ),
        );
    final evidence = <String>[
      '功能：${context.feature}',
      if (context.latestUserFragment.trim().isNotEmpty)
        '最后片段：${context.latestUserFragment.trim()}',
      if (context.keyPeople.isNotEmpty)
        '人物：${context.keyPeople.take(2).join('、')}',
      if (context.placeType != PlaceTypeCatalog.unknown)
        '地点：${context.placeLabel}',
      if (context.objectNames.isNotEmpty)
        '物品：${context.objectNames.take(2).join('、')}',
      if (userRequested) '用户主动触发',
      if (autoDetectionEnabled) '自动检测开启',
    ];

    if (effectiveMode == CompanionAssistMode.comprehension) {
      return CompanionActionPlan(
        type: CompanionActionType.explain,
        title: '帮用户理解对方内容',
        uiPrompt: '把对方的话拆成重点',
        modelInstruction: '优先做理解辅助：保留原话，把人物、地点、动作和请求拆开解释；不要替用户生成新事实。',
        requiresConfirmation: false,
        priority: 82,
        evidence: evidence,
      );
    }
    if (effectiveMode == CompanionAssistMode.clarification) {
      return CompanionActionPlan(
        type: CompanionActionType.clarify,
        title: '生成确认澄清句',
        uiPrompt: '帮用户确认是不是这个意思',
        modelInstruction: '优先生成确认或澄清表达，例如“你是说……吗？”；不要把不确定内容写成确定事实。',
        requiresConfirmation: true,
        priority: 78,
        evidence: evidence,
      );
    }
    if (context.feature == 'conversation' ||
        slot == RecommendationSlot.sentence) {
      return CompanionActionPlan(
        type: CompanionActionType.recommendSentence,
        title: '整理成可播报句子',
        uiPrompt: '给出一句可以确认后播报的话',
        modelInstruction: '优先生成完整、短、可直接播报的中文句子；必须基于当前对话和用户记忆，新增信息要写成请求、询问或可能性。',
        requiresConfirmation: true,
        priority: effectiveMode == CompanionAssistMode.expression ? 88 : 66,
        evidence: evidence,
      );
    }

    final wordSlots = {
      RecommendationSlot.person,
      RecommendationSlot.place,
      RecommendationSlot.time,
      RecommendationSlot.bodyPart,
      RecommendationSlot.feeling,
    };
    if (wordSlots.contains(slot)) {
      return CompanionActionPlan(
        type: CompanionActionType.recommendWord,
        title: '推荐下一步关键词',
        uiPrompt: '先帮用户缩小选择范围',
        modelInstruction: '优先生成当前槽位的短关键词，每项尽量 2 到 6 个汉字；不要提前替用户组成完整句。',
        requiresConfirmation: true,
        priority: 70,
        evidence: evidence,
      );
    }
    if (slot == RecommendationSlot.actionOrObject ||
        slot == RecommendationSlot.topic) {
      return CompanionActionPlan(
        type: CompanionActionType.recommendPhrase,
        title: '推荐短语或动作',
        uiPrompt: '给出不同方向的短语',
        modelInstruction: '优先生成不同语义方向的短语或动作表达，每项不超过 18 个汉字；避免只给同义词。',
        requiresConfirmation: true,
        priority: 72,
        evidence: evidence,
      );
    }
    return CompanionActionPlan(
      type: CompanionActionType.observe,
      title: '继续积累上下文',
      uiPrompt: '继续听取和记录上下文',
      modelInstruction: '上下文不足时先保持保守，优先给通用、安全、可撤回的表达。',
      requiresConfirmation: false,
      priority: 30,
      evidence: evidence.isEmpty ? const ['暂无足够上下文'] : evidence,
    );
  }

  CompanionAssistMode _assistModeFor(
    UserContextModel context,
    bool likelyStuck,
  ) {
    final latest = context.latestUserFragment;
    if (RegExp(r'什么意思|没听懂|不明白|再说|太快').hasMatch(latest)) {
      return CompanionAssistMode.comprehension;
    }
    if (RegExp(r'对吗|是不是|不是这个|说错').hasMatch(latest)) {
      return CompanionAssistMode.clarification;
    }
    if (likelyStuck) return CompanionAssistMode.expression;
    final recent = context.recentTranscript;
    if (RegExp(r'[？?]|吗|什么|哪里|怎么|为什么').hasMatch(recent)) {
      return CompanionAssistMode.expression;
    }
    return CompanionAssistMode.none;
  }

  String _topicFor(UserContextModel context) {
    if (context.keyPeople.isNotEmpty) {
      return '和${context.keyPeople.first}相关的对话';
    }
    if (context.keyPlaces.isNotEmpty) {
      return '${context.keyPlaces.first}相关';
    }
    if (context.placeType != PlaceTypeCatalog.unknown) {
      return context.placeLabel;
    }
    final frequent = ExpressionHabitStore.rank(
      context.expressionHabits,
      limit: 1,
    );
    if (frequent.isNotEmpty) return frequent.first.text;
    return '日常交流';
  }

  static List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      final normalized = LocationRecommendationController.normalizeText(clean);
      if (clean.isEmpty || normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      result.add(clean);
    }
    return result;
  }

  static String _timeLabel(DateTime now) {
    final period = switch (now.hour) {
      >= 5 && < 11 => '早上',
      >= 11 && < 14 => '中午',
      >= 14 && < 18 => '下午',
      >= 18 && < 24 => '晚上',
      _ => '深夜',
    };
    return '$period ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }
}

class CompanionFeedbackProfile {
  const CompanionFeedbackProfile({
    required this.accepted,
    required this.rejected,
  });

  final Map<String, int> accepted;
  final Map<String, int> rejected;

  int get acceptedTotal => accepted.values.fold(0, (sum, value) => sum + value);

  int get rejectedTotal => rejected.values.fold(0, (sum, value) => sum + value);

  List<String> get topAccepted => _topKeys(accepted);

  List<String> get topRejected => _topKeys(rejected);

  double scoreFor(String text) {
    final normalized = LocationRecommendationController.normalizeText(text);
    return (accepted[normalized] ?? 0) * 260.0 -
        (rejected[normalized] ?? 0) * 520.0;
  }

  static List<String> _topKeys(Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(5)
        .map((entry) => '${entry.key} x${entry.value}')
        .toList(growable: false);
  }
}

class CompanionLearnedExpression {
  const CompanionLearnedExpression({
    required this.text,
    required this.normalizedText,
    required this.acceptedCount,
    required this.rejectedCount,
  });

  final String text;
  final String normalizedText;
  final int acceptedCount;
  final int rejectedCount;

  double get score => acceptedCount - rejectedCount * 1.6;

  String get displayLine {
    final rejected = rejectedCount > 0 ? '，跳过 $rejectedCount 次' : '';
    return '$text · 正向 $acceptedCount 次$rejected';
  }
}

class CompanionFeedbackStore {
  static const _storageKey = 'companion_agent_feedback_v1';
  static const _maxEntries = 240;
  static const _actionPlanPrefix = '__action_plan__:';

  Future<void> record({
    required String contextKey,
    required String text,
    required String feature,
    required CompanionFeedbackAction action,
  }) async {
    final clean = text.trim();
    final normalized = LocationRecommendationController.normalizeText(clean);
    if (contextKey.trim().isEmpty || normalized.isEmpty) return;
    final entries = await _load();
    entries.add(_CompanionFeedbackEntry(
      contextKey: contextKey,
      text: clean,
      normalizedText: normalized,
      feature: feature,
      action: action.name,
      createdAt: DateTime.now(),
    ));
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    await SensitiveLocalStore.writeString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> recordActionPlan({
    required String contextKey,
    required CompanionActionType type,
    required String feature,
    required CompanionFeedbackAction action,
  }) async {
    if (contextKey.trim().isEmpty) return;
    final entries = await _load();
    entries.add(_CompanionFeedbackEntry(
      contextKey: contextKey,
      text: '$_actionPlanPrefix${type.name}',
      normalizedText: 'action:${type.name}',
      feature: feature,
      action: action.name,
      createdAt: DateTime.now(),
    ));
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    await SensitiveLocalStore.writeString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<CompanionFeedbackProfile> profileFor(String contextKey) {
    return profileForContextKeys([contextKey]);
  }

  Future<CompanionFeedbackProfile> profileForContextKeys(
    List<String> contextKeys,
  ) async {
    final entries = await _load();
    final keys = contextKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final accepted = <String, int>{};
    final rejected = <String, int>{};
    for (final entry in entries.where((item) => _matchesAnyKey(item, keys))) {
      if (_isActionPlanEntry(entry)) continue;
      if (_isPositive(entry.action)) {
        accepted.update(entry.normalizedText, (value) => value + 1,
            ifAbsent: () => 1);
      } else if (_isNegative(entry.action)) {
        rejected.update(entry.normalizedText, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    return CompanionFeedbackProfile(
      accepted: accepted,
      rejected: rejected,
    );
  }

  Future<CompanionFeedbackProfile> profileForGlobalSignals({
    String? feature,
    RecommendationSlot? slot,
  }) async {
    final entries = await _load();
    final accepted = <String, int>{};
    final rejected = <String, int>{};
    for (final entry in entries) {
      if (_isActionPlanEntry(entry)) continue;
      if (feature != null && entry.feature != feature) continue;
      if (slot != null && !_entryMatchesSlot(entry, slot)) continue;
      if (_isPositive(entry.action)) {
        accepted.update(entry.normalizedText, (value) => value + 1,
            ifAbsent: () => 1);
      } else if (_isNegative(entry.action)) {
        rejected.update(entry.normalizedText, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    return CompanionFeedbackProfile(
      accepted: accepted,
      rejected: rejected,
    );
  }

  Future<CompanionActionBias> actionBiasForContextKeys(
    List<String> contextKeys,
  ) async {
    final entries = await _load();
    final keys = contextKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final accepted = <CompanionActionType, int>{};
    final rejected = <CompanionActionType, int>{};
    for (final entry in entries.where((item) => _matchesAnyKey(item, keys))) {
      if (!_isActionPlanEntry(entry)) continue;
      final actionType = _actionTypeForEntry(entry);
      if (actionType == null) continue;
      if (_isPositive(entry.action)) {
        accepted.update(actionType, (value) => value + 1, ifAbsent: () => 1);
      } else if (_isNegative(entry.action)) {
        rejected.update(actionType, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return CompanionActionBias(accepted: accepted, rejected: rejected);
  }

  Future<List<String>> recentEventsFor(String contextKey, {int limit = 8}) {
    return recentEventsForContextKeys([contextKey], limit: limit);
  }

  Future<List<String>> recentEventsForContextKeys(
    List<String> contextKeys, {
    int limit = 8,
  }) async {
    final entries = await _load();
    final keys = contextKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final seen = <String>{};
    return entries
        .where((entry) => _matchesAnyKey(entry, keys))
        .toList()
        .reversed
        .where((entry) {
          final eventKey =
              '${entry.createdAt.toIso8601String()}|${entry.action}|${entry.text}';
          return seen.add(eventKey);
        })
        .take(limit)
        .map((entry) {
          final minute = entry.createdAt.minute.toString().padLeft(2, '0');
          return '${entry.createdAt.hour}:$minute ${entry.action} · ${entry.text}';
        })
        .toList(growable: false);
  }

  Future<List<CompanionLearnedExpression>> topLearnedExpressions({
    int limit = 8,
    String? feature,
  }) async {
    final entries = await _load();
    final accepted = <String, int>{};
    final rejected = <String, int>{};
    final latestText = <String, String>{};
    for (final entry in entries) {
      if (_isActionPlanEntry(entry)) continue;
      if (feature != null && entry.feature != feature) continue;
      latestText[entry.normalizedText] = entry.text;
      if (_isPositive(entry.action)) {
        accepted.update(entry.normalizedText, (value) => value + 1,
            ifAbsent: () => 1);
      } else if (_isNegative(entry.action)) {
        rejected.update(entry.normalizedText, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    final learned = latestText.entries
        .map((entry) => CompanionLearnedExpression(
              text: entry.value,
              normalizedText: entry.key,
              acceptedCount: accepted[entry.key] ?? 0,
              rejectedCount: rejected[entry.key] ?? 0,
            ))
        .where((item) => item.acceptedCount > 0 && item.score > 0)
        .toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        return b.acceptedCount.compareTo(a.acceptedCount);
      });
    return learned.take(limit).toList(growable: false);
  }

  Future<void> clearAll() async {
    await SensitiveLocalStore.delete(
      _storageKey,
      legacySharedPreferencesKey: _storageKey,
    );
  }

  static bool _matchesAnyKey(
    _CompanionFeedbackEntry entry,
    List<String> contextKeys,
  ) {
    if (contextKeys.isEmpty) return false;
    return contextKeys.any(
      (key) => entry.contextKey == key || entry.contextKey.startsWith('$key|'),
    );
  }

  static bool _entryMatchesSlot(
    _CompanionFeedbackEntry entry,
    RecommendationSlot slot,
  ) {
    final parts = entry.contextKey.split('|');
    return parts.length >= 2 && parts[1] == slot.name;
  }

  Future<List<_CompanionFeedbackEntry>> _load() async {
    final raw = await SensitiveLocalStore.readString(
      _storageKey,
      legacySharedPreferencesKey: _storageKey,
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => _CompanionFeedbackEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .whereType<_CompanionFeedbackEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static bool _isPositive(String action) {
    return action == CompanionFeedbackAction.accepted.name ||
        action == CompanionFeedbackAction.spoken.name ||
        action == CompanionFeedbackAction.saved.name;
  }

  static bool _isNegative(String action) {
    return action == CompanionFeedbackAction.rejected.name ||
        action == CompanionFeedbackAction.skipped.name ||
        action == CompanionFeedbackAction.refreshed.name ||
        action == CompanionFeedbackAction.deleted.name;
  }

  static CompanionActionType? _actionTypeForEntry(
    _CompanionFeedbackEntry entry,
  ) {
    if (entry.text.startsWith(_actionPlanPrefix)) {
      final raw = entry.text.substring(_actionPlanPrefix.length);
      return CompanionActionType.values.firstWhere(
        (type) => type.name == raw,
        orElse: () => CompanionActionType.observe,
      );
    }
    return null;
  }

  static bool _isActionPlanEntry(_CompanionFeedbackEntry entry) {
    return entry.text.startsWith(_actionPlanPrefix) ||
        entry.normalizedText.startsWith('action:');
  }
}

class _CompanionFeedbackEntry {
  const _CompanionFeedbackEntry({
    required this.contextKey,
    required this.text,
    required this.normalizedText,
    required this.feature,
    required this.action,
    required this.createdAt,
  });

  final String contextKey;
  final String text;
  final String normalizedText;
  final String feature;
  final String action;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
        'contextKey': contextKey,
        'text': text,
        'normalizedText': normalizedText,
        'feature': feature,
        'action': action,
        'createdAt': createdAt.toIso8601String(),
      };

  static _CompanionFeedbackEntry? fromJson(Map<String, dynamic> json) {
    final contextKey = json['contextKey']?.toString() ?? '';
    final text = json['text']?.toString() ?? '';
    final normalized = json['normalizedText']?.toString() ??
        LocationRecommendationController.normalizeText(text);
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (contextKey.isEmpty || normalized.isEmpty || createdAt == null) {
      return null;
    }
    return _CompanionFeedbackEntry(
      contextKey: contextKey,
      text: text,
      normalizedText: normalized,
      feature: json['feature']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      createdAt: createdAt,
    );
  }
}

class _CompanionScoredText {
  const _CompanionScoredText({
    required this.text,
    required this.score,
    required this.baseScore,
    required this.memoryScore,
    required this.preferenceScore,
    required this.feedbackScore,
    required this.reason,
  });

  final String text;
  final double score;
  final double baseScore;
  final double memoryScore;
  final double preferenceScore;
  final double feedbackScore;
  final String reason;
}
