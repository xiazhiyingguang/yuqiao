import 'dart:io';

import 'package:yuqiao_app/mulberry_symbol_data.dart';

void main(List<String> args) {
  final root = Directory.current;
  final pubspec = File('${root.path}/pubspec.yaml');
  final symbolInfo = File('${root.path}/symbol-info.csv');
  final errors = <String>[];
  final warnings = <String>[];

  if (!pubspec.existsSync()) {
    stderr.writeln('ERROR: pubspec.yaml not found.');
    exit(2);
  }

  final pubspecText = pubspec.readAsStringSync();
  final registeredAssets = _registeredAssets(pubspecText);
  final hasDirectoryRegistration = registeredAssets.contains('EN-symbols/');
  final symbolInfoNames =
      symbolInfo.existsSync() ? _symbolInfoNames(symbolInfo) : <String>{};

  final keywordOwners = <String, List<MulberrySymbolEntry>>{};
  final assetOwners = <String, List<MulberrySymbolEntry>>{};

  for (final entry in MulberrySymbolResolver.entries) {
    if (entry.asset.trim().isEmpty) {
      errors.add('Empty asset path for ${entry.keywords}');
      continue;
    }

    final assetFile = File('${root.path}/${entry.asset}');
    if (!assetFile.existsSync()) {
      errors.add('Missing SVG file: ${entry.asset}');
    }

    if (!hasDirectoryRegistration && !registeredAssets.contains(entry.asset)) {
      errors.add('Asset not registered in pubspec.yaml: ${entry.asset}');
    }

    final symbolName = entry.asset
        .split('/')
        .last
        .replaceAll(RegExp(r'\.svg$', caseSensitive: false), '');
    if (symbolInfoNames.isNotEmpty && !symbolInfoNames.contains(symbolName)) {
      warnings.add('Asset not found in symbol-info.csv: ${entry.asset}');
    }

    if (entry.keywords.isEmpty) {
      errors.add('No keywords for asset: ${entry.asset}');
    }

    for (final keyword in entry.keywords) {
      final normalized = MulberrySymbolResolver.normalize(keyword);
      if (normalized.isEmpty) {
        errors.add('Empty keyword in asset: ${entry.asset}');
        continue;
      }
      keywordOwners.putIfAbsent(normalized, () => []).add(entry);
    }

    assetOwners.putIfAbsent(entry.asset, () => []).add(entry);

    if (!const ['approved', 'review', 'disabled'].contains(entry.status)) {
      errors.add('Invalid status "${entry.status}" for ${entry.asset}');
    }
    if (!const ['high', 'medium', 'low'].contains(entry.confidence)) {
      errors.add('Invalid confidence "${entry.confidence}" for ${entry.asset}');
    }
  }

  for (final item in keywordOwners.entries) {
    final assets = item.value.map((entry) => entry.asset).toSet();
    if (assets.length > 1) {
      warnings.add(
        'Keyword "${item.key}" maps to multiple assets: ${assets.join(', ')}',
      );
    }
  }

  for (final item in assetOwners.entries) {
    if (item.value.length >= 6) {
      warnings.add(
        'Asset reused ${item.value.length} times: ${item.key}',
      );
    }
  }

  const expectedMatches = {
    '蛋糕': 'EN-symbols/cake.svg',
    '鸡蛋': 'EN-symbols/egg.svg',
    '水果': 'EN-symbols/fruit.svg',
    '奶酪': 'EN-symbols/cheese.svg',
    '牛油果': 'EN-symbols/avocado.svg',
    '头': 'EN-symbols/head.svg',
    '脸': 'EN-symbols/face_neutral_3.svg',
    '头发': 'EN-symbols/long_hair.svg',
    '舌头': 'EN-symbols/tongue.svg',
    '手': 'EN-symbols/left_hand.svg',
    '手腕': 'EN-symbols/wrist.svg',
    '手肘': 'EN-symbols/elbow.svg',
    '车': 'EN-symbols/car.svg',
    '公交车': 'EN-symbols/bus.svg',
    '火车': 'EN-symbols/train.svg',
    '出租车': 'EN-symbols/taxi.svg',
    '医院': 'EN-symbols/surgery_health_centre.svg',
    '灯光': 'EN-symbols/lamp.svg',
    '剪刀': 'EN-symbols/scissors.svg',
    '洗发水': 'EN-symbols/shampoo.svg',
    '手电筒': 'EN-symbols/torch.svg',
    '水槽': 'EN-symbols/sink.svg',
    '手表': 'EN-symbols/watch.svg',
    '手镯': 'EN-symbols/bracelet_1.svg',
    '手提包': 'EN-symbols/hand_bag.svg',
    '我想吃蛋糕': 'EN-symbols/cake.svg',
    '我要坐公交车': 'EN-symbols/bus.svg',
    '我的手表': 'EN-symbols/watch.svg',
    '洗一下头发': 'EN-symbols/long_hair.svg',
  };

  for (final item in expectedMatches.entries) {
    final actual = MulberrySymbolResolver.assetForText(item.key);
    if (actual != item.value) {
      errors.add(
        'Unexpected match for "${item.key}": expected ${item.value}, got $actual',
      );
    }
  }

  final total = MulberrySymbolResolver.entries.length;
  final uniqueAssets = assetOwners.length;
  final review = MulberrySymbolResolver.entries
      .where((entry) => entry.status == 'review')
      .length;
  final approved = MulberrySymbolResolver.entries
      .where((entry) => entry.status == 'approved')
      .length;
  final disabled = MulberrySymbolResolver.entries
      .where((entry) => entry.status == 'disabled')
      .length;

  stdout.writeln('Mulberry symbol validation');
  stdout.writeln('  mappings: $total');
  stdout.writeln('  unique assets: $uniqueAssets');
  stdout.writeln('  approved/review/disabled: $approved/$review/$disabled');
  stdout.writeln('  warnings: ${warnings.length}');
  stdout.writeln('  errors: ${errors.length}');

  if (warnings.isNotEmpty) {
    stdout.writeln('\nWarnings:');
    for (final warning in warnings.take(80)) {
      stdout.writeln('  - $warning');
    }
    if (warnings.length > 80) {
      stdout.writeln('  ... ${warnings.length - 80} more warnings');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('\nErrors:');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    exit(1);
  }
}

Set<String> _registeredAssets(String pubspecText) {
  final result = <String>{};
  final lines = pubspecText.split(RegExp(r'\r?\n'));
  var inAssets = false;
  for (final line in lines) {
    if (line.trim() == 'assets:') {
      inAssets = true;
      continue;
    }
    if (!inAssets) continue;
    if (line.startsWith('  ') && !line.startsWith('    - ')) {
      break;
    }
    final match = RegExp(r'^\s*-\s+(.+?)\s*$').firstMatch(line);
    if (match != null) {
      result.add(match.group(1)!);
    }
  }
  return result;
}

Set<String> _symbolInfoNames(File file) {
  final names = <String>{};
  final lines = file.readAsLinesSync();
  for (var i = 1; i < lines.length; i++) {
    final columns = _splitCsvLine(lines[i]);
    if (columns.length > 5 && columns[5].trim().isNotEmpty) {
      names.add(columns[5].trim());
    }
  }
  return names;
}

List<String> _splitCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      quoted = !quoted;
      continue;
    }
    if (char == ',' && !quoted) {
      values.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  values.add(buffer.toString());
  return values;
}
