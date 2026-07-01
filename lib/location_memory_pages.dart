import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'location_recommendation.dart';

typedef FavoriteWordCallback = Future<void> Function(String text);

const bool _showInternalDebugControls = false;
const bool _locationMemoryDebugLogs = false;

void _locationMemoryDebugLog(String message) {
  if (_locationMemoryDebugLogs) debugPrint(message);
}

class CurrentPlaceStatusCard extends StatefulWidget {
  const CurrentPlaceStatusCard({
    super.key,
    required this.controller,
  });

  final LocationRecommendationController controller;

  @override
  State<CurrentPlaceStatusCard> createState() => _CurrentPlaceStatusCardState();
}

class _CurrentPlaceStatusCardState extends State<CurrentPlaceStatusCard> {
  Timer? _autoHideTimer;
  String? _confirmedPlaceId;

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _startAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        widget.controller.dismissCurrentSuggestion();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!widget.controller.enabled ||
            widget.controller.currentSuggestionDismissed) {
          return const SizedBox.shrink();
        }
        final place = widget.controller.currentPlace;
        final semantic = widget.controller.currentSemantic;
        if (place == null && semantic == null) return const SizedBox.shrink();

        final userConfirmed = place?.isUserConfirmed ?? false;
        final type = userConfirmed
            ? place!.normalizedType
            : semantic?.type ?? place?.normalizedType;
        final typeLabel = PlaceTypeCatalog.labelOf(type);
        final name = userConfirmed
            ? place!.name
            : semantic?.displayName ?? place?.name ?? typeLabel;

        // 确认后自动隐藏
        if (userConfirmed && _confirmedPlaceId != place!.id) {
          _confirmedPlaceId = place.id;
          WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoHide());
        }

        return AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 1.1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: userConfirmed
                ? Row(
                    children: [
                      const Icon(
                        CupertinoIcons.location_fill,
                        color: Color(0xFF267D70),
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              place!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                            Text(
                              '$typeLabel · 已确认',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6E7178),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '修改地点',
                        onPressed: () => showPlaceEditorDialog(
                          context,
                          controller: widget.controller,
                          place: place,
                        ),
                        icon: const Icon(CupertinoIcons.pencil, size: 18),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.location_fill,
                            color: Color(0xFF267D70),
                            size: 18,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '这里可能是：$typeLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                          ),
                          Text(
                            '自动建议',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '是否保存为$typeLabel？  $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6E7178),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _PlaceActionButton(
                            label: '确认',
                            primary: true,
                            onTap: () =>
                                widget.controller.confirmCurrentSuggestion(
                              name: typeLabel,
                              type: type,
                            ),
                          ),
                          const SizedBox(width: 7),
                          _PlaceActionButton(
                            label: '修改',
                            onTap: () => showPlaceEditorDialog(
                              context,
                              controller: widget.controller,
                              place: place,
                              semantic: semantic,
                            ),
                          ),
                          const SizedBox(width: 7),
                          _PlaceActionButton(
                            label: '暂不',
                            onTap: widget.controller.dismissCurrentSuggestion,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _PlaceActionButton extends StatelessWidget {
  const _PlaceActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? const Color(0xFF267D70) : const Color(0xFFF0F2F5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary ? Colors.white : const Color(0xFF45474D),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showPlaceEditorDialog(
  BuildContext context, {
  required LocationRecommendationController controller,
  PlaceCluster? place,
  PlaceSemantic? semantic,
}) async {
  final suggestedType = semantic?.type ?? place?.suggestedType;
  final initialType =
      place?.normalizedType ?? suggestedType ?? PlaceTypeCatalog.unknown;
  final initialName = place?.name ??
      (suggestedType == null ? '' : PlaceTypeCatalog.labelOf(suggestedType));
  final result = await showDialog<_PlaceEditResult>(
    context: context,
    builder: (context) => _PlaceEditorDialog(
      initialName: initialName,
      initialType: initialType,
    ),
  );
  if (result == null) return;
  if (place == null) {
    await controller.confirmCurrentSuggestion(
      name: result.name,
      type: result.type,
    );
  } else {
    await controller.updatePlace(
      place.id,
      name: result.name,
      type: result.type,
    );
  }
}

class _PlaceEditResult {
  const _PlaceEditResult(this.name, this.type);

  final String name;
  final String type;
}

class _PlaceEditorDialog extends StatefulWidget {
  const _PlaceEditorDialog({
    required this.initialName,
    required this.initialType,
  });

  final String initialName;
  final String initialType;

  @override
  State<_PlaceEditorDialog> createState() => _PlaceEditorDialogState();
}

class _PlaceEditorDialogState extends State<_PlaceEditorDialog> {
  late final TextEditingController _nameController;
  late String _type;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认地点'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: '地点名称',
                hintText: '例如：家、常去的医院',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '地点类型',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: PlaceTypeCatalog.editableTypes.map((type) {
                return ChoiceChip(
                  label: Text(PlaceTypeCatalog.labelOf(type)),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              _PlaceEditResult(_nameController.text.trim(), _type),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class PlaceMemoryManagementPage extends StatefulWidget {
  const PlaceMemoryManagementPage({
    super.key,
    required this.controller,
    this.onFavoriteSaved,
  });

  final LocationRecommendationController controller;
  final FavoriteWordCallback? onFavoriteSaved;

  @override
  State<PlaceMemoryManagementPage> createState() =>
      _PlaceMemoryManagementPageState();
}

class _PlaceMemoryManagementPageState extends State<PlaceMemoryManagementPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final places = controller.places;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('地点记忆管理'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _SettingsBand(controller: controller),
          const SizedBox(height: 18),
          if (places.isEmpty)
            const _EmptyPlaces()
          else
            for (final place in places) ...[
              _PlaceMemoryCard(
                place: place,
                controller: controller,
                onOpenWords: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlaceWordsPage(
                      placeId: place.id,
                      controller: controller,
                      onFavoriteSaved: widget.onFavoriteSaved,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          if (_showInternalDebugControls) ...[
            const SizedBox(height: 10),
            _LocationDebugTools(controller: controller),
          ],
        ],
      ),
    );
  }
}

class _SettingsBand extends StatelessWidget {
  const _SettingsBand({required this.controller});

  final LocationRecommendationController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '地点词汇推荐',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              Switch.adaptive(
                value: controller.enabled,
                onChanged: controller.setEnabled,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '语桥会在你使用 App 时根据当前位置推荐这个地点常用表达。地点数据默认只保存在本机，你可以随时修改或清除。启用自动识别时，坐标会发送给高德地图，但不会发送给 AI。',
            style:
                TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF62666F)),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: controller.places.isEmpty
                ? null
                : () => _confirmClearAll(context, controller),
            icon: const Icon(CupertinoIcons.trash, size: 18),
            label: const Text('清除全部地点数据'),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFD44848)),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmClearAll(
  BuildContext context,
  LocationRecommendationController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除全部地点数据？'),
      content: const Text('地点名称、类型和地点词汇记录都会被删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.clearPlaceData();
}

class _EmptyPlaces extends StatelessWidget {
  const _EmptyPlaces();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      child: Column(
        children: [
          Icon(CupertinoIcons.location, size: 38, color: Color(0xFF9A9DA4)),
          SizedBox(height: 12),
          Text('还没有地点记忆', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            '在地点中使用一次词汇，或确认首页的地点建议后，这里会出现记录。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF777A82), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PlaceMemoryCard extends StatelessWidget {
  const _PlaceMemoryCard({
    required this.place,
    required this.controller,
    required this.onOpenWords,
  });

  final PlaceCluster place;
  final LocationRecommendationController controller;
  final VoidCallback onOpenWords;

  @override
  Widget build(BuildContext context) {
    final hasSuggestion = place.suggestedType != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.location_fill,
                  color: Color(0xFF267D70), size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  place.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                place.isUserConfirmed ? '用户已确认' : '自动建议',
                style: TextStyle(
                  fontSize: 11,
                  color: place.isUserConfirmed
                      ? const Color(0xFF267D70)
                      : const Color(0xFF777A82),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${place.typeLabel} · 访问 ${place.visitCount} 次 · ${_formatDate(place.lastSeenAt)}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF62666F)),
          ),
          if (hasSuggestion) ...[
            const SizedBox(height: 5),
            Text(
              '系统建议：${place.suggestedName ?? PlaceTypeCatalog.labelOf(place.suggestedType)} · ${PlaceTypeCatalog.labelOf(place.suggestedType)}${place.suggestedConfidence == null ? '' : ' · ${(place.suggestedConfidence! * 100).round()}%'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF777A82)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              TextButton.icon(
                onPressed: () => showPlaceEditorDialog(
                  context,
                  controller: controller,
                  place: place,
                ),
                icon: const Icon(CupertinoIcons.pencil, size: 16),
                label: const Text('编辑'),
              ),
              if (hasSuggestion)
                TextButton(
                  onPressed: () => controller.acceptSuggestion(place.id),
                  child: const Text('接受建议'),
                ),
              TextButton(
                onPressed: controller.enabled
                    ? () => controller.refreshSuggestionForPlace(place.id)
                    : null,
                child: const Text('重新识别'),
              ),
              TextButton(
                onPressed: onOpenWords,
                child: Text('常用词 ${controller.wordCountForPlace(place.id)}'),
              ),
              IconButton(
                tooltip: '删除地点',
                onPressed: () => _confirmDeletePlace(context),
                icon: const Icon(CupertinoIcons.trash,
                    size: 18, color: Color(0xFFD44848)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeletePlace(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${place.name}”？'),
        content: const Text('这个地点下的词汇记录也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deletePlace(place.id);
  }
}

class PlaceWordsPage extends StatefulWidget {
  const PlaceWordsPage({
    super.key,
    required this.placeId,
    required this.controller,
    this.onFavoriteSaved,
  });

  final String placeId;
  final LocationRecommendationController controller;
  final FavoriteWordCallback? onFavoriteSaved;

  @override
  State<PlaceWordsPage> createState() => _PlaceWordsPageState();
}

class _PlaceWordsPageState extends State<PlaceWordsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.controller.places.indexWhere(
      (place) => place.id == widget.placeId,
    );
    final place = index < 0 ? null : widget.controller.places[index];
    final words = widget.controller.wordsForPlace(widget.placeId);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(place == null ? '地点常用词' : '${place.name}的常用词'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: words.isEmpty
                ? null
                : () => widget.controller.clearWordsForPlace(widget.placeId),
            child: const Text('清空'),
          ),
        ],
      ),
      body: words.isEmpty
          ? const Center(child: Text('这个地点还没有词汇记录'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: words.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final usage = words[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(usage.wordText),
                  subtitle: Text(
                    '${usage.category} · 使用 ${usage.count} 次 · ${_formatDate(usage.lastUsedAt)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onFavoriteSaved != null)
                        IconButton(
                          tooltip: '加入收藏',
                          onPressed: () =>
                              widget.onFavoriteSaved!(usage.wordText),
                          icon: const Icon(CupertinoIcons.star, size: 20),
                        ),
                      IconButton(
                        tooltip: '删除记录',
                        onPressed: () =>
                            widget.controller.deleteWordUsage(usage.id),
                        icon: const Icon(CupertinoIcons.trash,
                            size: 19, color: Color(0xFFD44848)),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _LocationDebugTools extends StatelessWidget {
  const _LocationDebugTools({required this.controller});

  final LocationRecommendationController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.currentPlace;
    final semantic = controller.currentSemantic;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Debug 验证', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('当前地点：${current?.name ?? '无'}'),
          Text('当前类型：${current?.normalizedType ?? semantic?.type ?? '无'}'),
          Text('typeSource：${current?.typeSource ?? '无'}'),
          Text(
              'suggestedType：${current?.suggestedType ?? semantic?.type ?? '无'}'),
          Text(
            'suggestedConfidence：${current?.suggestedConfidence?.toStringAsFixed(2) ?? semantic?.confidence.toStringAsFixed(2) ?? '无'}',
          ),
          Text(
              '当前地点词汇：${current == null ? 0 : controller.wordCountForPlace(current.id)}'),
          if (controller.lastRecommendationScores.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('最近推荐排序：',
                style: TextStyle(fontWeight: FontWeight.w700)),
            for (final score in controller.lastRecommendationScores.take(8))
              Text(
                '${score.text} ${score.score.toStringAsFixed(0)} · ${score.reasons.join(' / ')}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
          if (controller.lastRecommendationFilters.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('本次过滤：', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final item in controller.lastRecommendationFilters.take(8))
              Text(
                '${item.text}：${item.reason}（${item.source}）',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9B4A4A)),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              OutlinedButton(
                onPressed: () => controller.refreshLocationContext(force: true),
                child: const Text('刷新位置'),
              ),
              OutlinedButton(
                onPressed: () => controller.recordWordUsed('喝水', 'debug'),
                child: const Text('记录“喝水”'),
              ),
              OutlinedButton(
                onPressed: () => controller.recordWordUsed('医生', 'debug'),
                child: const Text('记录“医生”'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final json = controller.exportDataJson();
                  await Clipboard.setData(ClipboardData(text: json));
                  _locationMemoryDebugLog(json);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('地点 JSON 已复制到剪贴板')),
                    );
                  }
                },
                child: const Text('导出 JSON'),
              ),
              OutlinedButton(
                onPressed: controller.clearPlaceData,
                child: const Text('清除地点'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
