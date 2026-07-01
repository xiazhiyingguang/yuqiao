import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class ExpressionHabit {
  const ExpressionHabit({
    required this.text,
    required this.normalizedText,
    required this.category,
    required this.source,
    required this.count,
    required this.firstUsedAt,
    required this.lastUsedAt,
    required this.timeBuckets,
    required this.placeTypes,
    required this.sources,
    required this.categories,
    this.favorite = false,
  });

  final String text;
  final String normalizedText;
  final String category;
  final String source;
  final int count;
  final DateTime firstUsedAt;
  final DateTime lastUsedAt;
  final Map<String, int> timeBuckets;
  final Map<String, int> placeTypes;
  final Map<String, int> sources;
  final Map<String, int> categories;
  final bool favorite;

  ExpressionHabit copyWith({
    String? text,
    String? normalizedText,
    String? category,
    String? source,
    int? count,
    DateTime? firstUsedAt,
    DateTime? lastUsedAt,
    Map<String, int>? timeBuckets,
    Map<String, int>? placeTypes,
    Map<String, int>? sources,
    Map<String, int>? categories,
    bool? favorite,
  }) {
    return ExpressionHabit(
      text: text ?? this.text,
      normalizedText: normalizedText ?? this.normalizedText,
      category: category ?? this.category,
      source: source ?? this.source,
      count: count ?? this.count,
      firstUsedAt: firstUsedAt ?? this.firstUsedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      timeBuckets: timeBuckets ?? this.timeBuckets,
      placeTypes: placeTypes ?? this.placeTypes,
      sources: sources ?? this.sources,
      categories: categories ?? this.categories,
      favorite: favorite ?? this.favorite,
    );
  }

  double scoreFor({
    String? category,
    String? source,
    String? timeBucket,
    String? placeType,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final ageHours = current.difference(lastUsedAt).inHours;
    final recency = math.max(0.0, 260.0 - ageHours * 1.6);
    final frequency = math.min(count, 30) * 72.0;
    final categoryBonus = category != null &&
            category.isNotEmpty &&
            categories.containsKey(category)
        ? 180.0 + math.min(categories[category]!, 8) * 18.0
        : 0.0;
    final sourceBonus =
        source != null && source.isNotEmpty && sources.containsKey(source)
            ? 80.0 + math.min(sources[source]!, 8) * 12.0
            : 0.0;
    final timeBonus = timeBucket != null && timeBuckets.containsKey(timeBucket)
        ? 120.0 + math.min(timeBuckets[timeBucket]!, 8) * 16.0
        : 0.0;
    final placeBonus = placeType != null && placeTypes.containsKey(placeType)
        ? 140.0 + math.min(placeTypes[placeType]!, 8) * 16.0
        : 0.0;
    final favoriteBonus = favorite ? 180.0 : 0.0;
    return frequency +
        recency +
        categoryBonus +
        sourceBonus +
        timeBonus +
        placeBonus +
        favoriteBonus;
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'normalizedText': normalizedText,
        'category': category,
        'source': source,
        'count': count,
        'firstUsedAt': firstUsedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
        'timeBuckets': timeBuckets,
        'placeTypes': placeTypes,
        'sources': sources,
        'categories': categories,
        'favorite': favorite,
      };

  static ExpressionHabit? fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString().trim() ?? '';
    final normalized =
        json['normalizedText']?.toString().trim() ?? normalizeHabitText(text);
    final firstUsedAt =
        DateTime.tryParse(json['firstUsedAt']?.toString() ?? '');
    final lastUsedAt = DateTime.tryParse(json['lastUsedAt']?.toString() ?? '');
    if (text.isEmpty ||
        normalized.isEmpty ||
        firstUsedAt == null ||
        lastUsedAt == null) {
      return null;
    }
    return ExpressionHabit(
      text: text,
      normalizedText: normalized,
      category: json['category']?.toString().trim() ?? 'expression',
      source: json['source']?.toString().trim() ?? 'unknown',
      count: (json['count'] as num?)?.toInt() ?? 1,
      firstUsedAt: firstUsedAt,
      lastUsedAt: lastUsedAt,
      timeBuckets: _intMap(json['timeBuckets']),
      placeTypes: _intMap(json['placeTypes']),
      sources: _intMap(json['sources']),
      categories: _intMap(json['categories']),
      favorite: json['favorite'] == true,
    );
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) {
      final count = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      return MapEntry('$key', count);
    })
      ..removeWhere((key, value) => key.trim().isEmpty || value <= 0);
  }
}

class ExpressionHabitStore {
  static const _storageKey = 'expression_habits_v1';
  static const _enabledKey = 'expression_habits_enabled_v1';
  static const _maxHabits = 160;

  Future<bool> loadEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }

  Future<List<ExpressionHabit>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <ExpressionHabit>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ExpressionHabit>[];
      return decoded
          .whereType<Map>()
          .map((item) => ExpressionHabit.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .whereType<ExpressionHabit>()
          .toList()
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    } catch (_) {
      return <ExpressionHabit>[];
    }
  }

  Future<void> recordUsed(
    String text, {
    required String category,
    required String source,
    String? placeType,
    bool favorite = false,
    DateTime? usedAt,
  }) async {
    final clean = _cleanText(text);
    final normalized = normalizeHabitText(clean);
    if (clean.isEmpty || normalized.isEmpty) return;
    final now = usedAt ?? DateTime.now();
    final timeBucket = bucketFor(now);
    final habits = List<ExpressionHabit>.of(await loadAll());
    final index =
        habits.indexWhere((habit) => habit.normalizedText == normalized);

    Map<String, int> inc(Map<String, int> input, String key) {
      final cleanKey = key.trim();
      if (cleanKey.isEmpty) return Map<String, int>.from(input);
      return Map<String, int>.from(input)
        ..update(cleanKey, (value) => value + 1, ifAbsent: () => 1);
    }

    if (index >= 0) {
      final existing = habits[index];
      habits[index] = existing.copyWith(
        text: clean,
        category: category.isEmpty ? existing.category : category,
        source: source.isEmpty ? existing.source : source,
        count: existing.count + 1,
        lastUsedAt: now,
        timeBuckets: inc(existing.timeBuckets, timeBucket),
        placeTypes: placeType == null
            ? existing.placeTypes
            : inc(existing.placeTypes, placeType),
        sources: inc(existing.sources, source),
        categories: inc(existing.categories, category),
        favorite: existing.favorite || favorite,
      );
    } else {
      habits.add(
        ExpressionHabit(
          text: clean,
          normalizedText: normalized,
          category: category,
          source: source,
          count: 1,
          firstUsedAt: now,
          lastUsedAt: now,
          timeBuckets: {timeBucket: 1},
          placeTypes: placeType == null || placeType.trim().isEmpty
              ? const {}
              : {placeType.trim(): 1},
          sources: source.trim().isEmpty ? const {} : {source.trim(): 1},
          categories: category.trim().isEmpty ? const {} : {category.trim(): 1},
          favorite: favorite,
        ),
      );
    }

    habits.sort((a, b) {
      final score = b.scoreFor(now: now).compareTo(a.scoreFor(now: now));
      return score != 0 ? score : b.lastUsedAt.compareTo(a.lastUsedAt);
    });
    final trimmed = habits.take(_maxHabits).toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(trimmed.map((habit) => habit.toJson()).toList()),
    );
  }

  Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  static String bucketFor(DateTime value) {
    final hour = value.hour;
    if (hour >= 5 && hour < 11) return 'morning';
    if (hour >= 11 && hour < 14) return 'noon';
    if (hour >= 14 && hour < 18) return 'afternoon';
    if (hour >= 18 && hour < 24) return 'evening';
    return 'night';
  }

  static List<ExpressionHabit> rank(
    Iterable<ExpressionHabit> habits, {
    String? category,
    String? source,
    String? timeBucket,
    String? placeType,
    int limit = 12,
  }) {
    final now = DateTime.now();
    final ranked = habits.toList()
      ..sort((a, b) {
        final score = b
            .scoreFor(
              category: category,
              source: source,
              timeBucket: timeBucket,
              placeType: placeType,
              now: now,
            )
            .compareTo(
              a.scoreFor(
                category: category,
                source: source,
                timeBucket: timeBucket,
                placeType: placeType,
                now: now,
              ),
            );
        return score != 0 ? score : b.lastUsedAt.compareTo(a.lastUsedAt);
      });
    return ranked.take(limit).toList(growable: false);
  }

  static String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'^\s*\d+[.、）)]\s*'), '')
        .replaceAll(RegExp(r'^["“”]+|["“”]+$'), '')
        .trim();
  }
}

String normalizeHabitText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s，。！？、,.!?：:；;（）()【】\[\]「」『』"“”‘’]'), '')
      .trim();
}
