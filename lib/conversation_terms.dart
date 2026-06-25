import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ConversationTermCandidate {
  const ConversationTermCandidate({
    required this.text,
    required this.type,
    this.confidence = 0.8,
  });

  final String text;
  final String type;
  final double confidence;

  String get normalizedText => normalizeConversationTerm(text);
}

class ConversationTerm {
  const ConversationTerm({
    required this.id,
    required this.text,
    required this.normalizedText,
    required this.type,
    required this.count,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final String id;
  final String text;
  final String normalizedText;
  final String type;
  final int count;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  ConversationTerm copyWith({
    String? text,
    String? type,
    int? count,
    DateTime? lastUsedAt,
  }) {
    return ConversationTerm(
      id: id,
      text: text ?? this.text,
      normalizedText: normalizeConversationTerm(text ?? this.text),
      type: type ?? this.type,
      count: count ?? this.count,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'normalizedText': normalizedText,
        'type': type,
        'count': count,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory ConversationTerm.fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString().trim() ?? '';
    return ConversationTerm(
      id: json['id']?.toString() ?? text,
      text: text,
      normalizedText:
          json['normalizedText']?.toString() ?? normalizeConversationTerm(text),
      type: normalizeConversationTermType(json['type']?.toString()),
      count: (json['count'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ConversationTermStore {
  static const _storageKey = 'conversation_special_terms_v1';

  Future<List<ConversationTerm>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    final terms = raw
        .map((value) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map<String, dynamic>) {
              return ConversationTerm.fromJson(decoded);
            }
          } catch (_) {}
          return null;
        })
        .whereType<ConversationTerm>()
        .where((term) {
          return term.text.isNotEmpty && term.normalizedText.isNotEmpty;
        })
        .toList();
    terms.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return terms;
  }

  Future<ConversationTerm> confirm(ConversationTermCandidate candidate) async {
    final terms = await loadAll();
    final normalized = candidate.normalizedText;
    final index = terms.indexWhere((term) => term.normalizedText == normalized);
    final now = DateTime.now();
    late final ConversationTerm saved;
    if (index >= 0) {
      saved = terms[index].copyWith(
        text: candidate.text.trim(),
        type: normalizeConversationTermType(candidate.type),
        count: terms[index].count + 1,
        lastUsedAt: now,
      );
      terms[index] = saved;
    } else {
      saved = ConversationTerm(
        id: 'conversation_term_${now.microsecondsSinceEpoch}',
        text: candidate.text.trim(),
        normalizedText: normalized,
        type: normalizeConversationTermType(candidate.type),
        count: 1,
        createdAt: now,
        lastUsedAt: now,
      );
      terms.insert(0, saved);
    }
    await _save(terms);
    return saved;
  }

  Future<void> _save(List<ConversationTerm> terms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      terms.map((term) => jsonEncode(term.toJson())).toList(),
    );
  }
}

String normalizeConversationTerm(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s，。！？、,.!?：:；;（）()]'), '');
}

String normalizeConversationTermType(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'person':
    case '人物':
    case '人名':
      return 'person';
    case 'place':
    case '地点':
    case '地名':
      return 'place';
    case 'organization':
    case '机构':
    case '组织':
      return 'organization';
    default:
      return 'custom';
  }
}

String conversationTermTypeLabel(String type) {
  switch (normalizeConversationTermType(type)) {
    case 'person':
      return '人名';
    case 'place':
      return '地点';
    case 'organization':
      return '机构';
    default:
      return '特殊词汇';
  }
}
