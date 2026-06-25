import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'expression_habits.dart';

abstract interface class LocationDataStore {
  Future<bool> loadLocationRecommendationEnabled();

  Future<void> saveLocationRecommendationEnabled(bool enabled);

  Future<String?> loadLocationRecommendationData();

  Future<void> saveLocationRecommendationData(String data);

  Future<void> clearLocationRecommendationData();
}

abstract final class PlaceTypeCatalog {
  static const String home = 'home';
  static const String hospital = 'hospital';
  static const String supermarket = 'supermarket';
  static const String school = 'school';
  static const String park = 'park';
  static const String pharmacy = 'pharmacy';
  static const String rehabilitationCenter = 'rehabilitationCenter';
  static const String restaurant = 'restaurant';
  static const String transport = 'transport';
  static const String company = 'company';
  static const String residential = 'residential';
  static const String convenienceStore = 'convenienceStore';
  static const String shoppingMall = 'shoppingMall';
  static const String lifeService = 'lifeService';
  static const String unknown = 'unknown';

  static const List<String> editableTypes = [
    home,
    hospital,
    supermarket,
    school,
    park,
    pharmacy,
    rehabilitationCenter,
    restaurant,
    transport,
    company,
    residential,
    unknown,
  ];

  static const Map<String, String> labels = {
    home: '家',
    hospital: '医院',
    supermarket: '超市',
    school: '学校',
    park: '公园',
    pharmacy: '药店',
    rehabilitationCenter: '康复中心',
    restaurant: '餐厅',
    transport: '交通',
    company: '公司',
    residential: '小区',
    convenienceStore: '便利店',
    shoppingMall: '商场',
    lifeService: '生活服务',
    unknown: '其他',
  };

  static const Map<String, List<String>> sceneWords = {
    home: ['喝水', '吃饭', '休息', '睡觉', '疼', '帮我', '家人', '上厕所'],
    hospital: [
      '医生',
      '护士',
      '挂号',
      '检查',
      '取药',
      '哪里疼',
      '我不舒服',
      '缴费',
      '病历',
      '排队',
    ],
    pharmacy: ['买药', '感冒药', '止痛药', '处方', '多少钱', '过敏', '用法', '药店'],
    supermarket: ['买东西', '多少钱', '结账', '袋子', '饮料', '水', '面包', '找不到'],
    convenienceStore: ['买东西', '多少钱', '结账', '袋子', '饮料', '水', '找不到'],
    shoppingMall: ['买东西', '多少钱', '结账', '洗手间', '出口', '找不到'],
    restaurant: ['吃饭', '菜单', '点餐', '买单', '水', '不要辣', '打包', '谢谢'],
    school: ['老师', '同学', '上课', '作业', '请假', '书包', '教室', '放学'],
    park: ['散步', '休息', '厕所', '回家', '喝水', '太累了', '坐一会儿'],
    transport: ['坐车', '到哪里', '多少钱', '下车', '车站', '地铁', '出口', '回家'],
    rehabilitationCenter: ['康复', '训练', '疼', '休息', '治疗师', '慢一点', '我累了', '继续'],
    company: ['同事', '开会', '文件', '请假', '休息', '帮我', '下班'],
    residential: ['回家', '上楼', '下楼', '门口', '家人', '帮我', '休息'],
    lifeService: ['多少钱', '帮我', '在哪里', '谢谢'],
    unknown: ['喝水', '帮我', '回家', '疼', '吃饭', '休息', '谢谢'],
  };

  static String labelOf(String? type) => labels[normalize(type)] ?? '其他';

  static List<String> wordsFor(String? type) =>
      sceneWords[normalize(type)] ?? sceneWords[unknown]!;

  static String normalize(String? value) {
    final raw = value?.trim() ?? '';
    if (labels.containsKey(raw)) return raw;
    const legacy = {
      '家': home,
      '医院': hospital,
      '超市': supermarket,
      '学校': school,
      '公园': park,
      '公园景区': park,
      '药店': pharmacy,
      '康复中心': rehabilitationCenter,
      '餐厅': restaurant,
      '餐饮': restaurant,
      '交通': transport,
      '交通地点': transport,
      '公司': company,
      '办公地点': company,
      '小区': residential,
      '住宅区': residential,
      '便利店': convenienceStore,
      '商场': shoppingMall,
      '生活服务': lifeService,
      '附近地点': unknown,
      '其他': unknown,
    };
    return legacy[raw] ?? unknown;
  }
}

abstract final class PlaceTypeSource {
  static const String automatic = 'automatic';
  static const String user = 'user';
}

enum RecommendationSlot {
  any,
  person,
  bodyPart,
  feeling,
  time,
  actionOrObject,
  place,
  sentence,
  topic,
}

class RecommendationContext {
  const RecommendationContext({
    required this.feature,
    this.intent = '',
    this.prompt = '',
    this.slot = RecommendationSlot.topic,
    this.selectedWords = const [],
    this.allowContextExpansion = false,
  });

  final String feature;
  final String intent;
  final String prompt;
  final RecommendationSlot slot;
  final List<String> selectedWords;

  /// When false, location data may only boost existing or directly related
  /// candidates. This prevents a frequent place word from appearing everywhere.
  final bool allowContextExpansion;

  static RecommendationSlot inferSlot(String prompt) {
    if (prompt.contains('谁')) return RecommendationSlot.person;
    if (prompt.contains('什么时候') || prompt.contains('时间')) {
      return RecommendationSlot.time;
    }
    if (prompt.contains('哪里不舒服') || prompt.contains('哪个部位')) {
      return RecommendationSlot.bodyPart;
    }
    if (prompt.contains('感觉') || prompt.contains('怎么样')) {
      return RecommendationSlot.feeling;
    }
    if (prompt.contains('哪里') || prompt.contains('地点')) {
      return RecommendationSlot.place;
    }
    if (prompt.contains('想要什么') ||
        prompt.contains('怎么做') ||
        prompt.contains('做什么')) {
      return RecommendationSlot.actionOrObject;
    }
    return RecommendationSlot.topic;
  }
}

class PlaceCluster {
  const PlaceCluster({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.visitCount,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isUserNamed,
    this.placeType,
    this.poiName,
    this.formattedAddress,
    this.typeSource = PlaceTypeSource.automatic,
    this.suggestedName,
    this.suggestedType,
    this.suggestedConfidence,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final int visitCount;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool isUserNamed;
  final String? placeType;
  final String? poiName;
  final String? formattedAddress;
  final String typeSource;
  final String? suggestedName;
  final String? suggestedType;
  final double? suggestedConfidence;

  bool get isUserConfirmed => typeSource == PlaceTypeSource.user;
  String get normalizedType => PlaceTypeCatalog.normalize(placeType);
  String get typeLabel => PlaceTypeCatalog.labelOf(placeType);

  PlaceCluster copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    int? visitCount,
    DateTime? lastSeenAt,
    bool? isUserNamed,
    String? placeType,
    String? poiName,
    String? formattedAddress,
    String? typeSource,
    String? suggestedName,
    String? suggestedType,
    double? suggestedConfidence,
  }) {
    return PlaceCluster(
      id: id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      visitCount: visitCount ?? this.visitCount,
      createdAt: createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isUserNamed: isUserNamed ?? this.isUserNamed,
      placeType: placeType ?? this.placeType,
      poiName: poiName ?? this.poiName,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      typeSource: typeSource ?? this.typeSource,
      suggestedName: suggestedName ?? this.suggestedName,
      suggestedType: suggestedType ?? this.suggestedType,
      suggestedConfidence: suggestedConfidence ?? this.suggestedConfidence,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'visitCount': visitCount,
        'createdAt': createdAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'isUserNamed': isUserNamed,
        'placeType': placeType,
        'poiName': poiName,
        'formattedAddress': formattedAddress,
        'typeSource': typeSource,
        'suggestedName': suggestedName,
        'suggestedType': suggestedType,
        'suggestedConfidence': suggestedConfidence,
      };

  factory PlaceCluster.fromJson(Map<String, dynamic> json) {
    return PlaceCluster(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num).toDouble(),
      visitCount: (json['visitCount'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      isUserNamed: json['isUserNamed'] as bool? ?? false,
      placeType: PlaceTypeCatalog.normalize(json['placeType'] as String?),
      poiName: json['poiName'] as String?,
      formattedAddress: json['formattedAddress'] as String?,
      typeSource: json['typeSource'] as String? ??
          ((json['isUserNamed'] as bool? ?? false)
              ? PlaceTypeSource.user
              : PlaceTypeSource.automatic),
      suggestedName: json['suggestedName'] as String?,
      suggestedType: json['suggestedType'] == null
          ? null
          : PlaceTypeCatalog.normalize(json['suggestedType'] as String?),
      suggestedConfidence: (json['suggestedConfidence'] as num?)?.toDouble(),
    );
  }
}

class PlaceSemantic {
  const PlaceSemantic({
    required this.type,
    required this.displayName,
    required this.confidence,
    this.poiName,
    this.formattedAddress,
  });

  final String type;
  final String displayName;
  final double confidence;
  final String? poiName;
  final String? formattedAddress;
}

abstract interface class PlaceSemanticService {
  bool get isConfigured;

  Future<PlaceSemantic?> recognize(double latitude, double longitude);
}

class AmapPlaceSemanticService implements PlaceSemanticService {
  const AmapPlaceSemanticService();

  static const String _apiKey = String.fromEnvironment('AMAP_WEB_KEY');

  @override
  bool get isConfigured {
    final key = _apiKey.trim();
    return key.isNotEmpty && !key.contains('你的') && key.length >= 20;
  }

  @override
  Future<PlaceSemantic?> recognize(double latitude, double longitude) async {
    if (!isConfigured) return null;
    final converted = _wgs84ToGcj02(latitude, longitude);
    final uri = Uri.https('restapi.amap.com', '/v3/geocode/regeo', {
      'key': _apiKey,
      'location': '${converted.longitude},${converted.latitude}',
      'radius': '120',
      'extensions': 'all',
      'batch': 'false',
      'roadlevel': '1',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw AmapServiceException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const AmapServiceException('响应格式错误');
    }
    if (decoded['status'] != '1') {
      final info = decoded['info']?.toString() ?? '未知错误';
      final code = decoded['infocode']?.toString() ?? '';
      throw AmapServiceException('$info${code.isEmpty ? '' : ' ($code)'}');
    }
    final regeocode = decoded['regeocode'];
    if (regeocode is! Map<String, dynamic>) return null;
    final address = _textOrNull(regeocode['formatted_address']);
    final pois = regeocode['pois'];
    if (pois is List) {
      final sortedPois = pois.whereType<Map<String, dynamic>>().toList()
        ..sort((a, b) => _distance(a).compareTo(_distance(b)));
      for (final poi in sortedPois) {
        if (_distance(poi) > 150) continue;
        final semantic = _semanticFromPoi(poi, address);
        if (semantic != null) return semantic;
      }
    }
    return address == null
        ? null
        : PlaceSemantic(
            type: PlaceTypeCatalog.unknown,
            displayName: '常去地点',
            confidence: 0.3,
            formattedAddress: address,
          );
  }

  static PlaceSemantic? _semanticFromPoi(
    Map<String, dynamic> poi,
    String? address,
  ) {
    final poiName = _textOrNull(poi['name']);
    final rawType = _textOrNull(poi['type']) ?? '';
    if (poiName == null || rawType.isEmpty) return null;
    final type = switch (rawType) {
      String value when value.contains('超级市场') => PlaceTypeCatalog.supermarket,
      String value when value.contains('便利店') =>
        PlaceTypeCatalog.convenienceStore,
      String value when value.contains('商场') || value.contains('购物中心') =>
        PlaceTypeCatalog.shoppingMall,
      String value when value.contains('康复') =>
        PlaceTypeCatalog.rehabilitationCenter,
      String value when value.contains('医院') || value.contains('诊所') =>
        PlaceTypeCatalog.hospital,
      String value when value.contains('药房') || value.contains('医药保健销售店') =>
        PlaceTypeCatalog.pharmacy,
      String value when value.contains('学校') || value.contains('培训机构') =>
        PlaceTypeCatalog.school,
      String value when value.contains('餐饮服务') => PlaceTypeCatalog.restaurant,
      String value when value.contains('公园广场') || value.contains('风景名胜') =>
        PlaceTypeCatalog.park,
      String value when value.contains('交通设施服务') => PlaceTypeCatalog.transport,
      String value when value.contains('商务住宅') => PlaceTypeCatalog.residential,
      String value when value.contains('公司企业') => PlaceTypeCatalog.company,
      String value when value.contains('生活服务') => PlaceTypeCatalog.lifeService,
      _ => PlaceTypeCatalog.unknown,
    };
    final distance = _distance(poi);
    final confidence = distance <= 30
        ? 0.92
        : distance <= 80
            ? 0.78
            : 0.62;
    final typeLabel = PlaceTypeCatalog.labelOf(type);
    return PlaceSemantic(
      type: type,
      displayName:
          type == PlaceTypeCatalog.unknown ? poiName : '$typeLabel · $poiName',
      confidence: confidence,
      poiName: poiName,
      formattedAddress: address,
    );
  }

  static double _distance(Map<String, dynamic> poi) =>
      double.tryParse('${poi['distance'] ?? ''}') ?? double.infinity;

  static String? _textOrNull(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == '[]' ? null : text;
  }

  static _Coordinate _wgs84ToGcj02(double latitude, double longitude) {
    if (longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271) {
      return _Coordinate(latitude, longitude);
    }
    const a = 6378245.0;
    const ee = 0.006693421622965943;
    var dLat = _transformLatitude(longitude - 105, latitude - 35);
    var dLng = _transformLongitude(longitude - 105, latitude - 35);
    final radLat = latitude / 180 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = dLat * 180 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
    dLng = dLng * 180 / (a / sqrtMagic * math.cos(radLat) * math.pi);
    return _Coordinate(latitude + dLat, longitude + dLng);
  }

  static double _transformLatitude(double x, double y) =>
      -100 +
      2 * x +
      3 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs()) +
      (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
          2 /
          3 +
      (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3 +
      (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
          2 /
          3;

  static double _transformLongitude(double x, double y) =>
      300 +
      x +
      2 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs()) +
      (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
          2 /
          3 +
      (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3 +
      (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
          2 /
          3;
}

class AmapServiceException implements Exception {
  const AmapServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Coordinate {
  const _Coordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class PlaceWordUsage {
  const PlaceWordUsage({
    required this.id,
    required this.placeId,
    required this.wordText,
    required this.normalizedText,
    required this.category,
    required this.count,
    required this.createdAt,
    required this.lastUsedAt,
  });

  final String id;
  final String placeId;
  final String wordText;
  final String normalizedText;
  final String category;
  final int count;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  PlaceWordUsage copyWith({
    String? wordText,
    String? category,
    int? count,
    DateTime? lastUsedAt,
  }) {
    return PlaceWordUsage(
      id: id,
      placeId: placeId,
      wordText: wordText ?? this.wordText,
      normalizedText: normalizedText,
      category: category ?? this.category,
      count: count ?? this.count,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'placeId': placeId,
        'wordText': wordText,
        'normalizedText': normalizedText,
        'category': category,
        'count': count,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory PlaceWordUsage.fromJson(Map<String, dynamic> json) {
    return PlaceWordUsage(
      id: json['id'] as String,
      placeId: json['placeId'] as String,
      wordText: json['wordText'] as String,
      normalizedText: json['normalizedText'] as String,
      category: json['category'] as String? ?? '',
      count: (json['count'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
    );
  }
}

abstract final class _WordSlotClassifier {
  static const Set<String> _people = {
    '妈妈',
    '爸爸',
    '女儿',
    '儿子',
    '家人',
    '医生',
    '护士',
    '护工',
    '康复师',
    '治疗师',
    '老师',
    '同学',
    '同事',
    '朋友',
    '工作人员',
    '服务员',
  };
  static const Set<String> _bodyParts = {
    '头',
    '头部',
    '手',
    '左手',
    '右手',
    '脚',
    '腿',
    '胸口',
    '肚子',
    '胃',
    '腰',
    '背',
    '肩膀',
    '嗓子',
    '喉咙',
    '眼睛',
    '耳朵',
    '牙',
    '膝盖',
  };
  static const Set<String> _feelings = {
    '疼',
    '痛',
    '麻',
    '晕',
    '恶心',
    '累',
    '冷',
    '热',
    '害怕',
    '不舒服',
    '过敏',
    '太累了',
    '我累了',
    '紧张',
    '难受',
    '开心',
    '难过',
  };
  static const Set<String> _times = {
    '现在',
    '稍后',
    '一会儿',
    '马上',
    '今天',
    '明天',
    '昨天',
    '早上',
    '中午',
    '晚上',
    '最近',
    '一直',
    '刚才',
    '很着急',
    '晚上更明显',
  };
  static const Set<String> _places = {
    '家',
    '家里',
    '医院',
    '超市',
    '学校',
    '公园',
    '药店',
    '餐厅',
    '公司',
    '小区',
    '车站',
    '地铁',
    '教室',
    '厕所',
    '洗手间',
    '楼下',
    '门口',
    '出口',
  };
  static const Set<String> _actionOrObject = {
    '喝水',
    '水',
    '吃饭',
    '休息',
    '睡觉',
    '帮我',
    '上厕所',
    '挂号',
    '检查',
    '取药',
    '缴费',
    '病历',
    '排队',
    '买药',
    '感冒药',
    '止痛药',
    '处方',
    '用法',
    '买东西',
    '结账',
    '袋子',
    '饮料',
    '面包',
    '菜单',
    '点餐',
    '买单',
    '不要辣',
    '打包',
    '上课',
    '作业',
    '请假',
    '书包',
    '放学',
    '散步',
    '回家',
    '坐一会儿',
    '坐车',
    '下车',
    '康复',
    '训练',
    '治疗',
    '慢一点',
    '继续',
    '开会',
    '文件',
    '下班',
    '上楼',
    '下楼',
  };

  static Set<RecommendationSlot> classify(String text) {
    final clean = text.trim();
    final normalized = LocationRecommendationController.normalizeText(clean);
    final result = <RecommendationSlot>{};
    if (_matches(normalized, _people)) result.add(RecommendationSlot.person);
    if (_matches(normalized, _bodyParts)) {
      result.add(RecommendationSlot.bodyPart);
    }
    if (_matches(normalized, _feelings)) {
      result.add(RecommendationSlot.feeling);
    }
    if (_matches(normalized, _times)) result.add(RecommendationSlot.time);
    if (_matches(normalized, _places)) result.add(RecommendationSlot.place);
    if (_matches(normalized, _actionOrObject)) {
      result.add(RecommendationSlot.actionOrObject);
    }
    if (clean.length >= 6 ||
        clean.contains('我') ||
        clean.contains('请') ||
        clean.contains('？') ||
        clean.contains('?')) {
      result.add(RecommendationSlot.sentence);
    }
    if (result.isEmpty && clean.length <= 6) {
      result.add(RecommendationSlot.actionOrObject);
    }
    return result;
  }

  static bool matches(String text, RecommendationSlot slot) {
    if (slot == RecommendationSlot.any || slot == RecommendationSlot.topic) {
      return true;
    }
    final slots = classify(text);
    if (slot != RecommendationSlot.sentence &&
        slot != RecommendationSlot.actionOrObject &&
        slots.contains(RecommendationSlot.sentence) &&
        (text.contains('我') || text.contains('请') || text.length >= 6)) {
      return false;
    }
    return slots.contains(slot);
  }

  static bool _matches(String normalized, Set<String> words) {
    for (final word in words) {
      final candidate = LocationRecommendationController.normalizeText(word);
      if (normalized == candidate ||
          (candidate.length >= 2 && normalized.contains(candidate))) {
        return true;
      }
    }
    return false;
  }
}

class LocationRecommendationController extends ChangeNotifier {
  LocationRecommendationController({
    required LocationDataStore store,
    PlaceSemanticService semanticService = const AmapPlaceSemanticService(),
  })  : _store = store,
        _semanticService = semanticService;

  static const Duration locationCacheDuration = Duration(minutes: 3);
  static const double unchangedDistanceMeters = 80;
  static const double defaultRadiusMeters = 120;
  static const double maximumUsefulAccuracyMeters = 120;

  final LocationDataStore _store;
  final PlaceSemanticService _semanticService;
  final List<PlaceCluster> _places = [];
  final List<PlaceWordUsage> _wordUsages = [];
  final Map<String, String> _favoriteWords = {};
  List<ExpressionHabit> _expressionHabits = const [];

  bool _enabled = false;
  DateTime? _lastLocationRequestAt;
  Future<bool>? _refreshInFlight;
  Position? _currentPosition;
  PlaceCluster? _currentPlace;
  String? _lastLocationError;
  String? _lastPlaceRecognitionError;
  PlaceSemantic? _currentSemantic;
  bool _currentSuggestionDismissed = false;
  List<WordRecommendationScore> _lastRecommendationScores = const [];
  List<WordRecommendationFilter> _lastRecommendationFilters = const [];

  bool get enabled => _enabled;
  int get placeCount => _places.length;
  PlaceCluster? get currentPlace => _currentPlace;
  String? get lastLocationError => _lastLocationError;
  String? get lastPlaceRecognitionError => _lastPlaceRecognitionError;
  PlaceSemantic? get currentSemantic => _currentSemantic;
  bool get automaticPlaceRecognitionAvailable => _semanticService.isConfigured;
  bool get currentSuggestionDismissed => _currentSuggestionDismissed;
  List<PlaceCluster> get places => List.unmodifiable(_places);
  List<PlaceWordUsage> get wordUsages => List.unmodifiable(_wordUsages);
  List<WordRecommendationScore> get lastRecommendationScores =>
      List.unmodifiable(_lastRecommendationScores);
  List<WordRecommendationFilter> get lastRecommendationFilters =>
      List.unmodifiable(_lastRecommendationFilters);
  List<PlaceCluster> get debugPlaces => places;
  List<PlaceWordUsage> get debugWordUsages => wordUsages;

  List<PlaceWordUsage> wordsForPlace(String placeId) {
    final result =
        _wordUsages.where((usage) => usage.placeId == placeId).toList()
          ..sort((a, b) {
            final count = b.count.compareTo(a.count);
            return count != 0 ? count : b.lastUsedAt.compareTo(a.lastUsedAt);
          });
    return result;
  }

  Future<void> initialize({Iterable<String> favoriteWords = const []}) async {
    _enabled = await _store.loadLocationRecommendationEnabled();
    updateFavoriteWords(favoriteWords, notify: false);
    final raw = await _store.loadLocationRecommendationData();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final places = decoded['places'];
          final usages = decoded['wordUsages'];
          if (places is List) {
            _places.addAll(
              places
                  .whereType<Map<String, dynamic>>()
                  .map(PlaceCluster.fromJson),
            );
          }
          if (usages is List) {
            _wordUsages.addAll(
              usages
                  .whereType<Map<String, dynamic>>()
                  .map(PlaceWordUsage.fromJson),
            );
          }
        }
      } catch (_) {
        _places.clear();
        _wordUsages.clear();
      }
    }
    notifyListeners();
    if (_enabled) {
      unawaited(refreshLocationContext(force: true));
    }
  }

  void updateFavoriteWords(
    Iterable<String> words, {
    bool notify = true,
  }) {
    _favoriteWords.clear();
    for (final word in words) {
      final clean = word.trim();
      final normalized = normalizeText(clean);
      if (normalized.isNotEmpty) _favoriteWords[normalized] = clean;
    }
    if (notify) notifyListeners();
  }

  void updateExpressionHabits(
    Iterable<ExpressionHabit> habits, {
    bool notify = true,
  }) {
    _expressionHabits = habits.toList(growable: false);
    if (notify) notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _lastLocationError = null;
    if (!enabled) {
      _currentPosition = null;
      _currentPlace = null;
      _currentSemantic = null;
      _currentSuggestionDismissed = false;
      _lastLocationRequestAt = null;
    }
    await _store.saveLocationRecommendationEnabled(enabled);
    notifyListeners();
    if (enabled) await refreshLocationContext(force: true);
  }

  Future<bool> refreshLocationContext({bool force = false}) async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _performRefreshLocationContext(force: force);
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<bool> _performRefreshLocationContext({bool force = false}) async {
    if (!_enabled) return false;
    final now = DateTime.now();
    if (!force &&
        _lastLocationRequestAt != null &&
        now.difference(_lastLocationRequestAt!) < locationCacheDuration) {
      return _hasUsefulPosition;
    }
    _lastLocationRequestAt = now;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _clearCurrentContext('location_services_disabled');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _clearCurrentContext('location_permission_denied');
        return false;
      }

      final previousPosition = _currentPosition;
      final previousPlaceId = _currentPlace?.id;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _currentPosition = position;
      _lastLocationError = null;

      if (position.accuracy > maximumUsefulAccuracyMeters) {
        _currentPlace = null;
        _currentSemantic = null;
        _lastLocationError =
            'location_accuracy_too_low_${position.accuracy.round()}m';
        notifyListeners();
        return false;
      }

      final movedDistance = previousPosition == null
          ? double.infinity
          : Geolocator.distanceBetween(
              previousPosition.latitude,
              previousPosition.longitude,
              position.latitude,
              position.longitude,
            );
      final matchedPlace = _nearestMatchingPlace(position);
      _currentPlace = matchedPlace;
      if (movedDistance >= unchangedDistanceMeters) {
        _currentSuggestionDismissed = false;
      }

      if (_semanticService.isConfigured &&
          (movedDistance >= unchangedDistanceMeters ||
              matchedPlace?.placeType == null)) {
        try {
          _currentSemantic = await _semanticService.recognize(
            position.latitude,
            position.longitude,
          );
          _lastPlaceRecognitionError =
              _currentSemantic == null ? '高德未返回附近地点信息' : null;
        } catch (error) {
          _currentSemantic = null;
          _lastPlaceRecognitionError = error.toString();
        }
      } else if (matchedPlace != null) {
        _currentSemantic = PlaceSemantic(
          type: matchedPlace.suggestedType ?? matchedPlace.normalizedType,
          displayName: matchedPlace.suggestedName ?? matchedPlace.name,
          confidence: matchedPlace.suggestedConfidence ?? 0.5,
          poiName: matchedPlace.poiName,
          formattedAddress: matchedPlace.formattedAddress,
        );
      }

      if (matchedPlace != null) {
        final isNewVisit = previousPlaceId != matchedPlace.id ||
            movedDistance >= unchangedDistanceMeters;
        final semantic = _currentSemantic;
        final userConfirmed = matchedPlace.isUserConfirmed;
        _replacePlace(
          matchedPlace.copyWith(
            visitCount: isNewVisit
                ? matchedPlace.visitCount + 1
                : matchedPlace.visitCount,
            lastSeenAt: now,
            name: !userConfirmed && semantic != null
                ? semantic.displayName
                : matchedPlace.name,
            placeType: !userConfirmed && semantic != null
                ? semantic.type
                : matchedPlace.placeType,
            poiName: semantic?.poiName,
            formattedAddress: semantic?.formattedAddress,
            suggestedName: semantic?.displayName,
            suggestedType: semantic?.type,
            suggestedConfidence: semantic?.confidence,
          ),
        );
        _currentPlace =
            _places.firstWhere((place) => place.id == matchedPlace.id);
        await _persist();
      }
      notifyListeners();
      return true;
    } catch (error) {
      _clearCurrentContext(error.runtimeType.toString());
      return false;
    }
  }

  Future<void> recordWordUsed(String text, String category) async {
    final cleanText = text.trim();
    final normalized = normalizeText(cleanText);
    if (!_enabled || cleanText.isEmpty || normalized.isEmpty) return;

    await refreshLocationContext();
    if (!_hasUsefulPosition) return;
    final now = DateTime.now();
    var place = _currentPlace ?? _nearestMatchingPlace(_currentPosition!);
    if (place == null) {
      place = PlaceCluster(
        id: 'place_${now.microsecondsSinceEpoch}',
        name: _currentSemantic?.displayName ?? '常去地点 ${_places.length + 1}',
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        radiusMeters: defaultRadiusMeters,
        visitCount: 1,
        createdAt: now,
        lastSeenAt: now,
        isUserNamed: false,
        placeType: _currentSemantic?.type ?? PlaceTypeCatalog.unknown,
        poiName: _currentSemantic?.poiName,
        formattedAddress: _currentSemantic?.formattedAddress,
        typeSource: PlaceTypeSource.automatic,
        suggestedName: _currentSemantic?.displayName,
        suggestedType: _currentSemantic?.type,
        suggestedConfidence: _currentSemantic?.confidence,
      );
      _places.add(place);
      _currentPlace = place;
    }

    final existingIndex = _wordUsages.indexWhere(
      (usage) =>
          usage.placeId == place!.id && usage.normalizedText == normalized,
    );
    if (existingIndex >= 0) {
      final existing = _wordUsages[existingIndex];
      _wordUsages[existingIndex] = existing.copyWith(
        wordText: cleanText,
        category: category.isEmpty ? existing.category : category,
        count: existing.count + 1,
        lastUsedAt: now,
      );
    } else {
      _wordUsages.add(
        PlaceWordUsage(
          id: 'place_word_${now.microsecondsSinceEpoch}',
          placeId: place.id,
          wordText: cleanText,
          normalizedText: normalized,
          category: category,
          count: 1,
          createdAt: now,
          lastUsedAt: now,
        ),
      );
    }
    await _persist();
    notifyListeners();
  }

  List<String> recommendWords(
    List<String> baseWords, {
    String? category,
    bool includeContextWords = true,
    RecommendationContext? context,
  }) {
    final effectiveContext = context ??
        RecommendationContext(
          feature: category ?? 'unknown',
          slot: RecommendationSlot.topic,
        );
    final accumulators = <String, _RecommendationAccumulator>{};
    final filters = <WordRecommendationFilter>[];
    final baseNormalized =
        baseWords.map(normalizeText).where((word) => word.isNotEmpty).toSet();
    final selectedNormalized = effectiveContext.selectedWords
        .map(normalizeText)
        .where((word) => word.isNotEmpty)
        .toSet();

    void add(String text, double score, String reason) {
      final clean = text.trim();
      final normalized = normalizeText(clean);
      if (normalized.isEmpty) return;
      final existing = accumulators[normalized];
      if (existing == null) {
        accumulators[normalized] = _RecommendationAccumulator(
          text: clean,
          score: score,
          reasons: [reason],
        );
      } else {
        if (score > existing.score) {
          existing
            ..text = clean
            ..score = score;
        }
        if (!existing.reasons.contains(reason)) existing.reasons.add(reason);
      }
    }

    bool directlyRelated(String normalized) {
      if (baseNormalized.contains(normalized)) return true;
      for (final reference in {...baseNormalized, ...selectedNormalized}) {
        if (reference.length >= 2 &&
            normalized.length >= 2 &&
            (reference.contains(normalized) ||
                normalized.contains(reference))) {
          return true;
        }
      }
      return false;
    }

    bool canUseContextWord(String text, String source) {
      final normalized = normalizeText(text);
      if (selectedNormalized.contains(normalized)) {
        filters.add(WordRecommendationFilter(
          text: text,
          source: source,
          reason: '已在当前步骤选择过',
        ));
        return false;
      }
      final slotMatches =
          _WordSlotClassifier.matches(text, effectiveContext.slot);
      if (!slotMatches) {
        filters.add(WordRecommendationFilter(
          text: text,
          source: source,
          reason: '期望${_slotLabel(effectiveContext.slot)}，词语类型不匹配',
        ));
        return false;
      }
      if (!effectiveContext.allowContextExpansion &&
          !directlyRelated(normalized)) {
        filters.add(WordRecommendationFilter(
          text: text,
          source: source,
          reason: '与当前候选和已选内容无直接关联',
        ));
        return false;
      }
      return true;
    }

    // Model/local base candidates are always preserved. Context only changes
    // their order; it never removes a candidate returned by the original flow.
    final timeBucket = ExpressionHabitStore.bucketFor(DateTime.now());
    final placeType = _currentPlace?.normalizedType ?? _currentSemantic?.type;
    final habitByNormalized = <String, ExpressionHabit>{
      for (final habit in _expressionHabits) habit.normalizedText: habit,
    };
    for (var index = 0; index < baseWords.length; index++) {
      final word = baseWords[index];
      final normalized = normalizeText(word);
      final habit = habitByNormalized[normalized];
      final favoriteBonus =
          _favoriteWords.containsKey(normalized) ? 120.0 : 0.0;
      final habitBonus = habit == null
          ? 0.0
          : math.min(
              520.0,
              habit.scoreFor(
                    category: category,
                    timeBucket: timeBucket,
                    placeType: placeType,
                  ) /
                  3.2,
            );
      add(
        word,
        9000 - index * 4 + favoriteBonus + habitBonus,
        habit == null ? '原候选' : '原候选 · 个人习惯 ${habit.count} 次',
      );
    }

    if (includeContextWords && _expressionHabits.isNotEmpty) {
      final rankedHabits = ExpressionHabitStore.rank(
        _expressionHabits,
        category: category,
        timeBucket: timeBucket,
        placeType: placeType,
        limit: 24,
      );
      for (final habit in rankedHabits) {
        if (!canUseContextWord(habit.text, '使用习惯')) continue;
        final normalized = habit.normalizedText;
        final isExact = baseNormalized.contains(normalized);
        final isRelated = directlyRelated(normalized);
        final relevanceBase = isExact
            ? 12600.0
            : isRelated
                ? 10500.0
                : 8200.0;
        add(
          habit.text,
          relevanceBase +
              habit.scoreFor(
                category: category,
                timeBucket: timeBucket,
                placeType: placeType,
              ),
          isExact
              ? '个人习惯 ${habit.count} 次 · 与原候选一致'
              : isRelated
                  ? '个人习惯 ${habit.count} 次 · 与上下文相关'
                  : '个人习惯 ${habit.count} 次 · 槽位匹配',
        );
      }
    }

    if (_enabled && _currentPlace != null && includeContextWords) {
      final now = DateTime.now();
      for (final usage in wordsForPlace(_currentPlace!.id)) {
        if (!canUseContextWord(usage.wordText, '地点历史')) continue;
        final normalized = usage.normalizedText;
        final isExact = baseNormalized.contains(normalized);
        final isRelated = directlyRelated(normalized);
        final ageDays = now.difference(usage.lastUsedAt).inHours / 24;
        final recency = math.max(0.0, 240.0 - ageDays * 8).toDouble();
        final frequency = math.min(usage.count, 20).toDouble() * 80;
        final categoryBonus = category != null &&
                category.isNotEmpty &&
                usage.category == category
            ? 200.0
            : 0.0;
        final favoriteBonus =
            _favoriteWords.containsKey(usage.normalizedText) ? 120.0 : 0.0;
        final relevanceBase = isExact
            ? 13000.0
            : isRelated
                ? 11000.0
                : 8500.0;
        add(
          usage.wordText,
          relevanceBase + frequency + recency + categoryBonus + favoriteBonus,
          isExact
              ? '地点使用 ${usage.count} 次 · 与原候选一致'
              : isRelated
                  ? '地点使用 ${usage.count} 次 · 与上下文相关'
                  : '地点使用 ${usage.count} 次 · 槽位匹配',
        );
      }
    }

    if (_enabled && includeContextWords) {
      final sceneWords = PlaceTypeCatalog.wordsFor(placeType);
      for (var index = 0; index < sceneWords.length; index++) {
        final word = sceneWords[index];
        if (!canUseContextWord(word, '地点场景')) continue;
        final normalized = normalizeText(word);
        final isExact = baseNormalized.contains(normalized);
        final isRelated = directlyRelated(normalized);
        final favoriteBonus =
            _favoriteWords.containsKey(normalized) ? 120.0 : 0.0;
        final relevanceBase = isExact
            ? 10000.0
            : isRelated
                ? 9500.0
                : 7600.0;
        add(
          word,
          relevanceBase - index * 8 + favoriteBonus,
          '${PlaceTypeCatalog.labelOf(placeType)}场景词 · ${isExact ? "原候选一致" : isRelated ? "上下文相关" : "槽位匹配"}',
        );
      }
    }

    if (_enabled &&
        includeContextWords &&
        effectiveContext.allowContextExpansion) {
      var favoriteIndex = 0;
      for (final favorite in _favoriteWords.values) {
        if (canUseContextWord(favorite, '收藏词')) {
          add(favorite, 5000 - favoriteIndex * 2, '收藏词 · 槽位匹配');
        }
        favoriteIndex++;
      }
    }

    final ranked = accumulators.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    _lastRecommendationScores = ranked
        .map(
          (item) => WordRecommendationScore(
            text: item.text,
            score: item.score,
            reasons: List.unmodifiable(item.reasons),
          ),
        )
        .toList(growable: false);
    _lastRecommendationFilters = filters;
    return ranked.map((item) => item.text).toList(growable: false);
  }

  Future<PlaceCluster?> confirmCurrentSuggestion({
    String? name,
    String? type,
  }) async {
    if (!_enabled) return null;
    await refreshLocationContext();
    if (!_hasUsefulPosition) return null;
    final semantic = _currentSemantic;
    final effectiveType = PlaceTypeCatalog.normalize(type ?? semantic?.type);
    final effectiveName = _resolvedUserPlaceName(
      name,
      effectiveType,
      fallback: semantic?.displayName,
    );
    final existing = _currentPlace ?? _nearestMatchingPlace(_currentPosition!);
    if (existing != null) {
      await updatePlace(existing.id, name: effectiveName, type: effectiveType);
      return _currentPlace;
    }
    final now = DateTime.now();
    final place = PlaceCluster(
      id: 'place_${now.microsecondsSinceEpoch}',
      name: effectiveName,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      radiusMeters: defaultRadiusMeters,
      visitCount: 1,
      createdAt: now,
      lastSeenAt: now,
      isUserNamed: true,
      placeType: effectiveType,
      poiName: semantic?.poiName,
      formattedAddress: semantic?.formattedAddress,
      typeSource: PlaceTypeSource.user,
      suggestedName: semantic?.displayName,
      suggestedType: semantic?.type,
      suggestedConfidence: semantic?.confidence,
    );
    _places.add(place);
    _currentPlace = place;
    _currentSuggestionDismissed = false;
    await _persist();
    notifyListeners();
    return place;
  }

  Future<void> updatePlace(
    String placeId, {
    required String name,
    required String type,
  }) async {
    final index = _places.indexWhere((place) => place.id == placeId);
    if (index < 0) return;
    final place = _places[index];
    final updated = place.copyWith(
      name: _resolvedUserPlaceName(name, type, fallback: place.name),
      placeType: PlaceTypeCatalog.normalize(type),
      typeSource: PlaceTypeSource.user,
      isUserNamed: true,
      lastSeenAt: DateTime.now(),
    );
    _places[index] = updated;
    if (_currentPlace?.id == placeId) _currentPlace = updated;
    await _persist();
    notifyListeners();
  }

  Future<void> acceptSuggestion(String placeId) async {
    final index = _places.indexWhere((item) => item.id == placeId);
    if (index < 0) return;
    final place = _places[index];
    if (place.suggestedType == null) return;
    await updatePlace(
      placeId,
      name:
          place.suggestedName ?? PlaceTypeCatalog.labelOf(place.suggestedType),
      type: place.suggestedType!,
    );
  }

  Future<void> refreshSuggestionForPlace(String placeId) async {
    final index = _places.indexWhere((place) => place.id == placeId);
    if (!_enabled || index < 0 || !_semanticService.isConfigured) return;
    try {
      final place = _places[index];
      final semantic = await _semanticService.recognize(
        place.latitude,
        place.longitude,
      );
      if (semantic == null) return;
      final userConfirmed = place.isUserConfirmed;
      final updated = place.copyWith(
        name: userConfirmed ? place.name : semantic.displayName,
        placeType: userConfirmed ? place.placeType : semantic.type,
        poiName: semantic.poiName,
        formattedAddress: semantic.formattedAddress,
        suggestedName: semantic.displayName,
        suggestedType: semantic.type,
        suggestedConfidence: semantic.confidence,
      );
      _places[index] = updated;
      if (_currentPlace?.id == placeId) {
        _currentPlace = updated;
        _currentSemantic = semantic;
      }
      _lastPlaceRecognitionError = null;
      await _persist();
      notifyListeners();
    } catch (error) {
      _lastPlaceRecognitionError = error.toString();
      notifyListeners();
    }
  }

  void dismissCurrentSuggestion() {
    _currentSuggestionDismissed = true;
    notifyListeners();
  }

  Future<void> deletePlace(String placeId) async {
    _places.removeWhere((place) => place.id == placeId);
    _wordUsages.removeWhere((usage) => usage.placeId == placeId);
    if (_currentPlace?.id == placeId) _currentPlace = null;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteWordUsage(String usageId) async {
    _wordUsages.removeWhere((usage) => usage.id == usageId);
    await _persist();
    notifyListeners();
  }

  Future<void> clearWordsForPlace(String placeId) async {
    _wordUsages.removeWhere((usage) => usage.placeId == placeId);
    await _persist();
    notifyListeners();
  }

  int wordCountForPlace(String placeId) =>
      _wordUsages.where((usage) => usage.placeId == placeId).length;

  String exportDataJson() => const JsonEncoder.withIndent('  ').convert({
        'places': _places.map((place) => place.toJson()).toList(),
        'wordUsages': _wordUsages.map((usage) => usage.toJson()).toList(),
      });

  String _resolvedUserPlaceName(
    String? name,
    String type, {
    String? fallback,
  }) {
    final clean = name?.trim() ?? '';
    if (clean.isNotEmpty) return clean;
    final fallbackClean = fallback?.trim() ?? '';
    if (fallbackClean.isNotEmpty) return fallbackClean;
    return PlaceTypeCatalog.labelOf(type);
  }

  Future<void> clearPlaceData() async {
    _places.clear();
    _wordUsages.clear();
    _currentPlace = null;
    _currentSemantic = null;
    _lastPlaceRecognitionError = null;
    await _store.clearLocationRecommendationData();
    notifyListeners();
  }

  bool get _hasUsefulPosition =>
      _currentPosition != null &&
      _currentPosition!.accuracy <= maximumUsefulAccuracyMeters;

  PlaceCluster? _nearestMatchingPlace(Position position) {
    PlaceCluster? nearest;
    var nearestDistance = double.infinity;
    for (final place in _places) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        place.latitude,
        place.longitude,
      );
      if (distance <= place.radiusMeters && distance < nearestDistance) {
        nearest = place;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  void _replacePlace(PlaceCluster updated) {
    final index = _places.indexWhere((place) => place.id == updated.id);
    if (index >= 0) _places[index] = updated;
  }

  void _clearCurrentContext(String error) {
    _currentPosition = null;
    _currentPlace = null;
    _currentSemantic = null;
    _lastPlaceRecognitionError = null;
    _lastLocationError = error;
    notifyListeners();
  }

  Future<void> _persist() {
    return _store.saveLocationRecommendationData(
      jsonEncode({
        'places': _places.map((place) => place.toJson()).toList(),
        'wordUsages': _wordUsages.map((usage) => usage.toJson()).toList(),
      }),
    );
  }

  static String normalizeText(String text) {
    return text.trim().toLowerCase().replaceAll(
          RegExp(r'''[\s，。！？、,.!?；;：:“”"'（）()【】\[\]{}<>《》…—_-]+'''),
          '',
        );
  }
}

class WordRecommendationScore {
  const WordRecommendationScore({
    required this.text,
    required this.score,
    required this.reasons,
  });

  final String text;
  final double score;
  final List<String> reasons;
}

class WordRecommendationFilter {
  const WordRecommendationFilter({
    required this.text,
    required this.source,
    required this.reason,
  });

  final String text;
  final String source;
  final String reason;
}

String _slotLabel(RecommendationSlot slot) {
  return switch (slot) {
    RecommendationSlot.any => '任意类型',
    RecommendationSlot.person => '人物词',
    RecommendationSlot.bodyPart => '身体部位',
    RecommendationSlot.feeling => '感受或症状',
    RecommendationSlot.time => '时间词',
    RecommendationSlot.actionOrObject => '动作或物品',
    RecommendationSlot.place => '地点词',
    RecommendationSlot.sentence => '完整表达',
    RecommendationSlot.topic => '当前话题相关词',
  };
}

class _RecommendationAccumulator {
  _RecommendationAccumulator({
    required this.text,
    required this.score,
    required this.reasons,
  });

  String text;
  double score;
  final List<String> reasons;
}
