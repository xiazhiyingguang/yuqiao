import 'companion_agent.dart';
import 'conversation_terms.dart';
import 'expression_habits.dart';
import 'location_recommendation.dart';
import 'personal_objects.dart';
import 'user_learning.dart';

enum MemoryInsightNodeType {
  self,
  expression,
  place,
  object,
  conversation,
  agent,
}

class MemoryInsightNode {
  const MemoryInsightNode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.detailTitle,
    required this.detailLines,
    this.speakText,
  });

  final String id;
  final String title;
  final String subtitle;
  final MemoryInsightNodeType type;
  final String detailTitle;
  final List<String> detailLines;
  final String? speakText;
}

class MemoryEvidenceCard {
  const MemoryEvidenceCard({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.emptyText,
    required this.type,
  });

  final String title;
  final String subtitle;
  final List<String> items;
  final String emptyText;
  final MemoryInsightNodeType type;
}

class MemoryInsightSnapshot {
  const MemoryInsightSnapshot({
    required this.learnedExpressionCount,
    required this.nodes,
    required this.evidenceCards,
    required this.personalizedLearningEnabled,
  });

  final int learnedExpressionCount;
  final List<MemoryInsightNode> nodes;
  final List<MemoryEvidenceCard> evidenceCards;
  final bool personalizedLearningEnabled;

  bool get hasAnyMemory {
    return learnedExpressionCount > 0 ||
        nodes.any((node) => node.type != MemoryInsightNodeType.self) ||
        evidenceCards.any((card) => card.items.isNotEmpty);
  }
}

class MemoryInsightService {
  const MemoryInsightService();

  MemoryInsightSnapshot build({
    required List<String> recentExpressions,
    required List<String> favoriteExpressions,
    required List<ExpressionHabit> expressionHabits,
    required List<PersonalObject> personalObjects,
    required LocationRecommendationController locationController,
    required List<ConversationTerm> conversationTerms,
    List<CompanionLearnedExpression> companionLearnedExpressions = const [],
    CompanionActionBias companionActionBias =
        const CompanionActionBias(accepted: {}, rejected: {}),
    UserPreferenceProfile? userPreferenceProfile,
    required bool personalizedLearningEnabled,
  }) {
    final effectiveUserPreferenceProfile =
        userPreferenceProfile ?? UserPreferenceProfile.empty;
    final learnedExpressions = _uniqueTexts([
      ...expressionHabits.map((habit) => habit.text),
      ...favoriteExpressions,
      ...recentExpressions,
      ...locationController.wordUsages.map((usage) => usage.wordText),
      ...personalObjects.expand((object) => object.commonExpressions),
      ...companionLearnedExpressions.map((item) => item.text),
    ]);

    final topHabits = ExpressionHabitStore.rank(
      expressionHabits,
      limit: 6,
    );
    final topExpressionItems = _uniqueDisplayItems([
      ...companionLearnedExpressions.take(4).map((item) => item.displayLine),
      ...topHabits.map((habit) => '${habit.text} · ${habit.count}次'),
      ...recentExpressions.take(4),
      ...favoriteExpressions.take(4),
    ]).take(4).toList(growable: false);
    final companionItems = companionLearnedExpressions
        .take(5)
        .map((item) => item.displayLine)
        .toList(growable: false);
    final actionPreferenceItems = _actionPreferenceItems(companionActionBias);
    final profileItems = _profileItems(effectiveUserPreferenceProfile);
    final learningLoopItems =
        effectiveUserPreferenceProfile.stats.displayLines(limit: 5);

    final topPlace = _topPlace(locationController);
    final topPlaceWords = topPlace == null
        ? const <PlaceWordUsage>[]
        : locationController.wordsForPlace(topPlace.id).take(5).toList();
    final topPlaceItems = topPlaceWords
        .map((usage) => '${usage.wordText} · ${usage.count}次')
        .toList(growable: false);

    final topObject = _topObject(personalObjects);
    final topObjectItems = topObject == null
        ? const <String>[]
        : _uniqueTexts([
            ...topObject.commonExpressions,
            topObject.displayName,
          ]).take(4).toList(growable: false);

    final topTerms = conversationTerms.take(6).toList(growable: false);
    final topTermItems = topTerms
        .map((term) =>
            '${term.text} · ${conversationTermTypeLabel(term.type)} · ${term.count}次')
        .toList(growable: false);

    final nodes = <MemoryInsightNode>[
      MemoryInsightNode(
        id: 'self',
        title: '你',
        subtitle: learnedExpressions.isEmpty
            ? '正在形成记忆'
            : '已学会 ${learnedExpressions.length} 个表达',
        type: MemoryInsightNodeType.self,
        detailTitle: '语桥记忆',
        detailLines: [
          if (personalizedLearningEnabled)
            '个性化学习已开启，语桥会在本机记录你常用的表达。'
          else
            '个性化学习已关闭，当前只展示本机已有记忆。',
          ...learningLoopItems.take(2),
          '不会上传精确地点、个人物品或对话特殊词。',
        ],
      ),
      if (topHabits.isNotEmpty)
        MemoryInsightNode(
          id: 'expression',
          title: companionLearnedExpressions.isNotEmpty
              ? companionLearnedExpressions.first.text
              : topHabits.first.text,
          subtitle: '常用表达',
          type: MemoryInsightNodeType.expression,
          detailTitle: '常用表达',
          detailLines: _uniqueDisplayItems([
            ...companionItems,
            ...topHabits
                .take(4)
                .map((habit) => '${habit.text} · 使用 ${habit.count} 次'),
          ]).take(5).toList(growable: false),
          speakText: companionLearnedExpressions.isNotEmpty
              ? companionLearnedExpressions.first.text
              : topHabits.first.text,
        ),
      if (topPlace != null)
        MemoryInsightNode(
          id: 'place',
          title: topPlace.name,
          subtitle: topPlace.typeLabel,
          type: MemoryInsightNodeType.place,
          detailTitle: '地点习惯',
          detailLines: topPlaceWords.isEmpty
              ? ['这个地点还没有记录到常用表达。']
              : topPlaceWords
                  .take(4)
                  .map((usage) => '${usage.wordText} · 使用 ${usage.count} 次')
                  .toList(growable: false),
        ),
      if (topObject != null)
        MemoryInsightNode(
          id: 'object',
          title: topObject.displayName,
          subtitle: topObject.category.isEmpty ? '个人物品' : topObject.category,
          type: MemoryInsightNodeType.object,
          detailTitle: '个人物品',
          detailLines:
              topObjectItems.isEmpty ? ['还没有为这个物品记录常用表达。'] : topObjectItems,
          speakText: topObject.commonExpressions.isNotEmpty
              ? topObject.commonExpressions.first
              : topObject.displayName,
        ),
      if (topTerms.isNotEmpty)
        MemoryInsightNode(
          id: 'conversation',
          title: topTerms.first.text,
          subtitle: conversationTermTypeLabel(topTerms.first.type),
          type: MemoryInsightNodeType.conversation,
          detailTitle: '对话特殊词',
          detailLines: topTerms
              .take(4)
              .map((term) =>
                  '${term.text} · ${conversationTermTypeLabel(term.type)} · ${term.count}次')
              .toList(growable: false),
        ),
      if (actionPreferenceItems.isNotEmpty)
        MemoryInsightNode(
          id: 'agent',
          title: '更懂怎么帮你',
          subtitle: '帮助方式偏好',
          type: MemoryInsightNodeType.agent,
          detailTitle: '智能体行动偏好',
          detailLines: actionPreferenceItems,
        ),
      if (profileItems.isNotEmpty)
        MemoryInsightNode(
          id: 'profile',
          title: '更懂你的表达',
          subtitle: '长期偏好摘要',
          type: MemoryInsightNodeType.agent,
          detailTitle: '长期学习画像',
          detailLines: profileItems,
        ),
    ];

    return MemoryInsightSnapshot(
      learnedExpressionCount: learnedExpressions.length,
      personalizedLearningEnabled: personalizedLearningEnabled,
      nodes: nodes.take(7).toList(growable: false),
      evidenceCards: [
        if (profileItems.isNotEmpty)
          MemoryEvidenceCard(
            title: '长期学习画像',
            subtitle: '来自确认、播报、保存、训练和跳过等本机行为',
            items: profileItems,
            emptyText: '还没有形成稳定的长期偏好摘要。',
            type: MemoryInsightNodeType.agent,
          ),
        if (learningLoopItems.isNotEmpty)
          MemoryEvidenceCard(
            title: '表达闭环状态',
            subtitle: '系统如何把你的操作转成下一次更贴近的候选',
            items: learningLoopItems,
            emptyText: '还没有记录到完整的表达反馈闭环。',
            type: MemoryInsightNodeType.agent,
          ),
        MemoryEvidenceCard(
          title: '常用表达',
          subtitle: '语桥会优先记住你确认、收藏和播报过的话',
          items: topExpressionItems,
          emptyText: '还没有足够的常用表达记录。',
          type: MemoryInsightNodeType.expression,
        ),
        MemoryEvidenceCard(
          title: '智能体学习',
          subtitle: '来自接受、播报、保存和跳过等真实反馈',
          items: companionItems,
          emptyText: '还没有形成足够清晰的智能体反馈记忆。',
          type: MemoryInsightNodeType.expression,
        ),
        MemoryEvidenceCard(
          title: '帮助方式偏好',
          subtitle: '语桥会学习你更常使用哪类辅助方式',
          items: actionPreferenceItems,
          emptyText: '还没有形成清晰的帮助方式偏好。',
          type: MemoryInsightNodeType.agent,
        ),
        MemoryEvidenceCard(
          title: topPlace == null ? '地点习惯' : '${topPlace.name}常说',
          subtitle: topPlace == null
              ? '开启地点推荐后，这里会显示不同地点的高频表达'
              : '${topPlace.typeLabel} · 访问 ${topPlace.visitCount} 次',
          items: topPlaceItems,
          emptyText: '这个地点还没有形成高频词。',
          type: MemoryInsightNodeType.place,
        ),
        MemoryEvidenceCard(
          title: topObject == null ? '个人物品' : '看到${topObject.displayName}时',
          subtitle: '拍照识别个人物品后，语桥会记住相关表达',
          items: topObjectItems,
          emptyText: '还没有保存个人物品，或物品还没有关联表达。',
          type: MemoryInsightNodeType.object,
        ),
        MemoryEvidenceCard(
          title: '对话特殊词',
          subtitle: '对话里确认过的人名、地点和专有词',
          items: topTermItems,
          emptyText: '还没有确认过对话特殊词。',
          type: MemoryInsightNodeType.conversation,
        ),
      ],
    );
  }

  static List<String> _uniqueTexts(Iterable<String> values) {
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

  static List<String> _uniqueDisplayItems(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      final key = clean.split('·').first.trim();
      final normalized = LocationRecommendationController.normalizeText(key);
      if (clean.isEmpty || normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      result.add(clean);
    }
    return result;
  }

  static List<String> _actionPreferenceItems(CompanionActionBias bias) {
    final accepted = bias.accepted.entries
        .map((entry) => (type: entry.key, count: entry.value, positive: true));
    final rejected = bias.rejected.entries
        .map((entry) => (type: entry.key, count: entry.value, positive: false));
    final items = [...accepted, ...rejected]..sort((a, b) {
        final count = b.count.compareTo(a.count);
        if (count != 0) return count;
        if (a.positive != b.positive) return a.positive ? -1 : 1;
        return a.type.index.compareTo(b.type.index);
      });
    return items.take(5).map((item) {
      final action = item.positive ? '确认' : '跳过';
      return '${item.type.label} · $action ${item.count}次';
    }).toList(growable: false);
  }

  static List<String> _profileItems(UserPreferenceProfile profile) {
    if (!profile.hasSignal) return const [];
    final summary = profile.displaySummaryLines(limit: 6);
    if (summary.isNotEmpty) return summary;
    final items = <String>[
      ...profile.topExpressions.take(3).map(
            (signal) => '常用表达趋势 · ${signal.latestText}',
          ),
      ...profile.intentPatterns.take(3).map(
            (signal) => '常用意图模式 · ${signal.label}',
          ),
      ...profile.semanticPreferences.take(3).map(
            (signal) => '语义偏好 · ${signal.label}',
          ),
      if (profile.expressionStyle.summary.isNotEmpty)
        profile.expressionStyle.displaySummary,
      ...profile.placeIntentPatterns.take(2).map(
            (signal) => '场景化表达模式 · ${signal.label}',
          ),
      ...profile.objectPatterns.take(2).map(
            (signal) => '物品相关表达模式 · ${signal.label}',
          ),
      ...profile.rejectedSemanticPreferences.take(2).map(
            (signal) => '较少选择的语义 · ${signal.label}',
          ),
      ...profile.rejectedExpressions.take(2).map(
            (signal) => '较少选择 · ${signal.latestText}',
          ),
    ];
    return _uniqueDisplayItems(items).take(6).toList(growable: false);
  }

  static PlaceCluster? _topPlace(
    LocationRecommendationController controller,
  ) {
    final places = controller.places.toList();
    if (places.isEmpty) return null;
    places.sort((a, b) {
      if (a.id == controller.currentPlace?.id) return -1;
      if (b.id == controller.currentPlace?.id) return 1;
      final visit = b.visitCount.compareTo(a.visitCount);
      return visit != 0 ? visit : b.lastSeenAt.compareTo(a.lastSeenAt);
    });
    return places.first;
  }

  static PersonalObject? _topObject(List<PersonalObject> objects) {
    if (objects.isEmpty) return null;
    final sorted = objects.toList()
      ..sort((a, b) {
        final usage = b.usageCount.compareTo(a.usageCount);
        return usage != 0 ? usage : b.updatedAt.compareTo(a.updatedAt);
      });
    return sorted.first;
  }
}
