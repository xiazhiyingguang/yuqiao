import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuqiao_app/mulberry_symbols.dart';
import 'package:yuqiao_app/personal_objects.dart';
import 'package:yuqiao_app/rehab_training.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a four-option picture word question from Mulberry symbols', () {
    final words = RehabTrainingDeck.words();
    final question = RehabTrainingDeck.buildQuestion(
      words: words,
      progress: const {},
      seed: 7,
    );

    expect(question.options, hasLength(4));
    expect(question.options.map((item) => item.text).toSet(), hasLength(4));
    expect(
      question.options.map((item) => item.text),
      contains(question.answer.text),
    );
    expect(
        MulberrySymbolResolver.assetForText(question.answer.text), isNotNull);
  });

  test('prefers related distractors instead of fully random words', () {
    const words = [
      RehabTrainingWord(text: '苹果', asset: 'apple.svg', category: '饮食'),
      RehabTrainingWord(text: '香蕉', asset: 'banana.svg', category: '饮食'),
      RehabTrainingWord(text: '面包', asset: 'bread.svg', category: '饮食'),
      RehabTrainingWord(text: '牛奶', asset: 'milk.svg', category: '饮食'),
      RehabTrainingWord(text: '公交车', asset: 'bus.svg', category: '交通'),
      RehabTrainingWord(text: '出租车', asset: 'taxi.svg', category: '交通'),
      RehabTrainingWord(text: '火车', asset: 'train.svg', category: '交通'),
      RehabTrainingWord(text: '地铁', asset: 'metro.svg', category: '交通'),
    ];
    final question = RehabTrainingDeck.buildQuestion(
      words: words,
      progress: const {},
      seed: 7,
    );

    final relatedCount = question.options
        .where((item) => item.category == question.answer.category)
        .length;

    expect(relatedCount, greaterThanOrEqualTo(2));
  });

  test('easy difficulty prefers different-category distractors', () {
    const words = [
      RehabTrainingWord(text: 'apple', asset: 'apple.svg', category: 'food'),
      RehabTrainingWord(text: 'banana', asset: 'banana.svg', category: 'food'),
      RehabTrainingWord(text: 'bread', asset: 'bread.svg', category: 'food'),
      RehabTrainingWord(text: 'milk', asset: 'milk.svg', category: 'food'),
      RehabTrainingWord(text: 'bus', asset: 'bus.svg', category: 'transport'),
      RehabTrainingWord(text: 'taxi', asset: 'taxi.svg', category: 'transport'),
      RehabTrainingWord(
          text: 'train', asset: 'train.svg', category: 'transport'),
      RehabTrainingWord(
          text: 'metro', asset: 'metro.svg', category: 'transport'),
    ];
    final question = RehabTrainingDeck.buildQuestion(
      words: words,
      progress: const {},
      seed: 7,
      difficulty: RehabTrainingDifficulty.easy,
    );

    final sameCategoryCount = question.options
        .where((item) => item.category == question.answer.category)
        .length;

    expect(sameCategoryCount, 1);
  });

  test('hard difficulty prefers same-category distractors', () {
    const words = [
      RehabTrainingWord(text: 'apple', asset: 'apple.svg', category: 'food'),
      RehabTrainingWord(text: 'banana', asset: 'banana.svg', category: 'food'),
      RehabTrainingWord(text: 'bread', asset: 'bread.svg', category: 'food'),
      RehabTrainingWord(text: 'milk', asset: 'milk.svg', category: 'food'),
      RehabTrainingWord(text: 'bus', asset: 'bus.svg', category: 'transport'),
      RehabTrainingWord(text: 'taxi', asset: 'taxi.svg', category: 'transport'),
      RehabTrainingWord(
          text: 'train', asset: 'train.svg', category: 'transport'),
      RehabTrainingWord(
          text: 'metro', asset: 'metro.svg', category: 'transport'),
    ];
    final question = RehabTrainingDeck.buildQuestion(
      words: words,
      progress: const {},
      seed: 7,
      difficulty: RehabTrainingDifficulty.hard,
    );

    final sameCategoryCount = question.options
        .where((item) => item.category == question.answer.category)
        .length;

    expect(sameCategoryCount, 4);
  });

  test('adds saved personal objects to training words', () {
    final words = RehabTrainingDeck.words(
      personalObjects: [
        PersonalObject(
          id: 'cup',
          displayName: '我的水杯',
          category: '杯子',
          visualDescription: '蓝色杯子',
          referenceImagePath: 'local/cup.jpg',
          commonExpressions: const ['我想喝水'],
          note: '',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );

    final objectWord = words.firstWhere((item) => item.text == '我的水杯');
    expect(objectWord.isPersonalObject, isTrue);
    expect(objectWord.imagePath, 'local/cup.jpg');
  });

  test('records local rehab training progress', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RehabTrainingStore();

    await store.record('水杯', correct: true);
    await store.record('水杯', correct: false);
    final progress = await store.loadAll();
    final item = progress[MulberrySymbolResolver.normalize('水杯')];

    expect(item, isNotNull);
    expect(item!.correctCount, 1);
    expect(item.wrongCount, 1);
    expect(item.totalCount, 2);
    expect(item.isWeakWord, isTrue);
    expect(item.nextReviewAt, isNotNull);
  });

  test('tracks mastery and review state', () {
    final progress = RehabTrainingProgress(
      wordText: '水杯',
      correctCount: 5,
      wrongCount: 0,
      lastPracticedAt: DateTime.now(),
      nextReviewAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    expect(progress.masteryLevel, greaterThanOrEqualTo(3));
    expect(progress.isDueForReview, isTrue);
    expect(progress.practicedOn(DateTime.now()), isTrue);
  });

  test('uses spaced review intervals from answer stability', () {
    final beginner = RehabTrainingProgress(
      wordText: 'apple',
      correctCount: 0,
      wrongCount: 0,
      lastPracticedAt: null,
      nextReviewAt: null,
    ).record(correct: true);
    final stable = RehabTrainingProgress(
      wordText: 'banana',
      correctCount: 7,
      wrongCount: 0,
      correctStreak: 6,
      lastPracticedAt: DateTime.now(),
      nextReviewAt: null,
    ).record(correct: true);
    final missed = stable.record(correct: false);

    expect(beginner.correctStreak, 1);
    expect(
      beginner.nextReviewAt!.difference(beginner.lastPracticedAt!).inHours,
      greaterThanOrEqualTo(7),
    );
    expect(stable.correctStreak, 7);
    expect(
      stable.nextReviewAt!.difference(stable.lastPracticedAt!).inDays,
      greaterThanOrEqualTo(29),
    );
    expect(missed.correctStreak, 0);
  });

  test('removes weak word status after repeated correct answers', () {
    var progress = RehabTrainingProgress(
      wordText: 'table',
      correctCount: 0,
      wrongCount: 0,
      lastPracticedAt: null,
      nextReviewAt: null,
    ).record(correct: false);

    expect(progress.isWeakWord, isTrue);

    for (var i = 0; i < 8; i++) {
      progress = progress.record(correct: true);
    }

    expect(progress.correctStreak, 8);
    expect(progress.hasRecoveredFromWeakness, isTrue);
    expect(progress.isWeakWord, isFalse);
  });
}
