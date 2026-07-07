import 'package:flutter_test/flutter_test.dart';
import 'package:yuqiao_app/companion_agent.dart';
import 'package:yuqiao_app/location_recommendation.dart';
import 'package:yuqiao_app/memory_insights.dart';
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
  test('adds companion action preference evidence to memory snapshot', () {
    final snapshot = const MemoryInsightService().build(
      recentExpressions: const [],
      favoriteExpressions: const [],
      expressionHabits: const [],
      personalObjects: const [],
      locationController: LocationRecommendationController(
        store: _MemoryLocationStore(),
      ),
      conversationTerms: const [],
      companionActionBias: const CompanionActionBias(
        accepted: {CompanionActionType.recommendSentence: 3},
        rejected: {CompanionActionType.explain: 1},
      ),
      personalizedLearningEnabled: true,
    );

    final agentCards = snapshot.evidenceCards
        .where((card) => card.type == MemoryInsightNodeType.agent)
        .toList();

    expect(agentCards, hasLength(1));
    expect(agentCards.first.items.join('\n'), contains('整理表达'));
    expect(agentCards.first.items.join('\n'), contains('帮我理解'));
    expect(
      snapshot.nodes.any((node) => node.type == MemoryInsightNodeType.agent),
      isTrue,
    );
  });

  test('adds long-term profile evidence to memory snapshot', () {
    final profile = const UserPreferenceProfileBuilder().build([
      UserLearningEvent(
        feature: 'conversation',
        action: 'accepted',
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
    final snapshot = MemoryInsightService().build(
      recentExpressions: const [],
      favoriteExpressions: const [],
      expressionHabits: const [],
      personalObjects: const [],
      locationController: LocationRecommendationController(
        store: _MemoryLocationStore(),
      ),
      conversationTerms: const [],
      userPreferenceProfile: profile,
      personalizedLearningEnabled: true,
    );

    expect(
      snapshot.evidenceCards.any((card) => card.title == '长期学习画像'),
      isTrue,
    );
    expect(
      snapshot.evidenceCards.any((card) => card.title == '表达闭环状态'),
      isTrue,
    );
    expect(
      snapshot.nodes.any((node) => node.id == 'profile'),
      isTrue,
    );
    expect(
      snapshot.evidenceCards.expand((card) => card.items).join('\n'),
      contains('画像摘要'),
    );
    expect(
      snapshot.evidenceCards.expand((card) => card.items).join('\n'),
      contains('常用表达'),
    );
    expect(
      snapshot.evidenceCards.expand((card) => card.items).join('\n'),
      contains('wait for me'),
    );
    expect(
      snapshot.evidenceCards.expand((card) => card.items).join('\n'),
      contains('学习闭环'),
    );
  });
}
