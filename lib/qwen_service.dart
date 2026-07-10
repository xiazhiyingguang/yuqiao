part of 'main.dart';

class QwenCancellationToken {
  final Completer<void> _abortCompleter = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _abortCompleter.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _abortCompleter.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const QwenCancelledException();
  }
}

class _StructuredSentenceCandidate {
  const _StructuredSentenceCandidate({
    required this.sentence,
    required this.evidence,
    required this.assumptions,
    required this.complete,
  });

  final String sentence;
  final List<String> evidence;
  final List<String> assumptions;
  final bool complete;

  static _StructuredSentenceCandidate? fromJson(Map<String, dynamic> json) {
    final sentence = json['sentence'];
    if (sentence is! String || sentence.trim().isEmpty) return null;
    List<String> stringsOf(Object? value) => value is List
        ? value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : const [];
    return _StructuredSentenceCandidate(
      sentence: sentence.trim(),
      evidence: stringsOf(json['evidence']),
      assumptions: stringsOf(json['assumptions']),
      complete: json['complete'] == true,
    );
  }
}

class _SentenceValidation {
  const _SentenceValidation.valid(this.sentence) : reason = '';

  const _SentenceValidation.invalid(this.reason) : sentence = null;

  final String? sentence;
  final String reason;
}

class QwenService {
  final http.Client _client = http.Client();

  static const String _apiKey = String.fromEnvironment('QWEN_API_KEY');
  static const String _baseUrl = String.fromEnvironment(
    'QWEN_BASE_URL',
    defaultValue:
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
  );
  static const String _proxyUrl = String.fromEnvironment(
    'YUQIAO_QWEN_PROXY_URL',
  );
  static const String _proxyToken = String.fromEnvironment(
    'YUQIAO_PROXY_TOKEN',
  );
  static const String _textModel = String.fromEnvironment(
    'QWEN_TEXT_MODEL',
    defaultValue: 'qwen-plus',
  );
  static const String _recommendModel = String.fromEnvironment(
    'QWEN_RECOMMEND_MODEL',
    defaultValue: 'qwen-turbo',
  );
  static const String _visionModel = String.fromEnvironment(
    'QWEN_VISION_MODEL',
    defaultValue: 'qwen-vl-plus',
  );

  bool get _usesProxy => _proxyUrl.trim().isNotEmpty;

  void dispose() {
    _client.close();
  }

  Future<SpriteAssistantIntent> understandSpriteAssistantRequest(
    String text, {
    List<String> operationHints = const [],
  }) async {
    _ensureConfigured();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const QwenException('小精灵没有收到要处理的内容。');
    }
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.1,
      'messages': [
        {
          'role': 'system',
          'content': '你是“语桥”App 内的小精灵助手，只负责把用户口语请求归类为 App 已允许的内部动作。'
              '你不能编造新功能，不能直接执行危险操作，不能读取或输出隐私数据。'
              '只返回 JSON 对象，不要解释。'
              '允许的 actionId：'
              'set_image_scale, set_candidate_count, add_vocabulary_entry, '
              'save_favorite_expression, open_expression_preferences, '
              'open_vocabulary, open_personal_objects, open_family_contact, '
              'open_training, open_listening_training, open_memory, '
              'toggle_personalized_learning, toggle_auto_stuck_detection, '
              'toggle_location_recommendation, unsupported。'
              '参数规则：'
              'set_image_scale 使用 imageScale，取 0.9/1.0/1.25/1.55；'
              'set_candidate_count 使用 candidateCount，取 2/4/6；'
              'add_vocabulary_entry 使用 text 和 category，category 只能取 人物/饮食/地点/活动/物品/感受/常用句；'
              'save_favorite_expression 使用 text，必须是用户想保存的完整短句；'
              '如果用户明确想添加词或保存常用表达，但没有说具体文字，仍返回对应 actionId，parameters 可以留空，由 App 继续追问；'
              'toggle_* 使用 enabled 布尔值；'
              '无法确定或不在白名单内就返回 unsupported。'
              '历史操作只可在用户本次表达含糊但仍有明确可选动作时作为弱参考，不能覆盖用户本次原话。'
              'JSON 字段：actionId, parameters, confidence, title, confirmation, reason。',
        },
        {
          'role': 'user',
          'content': '用户说：$trimmed\n'
              '本机近期操作偏好（弱参考）：${operationHints.take(5).join('；')}',
        },
      ],
    });
    return SpriteAssistantIntent.fromJson(
      jsonDecode(_stripCodeFence(_messageContent(response))),
      rawText: trimmed,
    );
  }

  Future<List<String>> generateSentences(
    ExpressionDraft draft, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final accepted = <String>[];
    final rejectionReasons = <String>[];
    Object? lastError;
    for (var attempt = 0; attempt < 2 && accepted.length < 2; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        final response = await _requestStructuredSentences(
          draft,
          rejectionReasons: attempt == 0 ? const [] : rejectionReasons,
          cancellationToken: cancellationToken,
        );
        final candidates = _parseStructuredSentenceCandidates(
          _messageContent(response),
        );
        for (final candidate in candidates) {
          final validation = _validateStructuredSentence(candidate, draft);
          if (validation.sentence == null) {
            rejectionReasons.add(validation.reason);
            continue;
          }
          accepted.add(validation.sentence!);
        }
      } on QwenCancelledException {
        rethrow;
      } catch (error) {
        lastError = error;
        rejectionReasons.add('上次返回格式不稳定或候选句未通过校验，请严格返回 JSON');
        yuqiaoDebugLog('[Qwen generateSentences] retryable failure: $error');
      }
    }
    if (lastError != null) {
      yuqiaoDebugLog(
          '[Qwen generateSentences] recovered after retry: $lastError');
    }
    final seen = <String>{};
    final sentences = <String>[];
    for (final sentence in accepted) {
      final normalized = sentence.replaceAll(RegExp(r'[，。！？、,.!?\s]'), '');
      if (!seen.add(normalized)) continue;
      sentences.add(sentence);
      if (sentences.length == 3) break;
    }
    if (sentences.isEmpty) {
      throw const FormatException('模型没有返回逻辑完整的候选句');
    }
    return sentences;
  }

  Future<Map<String, dynamic>> _requestStructuredSentences(
    ExpressionDraft draft, {
    required List<String> rejectionReasons,
    QwenCancellationToken? cancellationToken,
  }) {
    return _post({
      'model': _textModel,
      'temperature': 0.15,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的句子整理与语义校验模块。'
              '每条候选必须是可独立播报、语法完整、逻辑通顺的中文句子。'
              '区分两类信息：evidence 是输入中原文可找到的证据；assumptions 是为了补全表达而提出的新信息。'
              '新人名、地点、数字、症状并非一律禁止，可以作为合理假设出现；'
              '但有 assumptions 时，句子必须明确写成询问、请求、建议或可能性，不能把假设说成已经确认的事实。'
              '例如“王医生在吗？”和“请帮我去三楼”可以保留；'
              '没有依据时，“我已经吃了三片药”或“我得了某种病”不能保留。'
              'evidence 必须填写输入里的简短原文片段，不能把推测伪装成证据。'
              '不要机械拼接不同说话者的话，不要以“因为、但是、然后、我想”等未完成结构结束。'
              '只返回 JSON 对象：'
              '{"candidates":[{"sentence":"完整句子","intent":"询问或请求等","evidence":["输入原文"],"assumptions":["新增信息"],"complete":true}]}。',
        },
        {
          'role': 'user',
          'content': '来源：${draft.source}\n'
              '表达方向：${draft.intent}\n'
              '输入信息：${draft.keywords.join(' / ')}\n'
              '${rejectionReasons.isEmpty ? '' : '上次未通过原因：${rejectionReasons.take(6).join('；')}\n'}'
              '请生成 3 到 4 条简短、自然且彼此有区别的候选句。',
        },
      ],
    }, cancellationToken: cancellationToken);
  }

  List<_StructuredSentenceCandidate> _parseStructuredSentenceCandidates(
    String content,
  ) {
    Object decoded;
    try {
      decoded = jsonDecode(_stripCodeFence(content));
    } catch (_) {
      final recovered = _recoverStructuredSentenceCandidates(content);
      if (recovered.isNotEmpty) return recovered;
      rethrow;
    }
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw const QwenException('候选句返回格式错误，应为 JSON 对象。');
    }
    return (decoded['candidates'] as List)
        .whereType<Map>()
        .map((item) => _StructuredSentenceCandidate.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .whereType<_StructuredSentenceCandidate>()
        .take(6)
        .toList();
  }

  List<_StructuredSentenceCandidate> _recoverStructuredSentenceCandidates(
    String content,
  ) {
    final cleaned = _stripCodeFence(content);
    final results = <_StructuredSentenceCandidate>[];
    final seen = <String>{};
    final patterns = [
      RegExp(r'"sentence"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
      RegExp(r'“sentence”\s*[:：]\s*“([^”]+)”', dotAll: true),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(cleaned)) {
        final raw = match.group(1);
        if (raw == null || raw.trim().isEmpty) continue;
        final sentence = _decodeJsonStringFragment(raw);
        final normalized =
            LocationRecommendationController.normalizeText(sentence);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        results.add(_StructuredSentenceCandidate(
          sentence: sentence,
          evidence: const [],
          assumptions: const [],
          complete: true,
        ));
        if (results.length == 6) return results;
      }
    }
    return results;
  }

  String _decodeJsonStringFragment(String value) {
    try {
      final decoded = jsonDecode('"$value"');
      if (decoded is String) return decoded.trim();
    } catch (_) {}
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  _SentenceValidation _validateStructuredSentence(
    _StructuredSentenceCandidate candidate,
    ExpressionDraft draft,
  ) {
    if (!candidate.complete) {
      return const _SentenceValidation.invalid('模型标记句子尚不完整');
    }
    final sentence = _validatedCompleteSentence(candidate.sentence);
    if (sentence == null) {
      return const _SentenceValidation.invalid('句子缺少必要成分或结尾不完整');
    }
    final source = LocationRecommendationController.normalizeText(
      '${draft.source}${draft.intent}${draft.keywords.join()}',
    );
    for (final evidence in candidate.evidence) {
      final normalizedEvidence =
          LocationRecommendationController.normalizeText(evidence);
      if (normalizedEvidence.isNotEmpty &&
          !source.contains(normalizedEvidence)) {
        return _SentenceValidation.invalid('证据“$evidence”在输入中不存在');
      }
    }
    if (candidate.assumptions.isNotEmpty &&
        !_isExplicitlyFramedAssumption(sentence)) {
      return const _SentenceValidation.invalid(
        '新增信息被写成了确定事实，应改为询问、请求、建议或可能性',
      );
    }
    return _SentenceValidation.valid(sentence);
  }

  bool _isExplicitlyFramedAssumption(String sentence) {
    const markers = [
      '吗',
      '是不是',
      '是否',
      '可能',
      '也许',
      '大概',
      '要不要',
      '可以',
      '能不能',
      '请',
      '帮我',
      '麻烦',
      '我想',
      '我要',
      '我需要',
    ];
    return markers.any(sentence.contains) || sentence.endsWith('？');
  }

  String? _validatedCompleteSentence(String value) {
    var sentence = value
        .trim()
        .replaceFirst(RegExp(r'^\s*\d+[.、）)]\s*'), '')
        .replaceAll(RegExp(r'^["“”]+|["“”]+$'), '')
        .trim();
    if (sentence.length < 4 || sentence.length > 48) return null;
    if (sentence.contains('对话上下文：') || sentence.contains('用户已确认关键词：')) {
      return null;
    }
    final withoutPunctuation =
        sentence.replaceAll(RegExp(r'[，。！？、,.!?：:；;\s]+$'), '');
    const incompleteEndings = [
      '因为',
      '但是',
      '然后',
      '还有',
      '所以',
      '如果',
      '我想',
      '我要',
      '我需要',
      '能不能',
      '帮我',
      '给我',
    ];
    if (incompleteEndings.any(withoutPunctuation.endsWith)) return null;
    if (!RegExp(r'[。！？!?]$').hasMatch(sentence)) {
      sentence = '$sentence。';
    }
    return sentence;
  }

  Future<List<String>> recommendNextOptions(
      CandidateRecommendationRequest request) async {
    _ensureConfigured();
    yuqiaoDebugLog(
      '[Qwen recommendNextOptions] intent=${request.intent}, '
      'step=${request.stepTitle}, selected=${request.selectedKeywords.join('/')}, '
      'excluded=${request.excludeOptions.length}',
    );
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.35,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的候选词推荐模块。'
              '你的任务不是生成完整句子，而是预测用户下一步最可能想点的短候选词。'
              '必须紧扣“已确认内容”和“当前页面问题”，候选之间要有明显上下文关联。'
              '每个候选不超过 6 个汉字，适合按钮展示。'
              '除非本地兜底候选非常合适，否则不要简单照抄本地兜底候选。'
              '一次提供 8 到 12 个不重复候选，供界面分组展示。'
              '输出必须是 JSON 字符串数组，例如 ["医生","护士","家人","朋友","护工","老师","同事","康复师"]。',
        },
        {
          'role': 'user',
          'content': '表达方向：${request.intent}\n'
              '当前页面问题：${request.stepTitle}\n'
              '已确认内容：${request.selectedKeywords.join(' / ')}\n'
              '本地兜底候选：${request.fallbackOptions.join(' / ')}\n'
              '个人日常词库：${request.personalWords.join(' / ')}\n'
              '${request.excludeOptions.isEmpty ? '' : '不要推荐以下已出现过的词：${request.excludeOptions.join(' / ')}\n'}'
              '推荐要求：优先贴近日常生活表达，必要时使用个人词库中的人物、饮食、地点、活动、物品或常用句；'
              '不要过度偏向药品或重度照护场景，除非上下文明确提到身体不适或医疗问题。'
              '请尽量返回 8 到 12 个彼此不同的候选。\n'
              '请只返回下一步候选词 JSON 数组。',
        },
      ],
    });
    final options = _parseStringList(_messageContent(response))
        .map(_normalizeOption)
        .where((item) => item.isNotEmpty)
        .take(12)
        .toList();
    yuqiaoDebugLog(
      '[Qwen recommendNextOptions] returned=${options.length} '
      'options=${options.join('/')}',
    );
    return options;
  }

  Future<List<StuckCandidate>> recommendGuidedOptions(
    CandidateRecommendationRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    yuqiaoDebugLog(
      '[Qwen guided stuck] slot=${request.slotKey} '
      'diversify=${request.diversificationLevel} '
      'excluded=${request.excludeOptions.length}',
    );
    final expectedSlot = StuckExpressionSlot.values.firstWhere(
      (slot) => slot.key == request.slotKey,
      orElse: () => StuckExpressionSlot.detail,
    );
    final confirmedContext = request.selectedKeywords
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(' / ');
    final hasUserContext = confirmedContext.isNotEmpty;
    final response = await _post({
      'model': _recommendModel,
      'temperature': request.diversificationLevel > 0 ? 0.48 : 0.28,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的独立补词模块。'
              '这里没有实时对话上下文，只能使用用户当前选择的表达任务、已确认槽位和记得的文字片段。'
              '用户明确提供的信息是最高优先级：只要已有片段或已确认槽位，每个候选都必须能自然接在这些信息之后，不能重新猜一个无关话题。'
              '你只负责生成指定 slot 的候选，不能返回其他类型。'
              '候选可以是词、短语或很短的句子，每项不超过 18 个汉字。'
              'semanticGroup 表示候选代表的不同语义方向；前 ${request.displayCount} 项必须尽量属于不同方向，不能只是同义改写。'
              '地点、时间、历史词和个人词只能在符合当前 slot 且与用户已选内容连贯时使用。'
              '只返回 JSON 对象：'
              '{"candidates":[{"text":"候选","slot":"指定slot","semanticGroup":"语义方向"}]}。',
        },
        {
          'role': 'user',
          'content': '表达任务：${request.intent}\n'
              '当前时间：${request.timeText.isEmpty ? '未知' : request.timeText}\n'
              '当前地点：${request.locationText.isEmpty ? '未知' : request.locationText}\n'
              '当前问题：${request.stepTitle}\n'
              '当前槽位：${request.slotKey}（${request.slotLabel}）\n'
              '用户明确提供的信息（最高优先级）：${hasUserContext ? confirmedContext : '暂无，只有表达任务'}\n'
              '${hasUserContext ? '强约束：逐项检查候选是否与上述全部信息连贯；不连贯的候选不要输出。\n' : '当前信息不足，可以覆盖几个常见但不同的日常方向。\n'}'
              '${hasUserContext ? '' : '无上下文时的本地参考：${request.fallbackOptions.join(' / ')}\n'}'
              '个人词仅在与用户信息直接相关时使用：${request.personalWords.join(' / ')}\n'
              '${request.excludeOptions.isEmpty ? '' : '禁止重复：${request.excludeOptions.join(' / ')}\n'}'
              '${request.diversificationLevel > 0 ? '这是用户点击“换一组”后的第 ${request.diversificationLevel + 1} 组，必须重新基于已选内容生成，不要复用上一组语义方向，也不要只换同义词。\n' : ''}'
              '返回 ${math.max(8, request.displayCount + 4)} 到 12 个候选，严格保持 slot 为 ${request.slotKey}。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw const QwenException('补词候选格式错误，应为 JSON 对象。');
    }
    final excluded = request.excludeOptions
        .map(LocationRecommendationController.normalizeText)
        .toSet();
    final seen = <String>{};
    final candidates = <StuckCandidate>[];
    final rawCandidates = decoded['candidates'] as List;
    var rejected = 0;
    for (final raw in rawCandidates) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final text = (item['text']?.toString() ?? '')
          .trim()
          .replaceAll(RegExp(r'[。！？!?]+$'), '')
          .trim();
      final slot = item['slot']?.toString().trim() ?? '';
      final semanticGroup = item['semanticGroup']?.toString().trim() ?? '';
      final normalized = LocationRecommendationController.normalizeText(text);
      final slotMatches = slot.isEmpty ||
          slot == request.slotKey ||
          slot == request.slotLabel ||
          slot == expectedSlot.label;
      if (!slotMatches ||
          text.isEmpty ||
          text.length > 18 ||
          semanticGroup.isEmpty ||
          excluded.contains(normalized) ||
          !seen.add(normalized)) {
        rejected++;
        continue;
      }
      candidates.add(StuckCandidate(
        text: text,
        semanticGroup: semanticGroup,
        slot: expectedSlot,
        isModelGenerated: true,
      ));
      if (candidates.length == 12) break;
    }
    yuqiaoDebugLog(
      '[Qwen guided stuck] raw=${rawCandidates.length} '
      'accepted=${candidates.length} rejected=$rejected '
      'options=${candidates.map((item) => '${item.semanticGroup}:${item.text}').join('/')}',
    );
    return candidates;
  }

  Future<List<String>> recommendConversationOptions(
    ConversationContextRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    yuqiaoDebugLog(
        '[Qwen conversation] transcript=${request.transcript.length} chars');
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.3,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的对话补词模块。'
              '必须优先衔接指定用户最近尚未完成或刚完成的表达，而不是根据地点猜测通用需求。'
              '返回 4 个沟通功能不同的候选，可以是词、短语或完整短句，正文每项 2 到 14 个汉字。'
              '四项必须分别使用“继续、补充、询问、等待”作为类型前缀，格式为“类型：正文”；'
              '不能出现两个同义改写。可以提出上下文之外的新人物、地点、数字或症状，'
              '但只能写成询问、可能性或建议，不能当作用户已经确认的事实。'
              '上下文不足时宁可返回“请等我一下”等修复性表达，也不要猜测“我不舒服”。'
              '只返回 JSON 字符串数组，例如["继续：我想喝水","补充：要温水","询问：有温水吗","等待：请等我一下"]。',
        },
        {
          'role': 'user',
          'content': '当前时间：${request.timeText}\n'
              '当前位置：${request.locationText}\n'
              '用户对应说话者：${request.userSpeakerLabel}\n'
              '当前转写片段：${request.currentPartial}\n'
              '当前对话上下文：\n${request.transcript}\n\n'
              '近期表达：${request.recentExpressions.join(' / ')}\n'
              '个人常用语：${request.personalWords.join(' / ')}\n'
              '${request.preferredTypes.isEmpty ? '' : '用户过去更常选择的表达类型：${request.preferredTypes.join(' / ')}\n'}'
              '${request.rejectedCandidates.isEmpty ? '' : '本轮及相似语境中不合适的候选：${request.rejectedCandidates.join(' / ')}\n'}'
              '请紧扣该用户最后一句，返回四个意图不同的候选，只返回 JSON 数组。',
        },
      ],
    }, cancellationToken: cancellationToken);
    const allowedTypes = {'继续', '补充', '询问', '等待'};
    final seenTypes = <String>{};
    final seenContent = <String>{};
    final rejected = request.rejectedCandidates
        .map(LocationRecommendationController.normalizeText)
        .toSet();
    final options = <String>[];
    for (final value in _parseStringList(_messageContent(response))) {
      final option = _normalizeOption(value);
      final separator = option.indexOf(RegExp(r'[：:]'));
      if (separator <= 0) continue;
      final type = option.substring(0, separator).trim();
      final content = option.substring(separator + 1).trim();
      final normalizedContent =
          LocationRecommendationController.normalizeText(content);
      if (!allowedTypes.contains(type) ||
          content.isEmpty ||
          content.length > 14 ||
          rejected.contains(
            LocationRecommendationController.normalizeText(option),
          ) ||
          rejected.contains(normalizedContent) ||
          !seenTypes.add(type) ||
          !seenContent.add(normalizedContent)) {
        continue;
      }
      options.add('$type：$content');
    }
    yuqiaoDebugLog('[Qwen conversation] returned=${options.join('/')}');
    return options;
  }

  Future<String?> suggestStuckAssistSentence(
    ConversationContextRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.1,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的卡顿辅助模块。'
              '用户可能在表达中途卡住，请根据已经明确说出的内容整理一条可直接播报的简短句子。'
              '不能添加对话中没有出现的对象、意图、地点、症状或事实，不能替用户做决定。'
              '如果上下文不足以恢复具体意图，使用安全的沟通句，例如“请等一下，我还在想”。'
              '句子不超过 24 个汉字，只返回包含一个字符串的 JSON 数组。',
        },
        {
          'role': 'user',
          'content': '当前时间：${request.timeText}\n'
              '当前地点类型：${request.locationText}\n'
              '疑似卡顿片段：${request.currentPartial}\n'
              '最近对话：\n${request.transcript}\n\n'
              '近期表达：${request.recentExpressions.join(' / ')}\n'
              '个人词汇：${request.personalWords.join(' / ')}\n'
              '请整理一条需要用户确认后才能播报的候选句。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final options = _parseStringList(_messageContent(response))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item.length <= 30)
        .toList();
    return options.isEmpty ? null : options.first;
  }

  Future<_ConversationUnderstanding> _explainConversationUtterance({
    required String original,
    required String speakerLabel,
    required List<String> surroundingContext,
    required List<String> personalWords,
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final source = original.trim();
    if (source.isEmpty) throw const QwenException('转录内容为空。');
    final response = await _post({
      'model': _textModel,
      'temperature': 0.0,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症用户的语句理解辅助模块。'
              '任务是把用户主动选中的一句话拆成少量、清楚的信息，再用更简单的中文解释。'
              '必须保留原句中的人物、动作、对象、时间、地点、数字、否定和先后顺序。'
              '不得补充原句没有的事实，不得把相邻对话中的内容写进原句解释。'
              '相邻对话只能用来理解代词；无法确定代词时写入 uncertainties，不要猜。'
              '每个 parts 项必须给出 evidence，而evidence 必须是原句中连续出现的原文。'
              'label 优先使用“人物、时间、地点、先做、然后、动作、对象、要求、重点”。'
              '只返回 JSON 对象：'
              '{"original":"逐字原句","parts":[{"label":"时间","text":"简短解释","evidence":"原句片段"}],'
              '"simpleMeaning":"一句简单解释","importantNote":"最需注意的一点","uncertainties":[]}。',
        },
        {
          'role': 'user',
          'content': '选中说话者：$speakerLabel\n'
              '待解释原句：$source\n'
              '相邻对话（仅用于代词理解）：\n${surroundingContext.join('\n')}\n'
              '已确认个人词汇（仅用于识别名称）：${personalWords.join(' / ')}\n'
              '请将原句拆成 1 到 5 个信息点。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
    if (decoded is! Map<String, dynamic> ||
        decoded['original']?.toString().trim() != source ||
        decoded['parts'] is! List) {
      throw const QwenException('理解结果格式不正确。');
    }

    final parts = <_UnderstandingPart>[];
    for (final value in decoded['parts'] as List) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final label = item['label']?.toString().trim() ?? '';
      final text = item['text']?.toString().trim() ?? '';
      final evidence = item['evidence']?.toString().trim() ?? '';
      if (label.isEmpty ||
          label.length > 8 ||
          text.isEmpty ||
          text.length > 40 ||
          evidence.isEmpty ||
          !source.contains(evidence)) {
        continue;
      }
      parts.add(
        _UnderstandingPart(label: label, text: text, evidence: evidence),
      );
      if (parts.length == 5) break;
    }
    final simpleMeaning = decoded['simpleMeaning']?.toString().trim() ?? '';
    final importantNote = decoded['importantNote']?.toString().trim() ?? '';
    final uncertainties = decoded['uncertainties'] is List
        ? (decoded['uncertainties'] as List)
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .take(3)
            .toList(growable: false)
        : const <String>[];
    if (parts.isEmpty ||
        simpleMeaning.isEmpty ||
        simpleMeaning.length > 100 ||
        importantNote.length > 60 ||
        !_understandingPreservesCriticalMeaning(source, simpleMeaning)) {
      throw const QwenException('模型未能给出可靠的简化解释。');
    }
    return _ConversationUnderstanding(
      original: source,
      parts: parts,
      simpleMeaning: simpleMeaning,
      importantNote: importantNote,
      uncertainties: uncertainties,
    );
  }

  bool _understandingPreservesCriticalMeaning(
    String original,
    String simpleMeaning,
  ) {
    final sourceDigits = RegExp(r'\d+(?:[.:]\d+)?')
        .allMatches(original)
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet();
    final resultDigits = RegExp(r'\d+(?:[.:]\d+)?')
        .allMatches(simpleMeaning)
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet();
    if (!sourceDigits.containsAll(resultDigits)) return false;
    final hasSourceNegation = RegExp(r'不|没|别|禁止|无需|未').hasMatch(original);
    final hasResultNegation = RegExp(r'不|没|别|禁止|无需|未').hasMatch(simpleMeaning);
    return hasSourceNegation == hasResultNegation;
  }

  Future<_SpeechRepairSuggestion?> _analyzeSpeechRepair(
    ConversationContextRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.0,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的表达核对模块。'
              '你不是自动纠错器，只有在用户最后一句与已有对话存在强烈、可解释的语义冲突时才建议核对。'
              '不得因为句子稀有、不符合常识、包含新人名、地点、数字或症状就判定有错。'
              '地点、时间、个人词只是弱参考，不能作为唯一依据。'
              '不确定时必须返回 needsConfirmation=false。'
              '需要核对时，original 必须逐字保留用户原话；'
              'candidates 必须包含原话，再给出 1 到 3 个语义不同的可能表达，不能只换同义词。'
              '不能替用户确定意图。'
              '只返回 JSON：'
              '{"needsConfirmation":true,"original":"用户原话","reason":"简短中性原因","candidates":["用户原话","可能表达"]}。',
        },
        {
          'role': 'user',
          'content': '当前时间：${request.timeText}\n'
              '当前地点类型：${request.locationText}\n'
              '用户对应说话者：${request.userSpeakerLabel}\n'
              '待核对原话：${request.currentPartial}\n'
              '最近对话：\n${request.transcript}\n\n'
              '近期表达：${request.recentExpressions.join(' / ')}\n'
              '个人词汇：${request.personalWords.join(' / ')}\n'
              '请优先避免打扰；只有证据充分时才请用户核对。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
    if (decoded is! Map<String, dynamic> ||
        decoded['needsConfirmation'] != true) {
      return null;
    }
    final original = request.currentPartial.trim();
    final returnedOriginal = decoded['original']?.toString().trim() ?? '';
    if (original.isEmpty || returnedOriginal != original) return null;
    final values = decoded['candidates'];
    if (values is! List) return null;
    final candidates = <String>[original];
    final seen = <String>{
      LocationRecommendationController.normalizeText(original),
    };
    for (final value in values) {
      final candidate = value?.toString().trim() ?? '';
      final normalized =
          LocationRecommendationController.normalizeText(candidate);
      if (candidate.isEmpty ||
          candidate.length > 48 ||
          normalized.isEmpty ||
          !seen.add(normalized)) {
        continue;
      }
      candidates.add(candidate);
      if (candidates.length == 4) break;
    }
    if (candidates.length < 2) return null;
    final reason = decoded['reason']?.toString().trim() ?? '';
    return _SpeechRepairSuggestion(
      original: original,
      candidates: candidates,
      reason: reason.length <= 40 ? reason : '这句话可能与前文不一致，请你来确认。',
    );
  }

  Future<List<ConversationTermCandidate>> extractConversationTerms(
    String transcript, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final text = transcript.trim();
    if (text.isEmpty) return const [];
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.0,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文对话中的专有词汇提取模块。'
              '只提取明确出现的人名、具体地名、机构名或高度个性化的专有称呼。'
              '不要提取“妈妈、朋友、医院、公园、今天、吃饭”等普通词。'
              'text 必须逐字来自原句，不能纠错、补全或猜测。'
              'type 只能是 person、place、organization、custom。'
              'confidence 是 0 到 1。没有明确专有词时返回空数组。'
              '只返回 JSON：{"terms":[{"text":"王阿姨","type":"person","confidence":0.95}]}。',
        },
        {
          'role': 'user',
          'content': '原句：$text',
        },
      ],
    }, cancellationToken: cancellationToken);
    final cleaned = _stripCodeFence(_messageContent(response));
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic> || decoded['terms'] is! List) {
      return const [];
    }
    final seen = <String>{};
    final terms = <ConversationTermCandidate>[];
    for (final value in (decoded['terms'] as List)) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final termText = item['text']?.toString().trim() ?? '';
      final normalized = normalizeConversationTerm(termText);
      final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.0;
      if (termText.length < 2 ||
          termText.length > 20 ||
          !text.contains(termText) ||
          confidence < 0.65 ||
          !seen.add(normalized)) {
        continue;
      }
      terms.add(ConversationTermCandidate(
        text: termText,
        type: normalizeConversationTermType(item['type']?.toString()),
        confidence: confidence,
      ));
      if (terms.length == 6) break;
    }
    return terms;
  }

  Future<ObjectRecognition> recognizeObject(
    Uint8List imageBytes, {
    List<PersonalObject> personalObjects = const [],
    String locationType = '未知地点',
    String timeContext = '未知时间',
  }) async {
    _ensureConfigured();
    final encoded = base64Encode(imageBytes);
    final imageContent = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '请识别第一张图片中的所有物品并给出位置坐标。'
            '当前地点类型：$locationType。当前本地时间：$timeContext。'
            '请优先给出在这个场景和时间下自然、可立即使用的表达。',
      },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$encoded'},
      },
    ];
    final response = await _post({
      'model': _visionModel,
      'temperature': 0.1,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文 AAC 辅助沟通 App 的拍照识别模块。'
              '直接识别图片中所有可见的物品，不要求用户确认，直接告诉用户图片中有什么。'
              '每个物品给出 3 个意图明显不同的表达选项（适合失语症患者使用）。'
              '每个选项必须包含 type 和 phrase：type 是 2 到 4 个汉字的表达类型，'
              '例如“购买、饮用、使用、寻找、询问、求助”；phrase 是可以直接播报的简短表达。'
              '同一物品的三个 type 不能重复或语义近似，不能只是对同一句话换一种说法。'
              '表达选项需要结合用户当前的地点类型和时间，但不能据此虚构用户意图。'
              'category 只能从“饮食、生活用品、衣物、电子设备、钥匙证件、康复用品、其他”中选择。'
              '同时给出每个物品在图片中的大致位置（归一化坐标，范围 0-1000）。'
              'bbox 必须紧贴物品可见轮廓，不要把大片背景、桌面或相邻物品包含进去；'
              '坐标必须相对于上传图片完整画面，而不是模型自行裁剪或缩放后的局部画面。'
              '这是客观识别阶段，不提供个人物品参考，personalObjectId 必须始终返回空字符串。'
              '输出必须是 JSON 对象，格式：'
              '{"candidates":[{"objectName":"水杯","category":"饮食","visualDescription":"蓝色杯身","personalObjectId":"","bbox":[100,200,500,600],"expressionOptions":[{"type":"购买","phrase":"我想买一个水杯"},{"type":"饮用","phrase":"我想喝水"},{"type":"使用","phrase":"帮我打开杯盖"}]}]}。'
              'bbox 为 [x1, y1, x2, y2]，分别表示左上角和右下角的归一化坐标（0-1000）。',
        },
        {
          'role': 'user',
          'content': imageContent,
        },
      ],
    });
    final parsedRecognition = _parseRecognition(_messageContent(response));
    final genericRecognition = ObjectRecognition(
      candidates: parsedRecognition.candidates
          .map((candidate) => candidate.copyWith(personalObjectId: ''))
          .toList(growable: false),
    );
    if (personalObjects.isEmpty || genericRecognition.candidates.isEmpty) {
      return genericRecognition;
    }
    return _verifyPersonalObjectMatches(
      imageBytes,
      genericRecognition,
      personalObjects,
    );
  }

  Future<ObjectRecognition> refineObjectBoundingBoxes(
    Uint8List imageBytes,
    ObjectRecognition recognition,
  ) async {
    if (recognition.candidates.isEmpty) return recognition;
    final targets = [
      for (var index = 0; index < recognition.candidates.length; index++)
        {
          'candidateIndex': index,
          'objectName': recognition.candidates[index].objectName,
          'roughBbox': recognition.candidates[index].bbox,
        },
    ];
    try {
      final response = await _post({
        'model': _visionModel,
        'temperature': 0.0,
        'messages': [
          {
            'role': 'system',
            'content': '你是视觉定位模块，只精修已识别物品的位置，不重新命名物品，不生成表达。'
                '对每个目标寻找其在图片中实际可见的完整轮廓，bbox 必须紧贴物品，不包含桌面、墙面或相邻物品。'
                '坐标统一使用相对于整张上传图片的 0-1000 归一化坐标，不能使用裁剪图、百分比或像素坐标。'
                '如果目标在图片中不可见或无法可靠定位，就省略该目标，不能猜测。'
                '只返回 JSON：{"boxes":[{"candidateIndex":0,"bbox":[x1,y1,x2,y2],"confidence":0.95}]}。',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '需要精修的目标：${jsonEncode(targets)}',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
                },
              },
            ],
          },
        ],
      });
      final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
      if (decoded is! Map<String, dynamic> || decoded['boxes'] is! List) {
        return recognition;
      }
      final refined = <int, List<double>>{};
      for (final raw in decoded['boxes'] as List) {
        if (raw is! Map) continue;
        final box = Map<String, dynamic>.from(raw);
        final index = (box['candidateIndex'] as num?)?.toInt() ?? -1;
        final confidence = (box['confidence'] as num?)?.toDouble() ?? 0;
        final bbox = normalizeModelBoundingBox(box['bbox']);
        if (index < 0 ||
            index >= recognition.candidates.length ||
            confidence < 0.72 ||
            bbox == null) {
          continue;
        }
        final area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]);
        if (area < 400 || area > 950000) continue;
        refined[index] = bbox;
        yuqiaoDebugLog(
          '[Camera bbox refine] index=$index confidence=$confidence bbox=$bbox',
        );
      }
      if (refined.isEmpty) return recognition;
      return ObjectRecognition(
        candidates: [
          for (var index = 0; index < recognition.candidates.length; index++)
            refined[index] == null
                ? recognition.candidates[index]
                : recognition.candidates[index].copyWith(
                    bbox: refined[index],
                  ),
        ],
      );
    } catch (error) {
      yuqiaoDebugLog('[Camera bbox refine] skipped: $error');
      return recognition;
    }
  }

  Future<ObjectRecognition> _verifyPersonalObjectMatches(
    Uint8List imageBytes,
    ObjectRecognition recognition,
    List<PersonalObject> personalObjects,
  ) async {
    final references = <PersonalObject>[];
    for (final object in personalObjects) {
      if (references.length >= 3) break;
      if (object.referenceImagePath.isEmpty ||
          !recognition.candidates.any(
            (candidate) => PersonalObjectMatchPolicy.kindsCompatible(
              candidate.objectName,
              object.displayName,
            ),
          )) {
        continue;
      }
      if (await File(object.referenceImagePath).exists()) {
        references.add(object);
      }
    }
    if (references.isEmpty) return recognition;

    final candidateSummary = [
      for (var index = 0; index < recognition.candidates.length; index++)
        {
          'candidateIndex': index,
          'objectName': recognition.candidates[index].objectName,
          'category': recognition.candidates[index].category,
          'visualDescription': recognition.candidates[index].visualDescription,
          'bbox': recognition.candidates[index].bbox,
        },
    ];
    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '第一张图片是本次拍摄图。第一阶段客观识别结果：'
            '${jsonEncode(candidateSummary)}。接下来是可能相关的个人物品参考图。',
      },
      {
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
        },
      },
    ];
    for (final object in references) {
      final bytes = await File(object.referenceImagePath).readAsBytes();
      content
        ..add({
          'type': 'text',
          'text': '参考物品：ID=${object.id}；名称=${object.displayName}；'
              '类型=${object.category}；用户记录的独特外观=${object.visualDescription}。',
        })
        ..add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,${base64Encode(bytes)}',
          },
        });
    }

    try {
      final response = await _post({
        'model': _visionModel,
        'temperature': 0.0,
        'messages': [
          {
            'role': 'system',
            'content': '你是个人物品同一实体核验器，不负责重新识别物品。'
                '只有能确认本次拍摄物体与参考图是同一件物理实体时才能匹配；同品类、同款、同颜色、同品牌都不足以证明是同一件。'
                '至少需要两条相互独立的外观证据，其中至少一条必须是贴纸、独特图案、划痕、磨损、缺口、挂件、标签、污渍、凹痕或用户记录的独特组合特征。'
                '角度、光照、背景不同不能当作匹配证据。有任何明显冲突或物体在本次图片中看不清时必须拒绝。'
                '不要因为系统提供了参考图就倾向匹配。宁可漏认，也不能误认。'
                '只返回 JSON：{"matches":[{"candidateIndex":0,"personalObjectId":"ID","samePhysicalObject":true,"confidence":0.98,"matchingEvidence":["证据1","证据2"],"conflictingEvidence":[]}]}。'
                '没有达到标准时返回 {"matches":[]}。',
          },
          {'role': 'user', 'content': content},
        ],
      });
      final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
      if (decoded is! Map<String, dynamic> || decoded['matches'] is! List) {
        return recognition;
      }
      final referenceById = {for (final item in references) item.id: item};
      final accepted = <int, PersonalObject>{};
      for (final raw in decoded['matches'] as List) {
        if (raw is! Map) continue;
        final match = Map<String, dynamic>.from(raw);
        final index = (match['candidateIndex'] as num?)?.toInt() ?? -1;
        final id = match['personalObjectId']?.toString() ?? '';
        final confidence = (match['confidence'] as num?)?.toDouble() ?? 0;
        final evidence = (match['matchingEvidence'] as List? ?? const [])
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final conflicts = (match['conflictingEvidence'] as List? ?? const [])
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final object = referenceById[id];
        final validIndex = index >= 0 && index < recognition.candidates.length;
        final acceptedMatch = object != null &&
            validIndex &&
            PersonalObjectMatchPolicy.kindsCompatible(
              recognition.candidates[index].objectName,
              object.displayName,
            ) &&
            PersonalObjectMatchPolicy.acceptsMatch(
              samePhysicalObject: match['samePhysicalObject'] == true,
              confidence: confidence,
              matchingEvidence: evidence,
              conflictingEvidence: conflicts,
            );
        yuqiaoDebugLog(
          '[Personal object match] candidate=$index id=$id '
          'confidence=$confidence evidence=${evidence.length} '
          'conflicts=${conflicts.length} accepted=$acceptedMatch',
        );
        if (acceptedMatch) accepted[index] = object;
      }
      return ObjectRecognition(
        candidates: [
          for (var index = 0; index < recognition.candidates.length; index++)
            _applyPersonalObjectMatch(
              recognition.candidates[index],
              accepted[index],
            ),
        ],
      );
    } catch (error) {
      yuqiaoDebugLog('[Personal object match] verification skipped: $error');
      return recognition;
    }
  }

  ObjectCandidate _applyPersonalObjectMatch(
    ObjectCandidate candidate,
    PersonalObject? object,
  ) {
    if (object == null) return candidate.copyWith(personalObjectId: '');
    final options = <ObjectExpressionOption>[];
    final seen = <String>{};
    for (final phrase in [
      ...object.commonExpressions,
      ...candidate.expressions,
    ]) {
      final clean = phrase.trim();
      final normalized = LocationRecommendationController.normalizeText(clean);
      if (clean.isEmpty || !seen.add(normalized)) continue;
      options.add(ObjectExpressionOption(
        type: _inferExpressionType(clean),
        phrase: clean,
      ));
      if (options.length == 3) break;
    }
    return candidate.copyWith(
      objectName: object.displayName,
      personalObjectId: object.id,
      expressions: options.map((item) => item.phrase).toList(),
      expressionOptions: options,
    );
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body, {
    QwenCancellationToken? cancellationToken,
  }) async {
    final uri = Uri.parse(_usesProxy ? _proxyUrl : _baseUrl);
    yuqiaoDebugLog('[Qwen API] POST $uri model=${body['model']}');
    const retryableStatusCodes = {429, 500, 502, 503, 504};
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        final request = http.AbortableRequest(
          'POST',
          uri,
          abortTrigger: cancellationToken?.whenCancelled,
        )
          ..headers.addAll({
            'Content-Type': 'application/json',
            if (_usesProxy && _proxyToken.trim().isNotEmpty)
              'Authorization': 'Bearer $_proxyToken'
            else if (!_usesProxy)
              'Authorization': 'Bearer $_apiKey',
          })
          ..body = jsonEncode(body);
        final streamed =
            await _client.send(request).timeout(const Duration(seconds: 35));
        final result = await http.Response.fromStream(streamed);
        cancellationToken?.throwIfCancelled();
        if (result.statusCode >= 200 && result.statusCode < 300) {
          yuqiaoDebugLog('[Qwen API] success ${result.statusCode}');
          final decoded = jsonDecode(utf8.decode(result.bodyBytes));
          if (decoded is! Map<String, dynamic>) {
            throw const QwenException('Qwen API 返回格式不是 JSON 对象。');
          }
          return decoded;
        }
        yuqiaoDebugLog('[Qwen API] error ${result.statusCode}');
        if (!retryableStatusCodes.contains(result.statusCode) || attempt == 2) {
          throw QwenException(
            'Qwen API 请求失败：${result.statusCode}',
          );
        }
        lastError = QwenException('Qwen API 暂时不可用：${result.statusCode}');
      } on QwenCancelledException {
        rethrow;
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
      } on SocketException catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
      } on http.ClientException catch (error) {
        if (cancellationToken?.isCancelled == true) {
          throw const QwenCancelledException();
        }
        lastError = error;
        if (attempt == 2) rethrow;
      }
      cancellationToken?.throwIfCancelled();
      await Future<void>.delayed(Duration(milliseconds: 650 * attempt));
    }
    throw QwenException('Qwen API 请求失败：$lastError');
  }

  String _messageContent(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const QwenException('Qwen API 未返回候选结果。');
    }
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) {
      throw const QwenException('Qwen API 候选格式异常。');
    }
    final message = choice['message'];
    if (message is! Map<String, dynamic>) {
      throw const QwenException('Qwen API 消息格式异常。');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    throw const QwenException('Qwen API 返回内容为空。');
  }

  List<String> _parseStringList(String content) {
    final cleaned = _stripCodeFence(content);
    final decoded = jsonDecode(cleaned);
    if (decoded is! List) {
      throw const QwenException('候选句返回格式错误，应为 JSON 数组。');
    }
    final sentences = decoded
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (sentences.isEmpty) {
      throw const QwenException('未生成可用候选句。');
    }
    return sentences;
  }

  ObjectRecognition _parseRecognition(String content) {
    final cleaned = _stripCodeFence(content);
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic>) {
      throw const QwenException('识别结果返回格式错误，应为 JSON 对象。');
    }
    final candidates = decoded['candidates'];
    if (candidates is List) {
      final parsedCandidates = candidates
          .whereType<Map<String, dynamic>>()
          .map(_parseObjectCandidate)
          .where((candidate) => candidate.objectName.isNotEmpty)
          .take(4)
          .toList();
      if (parsedCandidates.isNotEmpty) {
        return ObjectRecognition(candidates: parsedCandidates);
      }
    }

    // Backward compatible fallback for occasional single-result model output.
    final objectName = decoded['objectName'];
    final expressions = decoded['expressions'];
    if (objectName is! String ||
        objectName.trim().isEmpty ||
        expressions is! List) {
      throw const QwenException('识别结果缺少物品名称或表达候选。');
    }
    final expressionList = expressions
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList();
    if (expressionList.isEmpty) {
      throw const QwenException('识别结果没有可用表达候选。');
    }
    return ObjectRecognition(
      candidates: [
        ObjectCandidate(
          objectName: objectName.trim(),
          confidence: '高',
          expressions: expressionList,
          expressionOptions: expressionList
              .map(
                (phrase) => ObjectExpressionOption(
                  type: _inferExpressionType(phrase),
                  phrase: phrase,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  ObjectCandidate _parseObjectCandidate(Map<String, dynamic> json) {
    final objectName = json['objectName'];
    final rawExpressionOptions = json['expressionOptions'];
    final expressionOptions = _parseExpressionOptions(rawExpressionOptions);
    final expressions = json['expressions'];
    final legacyExpressionList = expressions is List
        ? expressions
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .take(3)
            .toList()
        : <String>[];
    final effectiveOptions = expressionOptions.isNotEmpty
        ? expressionOptions
        : legacyExpressionList
            .map(
              (phrase) => ObjectExpressionOption(
                type: _inferExpressionType(phrase),
                phrase: phrase,
              ),
            )
            .toList();
    final expressionList = effectiveOptions
        .map((item) => item.phrase)
        .where((item) => item.isNotEmpty)
        .toList();
    final rawBbox = json['bbox'];
    final bbox = normalizeModelBoundingBox(rawBbox);
    yuqiaoDebugLog(
        '[Camera bbox] object=${objectName is String ? objectName : ''} '
        'raw=$rawBbox normalized=$bbox');
    return ObjectCandidate(
      objectName: objectName is String ? objectName.trim() : '',
      confidence:
          json['confidence'] is String ? json['confidence'] as String : '',
      category: json['category'] is String ? json['category'] as String : '',
      visualDescription: json['visualDescription'] is String
          ? json['visualDescription'] as String
          : '',
      personalObjectId: json['personalObjectId'] is String
          ? json['personalObjectId'] as String
          : '',
      expressionOptions: effectiveOptions,
      expressions:
          expressionList.isEmpty ? const ['我想要这个', '请帮我拿一下'] : expressionList,
      bbox: bbox,
    );
  }

  String _inferExpressionType(String phrase) {
    if (phrase.contains('买') || phrase.contains('多少钱')) return '购买';
    if (phrase.contains('喝') || phrase.contains('吃')) return '饮用';
    if (phrase.contains('找') || phrase.contains('哪里')) return '寻找';
    if (phrase.contains('拿') || phrase.contains('打开') || phrase.contains('用')) {
      return '使用';
    }
    if (phrase.contains('帮') || phrase.contains('请')) return '求助';
    return '表达';
  }

  List<ObjectExpressionOption> _parseExpressionOptions(dynamic raw) {
    if (raw is! List) return const [];
    final options = <ObjectExpressionOption>[];
    final seenTypes = <String>{};
    for (final value in raw.whereType<Map<String, dynamic>>()) {
      final parsed = ObjectExpressionOption.fromJson(value);
      if (parsed.phrase.isEmpty) continue;
      final type = parsed.type.isEmpty
          ? _inferExpressionType(parsed.phrase)
          : parsed.type;
      final normalizedType = type.replaceAll(RegExp(r'\s+'), '');
      if (!seenTypes.add(normalizedType)) continue;
      options.add(ObjectExpressionOption(type: type, phrase: parsed.phrase));
      if (options.length == 3) break;
    }
    return options;
  }

  String _stripCodeFence(String value) {
    return value
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
  }

  String _normalizeOption(String value) {
    return value
        .replaceAll(RegExp(r'^[\s\d.、\-]+'), '')
        .replaceAll(RegExp(r'[。！？,.，；;：:]+$'), '')
        .trim();
  }

  void _ensureConfigured() {
    if (!_usesProxy && _apiKey.isEmpty) {
      throw const QwenException(
        '缺少 QWEN_API_KEY 或 YUQIAO_QWEN_PROXY_URL。请使用后端代理，或在调试时通过 --dart-define 注入 QWEN_API_KEY。',
      );
    }
  }
}
