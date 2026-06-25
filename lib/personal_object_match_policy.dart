class PersonalObjectMatchPolicy {
  const PersonalObjectMatchPolicy._();

  static bool kindsCompatible(String detectedName, String personalName) {
    final detectedKind = _kindOf(detectedName);
    final personalKind = _kindOf(personalName);
    if (detectedKind.isEmpty || personalKind.isEmpty) return false;
    if (detectedKind == personalKind) return true;
    return detectedKind.length >= 2 &&
        personalKind.length >= 2 &&
        (detectedKind.contains(personalKind) ||
            personalKind.contains(detectedKind));
  }

  static bool acceptsMatch({
    required bool samePhysicalObject,
    required double confidence,
    required List<String> matchingEvidence,
    required List<String> conflictingEvidence,
  }) {
    return samePhysicalObject &&
        confidence >= 0.96 &&
        matchingEvidence.length >= 2 &&
        matchingEvidence.any(_containsDistinctiveFeature) &&
        conflictingEvidence.isEmpty;
  }

  static bool _containsDistinctiveFeature(String text) => RegExp(
        r'贴纸|图案|划痕|磨损|缺口|挂件|标签|污渍|凹痕|独特|组合特征',
      ).hasMatch(text);

  static String _kindOf(String text) {
    final clean = text.replaceAll(RegExp(r'我的|这个|那个|个人|专属'), '');
    const kinds = <String, String>{
      '杯': '杯',
      '瓶': '瓶',
      '钥匙': '钥匙',
      '手机': '手机',
      '眼镜': '眼镜',
      '包': '包',
      '雨伞': '伞',
      '伞': '伞',
      '鞋': '鞋',
      '帽': '帽',
      '衣': '衣物',
      '药盒': '药盒',
      '遥控器': '遥控器',
      '耳机': '耳机',
      '电脑': '电脑',
      '平板': '平板',
      '书': '书',
      '笔': '笔',
    };
    for (final entry in kinds.entries) {
      if (clean.contains(entry.key)) return entry.value;
    }
    return clean.trim();
  }
}
