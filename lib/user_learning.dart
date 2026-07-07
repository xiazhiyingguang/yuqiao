import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'location_recommendation.dart';

class UserLearningEvent {
  const UserLearningEvent({
    required this.feature,
    required this.action,
    required this.text,
    required this.normalizedText,
    required this.intentTag,
    required this.objectTag,
    required this.placeType,
    required this.timeBucket,
    required this.slotName,
    required this.createdAt,
  });

  final String feature;
  final String action;
  final String text;
  final String normalizedText;
  final String intentTag;
  final String objectTag;
  final String placeType;
  final String timeBucket;
  final String slotName;
  final DateTime createdAt;

  bool get isPositive {
    return action == 'accepted' || action == 'spoken' || action == 'saved';
  }

  bool get isNegative {
    return action == 'rejected' ||
        action == 'skipped' ||
        action == 'refreshed' ||
        action == 'deleted';
  }

  Map<String, dynamic> toJson() => {
        'feature': feature,
        'action': action,
        'text': text,
        'normalizedText': normalizedText,
        'intentTag': intentTag,
        'objectTag': objectTag,
        'placeType': placeType,
        'timeBucket': timeBucket,
        'slotName': slotName,
        'createdAt': createdAt.toIso8601String(),
      };

  static UserLearningEvent? fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString().trim() ?? '';
    final normalized = json['normalizedText']?.toString().trim() ??
        LocationRecommendationController.normalizeText(text);
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final action = json['action']?.toString().trim() ?? '';
    if (text.isEmpty ||
        normalized.isEmpty ||
        createdAt == null ||
        action.isEmpty) {
      return null;
    }
    return UserLearningEvent(
      feature: json['feature']?.toString().trim() ?? 'unknown',
      action: action,
      text: text,
      normalizedText: normalized,
      intentTag: json['intentTag']?.toString().trim() ?? 'general',
      objectTag: json['objectTag']?.toString().trim() ?? '',
      placeType:
          json['placeType']?.toString().trim() ?? PlaceTypeCatalog.unknown,
      timeBucket: json['timeBucket']?.toString().trim() ?? '',
      slotName: json['slotName']?.toString().trim() ?? '',
      createdAt: createdAt,
    );
  }
}

class UserLearningSignal {
  const UserLearningSignal({
    required this.key,
    required this.label,
    required this.positiveCount,
    required this.negativeCount,
    required this.latestText,
    required this.lastSeenAt,
  });

  final String key;
  final String label;
  final int positiveCount;
  final int negativeCount;
  final String latestText;
  final DateTime lastSeenAt;

  double score(DateTime now) {
    final ageHours = now.difference(lastSeenAt).inHours;
    final recency = math.max(0.0, 120.0 - ageHours * 0.8);
    return positiveCount * 180.0 - negativeCount * 300.0 + recency;
  }
}

class UserSemanticPreference {
  const UserSemanticPreference({
    required this.signature,
    required this.label,
    required this.positiveCount,
    required this.negativeCount,
    required this.latestText,
    required this.lastSeenAt,
  });

  final String signature;
  final String label;
  final int positiveCount;
  final int negativeCount;
  final String latestText;
  final DateTime lastSeenAt;

  bool matches(String text) {
    final candidate = UserSemanticSignature.fromText(text);
    return UserSemanticSignature.overlapScore(signature, candidate) > 0;
  }

  double score(DateTime now) {
    final ageHours = now.difference(lastSeenAt).inHours;
    final recency = math.max(0.0, 96.0 - ageHours * 0.7);
    return positiveCount * 120.0 - negativeCount * 240.0 + recency;
  }
}

class UserExpressionStylePreference {
  const UserExpressionStylePreference({
    required this.shortScore,
    required this.mediumScore,
    required this.longScore,
    required this.sampleCount,
  });

  static const empty = UserExpressionStylePreference(
    shortScore: 0,
    mediumScore: 0,
    longScore: 0,
    sampleCount: 0,
  );

  final double shortScore;
  final double mediumScore;
  final double longScore;
  final int sampleCount;

  bool get hasSignal {
    return sampleCount >= 3 &&
        [shortScore, mediumScore, longScore].any((score) => score.abs() >= 2);
  }

  String get preferredLengthKey {
    final scores = {
      'short': shortScore,
      'medium': mediumScore,
      'long': longScore,
    };
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.value > 0 ? ranked.first.key : '';
  }

  String get preferredLengthLabel {
    return switch (preferredLengthKey) {
      'short' => 'shorter candidates',
      'medium' => 'balanced candidates',
      'long' => 'more detailed candidates',
      _ => '',
    };
  }

  String get summary {
    final label = preferredLengthLabel;
    if (!hasSignal || label.isEmpty) return '';
    return 'Expression style preference: prefers $label';
  }

  String get displaySummary {
    if (!hasSignal) return '';
    final label = switch (preferredLengthKey) {
      'short' => '更常选择短句候选',
      'medium' => '更常选择长度适中的候选',
      'long' => '更常选择更完整的候选',
      _ => '',
    };
    if (label.isEmpty) return '';
    return '表达风格：$label';
  }

  double scoreFor(String text) {
    if (!hasSignal) return 0;
    final score = switch (_lengthBucket(text)) {
      'short' => shortScore,
      'medium' => mediumScore,
      'long' => longScore,
      _ => 0.0,
    };
    return (score * 24.0).clamp(-120.0, 120.0).toDouble();
  }

  static String _lengthBucket(String text) {
    final length = LocationRecommendationController.normalizeText(text).length;
    if (length <= 8) return 'short';
    if (length <= 20) return 'medium';
    return 'long';
  }
}

class UserLearningPortrait {
  const UserLearningPortrait({
    required this.summary,
    required this.contextPattern,
    required this.stylePattern,
    required this.assistancePattern,
    required this.cautionPattern,
    required this.confidenceLabel,
    required this.evidenceCount,
  });

  static const empty = UserLearningPortrait(
    summary: '',
    contextPattern: '',
    stylePattern: '',
    assistancePattern: '',
    cautionPattern: '',
    confidenceLabel: '等待确认',
    evidenceCount: 0,
  );

  final String summary;
  final String contextPattern;
  final String stylePattern;
  final String assistancePattern;
  final String cautionPattern;
  final String confidenceLabel;
  final int evidenceCount;

  bool get hasSignal => summary.trim().isNotEmpty;

  List<String> promptHints({int limit = 5}) {
    if (!hasSignal) return const [];
    final hints = <String>[
      'User portrait summary: $summary',
      'User portrait confidence: $confidenceLabel based on $evidenceCount local feedback events',
      if (contextPattern.isNotEmpty) 'User context habit: $contextPattern',
      if (stylePattern.isNotEmpty) 'User expression style: $stylePattern',
      if (assistancePattern.isNotEmpty)
        'User assistance preference: $assistancePattern',
      if (cautionPattern.isNotEmpty) 'User avoidance pattern: $cautionPattern',
    ];
    return hints.take(limit).toList(growable: false);
  }

  List<String> displayLines({int limit = 5}) {
    if (!hasSignal) return const [];
    final lines = <String>[
      '画像摘要：$summary',
      '稳定度：$confidenceLabel（来自 $evidenceCount 次本机反馈）',
      if (contextPattern.isNotEmpty) '常见场景：$contextPattern',
      if (stylePattern.isNotEmpty) '表达风格：$stylePattern',
      if (assistancePattern.isNotEmpty) '帮助偏好：$assistancePattern',
      if (cautionPattern.isNotEmpty) '减少打扰：$cautionPattern',
    ];
    return lines.take(limit).toList(growable: false);
  }
}

class UserLearningProfileStats {
  const UserLearningProfileStats({
    required this.eventCount,
    required this.positiveCount,
    required this.negativeCount,
    required this.featureCounts,
    required this.actionCounts,
    required this.latestEventAt,
  });

  static const empty = UserLearningProfileStats(
    eventCount: 0,
    positiveCount: 0,
    negativeCount: 0,
    featureCounts: <String, int>{},
    actionCounts: <String, int>{},
    latestEventAt: null,
  );

  final int eventCount;
  final int positiveCount;
  final int negativeCount;
  final Map<String, int> featureCounts;
  final Map<String, int> actionCounts;
  final DateTime? latestEventAt;

  bool get hasSignal => eventCount > 0;

  String get maturityLabel {
    if (eventCount <= 0) return '等待确认';
    if (eventCount < 3) return '刚开始学习';
    if (eventCount < 8) return '画像正在形成';
    if (positiveCount >= 5 && featureCounts.length >= 2) return '偏好逐渐稳定';
    return '继续积累偏好';
  }

  String get compactStatusLabel {
    if (eventCount <= 0) return '等待确认';
    return '$maturityLabel · $eventCount 次';
  }

  List<String> displayLines({int limit = 4}) {
    if (!hasSignal) return const [];
    final features = featureCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final actions = actionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final items = <String>[
      '学习闭环：已记录 $eventCount 次反馈',
      '画像阶段：$maturityLabel',
      if (features.isNotEmpty)
        '覆盖入口：${features.take(4).map((entry) => _displayFeature(entry.key)).join('、')}',
      '确认/播报/保存：$positiveCount 次；跳过/刷新/删除：$negativeCount 次',
      if (actions.isNotEmpty)
        '高频反馈：${actions.take(3).map((entry) => '${_displayAction(entry.key)} ${entry.value} 次').join('、')}',
      if (latestEventAt != null) '最近学习：${_formatDateTime(latestEventAt!)}',
    ];
    return items.take(limit).toList(growable: false);
  }

  static UserLearningProfileStats fromEvents(List<UserLearningEvent> events) {
    if (events.isEmpty) return empty;
    final featureCounts = <String, int>{};
    final actionCounts = <String, int>{};
    var positiveCount = 0;
    var negativeCount = 0;
    DateTime? latestEventAt;
    for (final event in events) {
      featureCounts.update(
        event.feature,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      actionCounts.update(
        event.action,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (event.isPositive) positiveCount++;
      if (event.isNegative) negativeCount++;
      if (latestEventAt == null || event.createdAt.isAfter(latestEventAt)) {
        latestEventAt = event.createdAt;
      }
    }
    return UserLearningProfileStats(
      eventCount: events.length,
      positiveCount: positiveCount,
      negativeCount: negativeCount,
      featureCounts: Map.unmodifiable(featureCounts),
      actionCounts: Map.unmodifiable(actionCounts),
      latestEventAt: latestEventAt,
    );
  }

  static String _displayFeature(String feature) {
    return UserPreferenceProfile._displayLabelPart(feature);
  }

  static String _displayAction(String action) {
    return switch (action) {
      'accepted' => '确认',
      'spoken' => '播报',
      'saved' => '保存',
      'rejected' => '拒绝',
      'skipped' => '跳过',
      'refreshed' => '刷新',
      'deleted' => '删除',
      _ => action,
    };
  }

  static String _formatDateTime(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
  }
}

class UserPreferenceProfile {
  const UserPreferenceProfile({
    required this.topExpressions,
    required this.rejectedExpressions,
    required this.semanticPreferences,
    required this.rejectedSemanticPreferences,
    required this.expressionStyle,
    required this.intentPatterns,
    required this.placeIntentPatterns,
    required this.objectPatterns,
    required this.featurePreferences,
    required this.actionPlanPreferences,
    required this.expressionSlotNames,
    required this.portrait,
    required this.stats,
    required this.updatedAt,
  });

  static final empty = UserPreferenceProfile(
    topExpressions: const [],
    rejectedExpressions: const [],
    semanticPreferences: const [],
    rejectedSemanticPreferences: const [],
    expressionStyle: UserExpressionStylePreference.empty,
    intentPatterns: const [],
    placeIntentPatterns: const [],
    objectPatterns: const [],
    featurePreferences: const {},
    actionPlanPreferences: const {},
    expressionSlotNames: const {},
    portrait: UserLearningPortrait.empty,
    stats: UserLearningProfileStats.empty,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final List<UserLearningSignal> topExpressions;
  final List<UserLearningSignal> rejectedExpressions;
  final List<UserSemanticPreference> semanticPreferences;
  final List<UserSemanticPreference> rejectedSemanticPreferences;
  final UserExpressionStylePreference expressionStyle;
  final List<UserLearningSignal> intentPatterns;
  final List<UserLearningSignal> placeIntentPatterns;
  final List<UserLearningSignal> objectPatterns;
  final Map<String, double> featurePreferences;
  final Map<String, double> actionPlanPreferences;
  final Map<String, List<String>> expressionSlotNames;
  final UserLearningPortrait portrait;
  final UserLearningProfileStats stats;
  final DateTime updatedAt;

  bool get hasSignal {
    return topExpressions.isNotEmpty ||
        rejectedExpressions.isNotEmpty ||
        semanticPreferences.isNotEmpty ||
        rejectedSemanticPreferences.isNotEmpty ||
        expressionStyle.hasSignal ||
        intentPatterns.isNotEmpty ||
        placeIntentPatterns.isNotEmpty ||
        objectPatterns.isNotEmpty ||
        featurePreferences.isNotEmpty ||
        actionPlanPreferences.isNotEmpty ||
        portrait.hasSignal ||
        stats.hasSignal;
  }

  double expressionScore(String text, {String? slotName}) {
    final normalized = LocationRecommendationController.normalizeText(text);
    final matchesCurrentSlot = _matchesExpressionSlot(
      normalized,
      slotName,
    );
    var score = 0.0;
    if (matchesCurrentSlot) {
      for (final signal in topExpressions) {
        if (signal.key == normalized) {
          score += signal.positiveCount * 150.0;
        }
      }
      for (final signal in rejectedExpressions) {
        if (signal.key == normalized) {
          score -= signal.negativeCount * 360.0;
        }
      }
    }
    final semanticSignature = UserSemanticSignature.fromText(text);
    for (final signal in semanticPreferences) {
      final overlap = UserSemanticSignature.overlapScore(
        signal.signature,
        semanticSignature,
      );
      if (overlap > 0) {
        score += signal.positiveCount * 80.0 * overlap;
      }
    }
    for (final signal in rejectedSemanticPreferences) {
      final overlap = UserSemanticSignature.overlapScore(
        signal.signature,
        semanticSignature,
      );
      if (overlap > 0) {
        score -= signal.negativeCount * 160.0 * overlap;
      }
    }
    score += expressionStyle.scoreFor(text);
    return score;
  }

  bool _matchesExpressionSlot(String normalizedText, String? slotName) {
    final cleanSlot = slotName?.trim() ?? '';
    if (cleanSlot.isEmpty) return true;
    final slots = expressionSlotNames[normalizedText];
    if (slots == null || slots.isEmpty) return true;
    return slots.contains(cleanSlot);
  }

  bool hasExpressionSlotMismatch(String text, String slotName) {
    final normalized = LocationRecommendationController.normalizeText(text);
    final cleanSlot = slotName.trim();
    if (normalized.isEmpty || cleanSlot.isEmpty) return false;
    final slots = expressionSlotNames[normalized];
    return slots != null && slots.isNotEmpty && !slots.contains(cleanSlot);
  }

  double contextualScoreFor(
    String text, {
    required String feature,
    required String placeType,
    required String slotName,
  }) {
    if (!hasSignal) return 0;
    final signature = UserSemanticSignature.fromText(text);
    if (signature.isEmpty) return 0;
    var score = 0.0;
    for (final signal in intentPatterns) {
      final parts = signal.key.split('|');
      if (parts.length < 3) continue;
      final matchesFeature = parts[0] == feature;
      final matchesSlot = parts[1].isEmpty || parts[1] == slotName;
      if (!matchesFeature || !matchesSlot) continue;
      if (_intentMatchesSignature(parts[2], signature)) {
        score += math.min(signal.positiveCount, 5) * 28.0;
      }
    }
    for (final signal in placeIntentPatterns) {
      final parts = signal.key.split('|');
      if (parts.length < 4) continue;
      final matchesPlace =
          placeType != PlaceTypeCatalog.unknown && parts[0] == placeType;
      final matchesFeature = parts[1] == feature;
      if (!matchesPlace || !matchesFeature) continue;
      if (_intentMatchesSignature(parts[3], signature)) {
        score += math.min(signal.positiveCount, 5) * 44.0;
      }
    }
    return score.clamp(0.0, 360.0).toDouble();
  }

  List<String> promptHints({int limit = 10}) {
    return summaryLines(limit: limit);
  }

  List<String> summaryLines({int limit = 10}) {
    final actionItems = _rankedActionPlanPreferences;
    final hints = <String>[
      ...portrait.promptHints(limit: 4),
      ...topExpressions.take(4).map(
            (signal) => 'Long-term preferred expression: ${signal.latestText}',
          ),
      ...actionItems.take(3).where((entry) => entry.value > 0).map(
            (entry) =>
                'Long-term action preference: prefers ${entry.key} assistance (${entry.value.toStringAsFixed(1)} score)',
          ),
      ...intentPatterns.take(3).map(
            (signal) =>
                'Frequent intent pattern: ${signal.label} (${signal.positiveCount} positive)',
          ),
      ...semanticPreferences.take(3).map(
            (signal) =>
                'Semantic preference: ${signal.label} (${signal.positiveCount} positive)',
          ),
      if (expressionStyle.summary.isNotEmpty) expressionStyle.summary,
      ...placeIntentPatterns.take(3).map(
            (signal) =>
                'Place-specific pattern: ${signal.label} (${signal.positiveCount} positive)',
          ),
      ...objectPatterns.take(3).map(
            (signal) =>
                'Object-related pattern: ${signal.label} (${signal.positiveCount} positive)',
          ),
      ...rejectedExpressions.take(3).map(
            (signal) =>
                'Often rejected expression, avoid unless clearly needed: ${signal.latestText}',
          ),
      ...rejectedSemanticPreferences.take(2).map(
            (signal) =>
                'Often rejected semantic direction, avoid unless clearly needed: ${signal.label}',
          ),
    ];
    return hints.take(limit).toList(growable: false);
  }

  List<String> displaySummaryLines({int limit = 10}) {
    final featureItems = featurePreferences.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final actionItems = _rankedActionPlanPreferences;
    final items = <String>[
      ...portrait.displayLines(limit: 3),
      ...topExpressions.take(3).map(
            (signal) =>
                '常用表达：${signal.latestText}（已确认/播报 ${signal.positiveCount} 次）',
          ),
      ...actionItems.take(2).where((entry) => entry.value > 0).map(
            (entry) =>
                '帮助方式：更常接受${_displayLabelPart(entry.key)}（偏好强度 ${entry.value.toStringAsFixed(1)}）',
          ),
      ...intentPatterns.take(3).map(
            (signal) =>
                '常用意图：${_displayPatternLabel(signal.label)}（${signal.positiveCount} 次）',
          ),
      ...semanticPreferences.take(3).map(
            (signal) =>
                '常见语义：${UserSemanticSignature.displayLabelOf(signal.signature)}（${signal.positiveCount} 次）',
          ),
      if (expressionStyle.displaySummary.isNotEmpty)
        expressionStyle.displaySummary,
      ...placeIntentPatterns.take(3).map(
            (signal) =>
                '场景习惯：${_displayPatternLabel(signal.label)}（${signal.positiveCount} 次）',
          ),
      ...objectPatterns.take(3).map(
            (signal) =>
                '物品相关：${_displayPatternLabel(signal.label)}（${signal.positiveCount} 次）',
          ),
      ...featureItems.take(2).where((entry) => entry.value > 0).map(
            (entry) =>
                '更常使用：${_displayLabelPart(entry.key)}入口（偏好强度 ${entry.value.toStringAsFixed(1)}）',
          ),
      ...rejectedExpressions.take(3).map(
            (signal) => '较少选择：${signal.latestText}',
          ),
      ...rejectedSemanticPreferences.take(2).map(
            (signal) =>
                '较少选择的语义：${UserSemanticSignature.displayLabelOf(signal.signature)}',
          ),
    ];
    return _uniqueDisplayLines(items).take(limit).toList(growable: false);
  }

  List<MapEntry<String, double>> get _rankedActionPlanPreferences {
    return actionPlanPreferences.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  static List<String> _uniqueDisplayLines(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      result.add(clean);
    }
    return result;
  }

  static String _displayPatternLabel(String label) {
    return label
        .split('/')
        .map((part) => _displayLabelPart(part.trim()))
        .where((part) => part.isNotEmpty)
        .join(' / ');
  }

  static String _displayLabelPart(String part) {
    if (part.startsWith('prefers ') && part.endsWith(' assistance')) {
      final action =
          part.substring('prefers '.length, part.length - ' assistance'.length);
      return '偏好${_displayLabelPart(action)}帮助';
    }
    return _displayLabels[part] ?? part;
  }

  static bool _intentMatchesSignature(String intentTag, String signature) {
    final groups =
        signature.split('+').where((part) => part.trim().isNotEmpty).toSet();
    if (groups.isEmpty) return false;
    final expected = _intentSemanticGroups[intentTag] ?? const <String>[];
    return expected.any(groups.contains);
  }

  static const Map<String, String> _displayLabels = {
    'camera': '拍照找词',
    'conversation': '对话辅助',
    'stuck': '卡住求助',
    'vocabulary': '词库',
    'personalObject': '个人物品',
    'training': '训练',
    'word': '词语',
    'phrase': '短语',
    'sentence': '句子',
    'ask_time': '询问时间',
    'find_or_get': '寻找或拿取',
    'discomfort': '表达不适',
    'understand': '需要解释',
    'clarify': '澄清确认',
    'request_help': '请求帮助',
    'say_sentence': '表达句子',
    'observe': '继续观察',
    'recommendWord': '推荐关键词',
    'recommendPhrase': '推荐短语',
    'recommendSentence': '整理表达',
    'explain': '帮我理解',
    'home': '家',
    'hospital': '医院',
    'supermarket': '超市',
    'school': '学校',
    'park': '公园',
    'pharmacy': '药店',
    'rehabilitationCenter': '康复中心',
    'restaurant': '餐厅',
    'transport': '交通',
    'company': '公司',
    'residential': '小区',
    'convenienceStore': '便利店',
    'shoppingMall': '商场',
    'lifeService': '生活服务',
    'unknown': '其他',
  };

  static const Map<String, List<String>> _intentSemanticGroups = {
    'ask_time': ['time'],
    'find_or_get': ['object', 'location'],
    'discomfort': ['pain'],
    'understand': ['repeat'],
    'clarify': ['repeat'],
    'request_help': ['help', 'doctor', 'family'],
    'say_sentence': [
      'doctor',
      'time',
      'pain',
      'help',
      'family',
      'water',
      'toilet',
      'medicine',
      'object',
      'location',
      'repeat',
    ],
  };
}

class UserSemanticSignature {
  static String fromText(String text) {
    final normalized = LocationRecommendationController.normalizeText(text);
    if (normalized.isEmpty) return '';
    final groups = <String>[
      for (final entry in _groupKeywords.entries)
        if (entry.value.any((keyword) => normalized.contains(keyword)))
          entry.key,
    ];
    if (groups.isNotEmpty) return groups.join('+');

    if (normalized.length <= 4) return normalized;
    return normalized.substring(0, math.min(normalized.length, 8));
  }

  static String labelOf(String signature) {
    if (signature.isEmpty) return 'general';
    return signature
        .split('+')
        .map((part) => _groupLabels[part] ?? part)
        .join('/');
  }

  static String displayLabelOf(String signature) {
    if (signature.isEmpty) return '一般表达';
    return signature
        .split('+')
        .map((part) => _displayGroupLabels[part] ?? part)
        .join(' / ');
  }

  static bool isKnownGroupSignature(String signature) {
    if (signature.isEmpty) return false;
    return signature
        .split('+')
        .where((part) => part.isNotEmpty)
        .every(_groupLabels.containsKey);
  }

  static double overlapScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final left = a.split('+').where((part) => part.isNotEmpty).toSet();
    final right = b.split('+').where((part) => part.isNotEmpty).toSet();
    if (left.isEmpty || right.isEmpty) return 0;
    final shared = left.intersection(right).length;
    if (shared == 0) return 0;
    return shared / math.min(left.length, right.length);
  }

  static const Map<String, String> _groupLabels = {
    'doctor': 'doctor or care team',
    'time': 'time or schedule',
    'pain': 'discomfort or pain',
    'help': 'asking for help',
    'family': 'family contact',
    'water': 'drink or water',
    'toilet': 'toilet need',
    'medicine': 'medicine',
    'object': 'object request',
    'location': 'location or direction',
    'repeat': 'repeat or explain',
  };

  static const Map<String, String> _displayGroupLabels = {
    'doctor': '医生或照护团队',
    'time': '时间或日程',
    'pain': '疼痛或不适',
    'help': '请求帮助',
    'family': '家人联系',
    'water': '喝水需求',
    'toilet': '如厕需求',
    'medicine': '用药相关',
    'object': '拿取或操作物品',
    'location': '地点或方向',
    'repeat': '重复或解释',
  };

  static const Map<String, List<String>> _groupKeywords = {
    'doctor': [
      'doctor',
      'nurse',
      'caregiver',
      'physician',
      'yisheng',
      'hushi',
      '医生',
      '护士',
      '护工',
    ],
    'time': [
      'time',
      'clock',
      'schedule',
      'when',
      'today',
      'tomorrow',
      '时间',
      '几点',
      '多久',
      '今天',
      '明天',
    ],
    'pain': [
      'pain',
      'hurt',
      'ache',
      'uncomfortable',
      'tired',
      '疼',
      '痛',
      '不舒服',
      '难受',
      '累',
    ],
    'help': [
      'help',
      'please',
      'assist',
      'need',
      '帮',
      '请',
      '需要',
      '能不能',
    ],
    'family': [
      'family',
      'mom',
      'dad',
      'wife',
      'husband',
      'son',
      'daughter',
      '家人',
      '妈妈',
      '爸爸',
      '儿子',
      '女儿',
      '老伴',
    ],
    'water': [
      'water',
      'drink',
      'cup',
      '喝水',
      '水',
      '杯子',
      '口渴',
    ],
    'toilet': [
      'toilet',
      'bathroom',
      'restroom',
      '厕所',
      '卫生间',
      '上厕所',
    ],
    'medicine': [
      'medicine',
      'pill',
      'drug',
      '药',
      '吃药',
      '药片',
    ],
    'object': [
      'take',
      'bring',
      'get',
      'open',
      '拿',
      '取',
      '打开',
      '递给',
    ],
    'location': [
      'where',
      'go',
      'find',
      '哪',
      '哪里',
      '去',
      '找',
      '带我',
    ],
    'repeat': [
      'repeat',
      'again',
      'explain',
      'slow',
      '再说',
      '解释',
      '慢一点',
      '没听懂',
    ],
  };
}

class UserPreferenceProfileBuilder {
  const UserPreferenceProfileBuilder();

  UserPreferenceProfile build(List<UserLearningEvent> events) {
    if (events.isEmpty) return UserPreferenceProfile.empty;
    final now = DateTime.now();
    final stats = UserLearningProfileStats.fromEvents(events);
    final expressionStats = <String, _MutableSignal>{};
    final semanticStats = <String, _MutableSemanticSignal>{};
    final intentStats = <String, _MutableSignal>{};
    final placeIntentStats = <String, _MutableSignal>{};
    final objectStats = <String, _MutableSignal>{};
    final featureScores = <String, double>{};
    final actionPlanScores = <String, double>{};
    final expressionSlots = <String, Set<String>>{};
    final expressionStyleScores = <String, double>{
      'short': 0,
      'medium': 0,
      'long': 0,
    };
    var expressionStyleSampleCount = 0;

    for (final event in events) {
      if (!_isInternalActionEvent(event)) {
        _updateExpression(expressionStats, event);
        _updateExpressionSlotNames(expressionSlots, event);
        _updateSemantic(semanticStats, event);
        expressionStyleSampleCount += _updateExpressionStyle(
          expressionStyleScores,
          event,
        );
      } else {
        _updateActionPlanPreference(actionPlanScores, event);
      }
      _updatePattern(
        intentStats,
        key: '${event.feature}|${event.slotName}|${event.intentTag}',
        label: _compactLabel([
          event.feature,
          event.slotName,
          event.intentTag,
        ]),
        event: event,
      );
      if (event.placeType.isNotEmpty &&
          event.placeType != PlaceTypeCatalog.unknown) {
        _updatePattern(
          placeIntentStats,
          key:
              '${event.placeType}|${event.feature}|${event.slotName}|${event.intentTag}',
          label: _compactLabel([
            event.placeType,
            event.feature,
            event.intentTag,
          ]),
          event: event,
        );
      }
      if (event.objectTag.isNotEmpty) {
        _updatePattern(
          objectStats,
          key: '${event.objectTag}|${event.intentTag}|${event.slotName}',
          label: _compactLabel([
            event.objectTag,
            event.intentTag,
            event.slotName,
          ]),
          event: event,
        );
      }
      featureScores.update(
        event.feature,
        (value) => value + _eventPolarity(event),
        ifAbsent: () => _eventPolarity(event),
      );
    }

    List<UserLearningSignal> rankedPositive(Map<String, _MutableSignal> map) {
      final signals = map.values
          .map((item) => item.toSignal())
          .where((item) => item.positiveCount > 0)
          .toList()
        ..sort((a, b) => b.score(now).compareTo(a.score(now)));
      return signals.take(12).toList(growable: false);
    }

    final rejected = expressionStats.values
        .map((item) => item.toSignal())
        .where((item) => item.negativeCount > item.positiveCount)
        .toList()
      ..sort((a, b) => b.negativeCount.compareTo(a.negativeCount));
    List<UserSemanticPreference> rankedSemantic(
      Iterable<_MutableSemanticSignal> values,
    ) {
      final signals = values
          .map((item) => item.toSignal())
          .where((item) => item.positiveCount > 0)
          .toList()
        ..sort((a, b) => b.score(now).compareTo(a.score(now)));
      return signals.take(10).toList(growable: false);
    }

    final rejectedSemantic = semanticStats.values
        .map((item) => item.toSignal())
        .where((item) => item.negativeCount > item.positiveCount)
        .toList()
      ..sort((a, b) => b.negativeCount.compareTo(a.negativeCount));

    final activeFeaturePreferences = Map<String, double>.from(featureScores)
      ..removeWhere((key, value) => value == 0);
    final activeActionPlanPreferences =
        Map<String, double>.from(actionPlanScores)
          ..removeWhere((key, value) => value == 0);
    final activeExpressionSlotNames = <String, List<String>>{
      for (final entry in expressionSlots.entries)
        entry.key: List<String>.unmodifiable(entry.value.toList()..sort()),
    };
    final topExpressions = rankedPositive(expressionStats).take(8).toList();
    final topSemanticPreferences = rankedSemantic(semanticStats.values);
    final topIntentPatterns = rankedPositive(intentStats).take(8).toList();
    final topPlaceIntentPatterns =
        rankedPositive(placeIntentStats).take(8).toList();
    final topObjectPatterns = rankedPositive(objectStats).take(8).toList();
    final expressionStyle = UserExpressionStylePreference(
      shortScore: expressionStyleScores['short'] ?? 0,
      mediumScore: expressionStyleScores['medium'] ?? 0,
      longScore: expressionStyleScores['long'] ?? 0,
      sampleCount: expressionStyleSampleCount,
    );
    final portrait = _buildPortrait(
      stats: stats,
      topExpressions: topExpressions,
      semanticPreferences: topSemanticPreferences,
      expressionStyle: expressionStyle,
      intentPatterns: topIntentPatterns,
      placeIntentPatterns: topPlaceIntentPatterns,
      objectPatterns: topObjectPatterns,
      rejectedExpressions: rejected.take(8).toList(growable: false),
      actionPlanPreferences: activeActionPlanPreferences,
    );
    return UserPreferenceProfile(
      topExpressions: topExpressions,
      rejectedExpressions: rejected.take(8).toList(growable: false),
      semanticPreferences: topSemanticPreferences,
      rejectedSemanticPreferences:
          rejectedSemantic.take(8).toList(growable: false),
      expressionStyle: expressionStyle,
      intentPatterns: topIntentPatterns,
      placeIntentPatterns: topPlaceIntentPatterns,
      objectPatterns: topObjectPatterns,
      featurePreferences: Map.unmodifiable(activeFeaturePreferences),
      actionPlanPreferences: Map.unmodifiable(activeActionPlanPreferences),
      expressionSlotNames: Map.unmodifiable(activeExpressionSlotNames),
      portrait: portrait,
      stats: stats,
      updatedAt: stats.latestEventAt ?? now,
    );
  }

  UserLearningPortrait _buildPortrait({
    required UserLearningProfileStats stats,
    required List<UserLearningSignal> topExpressions,
    required List<UserSemanticPreference> semanticPreferences,
    required UserExpressionStylePreference expressionStyle,
    required List<UserLearningSignal> intentPatterns,
    required List<UserLearningSignal> placeIntentPatterns,
    required List<UserLearningSignal> objectPatterns,
    required List<UserLearningSignal> rejectedExpressions,
    required Map<String, double> actionPlanPreferences,
  }) {
    if (!stats.hasSignal) return UserLearningPortrait.empty;
    final strongestPlaceIntent =
        placeIntentPatterns.isEmpty ? null : placeIntentPatterns.first;
    final strongestIntent =
        intentPatterns.isEmpty ? null : intentPatterns.first;
    final strongestSemantic =
        semanticPreferences.isEmpty ? null : semanticPreferences.first;
    final strongestObject =
        objectPatterns.isEmpty ? null : objectPatterns.first;
    final strongestExpression =
        topExpressions.isEmpty ? null : topExpressions.first;
    final strongestAction = actionPlanPreferences.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final avoidedExpression =
        rejectedExpressions.isEmpty ? null : rejectedExpressions.first;

    final contextPattern = strongestPlaceIntent != null
        ? UserPreferenceProfile._displayPatternLabel(strongestPlaceIntent.label)
        : strongestIntent != null
            ? UserPreferenceProfile._displayPatternLabel(strongestIntent.label)
            : '';
    final semanticPattern = strongestSemantic == null
        ? ''
        : UserSemanticSignature.displayLabelOf(strongestSemantic.signature);
    final stylePattern = expressionStyle.displaySummary;
    final assistancePattern = strongestAction.isEmpty
        ? ''
        : '更常接受${UserPreferenceProfile._displayLabelPart(strongestAction.first.key)}';
    final objectPattern = strongestObject == null
        ? ''
        : UserPreferenceProfile._displayPatternLabel(strongestObject.label);
    final cautionPattern = avoidedExpression == null
        ? ''
        : '少推荐“${avoidedExpression.latestText}”一类候选';
    final confidenceLabel = _portraitConfidence(stats);

    final summaryParts = <String>[
      if (contextPattern.isNotEmpty) contextPattern,
      if (semanticPattern.isNotEmpty) semanticPattern,
      if (stylePattern.isNotEmpty) stylePattern,
      if (assistancePattern.isNotEmpty) assistancePattern,
      if (objectPattern.isNotEmpty) objectPattern,
      if (contextPattern.isEmpty &&
          semanticPattern.isEmpty &&
          strongestExpression != null)
        '常用“${strongestExpression.latestText}”',
    ];
    if (summaryParts.isEmpty) return UserLearningPortrait.empty;
    return UserLearningPortrait(
      summary: summaryParts.take(3).join('；'),
      contextPattern: contextPattern,
      stylePattern: stylePattern,
      assistancePattern: assistancePattern,
      cautionPattern: cautionPattern,
      confidenceLabel: confidenceLabel,
      evidenceCount: stats.eventCount,
    );
  }

  void _updateExpression(
    Map<String, _MutableSignal> stats,
    UserLearningEvent event,
  ) {
    final key = event.normalizedText;
    final label = event.text;
    _updatePattern(stats, key: key, label: label, event: event);
  }

  void _updateExpressionSlotNames(
    Map<String, Set<String>> expressionSlots,
    UserLearningEvent event,
  ) {
    final key = event.normalizedText.trim();
    final slot = event.slotName.trim();
    if (key.isEmpty || slot.isEmpty) return;
    expressionSlots.putIfAbsent(key, () => <String>{}).add(slot);
  }

  void _updateSemantic(
    Map<String, _MutableSemanticSignal> stats,
    UserLearningEvent event,
  ) {
    final signature = UserSemanticSignature.fromText(event.text);
    if (!UserSemanticSignature.isKnownGroupSignature(signature)) return;
    final signal = stats.putIfAbsent(
      signature,
      () => _MutableSemanticSignal(
        signature: signature,
        label: UserSemanticSignature.labelOf(signature),
      ),
    );
    signal.latestText = event.text;
    signal.lastSeenAt = event.createdAt;
    if (event.isPositive) {
      signal.positiveCount++;
    } else if (event.isNegative) {
      signal.negativeCount++;
    }
  }

  int _updateExpressionStyle(
    Map<String, double> styleScores,
    UserLearningEvent event,
  ) {
    if (event.normalizedText.isEmpty || event.text.startsWith('action:')) {
      return 0;
    }
    final bucket = UserExpressionStylePreference._lengthBucket(event.text);
    final delta = _eventPolarity(event);
    if (delta == 0) return 0;
    styleScores.update(bucket, (value) => value + delta, ifAbsent: () => delta);
    return 1;
  }

  void _updateActionPlanPreference(
    Map<String, double> actionPlanScores,
    UserLearningEvent event,
  ) {
    final intent = event.intentTag.trim();
    if (!intent.startsWith('action_plan_')) return;
    final actionType = intent.substring('action_plan_'.length);
    if (actionType.isEmpty) return;
    final delta = _eventPolarity(event);
    if (delta == 0) return;
    actionPlanScores.update(
      actionType,
      (value) => value + delta,
      ifAbsent: () => delta,
    );
  }

  void _updatePattern(
    Map<String, _MutableSignal> stats, {
    required String key,
    required String label,
    required UserLearningEvent event,
  }) {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) return;
    final signal = stats.putIfAbsent(
      cleanKey,
      () => _MutableSignal(key: cleanKey, label: label),
    );
    signal.latestText = event.text;
    signal.lastSeenAt = event.createdAt;
    if (event.isPositive) {
      signal.positiveCount++;
    } else if (event.isNegative) {
      signal.negativeCount++;
    }
  }

  double _eventPolarity(UserLearningEvent event) {
    if (event.isPositive) return 1;
    if (event.isNegative) return -1.2;
    return 0;
  }

  String _portraitConfidence(UserLearningProfileStats stats) {
    if (stats.eventCount < 3) return '刚开始';
    if (stats.eventCount < 8) return '形成中';
    if (stats.positiveCount >= 5 && stats.featureCounts.length >= 2) {
      return '较稳定';
    }
    return '继续观察';
  }

  static String _compactLabel(Iterable<String> parts) {
    return parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map(_displayLabelPart)
        .join('/');
  }

  static String _displayLabelPart(String part) {
    if (part.startsWith('action_plan_')) {
      final action = part.substring('action_plan_'.length);
      return 'prefers $action assistance';
    }
    return part;
  }

  static bool _isInternalActionEvent(UserLearningEvent event) {
    return event.text.startsWith('action:') ||
        event.intentTag.startsWith('action_plan_');
  }
}

class UserLearningStore {
  static const _storageKey = 'user_learning_events_v1';
  static const _maxEvents = 360;

  Future<void> record(UserLearningEvent event) async {
    final events = await loadEvents();
    events.add(event);
    if (events.length > _maxEvents) {
      events.removeRange(0, events.length - _maxEvents);
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }

  Future<List<UserLearningEvent>> loadEvents() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <UserLearningEvent>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <UserLearningEvent>[];
      return decoded
          .whereType<Map>()
          .map((item) => UserLearningEvent.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .whereType<UserLearningEvent>()
          .toList();
    } catch (_) {
      return <UserLearningEvent>[];
    }
  }

  Future<UserPreferenceProfile> loadProfile() async {
    return const UserPreferenceProfileBuilder().build(await loadEvents());
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}

class _MutableSignal {
  _MutableSignal({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;
  int positiveCount = 0;
  int negativeCount = 0;
  String latestText = '';
  DateTime lastSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  UserLearningSignal toSignal() {
    return UserLearningSignal(
      key: key,
      label: label,
      positiveCount: positiveCount,
      negativeCount: negativeCount,
      latestText: latestText.isEmpty ? label : latestText,
      lastSeenAt: lastSeenAt,
    );
  }
}

class _MutableSemanticSignal {
  _MutableSemanticSignal({
    required this.signature,
    required this.label,
  });

  final String signature;
  final String label;
  int positiveCount = 0;
  int negativeCount = 0;
  String latestText = '';
  DateTime lastSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  UserSemanticPreference toSignal() {
    return UserSemanticPreference(
      signature: signature,
      label: label,
      positiveCount: positiveCount,
      negativeCount: negativeCount,
      latestText: latestText,
      lastSeenAt: lastSeenAt,
    );
  }
}
