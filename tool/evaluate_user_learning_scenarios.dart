import 'dart:io';

class LearningScenario {
  const LearningScenario({
    required this.name,
    required this.acceptedText,
    required this.targetCandidate,
    required this.candidates,
  });

  final String name;
  final String acceptedText;
  final String targetCandidate;
  final List<String> candidates;
}

class ScenarioResult {
  const ScenarioResult({
    required this.uses,
    required this.rank,
    required this.score,
  });

  final int uses;
  final int rank;
  final double score;
}

class _Event {
  const _Event({
    required this.text,
    required this.action,
    this.placeType = 'unknown',
    this.intentTag = 'say_sentence',
  });

  final String text;
  final String action;
  final String placeType;
  final String intentTag;

  bool get isPositive {
    return action == 'accepted' || action == 'spoken' || action == 'saved';
  }

  bool get isNegative {
    return action == 'rejected' || action == 'skipped' || action == 'deleted';
  }
}

class _Profile {
  _Profile(List<_Event> events) {
    for (final event in events) {
      final normalized = _normalize(event.text);
      final signature = _semanticSignature(event.text);
      final lengthBucket = _lengthBucket(event.text);
      if (event.isPositive) {
        _expressionPositive[normalized] =
            (_expressionPositive[normalized] ?? 0) + 1;
        _semanticPositive[signature] = (_semanticPositive[signature] ?? 0) + 1;
        _intentPositive[_intentKey(event)] =
            (_intentPositive[_intentKey(event)] ?? 0) + 1;
        if (event.placeType != 'unknown') {
          _placeIntentPositive[_placeIntentKey(event)] =
              (_placeIntentPositive[_placeIntentKey(event)] ?? 0) + 1;
        }
        _lengthScores[lengthBucket] = (_lengthScores[lengthBucket] ?? 0) + 1;
      } else if (event.isNegative) {
        _expressionNegative[normalized] =
            (_expressionNegative[normalized] ?? 0) + 1;
        _semanticNegative[signature] = (_semanticNegative[signature] ?? 0) + 1;
        _lengthScores[lengthBucket] = (_lengthScores[lengthBucket] ?? 0) - 1.2;
      }
    }
  }

  final Map<String, int> _expressionPositive = {};
  final Map<String, int> _expressionNegative = {};
  final Map<String, int> _semanticPositive = {};
  final Map<String, int> _semanticNegative = {};
  final Map<String, int> _intentPositive = {};
  final Map<String, int> _placeIntentPositive = {};
  final Map<String, double> _lengthScores = {
    'short': 0,
    'medium': 0,
    'long': 0,
  };

  double expressionScore(String text) {
    final normalized = _normalize(text);
    final signature = _semanticSignature(text);
    final exactPositive = _expressionPositive[normalized] ?? 0;
    final exactNegative = _expressionNegative[normalized] ?? 0;
    final semanticPositive = _weightedSemanticCount(
      _semanticPositive,
      signature,
    );
    final semanticNegative = _weightedSemanticCount(
      _semanticNegative,
      signature,
    );
    final lengthScore = (_lengthScores[_lengthBucket(text)] ?? 0) * 24.0;
    return exactPositive * 150.0 -
        exactNegative * 360.0 +
        semanticPositive * 80.0 -
        semanticNegative * 160.0 +
        lengthScore.clamp(-120.0, 120.0);
  }

  double contextualScore(
    String text, {
    required String feature,
    required String placeType,
    required String slotName,
  }) {
    final signature = _semanticSignature(text);
    var score = 0.0;
    for (final entry in _intentPositive.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 3) continue;
      if (parts[0] != feature || parts[1] != slotName) continue;
      if (_intentMatchesSignature(parts[2], signature)) {
        score += entry.value * 28.0;
      }
    }
    for (final entry in _placeIntentPositive.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 4) continue;
      if (parts[0] != placeType || parts[1] != feature) continue;
      if (_intentMatchesSignature(parts[3], signature)) {
        score += entry.value * 44.0;
      }
    }
    return score.clamp(0.0, 360.0).toDouble();
  }

  static String _intentKey(_Event event) {
    return 'conversation|sentence|${event.intentTag}';
  }

  static String _placeIntentKey(_Event event) {
    return '${event.placeType}|conversation|sentence|${event.intentTag}';
  }
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final scenarios = [
    const LearningScenario(
      name: 'hospital-doctor-help',
      acceptedText: 'ask doctor',
      targetCandidate: 'call doctor',
      candidates: ['open window', 'call doctor', 'play music'],
    ),
    const LearningScenario(
      name: 'home-water-need',
      acceptedText: 'drink water',
      targetCandidate: 'need water',
      candidates: ['watch TV', 'need water', 'open door'],
    ),
  ];

  for (final scenario in scenarios) {
    final results = [
      _evaluate(scenario, uses: 1),
      _evaluate(scenario, uses: 3),
      _evaluate(scenario, uses: 5),
    ];
    check(
      results[1].rank <= results[0].rank,
      '${scenario.name}: rank did not improve by use 3',
    );
    check(
      results[2].rank <= results[1].rank,
      '${scenario.name}: rank did not improve by use 5',
    );
    check(
      results[2].rank == 0,
      '${scenario.name}: target candidate should be first by use 5',
    );
    stdout.writeln(
      '${scenario.name}: '
      'use1 rank=${results[0].rank + 1} score=${results[0].score}; '
      'use3 rank=${results[1].rank + 1} score=${results[1].score}; '
      'use5 rank=${results[2].rank + 1} score=${results[2].score}',
    );
  }
  _evaluateNegativeFeedback();
  _evaluateExpressionStyle();
  _evaluateContextIntentGeneralization();
}

ScenarioResult _evaluate(LearningScenario scenario, {required int uses}) {
  final profile = _Profile([
    for (var index = 0; index < uses; index++)
      _Event(text: scenario.acceptedText, action: 'accepted'),
  ]);
  final ranked = [...scenario.candidates]..sort((a, b) {
      final scoreA =
          scenario.candidates.indexOf(a) * -350.0 + profile.expressionScore(a);
      final scoreB =
          scenario.candidates.indexOf(b) * -350.0 + profile.expressionScore(b);
      return scoreB.compareTo(scoreA);
    });
  return ScenarioResult(
    uses: uses,
    rank: ranked.indexOf(scenario.targetCandidate),
    score: profile.expressionScore(scenario.targetCandidate),
  );
}

double _weightedSemanticCount(Map<String, int> counts, String signature) {
  var total = 0.0;
  for (final entry in counts.entries) {
    total += entry.value * _overlapScore(entry.key, signature);
  }
  return total;
}

double _overlapScore(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final left = a.split('+').where((part) => part.isNotEmpty).toSet();
  final right = b.split('+').where((part) => part.isNotEmpty).toSet();
  if (left.isEmpty || right.isEmpty) return 0;
  final shared = left.intersection(right).length;
  if (shared == 0) return 0;
  return shared / (left.length < right.length ? left.length : right.length);
}

String _normalize(String text) {
  return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _semanticSignature(String text) {
  final normalized = _normalize(text);
  final groups = [
    for (final entry in _semanticKeywords.entries)
      if (entry.value.any((keyword) => normalized.contains(keyword))) entry.key,
  ];
  return groups.isEmpty ? normalized : groups.join('+');
}

String _lengthBucket(String text) {
  final length = _normalize(text).length;
  if (length <= 8) return 'short';
  if (length <= 20) return 'medium';
  return 'long';
}

void _evaluateNegativeFeedback() {
  final profile = _Profile([
    const _Event(text: 'play music', action: 'rejected'),
    const _Event(text: 'play music', action: 'skipped'),
    const _Event(text: 'play music', action: 'deleted'),
  ]);
  final score = profile.expressionScore('play music');
  check(score < 0, 'negative feedback should lower candidate score');
  stdout.writeln('negative-feedback: play music score=$score');
}

void _evaluateExpressionStyle() {
  final profile = _Profile([
    const _Event(text: 'yes', action: 'accepted'),
    const _Event(text: 'ok', action: 'spoken'),
    const _Event(text: 'wait', action: 'saved'),
    const _Event(
      text: 'please wait for a few minutes before leaving',
      action: 'rejected',
    ),
  ]);
  final shortScore = profile.expressionScore('yes');
  final longScore = profile.expressionScore('please wait for a few minutes');
  check(
    shortScore > longScore,
    'short-style preference should rank short candidate above long candidate',
  );
  stdout.writeln(
    'expression-style: short score=$shortScore long score=$longScore',
  );
}

void _evaluateContextIntentGeneralization() {
  final profile = _Profile([
    for (var index = 0; index < 4; index++)
      const _Event(
        text: 'what time is it',
        action: 'accepted',
        placeType: 'hospital',
        intentTag: 'ask_time',
      ),
  ]);
  final hospitalTimeScore = profile.contextualScore(
    'when is the appointment',
    feature: 'conversation',
    placeType: 'hospital',
    slotName: 'sentence',
  );
  final unrelatedScore = profile.contextualScore(
    'play music',
    feature: 'conversation',
    placeType: 'hospital',
    slotName: 'sentence',
  );
  final otherPlaceScore = profile.contextualScore(
    'when is the appointment',
    feature: 'conversation',
    placeType: 'home',
    slotName: 'sentence',
  );
  check(
    hospitalTimeScore > unrelatedScore,
    'context intent should prefer semantically related candidates',
  );
  check(
    hospitalTimeScore > otherPlaceScore,
    'place-specific intent should be stronger in the learned scene',
  );
  stdout.writeln(
    'context-intent: hospital time score=$hospitalTimeScore; '
    'other-place score=$otherPlaceScore; unrelated score=$unrelatedScore',
  );
}

bool _intentMatchesSignature(String intentTag, String signature) {
  final groups = signature.split('+').where((part) => part.isNotEmpty).toSet();
  final expected = _intentSemanticGroups[intentTag] ?? const <String>[];
  return expected.any(groups.contains);
}

const Map<String, List<String>> _semanticKeywords = {
  'doctor': ['doctor', 'nurse', 'caregiver', 'physician'],
  'time': ['time', 'clock', 'schedule', 'when', 'today', 'tomorrow'],
  'water': ['water', 'drink', 'cup'],
  'pain': ['pain', 'hurt', 'ache', 'uncomfortable'],
  'help': ['help', 'please', 'assist', 'need'],
};

const Map<String, List<String>> _intentSemanticGroups = {
  'ask_time': ['time'],
  'find_or_get': ['object', 'location'],
  'discomfort': ['pain'],
  'understand': ['repeat'],
  'clarify': ['repeat'],
  'request_help': ['help', 'doctor'],
  'say_sentence': ['doctor', 'time', 'water', 'pain', 'help'],
};
