import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'expression_habits.dart';
import 'mulberry_symbols.dart';
import 'personal_objects.dart';
import 'user_learning.dart';

class RehabTrainingProgress {
  const RehabTrainingProgress({
    required this.wordText,
    required this.correctCount,
    required this.wrongCount,
    this.correctStreak = 0,
    required this.lastPracticedAt,
    required this.nextReviewAt,
  });

  final String wordText;
  final int correctCount;
  final int wrongCount;
  final int correctStreak;
  final DateTime? lastPracticedAt;
  final DateTime? nextReviewAt;

  int get totalCount => correctCount + wrongCount;

  int get masteryLevel {
    return _masteryLevelFor(
      correctCount: correctCount,
      wrongCount: wrongCount,
      correctStreak: correctStreak,
    );
  }

  bool get isDueForReview {
    final due = nextReviewAt;
    return due != null && !due.isAfter(DateTime.now());
  }

  bool practicedOn(DateTime day) {
    final last = lastPracticedAt;
    return last != null &&
        last.year == day.year &&
        last.month == day.month &&
        last.day == day.day;
  }

  bool get hasRecoveredFromWeakness => correctStreak >= 3 && mastery >= .72;

  bool get isWeakWord {
    if (wrongCount == 0 || hasRecoveredFromWeakness) return false;
    return mastery < .72 || wrongCount >= 2;
  }

  double get mastery {
    if (totalCount == 0) return 0;
    return (correctCount / totalCount).clamp(0, 1).toDouble();
  }

  RehabTrainingProgress record({required bool correct}) {
    final now = DateTime.now();
    final nextCorrectCount = correct ? correctCount + 1 : correctCount;
    final nextWrongCount = correct ? wrongCount : wrongCount + 1;
    final nextCorrectStreak = correct ? correctStreak + 1 : 0;
    final nextMasteryLevel = _masteryLevelFor(
      correctCount: nextCorrectCount,
      wrongCount: nextWrongCount,
      correctStreak: nextCorrectStreak,
    );
    return RehabTrainingProgress(
      wordText: wordText,
      correctCount: nextCorrectCount,
      wrongCount: nextWrongCount,
      correctStreak: nextCorrectStreak,
      lastPracticedAt: now,
      nextReviewAt: _nextReviewTime(
        now,
        correct: correct,
        correctCount: nextCorrectCount,
        wrongCount: nextWrongCount,
        correctStreak: nextCorrectStreak,
        masteryLevel: nextMasteryLevel,
      ),
    );
  }

  DateTime _nextReviewTime(
    DateTime now, {
    required bool correct,
    required int correctCount,
    required int wrongCount,
    required int correctStreak,
    required int masteryLevel,
  }) {
    if (!correct) {
      final minutes = wrongCount >= 3 ? 30 : 90;
      return now.add(Duration(minutes: minutes));
    }

    return now.add(_spacedReviewInterval(
      correctCount: correctCount,
      wrongCount: wrongCount,
      correctStreak: correctStreak,
      masteryLevel: masteryLevel,
    ));
  }

  Duration _spacedReviewInterval({
    required int correctCount,
    required int wrongCount,
    required int correctStreak,
    required int masteryLevel,
  }) {
    final stability = correctCount + correctStreak - wrongCount * 2;
    if (masteryLevel >= 5 && correctStreak >= 7 && stability >= 14) {
      return const Duration(days: 30);
    }
    if (masteryLevel >= 5 && correctStreak >= 5) {
      return const Duration(days: 15);
    }
    if (masteryLevel >= 4 && correctStreak >= 4) {
      return const Duration(days: 7);
    }
    if (masteryLevel >= 3 && correctStreak >= 3) {
      return const Duration(days: 3);
    }
    if (masteryLevel >= 2 && correctStreak >= 2) {
      return const Duration(days: 1);
    }
    return const Duration(hours: 8);
  }

  Map<String, dynamic> toJson() => {
        'wordText': wordText,
        'correctCount': correctCount,
        'wrongCount': wrongCount,
        'correctStreak': correctStreak,
        'lastPracticedAt': lastPracticedAt?.toIso8601String(),
        'nextReviewAt': nextReviewAt?.toIso8601String(),
      };

  static RehabTrainingProgress fromJson(Map<String, dynamic> json) {
    return RehabTrainingProgress(
      wordText: json['wordText']?.toString() ?? '',
      correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
      wrongCount: (json['wrongCount'] as num?)?.toInt() ?? 0,
      correctStreak: (json['correctStreak'] as num?)?.toInt() ?? 0,
      lastPracticedAt: DateTime.tryParse(
        json['lastPracticedAt']?.toString() ?? '',
      ),
      nextReviewAt: DateTime.tryParse(
        json['nextReviewAt']?.toString() ?? '',
      ),
    );
  }

  static int _masteryLevelFor({
    required int correctCount,
    required int wrongCount,
    int correctStreak = 0,
  }) {
    final total = correctCount + wrongCount;
    if (total == 0) return 0;
    final mastery = (correctCount / total).clamp(0, 1).toDouble();
    final streak =
        correctStreak == 0 && wrongCount == 0 ? correctCount : correctStreak;
    if (correctCount >= 8 && streak >= 5 && mastery >= .86) return 5;
    if (correctCount >= 5 && streak >= 3 && mastery >= .78) return 4;
    if (correctCount >= 3 && streak >= 2 && mastery >= .68) return 3;
    if (correctCount >= 2 && mastery >= .55) return 2;
    return 1;
  }
}

class RehabTrainingStore {
  static const _storageKey = 'rehab_training_progress_v1';
  static const _difficultyKey = 'rehab_training_difficulty_v1';

  Future<Map<String, RehabTrainingProgress>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      final result = <String, RehabTrainingProgress>{};
      for (final item in decoded.whereType<Map>()) {
        final progress = RehabTrainingProgress.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (progress.wordText.trim().isEmpty) continue;
        result[MulberrySymbolResolver.normalize(progress.wordText)] = progress;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> record(String wordText, {required bool correct}) async {
    final clean = wordText.trim();
    if (clean.isEmpty) return;
    final progress = await loadAll();
    final key = MulberrySymbolResolver.normalize(clean);
    final current = progress[key] ??
        RehabTrainingProgress(
          wordText: clean,
          correctCount: 0,
          wrongCount: 0,
          correctStreak: 0,
          lastPracticedAt: null,
          nextReviewAt: null,
        );
    progress[key] = current.record(correct: correct);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(progress.values.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<RehabTrainingDifficulty> loadDifficulty() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_difficultyKey);
    return RehabTrainingDifficulty.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => RehabTrainingDifficulty.standard,
    );
  }

  Future<void> saveDifficulty(RehabTrainingDifficulty difficulty) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_difficultyKey, difficulty.name);
  }
}

class RehabTrainingWord {
  const RehabTrainingWord({
    required this.text,
    required this.asset,
    required this.category,
    this.imagePath,
    this.source = RehabTrainingWordSource.symbol,
  });

  final String text;
  final String asset;
  final String category;
  final String? imagePath;
  final RehabTrainingWordSource source;

  bool get isPersonalObject => source == RehabTrainingWordSource.personalObject;
}

enum RehabTrainingWordSource { symbol, personalObject }

enum RehabTrainingMode { mixed, weakReview, personalObjects }

enum RehabTrainingDifficulty { easy, standard, hard }

extension RehabTrainingDifficultyLabel on RehabTrainingDifficulty {
  String get label => switch (this) {
        RehabTrainingDifficulty.easy => '简单',
        RehabTrainingDifficulty.standard => '标准',
        RehabTrainingDifficulty.hard => '困难',
      };

  String get description => switch (this) {
        RehabTrainingDifficulty.easy => '干扰项差异更大',
        RehabTrainingDifficulty.standard => '同类词一起练',
        RehabTrainingDifficulty.hard => '相近词和相似场景',
      };
}

class RehabTrainingQuestion {
  const RehabTrainingQuestion({
    required this.answer,
    required this.options,
  });

  final RehabTrainingWord answer;
  final List<RehabTrainingWord> options;
}

class RehabTrainingDeck {
  static const int minWordLength = 1;

  static List<RehabTrainingWord> words({
    List<PersonalObject> personalObjects = const [],
  }) {
    final seen = <String>{};
    final words = <RehabTrainingWord>[];
    for (final entry in MulberrySymbolResolver.entries) {
      if (entry.status == 'disabled') continue;
      final text = entry.primaryText.trim();
      final normalized = MulberrySymbolResolver.normalize(text);
      if (text.length < minWordLength || normalized.isEmpty) continue;
      if (!seen.add(normalized)) continue;
      words.add(RehabTrainingWord(
        text: text,
        asset: entry.asset,
        category: _trainingCategoryFor(text, entry.asset, entry.category),
      ));
    }
    for (final object in personalObjects) {
      final text = object.displayName.trim();
      final normalized = MulberrySymbolResolver.normalize(text);
      if (text.isEmpty || normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      words.add(RehabTrainingWord(
        text: text,
        asset: '',
        category: _trainingCategoryFor(
          '${object.displayName} ${object.category} ${object.visualDescription}',
          object.referenceImagePath,
          object.category,
        ),
        imagePath: object.referenceImagePath,
        source: RehabTrainingWordSource.personalObject,
      ));
    }
    return words;
  }

  static RehabTrainingQuestion buildQuestion({
    required List<RehabTrainingWord> words,
    required Map<String, RehabTrainingProgress> progress,
    required int seed,
    RehabTrainingMode mode = RehabTrainingMode.mixed,
    RehabTrainingDifficulty difficulty = RehabTrainingDifficulty.standard,
  }) {
    final rng = math.Random(seed);
    final ranked = List<RehabTrainingWord>.of(words)
      ..sort((a, b) {
        final aProgress = progress[MulberrySymbolResolver.normalize(a.text)];
        final bProgress = progress[MulberrySymbolResolver.normalize(b.text)];
        final aScore = _priorityScore(aProgress, word: a, mode: mode);
        final bScore = _priorityScore(bProgress, word: b, mode: mode);
        final score = bScore.compareTo(aScore);
        if (score != 0) return score;
        return a.text.compareTo(b.text);
      });

    final modePool = _answerPoolForMode(ranked, progress, mode);
    final candidates = modePool.isEmpty ? ranked : modePool;
    final answerPool =
        candidates.take(math.min(18, candidates.length)).toList();
    final answer = answerPool[rng.nextInt(answerPool.length)];
    final distractors = _distractorsFor(answer, words, rng, difficulty);
    final options = <RehabTrainingWord>[
      answer,
      ...distractors.take(3),
    ]..shuffle(rng);
    return RehabTrainingQuestion(answer: answer, options: options);
  }

  static List<RehabTrainingWord> _answerPoolForMode(
    List<RehabTrainingWord> ranked,
    Map<String, RehabTrainingProgress> progress,
    RehabTrainingMode mode,
  ) {
    return switch (mode) {
      RehabTrainingMode.personalObjects =>
        ranked.where((word) => word.isPersonalObject).toList(),
      RehabTrainingMode.weakReview => ranked.where((word) {
          final item = progress[MulberrySymbolResolver.normalize(word.text)];
          return item != null && (item.isWeakWord || item.isDueForReview);
        }).toList(),
      RehabTrainingMode.mixed => ranked,
    };
  }

  static List<RehabTrainingWord> _distractorsFor(
    RehabTrainingWord answer,
    List<RehabTrainingWord> words,
    math.Random rng,
    RehabTrainingDifficulty difficulty,
  ) {
    final answerKey = MulberrySymbolResolver.normalize(answer.text);
    final candidates = words
        .where(
            (word) => MulberrySymbolResolver.normalize(word.text) != answerKey)
        .toList()
      ..shuffle(rng);

    int score(RehabTrainingWord word) {
      var value = 0;
      if (word.category == answer.category) value += 100;
      if (_relatedCategories(answer.category).contains(word.category)) {
        value += 52;
      }
      if (word.source == answer.source) value += 18;
      if (_sharesMeaningClue(answer.text, word.text)) value += 28;
      if (word.asset.isNotEmpty &&
          answer.asset.isNotEmpty &&
          _assetFamily(word.asset) == _assetFamily(answer.asset)) {
        value += 24;
      }
      return value;
    }

    candidates.sort((a, b) {
      final aScore = score(a);
      final bScore = score(b);
      final byScore = switch (difficulty) {
        RehabTrainingDifficulty.easy => aScore.compareTo(bScore),
        RehabTrainingDifficulty.standard => bScore.compareTo(aScore),
        RehabTrainingDifficulty.hard => _hardDistractorScore(b, answer, bScore)
            .compareTo(_hardDistractorScore(a, answer, aScore)),
      };
      if (byScore != 0) return byScore;
      return a.text.compareTo(b.text);
    });
    return candidates;
  }

  static int _hardDistractorScore(
    RehabTrainingWord word,
    RehabTrainingWord answer,
    int baseScore,
  ) {
    var value = baseScore;
    if (word.category == answer.category) value += 80;
    if (_sharesMeaningClue(answer.text, word.text)) value += 70;
    if (word.asset.isNotEmpty &&
        answer.asset.isNotEmpty &&
        _assetFamily(word.asset) == _assetFamily(answer.asset)) {
      value += 58;
    }
    if (word.text.length == answer.text.length) value += 12;
    return value;
  }

  static double _priorityScore(
    RehabTrainingProgress? progress, {
    required RehabTrainingWord word,
    required RehabTrainingMode mode,
  }) {
    final modeBoost = switch (mode) {
      RehabTrainingMode.personalObjects => word.isPersonalObject ? 1200.0 : 0.0,
      RehabTrainingMode.weakReview => 0.0,
      RehabTrainingMode.mixed => 0.0,
    };
    if (progress == null || progress.totalCount == 0) return 1000 + modeBoost;
    final dueBoost = progress.isDueForReview ? 420.0 : 0.0;
    final weakBoost = progress.isWeakWord ? 260.0 : 0.0;
    final wrongBoost = progress.wrongCount * 150.0;
    final masteryPenalty = progress.masteryLevel * 90.0;
    final last = progress.lastPracticedAt;
    final daysSincePractice =
        last == null ? 30.0 : DateTime.now().difference(last).inHours / 24.0;
    return 600.0 +
        dueBoost +
        weakBoost +
        wrongBoost +
        daysSincePractice * 16.0 -
        masteryPenalty +
        modeBoost;
  }

  static Set<String> _relatedCategories(String category) {
    return switch (category) {
      '饮食' => {'物品', '家里', '购物'},
      '身体' => {'医疗', '感受'},
      '医疗' => {'身体', '地点', '人物'},
      '地点' => {'交通', '购物', '医疗'},
      '交通' => {'地点', '物品'},
      '人物' => {'家人', '医疗'},
      '家人' => {'人物', '家里'},
      '物品' => {'饮食', '交通', '家里'},
      '个人物品' => {'物品', '家里'},
      _ => const <String>{},
    };
  }

  static bool _sharesMeaningClue(String a, String b) {
    const clues = [
      '水',
      '饭',
      '药',
      '疼',
      '车',
      '家',
      '手',
      '头',
      '脸',
      '杯',
      '包',
      '钥匙',
      '手机',
    ];
    return clues.any((clue) => a.contains(clue) && b.contains(clue));
  }

  static String _assetFamily(String asset) {
    final file = asset.split('/').last.split('.').first;
    return file.split(RegExp(r'[_,-]')).first;
  }

  static String _trainingCategoryFor(
    String text,
    String asset,
    String originalCategory,
  ) {
    final source = '$text $asset $originalCategory'.toLowerCase();
    bool hasAny(List<String> values) => values.any(source.contains);
    if (hasAny(['我的', '个人物品'])) return '个人物品';
    if (hasAny([
      '水',
      '杯',
      '饭',
      '吃',
      '喝',
      '面包',
      '水果',
      '苹果',
      '香蕉',
      '茶',
      '咖啡',
      '奶',
      'cheese',
      'food',
      'drink',
      'bread'
    ])) {
      return '饮食';
    }
    if (hasAny([
      '头',
      '脸',
      '手',
      '脚',
      '疼',
      '痛',
      '身体',
      'body',
      'head',
      'face',
      'hand',
      'foot'
    ])) {
      return '身体';
    }
    if (hasAny([
      '医生',
      '护士',
      '医院',
      '药',
      '病',
      'doctor',
      'nurse',
      'medicine',
      'hospital'
    ])) {
      return '医疗';
    }
    if (hasAny([
      '妈妈',
      '爸爸',
      '家人',
      '朋友',
      '老师',
      'person',
      'people',
      'mother',
      'father'
    ])) {
      return '人物';
    }
    if (hasAny([
      '家',
      '房',
      '厕所',
      '学校',
      '公园',
      '超市',
      '地点',
      'home',
      'house',
      'toilet',
      'school',
      'park'
    ])) {
      return '地点';
    }
    if (hasAny(['车', '公交', '火车', '出租', '地铁', 'bus', 'train', 'taxi', 'car'])) {
      return '交通';
    }
    if (hasAny(['买', '钱', '商店', '购物', 'shop', 'money'])) {
      return '购物';
    }
    if (hasAny([
      '钥匙',
      '手机',
      '眼镜',
      '包',
      '灯',
      '剪刀',
      '手表',
      'key',
      'phone',
      'glasses',
      'bag',
      'lamp',
      'scissors',
      'watch'
    ])) {
      return '物品';
    }
    return originalCategory == '未分类' ? '生活' : originalCategory;
  }
}

class RehabTrainingPage extends StatefulWidget {
  const RehabTrainingPage({
    super.key,
    this.initialMode = RehabTrainingMode.mixed,
    this.onLearningProfileChanged,
  });

  final RehabTrainingMode initialMode;
  final Future<void> Function()? onLearningProfileChanged;

  @override
  State<RehabTrainingPage> createState() => _RehabTrainingPageState();
}

class _RehabTrainingPageState extends State<RehabTrainingPage> {
  final RehabTrainingStore _store = RehabTrainingStore();
  final ExpressionHabitStore _habitStore = ExpressionHabitStore();
  final UserLearningStore _learningStore = UserLearningStore();
  final PersonalObjectStore _personalObjectStore = PersonalObjectStore();
  final FlutterTts _tts = FlutterTts();
  List<RehabTrainingWord> _words = const [];
  Map<String, RehabTrainingProgress> _progress = const {};
  RehabTrainingQuestion? _question;
  String? _selectedText;
  bool? _lastCorrect;
  bool _loading = true;
  bool _speakerActive = false;
  int _questionSeed = 0;
  late RehabTrainingMode _mode;
  RehabTrainingDifficulty _difficulty = RehabTrainingDifficulty.standard;
  int _sessionCorrect = 0;
  int _sessionWrong = 0;
  final Set<String> _sessionWords = {};
  final Set<String> _newlyMastered = {};
  bool _showingSummary = false;
  String _learningReceiptText = '';

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _initialize();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.42);
    final progress = await _store.loadAll();
    final difficulty = await _store.loadDifficulty();
    final personalObjects = await _personalObjectStore.loadAll();
    if (!mounted) return;
    setState(() {
      _words = RehabTrainingDeck.words(personalObjects: personalObjects);
      _progress = progress;
      _difficulty = difficulty;
      _loading = false;
    });
    _nextQuestion(speak: false);
  }

  void _nextQuestion({bool speak = true}) {
    if (_words.length < 4) return;
    if (!_hasEnoughWordsForMode(_mode)) {
      setState(() {
        _question = null;
        _selectedText = null;
        _lastCorrect = null;
      });
      return;
    }
    setState(() {
      _questionSeed++;
      _question = RehabTrainingDeck.buildQuestion(
        words: _words,
        progress: _progress,
        seed: DateTime.now().millisecondsSinceEpoch + _questionSeed,
        mode: _mode,
        difficulty: _difficulty,
      );
      _selectedText = null;
      _lastCorrect = null;
      _learningReceiptText = '';
    });
    if (speak) {
      Future<void>.delayed(
        const Duration(milliseconds: 220),
        () => _speakAnswer(),
      );
    }
  }

  bool _hasEnoughWordsForMode(RehabTrainingMode mode) {
    return switch (mode) {
      RehabTrainingMode.mixed => _words.length >= 4,
      RehabTrainingMode.personalObjects =>
        _words.where((word) => word.isPersonalObject).isNotEmpty &&
            _words.length >= 4,
      RehabTrainingMode.weakReview => _words.any((word) {
            final item = _progress[MulberrySymbolResolver.normalize(word.text)];
            return item != null && (item.isWeakWord || item.isDueForReview);
          }) &&
          _words.length >= 4,
    };
  }

  String get _pageSubtitle => switch (_mode) {
        RehabTrainingMode.mixed => '看图、听音、选词，让熟悉的词更容易想起',
        RehabTrainingMode.weakReview => '把容易忘的词再照料一次',
        RehabTrainingMode.personalObjects => '用自己的物品练习，更贴近日常',
      };

  Future<void> _speakAnswer() async {
    final answer = _question?.answer.text.trim();
    if (answer == null || answer.isEmpty) return;
    setState(() => _speakerActive = true);
    await _tts.stop();
    await _tts.speak(answer);
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    setState(() => _speakerActive = false);
  }

  Future<void> _choose(RehabTrainingWord option) async {
    final question = _question;
    if (question == null || _selectedText != null) return;
    final correct = MulberrySymbolResolver.normalize(option.text) ==
        MulberrySymbolResolver.normalize(question.answer.text);
    setState(() {
      _selectedText = option.text;
      _lastCorrect = correct;
    });

    // --- Session tracking ---
    final answerKey = MulberrySymbolResolver.normalize(question.answer.text);
    final oldProgress = _progress[answerKey];
    final oldLevel = oldProgress?.masteryLevel ?? 0;
    final alreadyPracticed = _sessionWords.contains(answerKey);
    _sessionWords.add(answerKey);
    if (correct) {
      _sessionCorrect++;
    } else {
      _sessionWrong++;
    }

    await _store.record(question.answer.text, correct: correct);
    final learningEnabled = await _habitStore.loadEnabled();
    var learningReceiptText = '';
    if (learningEnabled) {
      await _learningStore.record(UserLearningEvent(
        feature: 'training',
        action: correct ? 'accepted' : 'rejected',
        text: question.answer.text,
        normalizedText: MulberrySymbolResolver.normalize(question.answer.text),
        intentTag: correct ? 'training_correct' : 'training_review',
        objectTag: question.answer.isPersonalObject
            ? MulberrySymbolResolver.normalize(question.answer.text)
            : '',
        placeType: 'unknown',
        timeBucket: 'training',
        slotName: 'topic',
        createdAt: DateTime.now(),
      ));
      await widget.onLearningProfileChanged?.call();
      learningReceiptText = correct ? '已学习这次选择' : '已加入复习画像';
    }
    final progress = await _store.loadAll();
    if (!mounted) return;

    // Detect newly mastered words (mastery level crosses 3 for the first time this session)
    final newProgress = progress[answerKey];
    final newLevel = newProgress?.masteryLevel ?? 0;
    if (correct && oldLevel < 3 && newLevel >= 3 && !alreadyPracticed) {
      _newlyMastered.add(question.answer.text);
    }

    setState(() {
      _progress = progress;
      _learningReceiptText = learningReceiptText;
    });
    await _tts.stop();
    await _tts.speak(
      correct ? '答对了，${question.answer.text}' : '正确答案是${question.answer.text}',
    );
  }

  String _resultTextFor(RehabTrainingQuestion question) {
    final base = _lastCorrect == true ? '答对了' : '正确答案：${question.answer.text}';
    if (_learningReceiptText.isEmpty) return base;
    return '$base · $_learningReceiptText';
  }

  void _handleBack() {
    final total = _sessionCorrect + _sessionWrong;
    if (total == 0 || _showingSummary) {
      Navigator.of(context).maybePop();
      return;
    }
    _showSessionSummary();
  }

  Future<void> _showDifficultySettings() async {
    final selected = await showModalBottomSheet<RehabTrainingDifficulty>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DifficultySheet(current: _difficulty),
    );
    if (selected == null || selected == _difficulty) return;
    await _store.saveDifficulty(selected);
    if (!mounted) return;
    setState(() => _difficulty = selected);
    _nextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _sessionCorrect + _sessionWrong == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF9FBFF), Color(0xFFEFF5FF), Color(0xFFF7F2EA)],
            ),
          ),
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _words.length < 4
                    ? const Center(child: Text('可练习词汇不足'))
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        child: Column(
                          children: [
                            _buildTopBar(context),
                            const SizedBox(height: 12),
                            Expanded(child: _buildPracticeSection()),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        _GlassIconButton(
          icon: CupertinoIcons.chevron_left,
          onTap: _handleBack,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '词语花园',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
              SizedBox(height: 4),
              Text(
                _pageSubtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8A8D98),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _GlassIconButton(
          icon: CupertinoIcons.slider_horizontal_3,
          onTap: _showDifficultySettings,
        ),
      ],
    );
  }

  Widget _buildPracticeSection() {
    final question = _question;
    if (question == null) {
      return _buildEmptyModeState();
    }
    return KeyedSubtree(
      key: const ValueKey('practice'),
      child: _buildQuestionCard(question),
    );
  }

  Widget _buildEmptyModeState() {
    final (icon, title, subtitle) = switch (_mode) {
      RehabTrainingMode.weakReview => (
          CupertinoIcons.arrow_counterclockwise_circle_fill,
          '还没有常错词',
          '先完成几次普通练习，答错或到期复习的词会自动来到这里。'
        ),
      RehabTrainingMode.personalObjects => (
          CupertinoIcons.cube_box_fill,
          '还没有个人物品',
          '先在拍照识物或我的物品里保存个人物品，再回来练习。'
        ),
      RehabTrainingMode.mixed => (
          CupertinoIcons.square_grid_2x2_fill,
          '可练习词汇不足',
          '当前图文词库不足以生成四选一练习。'
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _glassDecoration(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .82)),
            ),
            child: Icon(icon, size: 38, color: const Color(0xFF7A9E9F)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2E3038),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A8D98),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(RehabTrainingQuestion question) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ultraCompact = constraints.maxHeight < 560;
        final compact = constraints.maxHeight < 660;
        final verticalGap = ultraCompact
            ? 8.0
            : compact
                ? 12.0
                : 18.0;
        final verticalPadding = ultraCompact ? 26.0 : 32.0;
        const headerReserved = 52.0;
        final footerReserved = ultraCompact ? 88.0 : 98.0;
        final remaining = math.max(
          190.0,
          constraints.maxHeight -
              verticalPadding -
              headerReserved -
              footerReserved -
              verticalGap * 2,
        );
        final optionHeight =
            ((remaining * .42 - 12) / 2).clamp(54.0, compact ? 86.0 : 100.0);
        final optionsBlockHeight = optionHeight * 2 + 10;
        final imageSize = math
            .min(
              constraints.maxWidth - 36,
              math.max(84.0, remaining - optionsBlockHeight),
            )
            .clamp(84.0, 330.0);
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(18, ultraCompact ? 10 : 16, 18, 16),
          decoration: _glassDecoration(),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _GlassIconButton(
                  icon: CupertinoIcons.speaker_2_fill,
                  onTap: _speakAnswer,
                  size: 52,
                  active: _speakerActive,
                  activeColor: const Color(0xFF4E8FD8),
                ),
              ),
              SizedBox(height: verticalGap),
              Center(
                child: Container(
                  width: imageSize,
                  height: imageSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(36),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .78)),
                  ),
                  child: _TrainingWordVisual(
                    word: question.answer,
                    size: (imageSize * .72).clamp(126.0, 226.0),
                    backgroundColor: Colors.white.withValues(alpha: .86),
                    padding: 16,
                  ),
                ),
              ),
              SizedBox(height: verticalGap),
              SizedBox(
                height: optionsBlockHeight,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: question.options.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 12,
                    mainAxisExtent: optionHeight,
                  ),
                  itemBuilder: (context, index) {
                    final option = question.options[index];
                    return _OptionButton(
                      text: option.text,
                      selectedText: _selectedText,
                      answerText: question.answer.text,
                      styleIndex: index,
                      onTap: () => _choose(option),
                    );
                  },
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _lastCorrect == null
                    ? const SizedBox(
                        key: ValueKey('empty-result'),
                        height: 28,
                      )
                    : Row(
                        key: const ValueKey('result'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _lastCorrect!
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.info_circle_fill,
                            color: _lastCorrect!
                                ? const Color(0xFF7A9E9F)
                                : const Color(0xFFD08C60),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _resultTextFor(question),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                color: _lastCorrect!
                                    ? const Color(0xFF547B7C)
                                    : const Color(0xFFA96844),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: const Color(0xFF2E3038),
                  borderRadius: BorderRadius.circular(20),
                  onPressed:
                      _selectedText == null ? null : () => _nextQuestion(),
                  child: const Text(
                    '下一题',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSessionSummary() async {
    _showingSummary = true;
    final total = _sessionCorrect + _sessionWrong;
    final accuracy = total > 0 ? (_sessionCorrect / total * 100).round() : 0;
    final mastered = _newlyMastered.toList();
    final outerNav = Navigator.of(context);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFE8ECF2)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7E8BA3).withValues(alpha: .18),
                  blurRadius: 36,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFC9F1E8), Color(0xFFA8E6D3)],
                    ),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .8)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7A9E9F).withValues(alpha: .2),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.leaf_arrow_circlepath,
                    size: 34,
                    color: Color(0xFF3D7A6E),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '本次练习',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E3038),
                  ),
                ),
                const SizedBox(height: 20),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SummaryStat(
                      value: '${_sessionWords.length}',
                      label: '练习词语',
                      color: const Color(0xFF4E8FD8),
                    ),
                    _SummaryStat(
                      value: '$_sessionCorrect',
                      label: '答对',
                      color: const Color(0xFF7A9E9F),
                    ),
                    _SummaryStat(
                      value: '$accuracy%',
                      label: '正确率',
                      color: accuracy >= 80
                          ? const Color(0xFF7A9E9F)
                          : const Color(0xFFD08C60),
                    ),
                  ],
                ),
                // Newly mastered words
                if (mastered.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FAF6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: const Color(0xFFD4EDE4), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.star_fill,
                              size: 16,
                              color: Color(0xFFD4A843),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '新掌握 ${mastered.length} 个词',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF3D7A6E),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: mastered
                              .map((word) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: const Color(0xFFD4EDE4)),
                                    ),
                                    child: Text(
                                      word,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2E3038),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  _encouragementForAccuracy(accuracy, mastered.length),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8A8D98),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    color: const Color(0xFF2E3038),
                    borderRadius: BorderRadius.circular(18),
                    onPressed: () {
                      Navigator.of(context).pop();
                      outerNav.pop();
                    },
                    child: const Text(
                      '继续',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    _showingSummary = false;
  }

  String _encouragementForAccuracy(int accuracy, int masteredCount) {
    if (masteredCount >= 3) return '进步很大，词语们在花园里扎下根了';
    if (accuracy >= 90) return '太棒了，你的词语花园越来越茂盛';
    if (accuracy >= 70) return '做得很好，继续浇灌你的词语花园';
    return '每次练习都有收获，慢慢来就好';
  }

  BoxDecoration _glassDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: .58),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: .76)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF7E8BA3).withValues(alpha: .13),
          blurRadius: 28,
          offset: const Offset(0, 16),
        ),
      ],
    );
  }
}

enum _TrainingSummarySection { mastered, learning, allWords }

class RehabTrainingSummaryPage extends StatefulWidget {
  const RehabTrainingSummaryPage({super.key});

  @override
  State<RehabTrainingSummaryPage> createState() =>
      _RehabTrainingSummaryPageState();
}

class _RehabTrainingSummaryPageState extends State<RehabTrainingSummaryPage> {
  final RehabTrainingStore _store = RehabTrainingStore();
  final PersonalObjectStore _personalObjectStore = PersonalObjectStore();
  List<RehabTrainingWord> _words = const [];
  Map<String, RehabTrainingProgress> _progress = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await _store.loadAll();
    final personalObjects = await _personalObjectStore.loadAll();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _words = RehabTrainingDeck.words(personalObjects: personalObjects);
      _loading = false;
    });
  }

  List<RehabTrainingWord> _wordsFor(_TrainingSummarySection section) {
    return switch (section) {
      _TrainingSummarySection.mastered => _words.where((word) {
          final item = _progress[MulberrySymbolResolver.normalize(word.text)];
          return item != null && item.masteryLevel >= 3;
        }).toList(),
      _TrainingSummarySection.learning => _words.where((word) {
          final item = _progress[MulberrySymbolResolver.normalize(word.text)];
          return item != null && item.totalCount > 0 && item.masteryLevel < 3;
        }).toList(),
      _TrainingSummarySection.allWords => List<RehabTrainingWord>.of(_words),
    }
      ..sort((a, b) {
        final aProgress = _progress[MulberrySymbolResolver.normalize(a.text)];
        final bProgress = _progress[MulberrySymbolResolver.normalize(b.text)];
        final byPractice =
            (bProgress?.totalCount ?? 0).compareTo(aProgress?.totalCount ?? 0);
        if (byPractice != 0) return byPractice;
        return a.text.compareTo(b.text);
      });
  }

  Future<void> _openSection(_TrainingSummarySection section) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _TrainingWordListPage(
          section: section,
          words: _wordsFor(section),
          progress: _progress,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mastered = _wordsFor(_TrainingSummarySection.mastered);
    final learning = _wordsFor(_TrainingSummarySection.learning);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2EA),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FBFF), Color(0xFFEFF5FF), Color(0xFFF7F2EA)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _GlassIconButton(
                            icon: CupertinoIcons.chevron_left,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '学习总结',
                                  style: TextStyle(
                                    fontSize: 28,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2E3038),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '看看哪些词已经熟悉，哪些还在练',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8A8D98),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: ListView(
                          children: [
                            _SummaryHeroCard(
                              masteredCount: mastered.length,
                              learningCount: learning.length,
                              totalCount: _words.length,
                            ),
                            const SizedBox(height: 14),
                            _SummarySectionCard(
                              icon: CupertinoIcons.check_mark_circled_solid,
                              title: '已掌握词汇',
                              count: mastered.length,
                              color: const Color(0xFF7A9E9F),
                              onTap: () => _openSection(
                                _TrainingSummarySection.mastered,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _SummarySectionCard(
                              icon: CupertinoIcons.flame_fill,
                              title: '正在学习',
                              count: learning.length,
                              color: const Color(0xFFD7A86E),
                              onTap: () => _openSection(
                                _TrainingSummarySection.learning,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _SummarySectionCard(
                              icon: CupertinoIcons.square_grid_2x2_fill,
                              title: '全部词表',
                              count: _words.length,
                              color: const Color(0xFF8D9DC2),
                              onTap: () => _openSection(
                                _TrainingSummarySection.allWords,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SummaryHeroCard extends StatelessWidget {
  const _SummaryHeroCard({
    required this.masteredCount,
    required this.learningCount,
    required this.totalCount,
  });

  final int masteredCount;
  final int learningCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final progress =
        totalCount <= 0 ? 0.0 : (masteredCount / totalCount).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _summaryGlassDecoration(),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: CustomPaint(
              painter: _SummaryRingPainter(progress: progress),
              child: Center(
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E3038),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '词汇掌握进度',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E3038),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已掌握 $masteredCount 个，正在学习 $learningCount 个',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7D8490),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummarySectionCard extends StatelessWidget {
  const _SummarySectionCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _summaryGlassDecoration(),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: Color(0xFF8A8D98),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingWordListPage extends StatelessWidget {
  const _TrainingWordListPage({
    required this.section,
    required this.words,
    required this.progress,
  });

  final _TrainingSummarySection section;
  final List<RehabTrainingWord> words;
  final Map<String, RehabTrainingProgress> progress;

  String get _title => switch (section) {
        _TrainingSummarySection.mastered => '已掌握词汇',
        _TrainingSummarySection.learning => '正在学习',
        _TrainingSummarySection.allWords => '全部词表',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2EA),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FBFF), Color(0xFFEFF5FF), Color(0xFFF7F2EA)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    _GlassIconButton(
                      icon: CupertinoIcons.chevron_left,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2E3038),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: words.isEmpty
                      ? _SummaryEmptyState(title: _title)
                      : ListView.separated(
                          itemCount: words.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final word = words[index];
                            final item = progress[
                                MulberrySymbolResolver.normalize(word.text)];
                            return _TrainingWordListTile(
                              word: word,
                              progress: item,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainingWordListTile extends StatelessWidget {
  const _TrainingWordListTile({
    required this.word,
    required this.progress,
  });

  final RehabTrainingWord word;
  final RehabTrainingProgress? progress;

  @override
  Widget build(BuildContext context) {
    final item = progress;
    final status = item == null || item.totalCount == 0
        ? '未开始'
        : '掌握 ${item.masteryLevel}/5 · 答对 ${item.correctCount} 次';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _summaryGlassDecoration(),
      child: Row(
        children: [
          _TrainingWordVisual(
            word: word,
            size: 58,
            backgroundColor: Colors.white.withValues(alpha: .86),
            padding: 8,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E3038),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${word.category} · $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8A8D98),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryEmptyState extends StatelessWidget {
  const _SummaryEmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _summaryGlassDecoration(),
        child: Text(
          '$title 还没有词汇',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFF7D8490),
          ),
        ),
      ),
    );
  }
}

class _SummaryRingPainter extends CustomPainter {
  const _SummaryRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .72);
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF7A9E9F);
    canvas.drawCircle(center, radius, basePaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SummaryRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

BoxDecoration _summaryGlassDecoration() {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: .62),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.white.withValues(alpha: .78)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF7E8BA3).withValues(alpha: .12),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

class _TrainingWordVisual extends StatelessWidget {
  const _TrainingWordVisual({
    required this.word,
    required this.size,
    required this.backgroundColor,
    required this.padding,
  });

  final RehabTrainingWord word;
  final double size;
  final Color backgroundColor;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final imagePath = word.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (file.existsSync()) {
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(padding * .45),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(size * .22),
            border: Border.all(color: Colors.white.withValues(alpha: .74)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .18),
            child: Image.file(file, fit: BoxFit.cover),
          ),
        );
      }
    }
    return MulberrySymbolIcon(
      text: word.text,
      size: size,
      padding: padding,
      backgroundColor: backgroundColor,
    );
  }
}

class _DifficultySheet extends StatelessWidget {
  const _DifficultySheet({required this.current});

  final RehabTrainingDifficulty current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .82)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7E8BA3).withValues(alpha: .18),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '训练难度',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '调整选项之间的相似程度',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A8D98),
                ),
              ),
              const SizedBox(height: 16),
              for (final difficulty in RehabTrainingDifficulty.values) ...[
                _DifficultyOption(
                  difficulty: difficulty,
                  selected: difficulty == current,
                ),
                if (difficulty != RehabTrainingDifficulty.values.last)
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyOption extends StatelessWidget {
  const _DifficultyOption({
    required this.difficulty,
    required this.selected,
  });

  final RehabTrainingDifficulty difficulty;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      RehabTrainingDifficulty.easy => const Color(0xFF7A9E9F),
      RehabTrainingDifficulty.standard => const Color(0xFFD7A86E),
      RehabTrainingDifficulty.hard => const Color(0xFFD77F8B),
    };
    final icon = switch (difficulty) {
      RehabTrainingDifficulty.easy => CupertinoIcons.circle_grid_3x3_fill,
      RehabTrainingDifficulty.standard => CupertinoIcons.square_grid_2x2_fill,
      RehabTrainingDifficulty.hard => CupertinoIcons.scope,
    };
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(difficulty),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: .16) : const Color(0xFFF6F7FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white.withValues(alpha: .9),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    difficulty.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2E3038),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    difficulty.description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8A8D98),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: color,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _TrainingOptionStyle {
  const _TrainingOptionStyle({
    required this.background,
    required this.shadow,
  });

  final Color background;
  final Color shadow;
}

const List<_TrainingOptionStyle> _trainingOptionStyles = [
  _TrainingOptionStyle(
    background: Color(0xFFFFE2C8),
    shadow: Color(0xFFFFB36C),
  ),
  _TrainingOptionStyle(
    background: Color(0xFFDCD9FF),
    shadow: Color(0xFF9B91FF),
  ),
  _TrainingOptionStyle(
    background: Color(0xFFC9F1E8),
    shadow: Color(0xFF5BCDBB),
  ),
  _TrainingOptionStyle(
    background: Color(0xFFFFC9CC),
    shadow: Color(0xFFFF7B82),
  ),
];

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.text,
    required this.selectedText,
    required this.answerText,
    required this.styleIndex,
    required this.onTap,
  });

  final String text;
  final String? selectedText;
  final String answerText;
  final int styleIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalized = MulberrySymbolResolver.normalize(text);
    final selected = selectedText != null &&
        MulberrySymbolResolver.normalize(selectedText!) == normalized;
    final answer = MulberrySymbolResolver.normalize(answerText) == normalized;
    final revealed = selectedText != null;
    final style =
        _trainingOptionStyles[styleIndex % _trainingOptionStyles.length];
    final correctAnswer = revealed && answer;
    final wrongSelection = selected && !answer;
    final borderColor = correctAnswer
        ? const Color(0xFF2F8F68)
        : wrongSelection
            ? const Color(0xFFE05858)
            : Colors.white.withValues(alpha: .72);
    final foregroundColor = correctAnswer
        ? const Color(0xFF1F6F52)
        : wrongSelection
            ? const Color(0xFFA83E3E)
            : const Color(0xFF2E3038);
    final badgeColor = correctAnswer
        ? const Color(0xFF2F8F68)
        : wrongSelection
            ? const Color(0xFFE05858)
            : Colors.transparent;
    return GestureDetector(
      onTap: revealed ? null : onTap,
      child: AnimatedScale(
        scale: selected || correctAnswer ? 1.025 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: borderColor,
              width: revealed ? 3.2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (correctAnswer || wrongSelection
                        ? borderColor
                        : style.shadow)
                    .withValues(
                        alpha: correctAnswer || wrongSelection
                            ? .24
                            : revealed
                                ? .08
                                : .18),
                blurRadius: correctAnswer || wrongSelection ? 24 : 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: foregroundColor,
                  ),
                ),
              ),
              if (correctAnswer || wrongSelection)
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .95),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: .24),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      correctAnswer
                          ? CupertinoIcons.check_mark
                          : CupertinoIcons.xmark,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatefulWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.size = 46,
    this.active = false,
    this.activeColor = const Color(0xFF4E8FD8),
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;
  final Color activeColor;

  @override
  State<_GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<_GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final active = widget.active;
    return GestureDetector(
      onTapDown: (_) {
        if (!mounted) return;
        setState(() => _pressed = true);
      },
      onTapCancel: () {
        if (!mounted) return;
        setState(() => _pressed = false);
      },
      onTapUp: (_) {
        if (!mounted) return;
        setState(() => _pressed = false);
      },
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _pressed
              ? const Color(0xFFD0D0D0).withValues(alpha: .64)
              : Colors.white.withValues(alpha: .64),
          borderRadius: BorderRadius.circular(size * .34),
          border: Border.all(color: Colors.white.withValues(alpha: .82)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7E8BA3).withValues(alpha: .12),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          widget.icon,
          color: active ? widget.activeColor : const Color(0xFF4D525E),
          size: size * .48,
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A8D98),
          ),
        ),
      ],
    );
  }
}
