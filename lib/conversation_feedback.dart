import 'dart:convert';

import 'sensitive_local_store.dart';

class ConversationFeedbackProfile {
  const ConversationFeedbackProfile({
    required this.preferredTypes,
    required this.rejectedCandidates,
  });

  final List<String> preferredTypes;
  final List<String> rejectedCandidates;
}

class ConversationFeedbackStore {
  static const _storageKey = 'conversation_candidate_feedback_v1';
  static const _maxEntries = 60;

  Future<void> recordAccepted({
    required String contextKey,
    required String candidate,
  }) {
    return _record(
      contextKey: contextKey,
      candidate: candidate,
      accepted: true,
    );
  }

  Future<void> recordRejectedBatch({
    required String contextKey,
    required List<String> candidates,
  }) async {
    for (final candidate in candidates) {
      await _record(
        contextKey: contextKey,
        candidate: candidate,
        accepted: false,
      );
    }
  }

  Future<ConversationFeedbackProfile> profileFor(String contextKey) async {
    final entries = await _load();
    final matching = entries.where((entry) => entry.contextKey == contextKey);
    final typeScores = <String, int>{};
    final rejectedScores = <String, int>{};
    for (final entry in matching) {
      if (entry.accepted) {
        typeScores.update(entry.type, (value) => value + 1, ifAbsent: () => 1);
      } else {
        rejectedScores.update(entry.candidate, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    final preferredTypes = typeScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rejectedCandidates = rejectedScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ConversationFeedbackProfile(
      preferredTypes: preferredTypes.take(3).map((entry) => entry.key).toList(),
      rejectedCandidates:
          rejectedCandidates.take(12).map((entry) => entry.key).toList(),
    );
  }

  Future<void> _record({
    required String contextKey,
    required String candidate,
    required bool accepted,
  }) async {
    final normalizedCandidate = candidate.trim();
    if (contextKey.isEmpty || normalizedCandidate.isEmpty) return;
    final entries = await _load();
    entries.add(_ConversationFeedbackEntry(
      contextKey: contextKey,
      candidate: normalizedCandidate,
      accepted: accepted,
      createdAt: DateTime.now(),
    ));
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    await SensitiveLocalStore.writeString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<List<_ConversationFeedbackEntry>> _load() async {
    final raw = await SensitiveLocalStore.readString(
      _storageKey,
      legacySharedPreferencesKey: _storageKey,
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => _ConversationFeedbackEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .whereType<_ConversationFeedbackEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class _ConversationFeedbackEntry {
  const _ConversationFeedbackEntry({
    required this.contextKey,
    required this.candidate,
    required this.accepted,
    required this.createdAt,
  });

  final String contextKey;
  final String candidate;
  final bool accepted;
  final DateTime createdAt;

  String get type {
    final separator = candidate.indexOf(RegExp(r'[：:]'));
    return separator > 0 ? candidate.substring(0, separator).trim() : '其他';
  }

  Map<String, dynamic> toJson() => {
        'contextKey': contextKey,
        'candidate': candidate,
        'accepted': accepted,
        'createdAt': createdAt.toIso8601String(),
      };

  static _ConversationFeedbackEntry? fromJson(Map<String, dynamic> json) {
    final contextKey = json['contextKey'];
    final candidate = json['candidate'];
    final accepted = json['accepted'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (contextKey is! String ||
        candidate is! String ||
        accepted is! bool ||
        createdAt == null) {
      return null;
    }
    return _ConversationFeedbackEntry(
      contextKey: contextKey,
      candidate: candidate,
      accepted: accepted,
      createdAt: createdAt,
    );
  }
}
