part of 'main.dart';

class SpriteAssistantActionIds {
  static const setImageScale = 'set_image_scale';
  static const setCandidateCount = 'set_candidate_count';
  static const addVocabularyEntry = 'add_vocabulary_entry';
  static const saveFavoriteExpression = 'save_favorite_expression';
  static const openExpressionPreferences = 'open_expression_preferences';
  static const openVocabulary = 'open_vocabulary';
  static const openPersonalObjects = 'open_personal_objects';
  static const openFamilyContact = 'open_family_contact';
  static const openTraining = 'open_training';
  static const openListeningTraining = 'open_listening_training';
  static const openMemory = 'open_memory';
  static const togglePersonalizedLearning = 'toggle_personalized_learning';
  static const toggleAutoStuckDetection = 'toggle_auto_stuck_detection';
  static const toggleLocationRecommendation = 'toggle_location_recommendation';
  static const unsupported = 'unsupported';

  static const allowed = <String>{
    setImageScale,
    setCandidateCount,
    addVocabularyEntry,
    saveFavoriteExpression,
    openExpressionPreferences,
    openVocabulary,
    openPersonalObjects,
    openFamilyContact,
    openTraining,
    openListeningTraining,
    openMemory,
    togglePersonalizedLearning,
    toggleAutoStuckDetection,
    toggleLocationRecommendation,
    unsupported,
  };
}

class SpriteAssistantUsageStore {
  static const _storageKey = 'sprite_assistant_usage_v1';
  static const _maxEntries = 80;

  Future<void> record(String actionId, {required String outcome}) async {
    if (!SpriteAssistantActionIds.allowed.contains(actionId) ||
        actionId == SpriteAssistantActionIds.unsupported) {
      return;
    }
    final entries = await _load();
    entries.add({
      'actionId': actionId,
      'outcome': outcome,
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    await SensitiveLocalStore.writeString(_storageKey, jsonEncode(entries));
  }

  Future<List<String>> promptHints({int limit = 5}) async {
    final entries = await _load();
    final scores = <String, double>{};
    final counts = <String, int>{};
    for (final entry in entries) {
      final actionId = entry['actionId']?.toString() ?? '';
      final outcome = entry['outcome']?.toString() ?? '';
      final delta = switch (outcome) {
        'completed' => 1.0,
        'cancelled' => -0.35,
        'failed' => -0.6,
        'undone' => -0.8,
        _ => 0.0,
      };
      scores.update(actionId, (value) => value + delta, ifAbsent: () => delta);
      if (outcome == 'completed') {
        counts.update(actionId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final ranked = scores.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(limit).map((entry) {
      final title = SpriteAssistantIntent._defaultTitle(entry.key);
      return '常用操作：$title（成功 ${counts[entry.key] ?? 0} 次）';
    }).toList(growable: false);
  }

  Future<void> clear() {
    return SensitiveLocalStore.delete(_storageKey);
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await SensitiveLocalStore.readString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class SpriteAssistantIntent {
  const SpriteAssistantIntent({
    required this.actionId,
    required this.parameters,
    required this.confidence,
    required this.title,
    required this.confirmation,
    required this.reason,
    required this.rawText,
    this.usedLocalFallback = false,
  });

  final String actionId;
  final Map<String, dynamic> parameters;
  final double confidence;
  final String title;
  final String confirmation;
  final String reason;
  final String rawText;
  final bool usedLocalFallback;

  bool get isSupported => validationMessage == null;

  String? get validationMessage {
    if (actionId == SpriteAssistantActionIds.unsupported ||
        !SpriteAssistantActionIds.allowed.contains(actionId)) {
      return '这个请求暂时不在小精灵能安全执行的范围内。';
    }
    if (confidence < 0.45) return '我还没有听懂具体要执行什么。';
    final text = parameters['text']?.toString().trim() ?? '';
    return switch (actionId) {
      SpriteAssistantActionIds.setImageScale
          when parameters['imageScale'] is! num =>
        '请再说一次图片要调大、调小还是恢复标准大小。',
      SpriteAssistantActionIds.setCandidateCount
          when parameters['candidateCount'] is! int =>
        '请告诉我每次要显示两项、四项还是六项候选。',
      SpriteAssistantActionIds.togglePersonalizedLearning ||
      SpriteAssistantActionIds.toggleAutoStuckDetection ||
      SpriteAssistantActionIds.toggleLocationRecommendation
          when parameters['enabled'] is! bool =>
        '请明确告诉我要开启还是关闭。',
      SpriteAssistantActionIds.addVocabularyEntry when text.isEmpty =>
        '请告诉我想添加哪个词。',
      SpriteAssistantActionIds.addVocabularyEntry when text.length > 12 =>
        '词条有点长，请缩短到 12 个字以内。',
      SpriteAssistantActionIds.saveFavoriteExpression when text.isEmpty =>
        '请告诉我想保存哪一句常用表达。',
      SpriteAssistantActionIds.saveFavoriteExpression when text.length > 32 =>
        '常用表达有点长，请缩短到 32 个字以内。',
      _ => null,
    };
  }

  bool get needsTextFollowUp {
    if (actionId == SpriteAssistantActionIds.unsupported ||
        !SpriteAssistantActionIds.allowed.contains(actionId) ||
        confidence < 0.45) {
      return false;
    }
    return validationMessage != null &&
        SpriteAssistantActionIds.allowed.contains(actionId) &&
        switch (actionId) {
          SpriteAssistantActionIds.setImageScale ||
          SpriteAssistantActionIds.setCandidateCount ||
          SpriteAssistantActionIds.addVocabularyEntry ||
          SpriteAssistantActionIds.saveFavoriteExpression ||
          SpriteAssistantActionIds.togglePersonalizedLearning ||
          SpriteAssistantActionIds.toggleAutoStuckDetection ||
          SpriteAssistantActionIds.toggleLocationRecommendation =>
            true,
          _ => false,
        };
  }

  SpriteAssistantIntent copyWith({
    Map<String, dynamic>? parameters,
    double? confidence,
    String? title,
    String? confirmation,
    String? reason,
    bool? usedLocalFallback,
  }) {
    final nextParameters = parameters ?? this.parameters;
    return SpriteAssistantIntent(
      actionId: actionId,
      parameters: nextParameters,
      confidence: confidence ?? this.confidence,
      title: title ?? this.title,
      confirmation:
          confirmation ?? _defaultConfirmation(actionId, nextParameters),
      reason: reason ?? this.reason,
      rawText: rawText,
      usedLocalFallback: usedLocalFallback ?? this.usedLocalFallback,
    );
  }

  factory SpriteAssistantIntent.fromJson(
    Object? value, {
    required String rawText,
  }) {
    if (value is! Map) {
      return SpriteAssistantIntent.unsupported(rawText, reason: '模型没有返回可识别的动作');
    }
    final actionId = value['actionId']?.toString().trim() ??
        SpriteAssistantActionIds.unsupported;
    final safeActionId = SpriteAssistantActionIds.allowed.contains(actionId)
        ? actionId
        : SpriteAssistantActionIds.unsupported;
    final rawParameters = value['parameters'];
    final parsedParameters = rawParameters is Map
        ? rawParameters.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};
    final parameters = _sanitizeParameters(safeActionId, parsedParameters);
    final rawConfidence = value['confidence'];
    final parsedConfidence = rawConfidence is num
        ? rawConfidence.toDouble()
        : double.tryParse(rawConfidence?.toString() ?? '');
    final confidence = (parsedConfidence ?? 0.0).clamp(0.0, 1.0).toDouble();
    final reason = value['reason']?.toString().trim() ?? '';
    return SpriteAssistantIntent(
      actionId: safeActionId,
      parameters: parameters,
      confidence: safeActionId == SpriteAssistantActionIds.unsupported
          ? 0.0
          : confidence,
      title: _defaultTitle(safeActionId),
      confirmation: _defaultConfirmation(safeActionId, parameters),
      reason: reason.isEmpty ? '根据你的语音请求匹配到这个操作。' : reason,
      rawText: rawText,
    );
  }

  static Map<String, dynamic> _sanitizeParameters(
    String actionId,
    Map<String, dynamic> raw,
  ) {
    final result = <String, dynamic>{};
    switch (actionId) {
      case SpriteAssistantActionIds.setImageScale:
        final value = _asDouble(raw['imageScale']);
        if (value != null && value >= 0.8 && value <= 1.7) {
          const options = [0.9, 1.0, 1.25, 1.55];
          result['imageScale'] = options.reduce(
            (best, item) =>
                (item - value).abs() < (best - value).abs() ? item : best,
          );
        }
        break;
      case SpriteAssistantActionIds.setCandidateCount:
        final value = _asDouble(raw['candidateCount']);
        if (value != null && value >= 1 && value <= 8) {
          const options = [2, 4, 6];
          result['candidateCount'] = options.reduce(
            (best, item) =>
                (item - value).abs() < (best - value).abs() ? item : best,
          );
        }
        break;
      case SpriteAssistantActionIds.togglePersonalizedLearning:
      case SpriteAssistantActionIds.toggleAutoStuckDetection:
      case SpriteAssistantActionIds.toggleLocationRecommendation:
        final enabled = _asBool(raw['enabled']);
        if (enabled != null) result['enabled'] = enabled;
        break;
      case SpriteAssistantActionIds.addVocabularyEntry:
        final text = _cleanText(raw['text']);
        if (text.isNotEmpty) result['text'] = text;
        final category = raw['category']?.toString().trim() ?? '';
        const categories = ['人物', '饮食', '地点', '活动', '物品', '感受', '常用句'];
        if (categories.contains(category)) result['category'] = category;
        break;
      case SpriteAssistantActionIds.saveFavoriteExpression:
        final text = _cleanText(raw['text']);
        if (text.isNotEmpty) result['text'] = text;
        break;
      default:
        break;
    }
    return result;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (['true', '1', 'yes', 'on', 'open', '开启'].contains(normalized)) {
      return true;
    }
    if (['false', '0', 'no', 'off', 'close', '关闭'].contains(normalized)) {
      return false;
    }
    return null;
  }

  static String _cleanText(Object? value) {
    return value
            ?.toString()
            .replaceAll(RegExp(r'^[“”"‘’\s]+|[“”"‘’\s]+$'), '')
            .trim() ??
        '';
  }

  factory SpriteAssistantIntent.unsupported(
    String rawText, {
    String reason = '这个请求暂时不在小精灵能安全执行的范围内。',
  }) {
    return SpriteAssistantIntent(
      actionId: SpriteAssistantActionIds.unsupported,
      parameters: const {},
      confidence: 0,
      title: '还不能直接完成',
      confirmation: '我还不能安全执行这个操作',
      reason: reason,
      rawText: rawText,
    );
  }

  static String _defaultTitle(String actionId) {
    return switch (actionId) {
      SpriteAssistantActionIds.setImageScale => '调整图片大小',
      SpriteAssistantActionIds.setCandidateCount => '调整候选数量',
      SpriteAssistantActionIds.addVocabularyEntry => '添加词库词条',
      SpriteAssistantActionIds.saveFavoriteExpression => '保存常用表达',
      SpriteAssistantActionIds.openExpressionPreferences => '打开表达偏好',
      SpriteAssistantActionIds.openVocabulary => '打开我的词库',
      SpriteAssistantActionIds.openPersonalObjects => '管理个人物品',
      SpriteAssistantActionIds.openFamilyContact => '配置家人联系',
      SpriteAssistantActionIds.openTraining => '打开词语花园',
      SpriteAssistantActionIds.openListeningTraining => '打开听理解训练',
      SpriteAssistantActionIds.openMemory => '查看语桥记忆',
      SpriteAssistantActionIds.togglePersonalizedLearning => '调整学习记忆',
      SpriteAssistantActionIds.toggleAutoStuckDetection => '调整自动帮助',
      SpriteAssistantActionIds.toggleLocationRecommendation => '调整地点推荐',
      _ => '还不能直接完成',
    };
  }

  static String _defaultConfirmation(
    String actionId,
    Map<String, dynamic> parameters,
  ) {
    return switch (actionId) {
      SpriteAssistantActionIds.setImageScale =>
        _imageScaleConfirmation(parameters),
      SpriteAssistantActionIds.setCandidateCount =>
        _candidateCountConfirmation(parameters),
      SpriteAssistantActionIds.addVocabularyEntry => _addVocabularyConfirmation(
          parameters,
        ),
      SpriteAssistantActionIds.saveFavoriteExpression =>
        _saveFavoriteConfirmation(parameters),
      SpriteAssistantActionIds.openExpressionPreferences => '打开表达偏好设置页',
      SpriteAssistantActionIds.openVocabulary => '打开我的词库页面',
      SpriteAssistantActionIds.openPersonalObjects => '打开个人物品管理',
      SpriteAssistantActionIds.openFamilyContact => '打开家人联系配置',
      SpriteAssistantActionIds.openTraining => '打开词语花园训练',
      SpriteAssistantActionIds.openListeningTraining => '打开听理解训练',
      SpriteAssistantActionIds.openMemory => '打开语桥记忆页面',
      SpriteAssistantActionIds.togglePersonalizedLearning =>
        _toggleConfirmation(parameters, '个性化学习记忆'),
      SpriteAssistantActionIds.toggleAutoStuckDetection =>
        _toggleConfirmation(parameters, '表达卡住时的自动帮助'),
      SpriteAssistantActionIds.toggleLocationRecommendation =>
        _toggleConfirmation(parameters, '地点场景推荐'),
      _ => '我还不能安全执行这个操作',
    };
  }

  static String _addVocabularyConfirmation(Map<String, dynamic> parameters) {
    final text = parameters['text']?.toString().trim() ?? '';
    final category = parameters['category']?.toString().trim() ?? '';
    if (text.isEmpty) return '把这个词添加到我的词库';
    if (category.isEmpty) return '把“$text”添加到我的词库';
    return '把“$text”添加到“$category”分类';
  }

  static String _saveFavoriteConfirmation(Map<String, dynamic> parameters) {
    final text = parameters['text']?.toString().trim() ?? '';
    if (text.isEmpty) return '把这句话保存为常用表达';
    return '把“$text”保存为常用表达';
  }

  static String _imageScaleConfirmation(Map<String, dynamic> parameters) {
    final scale = parameters['imageScale'];
    final label = switch (scale) {
      0.9 => '较小',
      1.0 => '标准',
      1.25 => '较大',
      1.55 => '最大',
      _ => '',
    };
    return label.isEmpty ? '调整表达候选里的图片大小' : '把表达候选里的图片调整为$label';
  }

  static String _candidateCountConfirmation(
    Map<String, dynamic> parameters,
  ) {
    final count = parameters['candidateCount'];
    return count is int ? '把每次显示的候选调整为 $count 项' : '调整每次显示的候选数量';
  }

  static String _toggleConfirmation(
    Map<String, dynamic> parameters,
    String label,
  ) {
    final enabled = parameters['enabled'];
    return enabled is bool ? '${enabled ? '开启' : '关闭'}$label' : '调整$label';
  }
}

class SpriteAssistantExecutionResult {
  const SpriteAssistantExecutionResult({
    required this.title,
    required this.message,
    this.undoLabel,
    this.onUndo,
  });

  final String title;
  final String message;
  final String? undoLabel;
  final Future<SpriteAssistantExecutionResult> Function()? onUndo;
}

enum _SpriteAssistantStage {
  idle,
  listening,
  interpreting,
  asking,
  confirm,
  executing,
  completed,
  unsupported,
  error,
}

class SpriteAssistantPage extends StatefulWidget {
  const SpriteAssistantPage({
    super.key,
    required this.qwenService,
    required this.onExecute,
  });

  final QwenService qwenService;
  final Future<SpriteAssistantExecutionResult> Function(
    BuildContext context,
    SpriteAssistantIntent intent,
  ) onExecute;

  @override
  State<SpriteAssistantPage> createState() => _SpriteAssistantPageState();
}

class _SpriteAssistantPageState extends State<SpriteAssistantPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ParaformerAsrService _asrService = ParaformerAsrService();
  final SpriteAssistantUsageStore _usageStore = SpriteAssistantUsageStore();
  late final AnimationController _orbController;

  _SpriteAssistantStage _stage = _SpriteAssistantStage.idle;
  SpriteAssistantIntent? _intent;
  SpriteAssistantIntent? _pendingFollowUpIntent;
  SpriteAssistantExecutionResult? _result;
  String? _message;
  bool _recording = false;
  bool _undoing = false;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _orbController.dispose();
    unawaited(_asrService.dispose());
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      await _asrService.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _stage = _controller.text.trim().isEmpty
            ? _SpriteAssistantStage.idle
            : _SpriteAssistantStage.idle;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _stage = _SpriteAssistantStage.listening;
      _message = null;
      _intent = null;
      _result = null;
    });
    try {
      await _asrService.start(
        onTranscript: (text, isFinal) {
          if (!mounted) return;
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          if (isFinal) {
            setState(() {
              _recording = false;
              _stage = _SpriteAssistantStage.idle;
            });
            unawaited(_asrService.stop());
          }
        },
        onStatus: (_) {},
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _recording = false;
            _stage = _SpriteAssistantStage.error;
            _message = message;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _stage = _SpriteAssistantStage.error;
        _message = error.toString();
      });
    }
  }

  Future<void> _understand() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _stage == _SpriteAssistantStage.interpreting) return;
    if (_pendingFollowUpIntent != null) {
      _completeFollowUp(text);
      return;
    }
    HapticFeedback.selectionClick();
    await _asrService.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _stage = _SpriteAssistantStage.interpreting;
      _intent = null;
      _pendingFollowUpIntent = null;
      _result = null;
      _message = null;
    });
    try {
      final operationHints = await _usageStore.promptHints();
      final intent = await widget.qwenService.understandSpriteAssistantRequest(
        text,
        operationHints: operationHints,
      );
      if (!mounted) return;
      if (intent.needsTextFollowUp) {
        _askForMissingParameter(intent);
        return;
      }
      setState(() {
        _intent = intent;
        _stage = intent.isSupported
            ? _SpriteAssistantStage.confirm
            : _SpriteAssistantStage.unsupported;
        _message = intent.isSupported
            ? intent.reason
            : intent.validationMessage ?? intent.reason;
      });
    } catch (error) {
      final fallback = _localFallbackIntent(text);
      if (!mounted) return;
      if (fallback.needsTextFollowUp) {
        _askForMissingParameter(fallback);
        return;
      }
      setState(() {
        _intent = fallback;
        _stage = fallback.isSupported
            ? _SpriteAssistantStage.confirm
            : _SpriteAssistantStage.error;
        _message = fallback.isSupported
            ? '智能理解暂时不可用，我先用本地规则匹配到这个安全操作。'
            : '智能理解暂时不可用，也没有匹配到可执行的本地操作。';
      });
    }
  }

  void _askForMissingParameter(SpriteAssistantIntent intent) {
    setState(() {
      _pendingFollowUpIntent = intent;
      _intent = intent;
      _controller.clear();
      _stage = _SpriteAssistantStage.asking;
      _message = switch (intent.actionId) {
        SpriteAssistantActionIds.addVocabularyEntry => '想添加哪个词？',
        SpriteAssistantActionIds.saveFavoriteExpression => '想保存哪一句常用表达？',
        SpriteAssistantActionIds.setImageScale => '图片要调小、标准、较大，还是最大？',
        SpriteAssistantActionIds.setCandidateCount => '每次显示两项、四项，还是六项候选？',
        SpriteAssistantActionIds.togglePersonalizedLearning =>
          '要开启还是关闭个性化学习记忆？',
        SpriteAssistantActionIds.toggleAutoStuckDetection =>
          '要开启还是关闭表达卡住时的自动帮助？',
        SpriteAssistantActionIds.toggleLocationRecommendation =>
          '要开启还是关闭地点场景推荐？',
        _ => intent.validationMessage ?? '请补充需要执行的内容。',
      };
    });
  }

  void _completeFollowUp(String text) {
    final pending = _pendingFollowUpIntent;
    if (pending == null) return;
    final cleanText =
        text.replaceAll(RegExp(r'^[“”"‘’\s]+|[“”"‘’\s]+$'), '').trim();
    if (cleanText.isEmpty) return;
    final followUpParameters = _followUpParameters(pending, cleanText);
    if (followUpParameters == null) {
      setState(() {
        _message = pending.validationMessage ?? '我还没有听懂，请再说一次。';
        _controller.clear();
      });
      return;
    }
    final parameters = <String, dynamic>{
      ...pending.parameters,
      ...followUpParameters,
    };
    final completed = pending.copyWith(
      parameters: parameters,
      confirmation: SpriteAssistantIntent._defaultConfirmation(
        pending.actionId,
        parameters,
      ),
      reason: '已补充需要保存的文字，请确认后执行。',
    );
    setState(() {
      _pendingFollowUpIntent = null;
      _intent = completed;
      _controller.text = cleanText;
      _stage = _SpriteAssistantStage.confirm;
      _message = completed.reason;
    });
  }

  Map<String, dynamic>? _followUpParameters(
    SpriteAssistantIntent pending,
    String text,
  ) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    switch (pending.actionId) {
      case SpriteAssistantActionIds.addVocabularyEntry:
        if (text.length > 12) return null;
        return {
          'text': text,
          if (pending.parameters['category'] == null)
            'category': _inferVocabularyCategory(text),
        };
      case SpriteAssistantActionIds.saveFavoriteExpression:
        if (text.length > 32) return null;
        return {'text': text};
      case SpriteAssistantActionIds.setImageScale:
        final scale = compact.contains('最大') || compact.contains('很大')
            ? 1.55
            : compact.contains('较大') ||
                    compact.contains('大一点') ||
                    compact.contains('更大')
                ? 1.25
                : compact.contains('标准') || compact.contains('正常')
                    ? 1.0
                    : compact.contains('小')
                        ? 0.9
                        : null;
        return scale == null ? null : {'imageScale': scale};
      case SpriteAssistantActionIds.setCandidateCount:
        final count = RegExp(r'(^|[^0-9])6([^0-9]|$)|六').hasMatch(compact)
            ? 6
            : RegExp(r'(^|[^0-9])4([^0-9]|$)|四').hasMatch(compact)
                ? 4
                : RegExp(r'(^|[^0-9])2([^0-9]|$)|两|二').hasMatch(compact)
                    ? 2
                    : null;
        return count == null ? null : {'candidateCount': count};
      case SpriteAssistantActionIds.togglePersonalizedLearning:
      case SpriteAssistantActionIds.toggleAutoStuckDetection:
      case SpriteAssistantActionIds.toggleLocationRecommendation:
        final enabled = RegExp(r'关闭|关掉|停用|不要|取消').hasMatch(compact)
            ? false
            : RegExp(r'开启|打开|启用|需要|要').hasMatch(compact)
                ? true
                : null;
        return enabled == null ? null : {'enabled': enabled};
      default:
        return null;
    }
  }

  SpriteAssistantIntent _localFallbackIntent(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    SpriteAssistantIntent intent(
      String actionId, {
      Map<String, dynamic> parameters = const {},
      String? title,
      String? confirmation,
    }) {
      return SpriteAssistantIntent(
        actionId: actionId,
        parameters: parameters,
        confidence: 0.7,
        title: title ?? SpriteAssistantIntent._defaultTitle(actionId),
        confirmation: confirmation ??
            SpriteAssistantIntent._defaultConfirmation(actionId, parameters),
        reason: '本地规则识别到这个常用操作。',
        rawText: text,
        usedLocalFallback: true,
      );
    }

    final favoriteText = _extractFavoriteExpression(text);
    if (favoriteText != null) {
      return intent(
        SpriteAssistantActionIds.saveFavoriteExpression,
        parameters: {'text': favoriteText},
      );
    }
    if (_looksLikeFavoriteRequest(text)) {
      return intent(SpriteAssistantActionIds.saveFavoriteExpression);
    }
    final vocabularyText = _extractVocabularyText(text);
    if (vocabularyText != null) {
      return intent(
        SpriteAssistantActionIds.addVocabularyEntry,
        parameters: {
          'text': vocabularyText,
          'category': _inferVocabularyCategory(vocabularyText),
        },
      );
    }
    if (_looksLikeVocabularyAddRequest(text)) {
      return intent(SpriteAssistantActionIds.addVocabularyEntry);
    }
    if (compact.contains('听理解')) {
      return intent(SpriteAssistantActionIds.openListeningTraining);
    }
    if (compact.contains('训练') || compact.contains('词语花园')) {
      return intent(SpriteAssistantActionIds.openTraining);
    }
    if (compact.contains('词库') || compact.contains('词典')) {
      return intent(SpriteAssistantActionIds.openVocabulary);
    }
    if (compact.contains('个人物品') || compact.contains('我的物品')) {
      return intent(SpriteAssistantActionIds.openPersonalObjects);
    }
    if (compact.contains('家人') || compact.contains('电话')) {
      return intent(SpriteAssistantActionIds.openFamilyContact);
    }
    if (compact.contains('记忆') || compact.contains('隐私')) {
      return intent(SpriteAssistantActionIds.openMemory);
    }
    if (compact.contains('候选') || compact.contains('选项')) {
      final count = compact.contains('六') || compact.contains('6')
          ? 6
          : compact.contains('四') || compact.contains('4')
              ? 4
              : 2;
      return intent(
        SpriteAssistantActionIds.setCandidateCount,
        parameters: {'candidateCount': count},
      );
    }
    if (compact.contains('图片') ||
        compact.contains('图标') ||
        compact.contains('卡片')) {
      final scale = compact.contains('小')
          ? 0.9
          : compact.contains('标准') || compact.contains('正常')
              ? 1.0
              : compact.contains('大一点') || compact.contains('更大')
                  ? 1.25
                  : 1.55;
      return intent(
        SpriteAssistantActionIds.setImageScale,
        parameters: {'imageScale': scale},
      );
    }
    return SpriteAssistantIntent.unsupported(text);
  }

  bool _looksLikeVocabularyAddRequest(String text) {
    return RegExp(r'(添加|新增|加入|保存).*(词库|词典|词条|词语|词)').hasMatch(text) ||
        RegExp(r'(词库|词典).*(添加|新增|加入)').hasMatch(text);
  }

  bool _looksLikeFavoriteRequest(String text) {
    return RegExp(r'(常用|收藏|常用表达|常用句)').hasMatch(text) &&
        RegExp(r'(设为|保存|加入|添加|放到)').hasMatch(text);
  }

  String? _extractVocabularyText(String text) {
    final trimmed = text.trim();
    if (!_looksLikeVocabularyAddRequest(trimmed)) {
      return null;
    }
    final separated = _textAfterSeparator(trimmed);
    if (separated != null) return separated;
    var candidate = trimmed
        .replaceAll(RegExp(r'^(请|帮我|麻烦你|小精灵)'), '')
        .replaceAll(RegExp(r'(添加|新增|加入|保存)'), '')
        .replaceAll(RegExp(r'(到|进|在)?(我的)?(词库|词典|词条|词语)'), '')
        .replaceAll(RegExp(r'^(一个|一条|这个)?词'), '')
        .replaceAll(RegExp(r'一个|一条|这个|这个词|这个词语|词$'), '')
        .replaceAll(RegExp(r'[“”"‘’\s，。！？、:：]+'), '')
        .trim();
    if (candidate.isEmpty || candidate.length > 12) return null;
    return candidate;
  }

  String? _extractFavoriteExpression(String text) {
    final trimmed = text.trim();
    if (!RegExp(r'(常用|收藏|常用表达|常用句)').hasMatch(trimmed)) {
      return null;
    }
    final separated = _textAfterSeparator(trimmed);
    if (separated != null) return separated;
    final between = RegExp(r'把(.+?)(设为|保存为|加入|添加到|放到)?(常用|收藏|常用表达|常用句)')
        .firstMatch(trimmed)
        ?.group(1)
        ?.trim();
    if (between != null && between.isNotEmpty && between.length <= 28) {
      return between.replaceAll(RegExp(r'^[“”"‘’\s]+|[“”"‘’\s]+$'), '');
    }
    return null;
  }

  String? _textAfterSeparator(String text) {
    final parts = text.split(RegExp(r'[:：]'));
    if (parts.length < 2) return null;
    final candidate = parts.sublist(1).join('：').trim();
    if (candidate.isEmpty || candidate.length > 28) return null;
    return candidate.replaceAll(RegExp(r'^[“”"‘’\s]+|[“”"‘’\s]+$'), '');
  }

  String _inferVocabularyCategory(String text) {
    if (RegExp(r'(爸爸|妈妈|医生|护士|家人|朋友|老师|同学|儿子|女儿)').hasMatch(text)) {
      return '人物';
    }
    if (RegExp(r'(水|饭|粥|面|水果|牛奶|茶|药|包子|饺子|汤)').hasMatch(text)) {
      return '饮食';
    }
    if (RegExp(r'(医院|家|超市|厕所|卫生间|公园|药房|病房|厨房)').hasMatch(text)) {
      return '地点';
    }
    if (RegExp(r'(疼|累|冷|热|饿|渴|不舒服|头晕|害怕|着急)').hasMatch(text)) {
      return '感受';
    }
    if (text.length >= 4 || RegExp(r'(请|我想|帮我|不要|需要)').hasMatch(text)) {
      return '常用句';
    }
    return '物品';
  }

  Future<void> _execute() async {
    final intent = _intent;
    if (intent == null || !intent.isSupported) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _stage = _SpriteAssistantStage.executing;
      _message = null;
    });
    try {
      final result = await widget.onExecute(context, intent);
      if (!mounted) return;
      unawaited(_usageStore.record(intent.actionId, outcome: 'completed'));
      setState(() {
        _result = result;
        _stage = _SpriteAssistantStage.completed;
      });
    } catch (error) {
      if (!mounted) return;
      unawaited(_usageStore.record(intent.actionId, outcome: 'failed'));
      setState(() {
        _stage = _SpriteAssistantStage.error;
        _message = error.toString();
      });
    }
  }

  Future<void> _undoLastResult() async {
    final undo = _result?.onUndo;
    if (undo == null || _undoing) return;
    HapticFeedback.selectionClick();
    setState(() => _undoing = true);
    try {
      final result = await undo();
      if (!mounted) return;
      final actionId = _intent?.actionId;
      if (actionId != null) {
        unawaited(_usageStore.record(actionId, outcome: 'undone'));
      }
      setState(() {
        _result = result;
        _undoing = false;
        _stage = _SpriteAssistantStage.completed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _undoing = false;
        _stage = _SpriteAssistantStage.error;
        _message = error.toString();
      });
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _controller.clear();
      _intent = null;
      _pendingFollowUpIntent = null;
      _result = null;
      _message = null;
      _undoing = false;
      _stage = _SpriteAssistantStage.idle;
    });
  }

  void _rejectAndReset() {
    final actionId = _intent?.actionId;
    if (actionId != null) {
      unawaited(_usageStore.record(actionId, outcome: 'cancelled'));
    }
    _reset();
  }

  String get _statusTitle {
    return switch (_stage) {
      _SpriteAssistantStage.listening => '我在听',
      _SpriteAssistantStage.interpreting => '正在理解',
      _SpriteAssistantStage.asking => '还差一点信息',
      _SpriteAssistantStage.confirm => '需要你确认',
      _SpriteAssistantStage.executing => '正在执行',
      _SpriteAssistantStage.completed => '已经完成',
      _SpriteAssistantStage.unsupported => '还做不了',
      _SpriteAssistantStage.error => '遇到问题',
      _ => '你想让我帮你做什么？',
    };
  }

  String get _statusSubtitle {
    return switch (_stage) {
      _SpriteAssistantStage.listening => '说完后我会把语音变成文字',
      _SpriteAssistantStage.interpreting => '我会先匹配到安全的 App 内操作',
      _SpriteAssistantStage.asking => _message ?? '请补充这个任务需要的文字',
      _SpriteAssistantStage.confirm => '确认后才会真正修改设置或打开页面',
      _SpriteAssistantStage.executing => '正在处理这个任务',
      _SpriteAssistantStage.completed => _result?.message ?? '任务已完成',
      _SpriteAssistantStage.unsupported => _message ?? '这个操作暂时不在白名单里',
      _SpriteAssistantStage.error => _message ?? '请稍后再试一次',
      _ => '可以说“把图标调大”“候选改成两个”“打开听理解训练”',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kYuqiaoSystemUiStyle,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F2EA),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 700;
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFF6E6),
                      Color(0xFFF7F2EA),
                      Color(0xFFEFF3EC),
                    ],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                      child: Column(
                        children: [
                          _buildTopBar(),
                          SizedBox(height: isCompact ? 10 : 18),
                          _buildHeroOrb(isCompact: isCompact),
                          SizedBox(height: isCompact ? 10 : 18),
                          _buildInputPanel(),
                          const SizedBox(height: 14),
                          Expanded(child: _buildStatePanel()),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .86)),
          ),
          child: const Icon(
            CupertinoIcons.sparkles,
            color: Color(0xFFD7A86E),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '小精灵助手',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF25272F),
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _buildHeroOrb({required bool isCompact}) {
    final size = isCompact ? 116.0 : 148.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggleVoice,
          child: AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(size),
                      painter: VoiceOrbPainter(
                        progress: _orbController.value,
                        isRecording: _recording ||
                            _stage == _SpriteAssistantStage.interpreting ||
                            _stage == _SpriteAssistantStage.executing,
                      ),
                    ),
                    Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 38,
                      color: const Color(0xFF2E3038).withValues(alpha: .82),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        AnimatedBuilder(
          animation: _orbController,
          builder: (context, _) => VoiceDotsIndicator(
            progress: _orbController.value,
            isRecording: _recording ||
                _stage == _SpriteAssistantStage.interpreting ||
                _stage == _SpriteAssistantStage.executing,
          ),
        ),
      ],
    );
  }

  Widget _buildInputPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .92)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C6A5F).withValues(alpha: .08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusTitle,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: Color(0xFF25272F),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _statusSubtitle,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Color(0xFF74706A),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _understand(),
              decoration: InputDecoration(
                hintText: '说出或输入一个任务',
                filled: true,
                fillColor: const Color(0xFFF4F1EA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  tooltip: _recording ? '停止录音' : '语音输入',
                  onPressed: _toggleVoice,
                  icon: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _recording
                        ? const Color(0xFFD77F8B)
                        : const Color(0xFF7A9E9F),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _stage == _SpriteAssistantStage.interpreting
                        ? null
                        : _understand,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('理解任务'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: const Color(0xFF2E3038),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: '重新输入',
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatePanel() {
    final intent = _intent;
    if (_stage == _SpriteAssistantStage.interpreting ||
        _stage == _SpriteAssistantStage.executing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7A9E9F)),
      );
    }
    if (_stage == _SpriteAssistantStage.confirm && intent != null) {
      return _AssistantResultCard(
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF7A9E9F),
        title: intent.title,
        body: intent.confirmation,
        footnote: intent.usedLocalFallback ? _message : intent.reason,
        primaryLabel: '确认执行',
        onPrimary: _execute,
        secondaryLabel: '重新说',
        onSecondary: _rejectAndReset,
      );
    }
    if (_stage == _SpriteAssistantStage.asking) {
      return _AssistantResultCard(
        icon: Icons.edit_note_rounded,
        color: const Color(0xFF7A9E9F),
        title: '请补充信息',
        body: _message ?? '请告诉我具体要保存的内容。',
        footnote: '补充后我会再让你确认，不会直接保存。',
        primaryLabel: '继续确认',
        onPrimary: _understand,
        secondaryLabel: '取消',
        onSecondary: _rejectAndReset,
      );
    }
    if (_stage == _SpriteAssistantStage.completed) {
      final result = _result;
      return _AssistantResultCard(
        icon: Icons.check_circle_rounded,
        color: const Color(0xFFD7A86E),
        title: result?.title ?? '已经完成',
        body: result?.message ?? '这个任务已经处理好了',
        footnote: '小精灵只执行你确认过的 App 内操作。',
        primaryLabel: '继续说一个任务',
        onPrimary: _reset,
        secondaryLabel: result?.undoLabel,
        onSecondary:
            result?.onUndo == null || _undoing ? null : _undoLastResult,
      );
    }
    if (_stage == _SpriteAssistantStage.unsupported ||
        _stage == _SpriteAssistantStage.error) {
      return _AssistantResultCard(
        icon: Icons.info_rounded,
        color: const Color(0xFFD77F8B),
        title: _stage == _SpriteAssistantStage.error ? '没能完成' : '还不能做',
        body: _message ?? '这个任务暂时不在可执行范围内。',
        footnote: '可以试试：添加词轮椅、把请慢一点设为常用、候选改成两个。',
        primaryLabel: '重新说',
        onPrimary: _reset,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _AssistantHintChip(text: '把图标调大'),
          _AssistantHintChip(text: '候选改成两个'),
          _AssistantHintChip(text: '添加词轮椅'),
          _AssistantHintChip(text: '把请慢一点设为常用'),
          _AssistantHintChip(text: '打开听理解训练'),
          _AssistantHintChip(text: '改家人电话'),
          _AssistantHintChip(text: '打开个人物品'),
        ],
      ),
    );
  }
}

class _AssistantHintChip extends StatelessWidget {
  const _AssistantHintChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .85)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF5F625D),
          ),
        ),
      ),
    );
  }
}

class _AssistantResultCard extends StatelessWidget {
  const _AssistantResultCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.footnote,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? footnote;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .88),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .9)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .10),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF25272F),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.36,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3B3D43),
                ),
              ),
              if (footnote != null && footnote!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  footnote!,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF827D73),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onPrimary,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: const Color(0xFF2E3038),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(primaryLabel),
                    ),
                  ),
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpriteAssistantFamilyContactPage extends StatefulWidget {
  const SpriteAssistantFamilyContactPage({super.key});

  @override
  State<SpriteAssistantFamilyContactPage> createState() =>
      _SpriteAssistantFamilyContactPageState();
}

class _SpriteAssistantFamilyContactPageState
    extends State<SpriteAssistantFamilyContactPage> {
  static const String _contactStorageKey = 'star_family_contact_v1';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await SensitiveLocalStore.readString(
      _contactStorageKey,
      legacySharedPreferencesKey: _contactStorageKey,
    );
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _nameController.text = decoded['name']?.toString() ?? '';
          _phoneController.text = decoded['phone']?.toString() ?? '';
          _messageController.text = decoded['message']?.toString() ?? '请帮我联系家人';
        }
      } catch (_) {
        _messageController.text = '请帮我联系家人';
      }
    } else {
      _messageController.text = '请帮我联系家人';
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final message = _messageController.text.trim();
    if (name.isEmpty) {
      _showMessage('请先填写家属姓名');
      return;
    }
    setState(() => _saving = true);
    await SensitiveLocalStore.writeString(
      _contactStorageKey,
      jsonEncode({
        'name': name,
        'phone': phone,
        'message': message.isEmpty ? '请帮我联系家人' : message,
      }),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _showMessage('已保存家人联系信息');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E3038),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kYuqiaoSystemUiStyle,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F2EA),
        appBar: AppBar(
          title: const Text('配置家人'),
          backgroundColor: const Color(0xFFF7F2EA),
          surfaceTintColor: Colors.transparent,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  const Text(
                    '这份信息会用于星语里的“联系家人”，只保存在本机安全存储中。',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B675F),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildField(
                    controller: _nameController,
                    label: '家属姓名',
                    icon: Icons.person_rounded,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _phoneController,
                    label: '电话号码',
                    icon: Icons.call_rounded,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _messageController,
                    label: '常用求助句',
                    icon: Icons.record_voice_over_rounded,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text('保存'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF2E3038),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .88),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
