import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'mulberry_symbol_data.dart';

export 'mulberry_symbol_data.dart';

class MulberrySymbolIcon extends StatelessWidget {
  const MulberrySymbolIcon({
    super.key,
    required this.text,
    this.size = 52,
    this.backgroundColor,
    this.padding = 8,
  });

  final String text;
  final double size;
  final Color? backgroundColor;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final asset = MulberrySymbolResolver.assetForText(text);
    if (asset == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
      ),
      child: SvgPicture.asset(
        asset,
        fit: BoxFit.contain,
        semanticsLabel: text,
      ),
    );
  }
}

class MulberrySymbolDebugPage extends StatefulWidget {
  const MulberrySymbolDebugPage({super.key});

  @override
  State<MulberrySymbolDebugPage> createState() =>
      _MulberrySymbolDebugPageState();
}

class _MulberrySymbolDebugPageState extends State<MulberrySymbolDebugPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MulberrySymbolEntry> get _filteredEntries {
    final normalizedQuery = MulberrySymbolResolver.normalize(_query);
    if (normalizedQuery.isEmpty) return MulberrySymbolResolver.entries;
    return MulberrySymbolResolver.entries.where((entry) {
      final text = [entry.asset, entry.category, ...entry.keywords].join(' ');
      return MulberrySymbolResolver.normalize(text).contains(normalizedQuery);
    }).toList();
  }

  Map<String, int> get _assetUseCounts {
    final counts = <String, int>{};
    for (final entry in MulberrySymbolResolver.entries) {
      counts[entry.asset] = (counts[entry.asset] ?? 0) + 1;
    }
    return counts;
  }

  int get _reviewCount => MulberrySymbolResolver.entries
      .where((entry) => entry.status == 'review')
      .length;

  Future<void> _copyJson() async {
    final buffer = StringBuffer('[\n');
    for (var i = 0; i < MulberrySymbolResolver.entries.length; i++) {
      final entry = MulberrySymbolResolver.entries[i];
      buffer.write('  {');
      buffer.write('"text":"${entry.primaryText}",');
      buffer.write('"asset":"${entry.asset}",');
      buffer.write('"keywords":${_stringListJson(entry.keywords)},');
      buffer.write('"status":"${entry.status}",');
      buffer.write('"confidence":"${entry.confidence}"');
      buffer.write('}');
      if (i != MulberrySymbolResolver.entries.length - 1) buffer.write(',');
      buffer.write('\n');
    }
    buffer.write(']');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制图文映射 JSON')),
    );
  }

  String _stringListJson(List<String> values) {
    final escaped = values
        .map((value) =>
            '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"')
        .join(',');
    return '[$escaped]';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;
    final uniqueAssetCount = MulberrySymbolResolver.entries
        .map((entry) => entry.asset)
        .toSet()
        .length;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5F0),
        foregroundColor: const Color(0xFF25272A),
        title: const Text('图文匹配调试'),
        actions: [
          TextButton(
            onPressed: _copyJson,
            child: const Text('复制 JSON'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _DebugSummaryCard(
            totalCount: MulberrySymbolResolver.entries.length,
            uniqueAssetCount: uniqueAssetCount,
            reviewCount: _reviewCount,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索中文词、英文文件名或分类',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.82),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final entry in entries)
            _SymbolDebugTile(
              entry: entry,
              useCount: _assetUseCounts[entry.asset] ?? 0,
            ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('没有匹配项')),
            ),
        ],
      ),
    );
  }
}

class _DebugSummaryCard extends StatelessWidget {
  const _DebugSummaryCard({
    required this.totalCount,
    required this.uniqueAssetCount,
    required this.reviewCount,
  });

  final int totalCount;
  final int uniqueAssetCount;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
      ),
      child: Row(
        children: [
          _StatItem(label: '映射', value: '$totalCount'),
          _StatItem(label: '图标', value: '$uniqueAssetCount'),
          _StatItem(label: '待审核', value: '$reviewCount'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF25272A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8E8A84),
            ),
          ),
        ],
      ),
    );
  }
}

class _SymbolDebugTile extends StatelessWidget {
  const _SymbolDebugTile({required this.entry, required this.useCount});

  final MulberrySymbolEntry entry;
  final int useCount;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (entry.status) {
      'approved' => const Color(0xFF6C8B78),
      'disabled' => const Color(0xFFC56C6C),
      _ => const Color(0xFFB38B58),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
      ),
      child: Row(
        children: [
          MulberrySymbolIcon(text: entry.primaryText, size: 58, padding: 7),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.primaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF25272A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.asset,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8E8A84),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(label: entry.status, color: statusColor),
                    _Chip(
                        label: entry.confidence,
                        color: const Color(0xFF6F86A8)),
                    if (useCount > 1)
                      _Chip(
                          label: '复用 $useCount',
                          color: const Color(0xFF9D7D9C)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
