import 'package:flutter_test/flutter_test.dart';
import 'package:yuqiao_app/companion_agent.dart';
import 'package:yuqiao_app/location_recommendation.dart';
import 'package:yuqiao_app/memory_insights.dart';

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
}
