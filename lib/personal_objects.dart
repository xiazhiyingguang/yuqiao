import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersonalObject {
  const PersonalObject({
    required this.id,
    required this.displayName,
    required this.category,
    required this.visualDescription,
    required this.referenceImagePath,
    required this.commonExpressions,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    this.usageCount = 0,
  });

  final String id;
  final String displayName;
  final String category;
  final String visualDescription;
  final String referenceImagePath;
  final List<String> commonExpressions;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int usageCount;

  PersonalObject copyWith({
    String? displayName,
    String? category,
    String? visualDescription,
    String? referenceImagePath,
    List<String>? commonExpressions,
    String? note,
    DateTime? updatedAt,
    int? usageCount,
  }) {
    return PersonalObject(
      id: id,
      displayName: displayName ?? this.displayName,
      category: category ?? this.category,
      visualDescription: visualDescription ?? this.visualDescription,
      referenceImagePath: referenceImagePath ?? this.referenceImagePath,
      commonExpressions: commonExpressions ?? this.commonExpressions,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      usageCount: usageCount ?? this.usageCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'category': category,
        'visualDescription': visualDescription,
        'referenceImagePath': referenceImagePath,
        'commonExpressions': commonExpressions,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'usageCount': usageCount,
      };

  factory PersonalObject.fromJson(Map<String, dynamic> json) {
    return PersonalObject(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? '',
      category: json['category'] as String? ?? '其他',
      visualDescription: json['visualDescription'] as String? ?? '',
      referenceImagePath: json['referenceImagePath'] as String? ?? '',
      commonExpressions: (json['commonExpressions'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class PersonalObjectDraft {
  const PersonalObjectDraft({
    required this.displayName,
    required this.category,
    required this.visualDescription,
    required this.commonExpressions,
    required this.note,
  });

  final String displayName;
  final String category;
  final String visualDescription;
  final List<String> commonExpressions;
  final String note;
}

class PersonalObjectStore {
  static const _storageKey = 'personal_objects_v1';

  Future<List<PersonalObject>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    final objects = raw
        .map((item) {
          try {
            final json = jsonDecode(item);
            return json is Map<String, dynamic>
                ? PersonalObject.fromJson(json)
                : null;
          } catch (_) {
            return null;
          }
        })
        .whereType<PersonalObject>()
        .toList();
    objects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return objects;
  }

  Future<PersonalObject> create({
    required PersonalObjectDraft draft,
    required Uint8List referenceImageBytes,
  }) async {
    final now = DateTime.now();
    final id = 'personal_object_${now.microsecondsSinceEpoch}';
    final directory = await _objectDirectory();
    final imagePath = '${directory.path}${Platform.pathSeparator}$id.jpg';
    final imageInput = Uint8List.fromList(referenceImageBytes);
    final optimizedBytes = await Isolate.run(
      () => _optimizeReferenceImage(imageInput),
    );
    await File(imagePath).writeAsBytes(optimizedBytes, flush: true);
    final object = PersonalObject(
      id: id,
      displayName: draft.displayName.trim(),
      category: draft.category.trim(),
      visualDescription: draft.visualDescription.trim(),
      referenceImagePath: imagePath,
      commonExpressions: _cleanExpressions(draft.commonExpressions),
      note: draft.note.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final objects = await loadAll();
    await _save([object, ...objects]);
    return object;
  }

  Future<void> update(PersonalObject object, PersonalObjectDraft draft) async {
    final objects = await loadAll();
    final updated = object.copyWith(
      displayName: draft.displayName.trim(),
      category: draft.category.trim(),
      visualDescription: draft.visualDescription.trim(),
      commonExpressions: _cleanExpressions(draft.commonExpressions),
      note: draft.note.trim(),
      updatedAt: DateTime.now(),
    );
    await _save([
      for (final item in objects)
        if (item.id == object.id) updated else item,
    ]);
  }

  Future<void> delete(PersonalObject object) async {
    final objects = await loadAll();
    await _save(objects.where((item) => item.id != object.id).toList());
    final image = File(object.referenceImagePath);
    if (await image.exists()) await image.delete();
  }

  Future<void> markUsed(String id) async {
    final objects = await loadAll();
    await _save([
      for (final item in objects)
        if (item.id == id)
          item.copyWith(
            usageCount: item.usageCount + 1,
            updatedAt: DateTime.now(),
          )
        else
          item,
    ]);
  }

  Future<void> _save(List<PersonalObject> objects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      objects.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<Directory> _objectDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}personal_objects',
    ).create(recursive: true);
  }

  static List<String> _cleanExpressions(List<String> values) {
    final seen = <String>{};
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .take(6)
        .toList();
  }
}

Uint8List _optimizeReferenceImage(Uint8List bytes) {
  var image = image_lib.decodeImage(bytes);
  if (image == null) return bytes;
  image = image_lib.bakeOrientation(image);
  const maxSide = 960;
  if (image.width > maxSide || image.height > maxSide) {
    image = image_lib.copyResize(
      image,
      width: image.width >= image.height ? maxSide : null,
      height: image.height > image.width ? maxSide : null,
      interpolation: image_lib.Interpolation.average,
    );
  }
  return Uint8List.fromList(image_lib.encodeJpg(image, quality: 76));
}
