import 'package:flutter_test/flutter_test.dart';
import 'package:yuqiao_app/location_recommendation.dart';

void main() {
  group('PlaceTypeCatalog', () {
    test('migrates legacy Chinese place types', () {
      expect(PlaceTypeCatalog.normalize('医院'), PlaceTypeCatalog.hospital);
      expect(PlaceTypeCatalog.normalize('住宅区'), PlaceTypeCatalog.residential);
      expect(PlaceTypeCatalog.labelOf('supermarket'), '超市');
    });

    test('provides local scene words', () {
      expect(
        PlaceTypeCatalog.wordsFor(PlaceTypeCatalog.hospital),
        containsAll(<String>['医生', '护士', '挂号', '检查']),
      );
      expect(
        PlaceTypeCatalog.wordsFor(PlaceTypeCatalog.home),
        contains('喝水'),
      );
    });
  });

  group('RecommendationContext', () {
    test('infers strict slots from stuck-flow prompts', () {
      expect(
        RecommendationContext.inferSlot('需要谁帮忙？'),
        RecommendationSlot.person,
      );
      expect(
        RecommendationContext.inferSlot('哪里不舒服？'),
        RecommendationSlot.bodyPart,
      );
      expect(
        RecommendationContext.inferSlot('这种感觉什么时候明显？'),
        RecommendationSlot.time,
      );
      expect(
        RecommendationContext.inferSlot('你想怎么做？'),
        RecommendationSlot.actionOrObject,
      );
    });
  });

  test('PlaceCluster preserves user ownership and suggestions in JSON', () {
    final place = PlaceCluster(
      id: 'place_1',
      name: '我的医院',
      latitude: 24.8,
      longitude: 102.8,
      radiusMeters: 120,
      visitCount: 3,
      createdAt: DateTime(2026, 6, 18),
      lastSeenAt: DateTime(2026, 6, 19),
      isUserNamed: true,
      placeType: PlaceTypeCatalog.hospital,
      typeSource: PlaceTypeSource.user,
      suggestedName: '医院 · 第一人民医院',
      suggestedType: PlaceTypeCatalog.hospital,
      suggestedConfidence: 0.92,
    );

    final restored = PlaceCluster.fromJson(
      Map<String, dynamic>.from(place.toJson()),
    );

    expect(restored.name, '我的医院');
    expect(restored.normalizedType, PlaceTypeCatalog.hospital);
    expect(restored.isUserConfirmed, isTrue);
    expect(restored.suggestedName, '医院 · 第一人民医院');
    expect(restored.suggestedConfidence, 0.92);
  });
}
