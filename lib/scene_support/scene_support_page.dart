import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../location_recommendation.dart';
import 'scene_pack.dart';

typedef SceneExpressionCallback = Future<void> Function(String text);

class SceneSupportPage extends StatefulWidget {
  const SceneSupportPage({
    super.key,
    required this.pack,
    required this.locationController,
    this.onExpressionSpoken,
  });

  final ScenePack pack;
  final LocationRecommendationController locationController;
  final SceneExpressionCallback? onExpressionSpoken;

  @override
  State<SceneSupportPage> createState() => _SceneSupportPageState();
}

class _SceneSupportPageState extends State<SceneSupportPage> {
  final FlutterTts _tts = FlutterTts();

  String _speakingText = '';
  String _bodyPart = '肚子';
  String _painLevel = '中等疼';
  String _duration = '今天';
  String _medicine = '说不清正在吃什么药';
  String _allergy = '没有过敏';
  String _request = '请医生告诉我下一步怎么做';
  String _nextStep = '是否需要做检查';
  String _careNote = '请把注意事项写下来';
  String _lastLearnedText = '';

  @override
  void initState() {
    super.initState();
    unawaited(_tts.setLanguage('zh-CN'));
    unawaited(_tts.setSpeechRate(0.42));
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  String get _placeLabel {
    final place = widget.locationController.currentPlace;
    final semantic = widget.locationController.currentSemantic;
    if (place != null) return place.typeLabel;
    if (semantic != null) return PlaceTypeCatalog.labelOf(semantic.type);
    return '当前场景';
  }

  String get _hospitalSentence {
    return '我想告诉医生：我$_bodyPart不舒服，$_painLevel，已经$_duration。'
        '$_medicine。$_allergy。$_request。';
  }

  String get _hospitalNextStepSentence {
    return '请帮我确认下一步：$_nextStep。$_careNote。';
  }

  Future<void> _speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _speakingText.isNotEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _speakingText = clean);
    try {
      await _tts.stop();
      await _tts.speak(clean);
      await widget.onExpressionSpoken?.call(clean);
      unawaited(
        widget.locationController
            .recordWordUsed(clean, 'scene_${widget.pack.id}'),
      );
      if (!mounted) return;
      setState(() => _lastLearnedText = clean);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              '已播报 · 已记录到当前场景',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            duration: const Duration(milliseconds: 900),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2E3038).withValues(alpha: .92),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _speakingText = '');
    }
  }

  Future<void> _confirmQuickAction(SceneQuickAction action) async {
    if (_speakingText.isNotEmpty) return;
    HapticFeedback.selectionClick();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SceneSpeakConfirmSheet(
        action: action,
        color: widget.pack.color,
        packTitle: widget.pack.title,
      ),
    );
    if (confirmed == true && mounted) {
      await _speak(action.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2EA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF2E3038),
        title: Text(
          pack.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            _SceneHeroCard(
              pack: pack,
              placeLabel: _placeLabel,
            ),
            const SizedBox(height: 12),
            _SceneFlowStrip(color: pack.color),
            if (_lastLearnedText.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SceneLearnedBanner(
                color: pack.color,
                text: _lastLearnedText,
              ),
            ],
            const SizedBox(height: 16),
            if (pack.kind == ScenePackKind.hospitalVisit) ...[
              _buildHospitalVisitCard(),
              const SizedBox(height: 16),
              _buildHospitalNextStepCard(),
              const SizedBox(height: 16),
            ],
            _buildQuickActions(),
            if (pack.partnerTips.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildPartnerTips(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHospitalVisitCard() {
    return _ScenePanel(
      title: '问诊卡',
      subtitle: '先点选，再确认播报给医生',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SceneChoiceSection(
            title: '哪里不舒服？',
            options: const ['头', '胸口', '肚子', '腰', '手脚', '说不清'],
            selected: _bodyPart,
            onSelected: (value) => setState(() => _bodyPart = value),
          ),
          _SceneChoiceSection(
            title: '疼痛程度',
            options: const ['轻微疼', '中等疼', '很疼', '非常疼'],
            selected: _painLevel,
            onSelected: (value) => setState(() => _painLevel = value),
          ),
          _SceneChoiceSection(
            title: '持续多久？',
            options: const ['刚刚', '今天', '几天了', '很久了'],
            selected: _duration,
            onSelected: (value) => setState(() => _duration = value),
          ),
          _SceneChoiceSection(
            title: '正在吃什么药？',
            options: const [
              '没有正在吃药',
              '正在吃降压药',
              '正在吃降糖药',
              '说不清正在吃什么药',
            ],
            selected: _medicine,
            onSelected: (value) => setState(() => _medicine = value),
          ),
          _SceneChoiceSection(
            title: '有没有过敏？',
            options: const ['没有过敏', '有药物过敏', '说不清有没有过敏'],
            selected: _allergy,
            onSelected: (value) => setState(() => _allergy = value),
          ),
          _SceneChoiceSection(
            title: '我需要医生',
            options: const [
              '请医生慢一点说',
              '请医生写下来',
              '请医生告诉我下一步怎么做',
              '请医生帮我联系家人',
            ],
            selected: _request,
            onSelected: (value) => setState(() => _request = value),
          ),
          const SizedBox(height: 12),
          _ScenePreviewBox(
            color: widget.pack.color,
            text: _hospitalSentence,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _speakingText.isEmpty
                  ? () => _speak(_hospitalSentence)
                  : null,
              icon: Icon(
                _speakingText == _hospitalSentence
                    ? Icons.volume_up_rounded
                    : Icons.record_voice_over_rounded,
              ),
              label: const Text(
                '确认播报',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: widget.pack.color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalNextStepCard() {
    return _ScenePanel(
      title: '下一步确认',
      subtitle: '听完医生后，用这张卡确认检查、用药或复诊安排',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SceneChoiceSection(
            title: '我想确认',
            options: const [
              '是否需要做检查',
              '是否需要吃药',
              '是否需要复诊',
              '什么时候再来',
            ],
            selected: _nextStep,
            onSelected: (value) => setState(() => _nextStep = value),
          ),
          _SceneChoiceSection(
            title: '请对方帮我',
            options: const [
              '请把注意事项写下来',
              '请告诉我家属需要知道什么',
              '请说慢一点',
              '请确认我理解对了',
            ],
            selected: _careNote,
            onSelected: (value) => setState(() => _careNote = value),
          ),
          const SizedBox(height: 12),
          _ScenePreviewBox(
            color: widget.pack.color,
            text: _hospitalNextStepSentence,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _speakingText.isEmpty
                  ? () => _speak(_hospitalNextStepSentence)
                  : null,
              icon: Icon(
                _speakingText == _hospitalNextStepSentence
                    ? Icons.volume_up_rounded
                    : Icons.task_alt_rounded,
              ),
              label: const Text(
                '确认下一步',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: widget.pack.color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final pack = widget.pack;
    return _ScenePanel(
      title: pack.kind == ScenePackKind.hospitalVisit ? '就医快捷表达' : pack.title,
      subtitle: '点选候选，确认后播报，并记住当前场景偏好',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: pack.quickActions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.45,
        ),
        itemBuilder: (context, index) {
          final action = pack.quickActions[index];
          final speaking = _speakingText == action.text;
          return _SceneQuickActionCard(
            action: action,
            color: pack.color,
            speaking: speaking,
            disabled: _speakingText.isNotEmpty && !speaking,
            onTap: () => _confirmQuickAction(action),
          );
        },
      ),
    );
  }

  Widget _buildPartnerTips() {
    return _ScenePanel(
      title: '给对方看的提示',
      subtitle: '帮助医生或家属用更低负担的方式沟通',
      child: Column(
        children: [
          for (final tip in widget.pack.partnerTips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, color: widget.pack.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F444A),
                    ),
                  ),
                ),
              ],
            ),
            if (tip != widget.pack.partnerTips.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SceneHeroCard extends StatelessWidget {
  const _SceneHeroCard({
    required this.pack,
    required this.placeLabel,
  });

  final ScenePack pack;
  final String placeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .86)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .045),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: pack.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(pack.icon, color: pack.color, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.title,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E3038),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$placeLabel · 场景任务模式',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7D8490),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  pack.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF626873),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneFlowStrip extends StatelessWidget {
  const _SceneFlowStrip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const steps = ['识别地点', '推荐表达', '确认播报', '记住习惯'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .64),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .78)),
      ),
      child: Row(
        children: [
          for (int index = 0; index < steps.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .14 + index * .03),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    steps[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF626873),
                    ),
                  ),
                ],
              ),
            ),
            if (index != steps.length - 1)
              Container(
                width: 12,
                height: 2,
                margin: const EdgeInsets.only(bottom: 21),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SceneLearnedBanner extends StatelessWidget {
  const _SceneLearnedBanner({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '已学习当前场景常用表达：$text',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF2E3038),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenePreviewBox extends StatelessWidget {
  const _ScenePreviewBox({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          height: 1.32,
          fontWeight: FontWeight.w900,
          color: Color(0xFF2E3038),
        ),
      ),
    );
  }
}

class _ScenePanel extends StatelessWidget {
  const _ScenePanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: .82)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2E3038),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7D8490),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SceneChoiceSection extends StatelessWidget {
  const _SceneChoiceSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF3F444A),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                _SceneChoiceChip(
                  label: option,
                  selected: selected == option,
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SceneChoiceChip extends StatelessWidget {
  const _SceneChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2E3038) : const Color(0xFFF4F3EF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : const Color(0xFF4E535A),
          ),
        ),
      ),
    );
  }
}

class _SceneQuickActionCard extends StatelessWidget {
  const _SceneQuickActionCard({
    required this.action,
    required this.color,
    required this.speaking,
    required this.disabled,
    required this.onTap,
  });

  final SceneQuickAction action;
  final Color color;
  final bool speaking;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFFF0F1F4)
              : color.withValues(alpha: speaking ? .24 : .13),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: speaking ? color : Colors.white.withValues(alpha: .82),
            width: speaking ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: disabled ? .35 : .68),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                speaking ? Icons.volume_up_rounded : action.icon,
                color: disabled ? const Color(0xFF9AA0AA) : color,
                size: 25,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.5,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                      color: disabled
                          ? const Color(0xFF9AA0AA)
                          : const Color(0xFF2E3038),
                    ),
                  ),
                  if (action.helper != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      action.helper!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: disabled
                            ? const Color(0xFFB0B4BD)
                            : const Color(0xFF7D8490),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneSpeakConfirmSheet extends StatelessWidget {
  const _SceneSpeakConfirmSheet({
    required this.action,
    required this.color,
    required this.packTitle,
  });

  final SceneQuickAction action;
  final Color color;
  final String packTitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: .86)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Icon(action.icon, color: color, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        packTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF7D8490),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '确认要播报这句话吗？',
                        style: TextStyle(
                          fontSize: 21,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2E3038),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ScenePreviewBox(color: color, text: action.text),
            if (action.helper != null) ...[
              const SizedBox(height: 10),
              Text(
                action.helper!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6E747D),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      foregroundColor: const Color(0xFF555A61),
                      side: BorderSide(color: color.withValues(alpha: .22)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      '换一句',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text(
                      '确认播报',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
