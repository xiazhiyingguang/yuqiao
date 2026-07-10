part of 'main.dart';

class StuckFlowPage extends StatefulWidget {
  const StuckFlowPage({
    super.key,
    required this.qwenService,
    required this.locationController,
    required this.companionAgent,
    required this.personalizedLearningEnabled,
    required this.vocabularyEntries,
    required this.expressionHabits,
    this.preferredCandidateCount = 4,
    this.candidateImageScale = 1.0,
    required this.featureLauncher,
    required this.onHabitRecorded,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
  });

  final QwenService qwenService;
  final LocationRecommendationController locationController;
  final CompanionAgentController companionAgent;
  final bool personalizedLearningEnabled;
  final List<VocabularyEntry> vocabularyEntries;
  final List<ExpressionHabit> expressionHabits;
  final int preferredCandidateCount;
  final double candidateImageScale;
  final YuqiaoFeatureLauncher featureLauncher;
  final HabitRecordCallback onHabitRecorded;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;

  @override
  State<StuckFlowPage> createState() => _GuidedStuckFlowPageState();
}

class _GuidedStuckFlowPageState extends State<StuckFlowPage> {
  final ParaformerAsrService _fragmentAsrService = ParaformerAsrService();
  StuckExpressionSession? _session;
  List<StuckCandidate> _visibleCandidates = const [];
  final Set<String> _seenCandidates = {};
  QwenCancellationToken? _recommendationToken;
  String _seedFragment = '';
  bool _isRecommending = false;
  bool _isRefreshing = false;
  bool _isHandlingBack = false;
  bool _isExitingCompletedFlow = false;
  int _recommendationRequestId = 0;
  int _refreshAttempts = 0;
  CompanionActionPlan? _activeActionPlan;

  @override
  void initState() {
    super.initState();
    widget.locationController.refreshLocationContext();
  }

  @override
  void dispose() {
    _recommendationToken?.cancel();
    unawaited(_fragmentAsrService.dispose());
    super.dispose();
  }

  String get _timeContext {
    final now = DateTime.now();
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

  String get _locationContext {
    if (!widget.locationController.enabled) return '未开启地点推荐';
    final place = widget.locationController.currentPlace;
    if (place != null) return place.typeLabel;
    final semantic = widget.locationController.currentSemantic;
    return semantic == null ? '未知地点' : PlaceTypeCatalog.labelOf(semantic.type);
  }

  void _chooseIntent(StuckExpressionIntent intent) {
    setState(() {
      _session = StuckExpressionSession(
        intent: intent,
        seedFragment: _seedFragment,
      );
      _resetStepState();
    });
    unawaited(_recommendCurrentStep());
  }

  void _resetStepState() {
    _recommendationRequestId++;
    _recommendationToken?.cancel();
    _visibleCandidates = const [];
    _seenCandidates.clear();
    _refreshAttempts = 0;
    _isRecommending = false;
    _isRefreshing = false;
    _activeActionPlan = null;
  }

  Future<void> _chooseCandidate(StuckCandidate candidate) async {
    final session = _session;
    if (session == null) return;
    final actionPlan = _activeActionPlan;
    unawaited(
      widget.locationController.recordWordUsed(candidate.text, 'stuck'),
    );
    unawaited(
      widget.onHabitRecorded(
        candidate.text,
        category: 'stuck',
        source: 'stuck_candidate',
      ),
    );
    unawaited(widget.companionAgent.recordInteraction(
      text: candidate.text,
      feature: 'stuck',
      action: CompanionFeedbackAction.accepted,
      prompt: session.currentStep?.title ?? session.intent.sentenceIntent,
      slot: _locationSlotFor(candidate.slot),
    ));
    if (actionPlan != null) {
      unawaited(widget.companionAgent.recordActionPlanFeedback(
        type: actionPlan.type,
        feature: 'stuck',
        action: CompanionFeedbackAction.accepted,
        prompt: session.currentStep?.title ?? session.intent.sentenceIntent,
        slot: _locationSlotFor(candidate.slot),
      ));
    }
    setState(() {
      session.select(candidate);
      _resetStepState();
    });
    if (session.currentStep != null) {
      await _recommendCurrentStep();
    }
  }

  Future<void> _skipCurrentStep() async {
    final session = _session;
    final step = session?.currentStep;
    if (session == null || step?.optional != true) return;
    _recordVisibleCandidateFeedback(
      session: session,
      step: step!,
      action: CompanionFeedbackAction.skipped,
    );
    setState(() {
      session.skipCurrent();
      _resetStepState();
    });
    if (session.currentStep != null) {
      await _recommendCurrentStep();
    }
  }

  Future<void> _editFrom(StuckExpressionSlot slot) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      session.clearFrom(slot);
      _resetStepState();
    });
    await _recommendCurrentStep();
  }

  Future<void> _goBackWithinFlow() async {
    if (!mounted || _isHandlingBack) return;
    _isHandlingBack = true;
    try {
      final session = _session;
      if (session == null) {
        _recommendationToken?.cancel();
        await _fragmentAsrService.stop();
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      final selections = session.selections;
      if (selections.isNotEmpty) {
        await _editFrom(selections.last.slot);
        return;
      }
      _recommendationToken?.cancel();
      setState(() {
        _session = null;
        _resetStepState();
      });
    } finally {
      _isHandlingBack = false;
    }
  }

  Future<void> _finishExpression() async {
    final session = _session;
    if (session == null || !session.canFinish) return;
    final keywords = <String>[
      if (session.seedFragment.trim().isNotEmpty)
        '用户记得的片段：${session.seedFragment.trim()}',
      ...session.selections.map(
        (selection) => '已确认${selection.slot.label}：${selection.candidate.text}',
      ),
    ];
    try {
      final hints = await widget.companionAgent.personalizedPromptHints(
        feature: 'stuck',
        prompt: session.intent.sentenceIntent,
        slot: RecommendationSlot.sentence,
        limit: 8,
      );
      keywords.addAll(hints.map((hint) => '智能体提示：$hint'));
    } catch (error) {
      yuqiaoDebugLog('[StuckFlow] personalized sentence hints skipped: $error');
    }
    if (!mounted) return;
    final draft = ExpressionDraft(
      source: '独立补词',
      intent: session.intent.sentenceIntent,
      keywords: keywords,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCandidatesPage(
          draft: draft,
          qwenService: widget.qwenService,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
          onExitFlow: _exitCompletedFlow,
          onCandidateSelected: (text) async {
            unawaited(widget.locationController.recordWordUsed(text, 'stuck'));
            unawaited(
              widget.onHabitRecorded(
                text,
                category: 'stuck',
                source: 'stuck_sentence_candidate',
              ),
            );
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'stuck',
              action: CompanionFeedbackAction.accepted,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            ));
            unawaited(widget.companionAgent.recordActionPlanFeedback(
              type: CompanionActionType.recommendSentence,
              feature: 'stuck',
              action: CompanionFeedbackAction.accepted,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            ));
          },
          onCandidateSaved: (text) async {
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'stuck',
              action: CompanionFeedbackAction.saved,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            ));
          },
          onCandidatesRejected: (sentences) async {
            await widget.companionAgent.recordRejectedBatch(
              texts: sentences,
              feature: 'stuck',
              action: CompanionFeedbackAction.rejected,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            );
            await widget.companionAgent.recordActionPlanFeedback(
              type: CompanionActionType.recommendSentence,
              feature: 'stuck',
              action: CompanionFeedbackAction.rejected,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            );
          },
          onExpressionCompleted: widget.onExpressionCompleted,
          onFavoriteSaved: widget.onFavoriteSaved,
        ),
      ),
    );
  }

  void _exitCompletedFlow() {
    if (!mounted || _isExitingCompletedFlow) return;
    _isExitingCompletedFlow = true;
    final flowRoute = ModalRoute.of(context);
    if (flowRoute == null) {
      Navigator.of(context).pop();
      return;
    }
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => identical(route, flowRoute));
    navigator.pop();
  }

  Future<void> _recommendCurrentStep({
    bool forceRefresh = false,
    int diversificationLevel = 0,
  }) async {
    final session = _session;
    final step = session?.currentStep;
    if (session == null || step == null) return;
    final requestId = ++_recommendationRequestId;
    _recommendationToken?.cancel();
    final token = QwenCancellationToken();
    _recommendationToken = token;
    final startedAt = DateTime.now();
    setState(() {
      _isRecommending = true;
      if (!forceRefresh) _visibleCandidates = const [];
    });

    final localCandidates = _localCandidates(step);
    List<String> personalizedHints = const [];
    try {
      final plan = await widget.companionAgent.adaptivePlanFor(
        feature: 'stuck',
        prompt: step.title.isEmpty ? session.intent.sentenceIntent : step.title,
        slot: _locationSlotFor(step.slot),
        userRequested: true,
      );
      personalizedHints = await widget.companionAgent.personalizedPromptHints(
        feature: 'stuck',
        prompt: step.title.isEmpty ? session.intent.sentenceIntent : step.title,
        slot: _locationSlotFor(step.slot),
        limit: 8,
      );
      if (!mounted || requestId != _recommendationRequestId) return;
      _activeActionPlan = plan;
    } catch (error) {
      yuqiaoDebugLog('[StuckFlow] adaptive action plan skipped: $error');
    }
    List<StuckCandidate> modelCandidates = const [];
    try {
      modelCandidates = await widget.qwenService
          .recommendGuidedOptions(
            CandidateRecommendationRequest(
              intent: session.intent.sentenceIntent,
              stepTitle: step.title,
              slotKey: step.slot.key,
              slotLabel: step.slot.label,
              timeText: _timeContext,
              locationText: _locationContext,
              selectedKeywords: [
                if (session.seedFragment.isNotEmpty)
                  '记得的片段：${session.seedFragment}',
                ...session.selections.map(
                  (selection) =>
                      '${selection.slot.label}：${selection.candidate.text}',
                ),
              ],
              fallbackOptions:
                  localCandidates.map((candidate) => candidate.text).toList(),
              personalWords: [
                ..._personalWordsForStep(step),
                ...personalizedHints,
              ].take(32).toList(),
              excludeOptions: _seenCandidates.toList(),
              displayCount: widget.preferredCandidateCount.clamp(2, 6).toInt(),
              diversificationLevel: diversificationLevel,
            ),
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 6));
    } catch (error) {
      final cancelled = token.isCancelled || error is QwenCancelledException;
      token.cancel();
      if (!cancelled) {
        yuqiaoDebugLog('[StuckFlow] Qwen candidate fallback: $error');
      }
    }
    if (!mounted || requestId != _recommendationRequestId) return;

    // 首次 TLS 连接和模型冷启动可能超过 5 秒，不能过早伪装成模型推荐。
    if (modelCandidates.isEmpty && !forceRefresh) {
      final elapsed = DateTime.now().difference(startedAt);
      const fallbackDelay = Duration(seconds: 5);
      if (elapsed < fallbackDelay) {
        await Future<void>.delayed(fallbackDelay - elapsed);
      }
    }
    if (!mounted || requestId != _recommendationRequestId) return;

    final merged = await _mergeCandidatePool(
      modelCandidates: modelCandidates,
      localCandidates: localCandidates,
      step: step,
    );
    if (!mounted || requestId != _recommendationRequestId) return;
    final next = _takeDiverseCandidates(merged, step);
    yuqiaoDebugLog(
      '[StuckFlow] source=${modelCandidates.isEmpty ? 'local-fallback' : 'qwen'} '
      'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds} '
      'context=${session.selections.map((item) => item.candidate.text).join('/')} '
      'seed=${session.seedFragment}',
    );
    setState(() {
      _visibleCandidates = next;
      _isRecommending = false;
      _isRefreshing = false;
    });
    if (next.isEmpty) {
      await _showClarificationSheet();
    }
  }

  List<StuckCandidate> _localCandidates(StuckStepDefinition step) {
    final result = <StuckCandidate>[];
    final seen = <String>{};
    for (final entry in widget.vocabularyEntries) {
      if (!step.vocabularyCategories.contains(entry.category)) continue;
      final normalized =
          LocationRecommendationController.normalizeText(entry.text);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(StuckCandidate(
        text: entry.text,
        semanticGroup: entry.category,
        slot: step.slot,
      ));
    }
    for (final candidate in step.options) {
      final normalized =
          LocationRecommendationController.normalizeText(candidate.text);
      if (seen.add(normalized)) result.add(candidate);
    }
    return result;
  }

  List<String> _personalWordsForStep(StuckStepDefinition step) {
    final habitWords = ExpressionHabitStore.rank(
      widget.expressionHabits,
      category: 'stuck',
      limit: 12,
    ).map((habit) => '常用${habit.count}次：${habit.text}');
    return [
      ...habitWords,
      ...widget.vocabularyEntries
          .where((entry) => step.vocabularyCategories.contains(entry.category))
          .map((entry) => '${entry.category}：${entry.text}'),
    ].take(24).toList();
  }

  Future<List<StuckCandidate>> _mergeCandidatePool({
    required List<StuckCandidate> modelCandidates,
    required List<StuckCandidate> localCandidates,
    required StuckStepDefinition step,
  }) async {
    final valid = <StuckCandidate>[];
    final seen = <String>{};
    for (final candidate in [...modelCandidates, ...localCandidates]) {
      if (candidate.slot != step.slot ||
          !StuckFlowCatalog.isPlausibleCandidate(
            candidate.slot,
            candidate.text,
          )) {
        continue;
      }
      final normalized =
          LocationRecommendationController.normalizeText(candidate.text);
      if (normalized.isEmpty ||
          _seenCandidates.contains(normalized) ||
          !seen.add(normalized)) {
        continue;
      }
      valid.add(candidate);
    }

    final rankedWords = widget.locationController.recommendWords(
      valid.map((candidate) => candidate.text).toList(),
      category: 'stuck',
      includeContextWords: true,
      context: _recommendationContext(step),
    );
    final locationRank = <String, int>{
      for (var index = 0; index < rankedWords.length; index++)
        LocationRecommendationController.normalizeText(rankedWords[index]):
            index,
    };
    final recommendationContext = _recommendationContext(step);
    final selectedWords = recommendationContext.selectedWords;
    List<String> companionRankedWords = const [];
    try {
      companionRankedWords = await widget.companionAgent.rankExpressions(
        valid.map((candidate) => candidate.text).toList(),
        feature: recommendationContext.feature,
        category: 'stuck',
        prompt: recommendationContext.prompt,
        slot: recommendationContext.slot,
        selectedWords: selectedWords,
        allowContextExpansion: recommendationContext.allowContextExpansion,
        limit: valid.length,
      );
    } catch (error) {
      yuqiaoDebugLog('[StuckFlow] companion ranking skipped: $error');
    }
    final companionRank = <String, int>{
      for (var index = 0; index < companionRankedWords.length; index++)
        LocationRecommendationController.normalizeText(
          companionRankedWords[index],
        ): index,
    };
    final baseIndex = <String, int>{
      for (var index = 0; index < valid.length; index++)
        LocationRecommendationController.normalizeText(valid[index].text):
            index,
    };
    valid.sort((a, b) {
      double scoreOf(StuckCandidate candidate) {
        final normalized =
            LocationRecommendationController.normalizeText(candidate.text);
        final sourceScore = candidate.isModelGenerated ? 1000.0 : 600.0;
        final orderScore = 120.0 - (baseIndex[normalized] ?? 12) * 8;
        final contextScore =
            math.max(0, 20 - (locationRank[normalized] ?? 20)).toDouble();
        final companionScore =
            math.max(0, 24 - (companionRank[normalized] ?? 24)).toDouble();
        return sourceScore + orderScore + contextScore + companionScore;
      }

      return scoreOf(b).compareTo(scoreOf(a));
    });

    final contextualSupplements = <StuckCandidate>[];
    final validNormalized = valid
        .map((candidate) =>
            LocationRecommendationController.normalizeText(candidate.text))
        .toSet();
    for (final word in rankedWords) {
      final normalized = LocationRecommendationController.normalizeText(word);
      if (validNormalized.contains(normalized)) continue;
      final contextual = _contextCandidate(word, step);
      if (contextual != null &&
          !_seenCandidates.contains(normalized) &&
          !contextualSupplements.any((item) =>
              LocationRecommendationController.normalizeText(item.text) ==
              normalized)) {
        // 地点和历史词只做补位，不插到模型及当前步骤候选之前。
        contextualSupplements.add(contextual);
      }
    }
    return [...valid, ...contextualSupplements.take(2)].take(16).toList();
  }

  RecommendationContext _recommendationContext(StuckStepDefinition step) {
    final session = _session!;
    return RecommendationContext(
      feature: 'stuck',
      intent: session.intent.sentenceIntent,
      prompt: step.title,
      slot: _locationSlotFor(step.slot),
      selectedWords: session.selections
          .map((selection) => selection.candidate.text)
          .toList(),
      allowContextExpansion: true,
    );
  }

  RecommendationSlot _locationSlotFor(StuckExpressionSlot slot) {
    return switch (slot) {
      StuckExpressionSlot.helper => RecommendationSlot.person,
      StuckExpressionSlot.communication => RecommendationSlot.sentence,
      StuckExpressionSlot.place => RecommendationSlot.place,
      StuckExpressionSlot.time => RecommendationSlot.time,
      StuckExpressionSlot.bodyPart => RecommendationSlot.bodyPart,
      StuckExpressionSlot.feeling ||
      StuckExpressionSlot.degree =>
        RecommendationSlot.feeling,
      StuckExpressionSlot.action => RecommendationSlot.actionOrObject,
      StuckExpressionSlot.target ||
      StuckExpressionSlot.object ||
      StuckExpressionSlot.subject =>
        RecommendationSlot.actionOrObject,
      StuckExpressionSlot.detail => RecommendationSlot.actionOrObject,
    };
  }

  StuckCandidate? _contextCandidate(
    String text,
    StuckStepDefinition step,
  ) {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 18) return null;
    final fits = switch (step.slot) {
      StuckExpressionSlot.place =>
        RegExp(r'家|医院|超市|学校|公园|药店|餐厅|公司|小区|楼|房间|厕所|车站|地铁|这里|外面')
            .hasMatch(clean),
      StuckExpressionSlot.time =>
        RegExp(r'现在|刚才|今天|明天|昨天|早上|晚上|一会|最近|一直').hasMatch(clean),
      StuckExpressionSlot.bodyPart =>
        RegExp(r'头|肩|手|胸|肚|腰|腿|脚|背|喉咙').hasMatch(clean),
      StuckExpressionSlot.feeling =>
        RegExp(r'累|疼|痛|冷|热|怕|难过|高兴|着急|晕|麻|恶心').hasMatch(clean),
      StuckExpressionSlot.degree =>
        RegExp(r'一点|比较|很|严重|明显|越来越').hasMatch(clean),
      StuckExpressionSlot.action =>
        RegExp(r'找|拿|打开|关|去|回|吃|喝|休息|陪|说|看|买|用').hasMatch(clean),
      StuckExpressionSlot.helper =>
        RegExp(r'妈妈|爸爸|家人|朋友|老师|医生|护士|工作人员|同事').hasMatch(clean),
      StuckExpressionSlot.communication =>
        RegExp(r'帮我|请|你|哪里|怎么|自己|不用').hasMatch(clean),
      StuckExpressionSlot.detail => clean.length <= 8,
      // 泛化的历史名词容易污染对象槽位，只允许已按词库分类加入的对象。
      StuckExpressionSlot.target ||
      StuckExpressionSlot.object ||
      StuckExpressionSlot.subject =>
        false,
    };
    if (!fits) return null;
    return StuckCandidate(
      text: clean,
      semanticGroup: '个人常用',
      slot: step.slot,
    );
  }

  String _candidateMeaningKey(StuckCandidate candidate) {
    var normalized = LocationRecommendationController.normalizeText(
      candidate.text,
    );
    normalized = normalized
        .replaceAll(RegExp(r'^(我想|我要|请|麻烦|能不能|可以|帮我|给我|把)'), '')
        .replaceAll(RegExp(r'(一下|一点|可以吗|好吗|吗)$'), '')
        .trim();
    if (normalized.isEmpty) normalized = candidate.text.trim();

    final synonymGroups = <String, List<String>>{
      'get_object': ['拿', '取', '递', '给我', '带来', '找给我'],
      'find_object': ['找', '寻找', '找不到', '在哪里', '哪儿', '哪'],
      'drink_water': ['喝水', '水杯', '水瓶', '口渴', '倒水'],
      'eat_food': ['吃饭', '吃东西', '饭', '饿', '点餐'],
      'rest': ['休息', '坐一会', '躺', '睡觉', '太累'],
      'toilet': ['厕所', '卫生间', '上厕所'],
      'pain': ['疼', '痛', '不舒服', '难受'],
      'repeat': ['再说', '重复', '没听清', '慢一点'],
      'family': ['妈妈', '爸爸', '家人', '朋友'],
      'medical_staff': ['医生', '护士', '治疗师'],
      'pay': ['付款', '缴费', '结账', '买单', '多少钱'],
      'go_home': ['回家', '回去', '到家'],
    };
    for (final entry in synonymGroups.entries) {
      if (entry.value.any(normalized.contains)) {
        return '${candidate.slot.name}:${entry.key}';
      }
    }

    final compact =
        normalized.length <= 4 ? normalized : normalized.substring(0, 4);
    return '${candidate.slot.name}:$compact';
  }

  List<StuckCandidate> _takeDiverseCandidates(
    List<StuckCandidate> pool,
    StuckStepDefinition step,
  ) {
    final result = <StuckCandidate>[];
    final targetCount = widget.preferredCandidateCount.clamp(2, 6).toInt();
    final groups = <String>{};
    final selectedTexts = <String>{};
    final selectedMeanings = <String>{};
    final normalizedSeen = _seenCandidates
        .map(LocationRecommendationController.normalizeText)
        .toSet();

    bool addCandidate(
      StuckCandidate candidate, {
      required bool requireNewGroup,
      required bool requireNewMeaning,
    }) {
      final normalized =
          LocationRecommendationController.normalizeText(candidate.text);
      final meaningKey = _candidateMeaningKey(candidate);
      if (candidate.slot != step.slot ||
          normalizedSeen.contains(normalized) ||
          selectedTexts.contains(normalized) ||
          (requireNewMeaning && selectedMeanings.contains(meaningKey)) ||
          (requireNewGroup && groups.contains(candidate.semanticGroup))) {
        return false;
      }
      groups.add(candidate.semanticGroup);
      selectedTexts.add(normalized);
      selectedMeanings.add(meaningKey);
      result.add(candidate);
      return result.length == targetCount;
    }

    // 第一轮优先使用真正的模型结果；本地词只在模型不足时补位。
    for (final candidate in pool.where((item) => item.isModelGenerated)) {
      if (addCandidate(
        candidate,
        requireNewGroup: true,
        requireNewMeaning: true,
      )) {
        return result;
      }
    }
    // 模型偶尔会复用 semanticGroup。此时优先保留其上下文候选，
    // 不要为了凑齐四种标签而立即回填无关的本地模板。
    for (final candidate in pool.where((item) => item.isModelGenerated)) {
      if (addCandidate(
        candidate,
        requireNewGroup: false,
        requireNewMeaning: true,
      )) {
        return result;
      }
    }
    for (final candidate in pool) {
      if (addCandidate(
        candidate,
        requireNewGroup: true,
        requireNewMeaning: true,
      )) {
        return result;
      }
    }
    for (final candidate in pool) {
      if (addCandidate(
        candidate,
        requireNewGroup: false,
        requireNewMeaning: false,
      )) {
        return result;
      }
    }
    return result;
  }

  Future<void> _refreshOptions() async {
    final session = _session;
    final step = session?.currentStep;
    if (session == null || step == null || _isRecommending || _isRefreshing) {
      return;
    }
    _recordVisibleCandidateFeedback(
      session: session,
      step: step,
      action: CompanionFeedbackAction.refreshed,
    );
    _seenCandidates.addAll(
      _visibleCandidates.map(
        (candidate) =>
            LocationRecommendationController.normalizeText(candidate.text),
      ),
    );
    _refreshAttempts++;
    setState(() => _isRefreshing = true);
    await _recommendCurrentStep(
      forceRefresh: true,
      diversificationLevel: _refreshAttempts,
    );
  }

  void _recordVisibleCandidateFeedback({
    required StuckExpressionSession session,
    required StuckStepDefinition step,
    required CompanionFeedbackAction action,
  }) {
    final texts = _visibleCandidates
        .map((candidate) => candidate.text.trim())
        .where((text) => text.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (texts.isEmpty) return;
    unawaited(widget.companionAgent.recordRejectedBatch(
      texts: texts,
      feature: 'stuck',
      action: action,
      prompt: step.title.isEmpty ? session.intent.sentenceIntent : step.title,
      slot: _locationSlotFor(step.slot),
    ));
    final actionPlan = _activeActionPlan;
    if (actionPlan != null) {
      unawaited(widget.companionAgent.recordActionPlanFeedback(
        type: actionPlan.type,
        feature: 'stuck',
        action: action,
        prompt: step.title.isEmpty ? session.intent.sentenceIntent : step.title,
        slot: _locationSlotFor(step.slot),
      ));
    }
  }

  Future<void> _showClarificationSheet() async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFFDFDFE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('换个方式找一找', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 6),
              const Text(
                '连续换组仍不合适时，补充一个字或修改前面的选择会更准确。',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 16),
              _ClarificationAction(
                icon: Icons.keyboard_alt_outlined,
                label: '输入一个字或词',
                onTap: () => Navigator.of(sheetContext).pop('type'),
              ),
              _ClarificationAction(
                icon: Icons.mic_rounded,
                label: '语音说出一部分',
                onTap: () => Navigator.of(sheetContext).pop('voice'),
              ),
              _ClarificationAction(
                icon: Icons.undo_rounded,
                label: '返回上一步修改',
                onTap: () => Navigator.of(sheetContext).pop('back'),
              ),
              _ClarificationAction(
                icon: Icons.category_outlined,
                label: '重新选择表达类型',
                onTap: () => Navigator.of(sheetContext).pop('restart'),
              ),
              _ClarificationAction(
                icon: Icons.refresh_rounded,
                label: '继续生成不同方向',
                onTap: () => Navigator.of(sheetContext).pop('more'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'type':
        await _openFragmentInput();
        return;
      case 'voice':
        await _openFragmentInput(autoStartVoice: true);
        return;
      case 'back':
        final selections = _session?.selections ?? const [];
        if (selections.isNotEmpty) await _editFrom(selections.last.slot);
        return;
      case 'restart':
        setState(() {
          _session = null;
          _resetStepState();
        });
        return;
      case 'more':
        setState(() => _refreshAttempts = 0);
        await _recommendCurrentStep(
          forceRefresh: true,
          diversificationLevel: 3,
        );
        return;
    }
  }

  Future<void> _openFragmentInput({
    bool autoStartVoice = false,
    bool asSeed = false,
  }) async {
    final step = asSeed ? null : _session?.currentStep;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FragmentInputSheet(
        service: _fragmentAsrService,
        title: step == null ? '你还记得哪些字？' : '补充“${step.slot.label}”',
        autoStartVoice: autoStartVoice,
      ),
    );
    await _fragmentAsrService.stop();
    if (!mounted || value == null || value.trim().isEmpty) return;
    if (asSeed || _session == null) {
      setState(() {
        _seedFragment = value.trim();
        _session?.seedFragment = _seedFragment;
        if (_session != null) _resetStepState();
      });
      if (_session?.currentStep != null) {
        await _recommendCurrentStep();
      }
      return;
    }
    await _chooseCandidate(StuckCandidate(
      text: value.trim(),
      semanticGroup: '用户输入',
      slot: step!.slot,
    ));
  }

  Widget _buildIntentPicker() {
    Widget card({
      required String title,
      required Color backgroundColor,
      required Color iconBackground,
      required IconData icon,
      required StuckExpressionIntent intent,
    }) {
      return Expanded(
        child: _IntentCard(
          title: title,
          backgroundColor: backgroundColor,
          iconBackground: iconBackground,
          icon: icon,
          onTap: () => _chooseIntent(intent),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            card(
              title: '要人帮忙',
              backgroundColor: const Color(0xFFFFE2C8),
              iconBackground: const Color(0xFFFFF1DC),
              icon: Icons.volunteer_activism_rounded,
              intent: StuckExpressionIntent.help,
            ),
            const SizedBox(width: 18),
            card(
              title: '表达不舒服',
              backgroundColor: const Color(0xFFC9F1E8),
              iconBackground: const Color(0xFFB7E6EE),
              icon: Icons.healing_rounded,
              intent: StuckExpressionIntent.discomfort,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            card(
              title: '要东西',
              backgroundColor: const Color(0xFFDCD9FF),
              iconBackground: const Color(0xFFEDD8F7),
              icon: Icons.local_mall_rounded,
              intent: StuckExpressionIntent.object,
            ),
            const SizedBox(width: 18),
            card(
              title: '问问题',
              backgroundColor: const Color(0xFFFFC9CC),
              iconBackground: const Color(0xFFFFE5E6),
              icon: Icons.help_outline_rounded,
              intent: StuckExpressionIntent.question,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _WideIntentCard(
          title: '说明情况',
          subtitle: '描述刚才发生的事，或补充一句背景',
          backgroundColor: const Color(0xFFEAF0FF),
          iconBackground: const Color(0xFFF2F5FF),
          icon: Icons.chat_bubble_outline_rounded,
          onTap: () => _chooseIntent(StuckExpressionIntent.situation),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _openFragmentInput(asSeed: true),
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(
            _seedFragment.isEmpty ? '我只记得几个字' : '已记住：$_seedFragment（点击修改）',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpressionTrail(StuckExpressionSession session) {
    final selectedCount = session.selections.length;
    final stepCount = session.activeSteps.length;
    final lastSelection =
        session.selections.isEmpty ? null : session.selections.last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.route_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              selectedCount == 0
                  ? session.intent.label
                  : '${session.intent.label} · 已补充 $selectedCount/$stepCount 项',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (session.seedFragment.isNotEmpty)
            TextButton(
              onPressed: () => _openFragmentInput(asSeed: true),
              child: const Text('改提示'),
            ),
          if (lastSelection != null)
            TextButton(
              onPressed: () => _editFrom(lastSelection.slot),
              child: const Text('改上一步'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final step = session?.currentStep;
    final pickingIntent = session == null;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                PageHeader(
                  title: pickingIntent ? '你想表达什么？' : step?.title ?? '表达已经足够清楚',
                  subtitle: pickingIntent
                      ? '先选择最接近的任务，也可以输入记得的几个字'
                      : step?.subtitle ?? '可以整理成完整句子，也可以返回修改',
                  onBack: _goBackWithinFlow,
                ),
                const SizedBox(height: 18),
                if (session != null) ...[
                  _buildExpressionTrail(session),
                  const SizedBox(height: AppSpacing.section),
                ],
                if (pickingIntent)
                  _buildIntentPicker()
                else ...[
                  if (step != null)
                    _isRecommending
                        ? _CandidateLoadingGrid(
                            count: widget.preferredCandidateCount,
                          )
                        : _StuckCandidateGrid(
                            candidates: _visibleCandidates,
                            imageScale: widget.candidateImageScale,
                            onSelected: _chooseCandidate,
                          ),
                  if (step != null && !_isRecommending) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: _isRefreshing ? null : _refreshOptions,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_isRefreshing ? '正在换一组' : '换一组'),
                        ),
                        if (step.optional) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _skipCurrentStep,
                            child: const Text('跳过这一步'),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (session.canFinish) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _finishExpression,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: Text(step == null ? '整理成完整句子' : '现在整理成句'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    if (step != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Center(
                          child: Text(
                            '也可以继续选择，让表达更准确',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
          YuqiaoFeatureAssistiveBall(
            currentFeature: YuqiaoFeature.stuck,
            launcher: widget.featureLauncher,
            bottomClearance: 28,
          ),
        ],
      ),
    );
  }
}

class _FragmentInputSheet extends StatefulWidget {
  const _FragmentInputSheet({
    required this.service,
    required this.title,
    required this.autoStartVoice,
  });

  final ParaformerAsrService service;
  final String title;
  final bool autoStartVoice;

  @override
  State<_FragmentInputSheet> createState() => _FragmentInputSheetState();
}

class _FragmentInputSheetState extends State<_FragmentInputSheet> {
  late final TextEditingController _controller;
  bool _recording = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    if (widget.autoStartVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_toggleVoice());
      });
    }
  }

  @override
  void dispose() {
    unawaited(widget.service.stop());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      await widget.service.stop();
      if (mounted) setState(() => _recording = false);
      return;
    }
    setState(() {
      _recording = true;
      _errorText = null;
    });
    try {
      await widget.service.start(
        onTranscript: (text, isFinal) {
          if (!mounted) return;
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          if (isFinal) {
            setState(() => _recording = false);
            unawaited(widget.service.stop());
          }
        },
        onStatus: (_) {},
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _recording = false;
            _errorText = message;
          });
        },
      );
      if (!mounted) await widget.service.stop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _errorText = error.toString();
      });
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    unawaited(widget.service.stop());
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFFDFDFE),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: AppTextStyles.sectionTitle),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: !widget.autoStartVoice,
              maxLength: 20,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '输入一个字、词或短语',
                filled: true,
                fillColor: const Color(0xFFF3F4F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  tooltip: _recording ? '停止录音' : '语音输入',
                  onPressed: _toggleVoice,
                  icon: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _recording ? AppColors.danger : AppColors.primary,
                  ),
                ),
              ),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('使用这段内容'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StuckCandidateGrid extends StatelessWidget {
  const _StuckCandidateGrid({
    super.key,
    required this.candidates,
    required this.imageScale,
    required this.onSelected,
  });

  final List<StuckCandidate> candidates;
  final double imageScale;
  final ValueChanged<StuckCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    final effectiveScale = imageScale.clamp(0.85, 1.55).toDouble();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: candidates.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.gap,
        mainAxisSpacing: AppSpacing.gap,
        childAspectRatio: effectiveScale >= 1.25 ? 0.95 : 1.2,
      ),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final style = _candidateCardStyles[index % _candidateCardStyles.length];
        final iconDiameter = (44 * effectiveScale).clamp(38.0, 70.0);
        final iconSize = (26 * effectiveScale).clamp(22.0, 42.0);
        final cardPadding = effectiveScale >= 1.3
            ? 12.0
            : effectiveScale >= 1.15
                ? 14.0
                : 16.0;
        return InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => onSelected(candidate),
          child: Container(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: style.shadow.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconDiameter,
                  height: iconDiameter,
                  decoration: BoxDecoration(
                    color: style.iconBackground.withValues(alpha: 0.88),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _candidateIconForText(
                      candidate.text,
                      semanticGroup: candidate.semanticGroup,
                    ),
                    size: iconSize,
                    color: const Color(0xFF151515),
                  ),
                ),
                SizedBox(height: 10 + (effectiveScale - 1) * 4),
                Flexible(
                  child: Text(
                    candidate.text,
                    textAlign: TextAlign.center,
                    maxLines: effectiveScale >= 1.3 ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClarificationAction extends StatelessWidget {
  const _ClarificationAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _CandidateLoadingGrid extends StatefulWidget {
  const _CandidateLoadingGrid({
    super.key,
    required this.count,
  });

  final int count;

  @override
  State<_CandidateLoadingGrid> createState() => _CandidateLoadingGridState();
}

class _CandidateLoadingGridState extends State<_CandidateLoadingGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count.clamp(2, 6).toInt();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.gap,
        mainAxisSpacing: AppSpacing.gap,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final style = _candidateCardStyles[index % _candidateCardStyles.length];
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = (_controller.value - index * 0.14) % 1.0;
            final pulse =
                (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0).toDouble();
            return Transform.scale(
              scale: 0.985 + pulse * 0.015,
              child: Container(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    style.background.withValues(alpha: 0.68),
                    style.background,
                    pulse,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.72),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: style.shadow.withValues(
                        alpha: 0.08 + pulse * 0.15,
                      ),
                      blurRadius: 12 + pulse * 10,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (dotIndex) {
                      final dotPhase =
                          (_controller.value * 1.5 - dotIndex * 0.16) % 1.0;
                      final dotPulse = (1 - (dotPhase * 2 - 1).abs())
                          .clamp(0.0, 1.0)
                          .toDouble();
                      return Container(
                        width: 7 + dotPulse * 2,
                        height: 7 + dotPulse * 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: style.shadow.withValues(
                            alpha: 0.30 + dotPulse * 0.50,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _IntentCard extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final Color iconBackground;
  final IconData icon;
  final VoidCallback onTap;

  const _IntentCard({
    required this.title,
    required this.backgroundColor,
    required this.iconBackground,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.98,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withValues(alpha: 0.26),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: iconBackground.withValues(alpha: 0.86),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 23, color: const Color(0xFF111111)),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF151515),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideIntentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color iconBackground;
  final IconData icon;
  final VoidCallback onTap;

  const _WideIntentCard({
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.iconBackground,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBackground.withValues(alpha: 0.92),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: const Color(0xFF111111)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF151515),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF151515).withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: const Color(0xFF151515).withValues(alpha: 0.46),
            ),
          ],
        ),
      ),
    );
  }
}
