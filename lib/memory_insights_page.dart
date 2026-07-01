import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'companion_agent.dart';
import 'conversation_terms.dart';
import 'expression_habits.dart';
import 'location_recommendation.dart';
import 'memory_insights.dart';
import 'mulberry_symbols.dart';
import 'personal_objects.dart';

class _MemoryInsightPageData {
  const _MemoryInsightPageData({
    required this.conversationTerms,
    required this.companionLearnedExpressions,
    required this.companionActionBias,
  });

  static const empty = _MemoryInsightPageData(
    conversationTerms: <ConversationTerm>[],
    companionLearnedExpressions: <CompanionLearnedExpression>[],
    companionActionBias: CompanionActionBias(
      accepted: <CompanionActionType, int>{},
      rejected: <CompanionActionType, int>{},
    ),
  );

  final List<ConversationTerm> conversationTerms;
  final List<CompanionLearnedExpression> companionLearnedExpressions;
  final CompanionActionBias companionActionBias;
}

class YuqiaoMemoryPage extends StatefulWidget {
  const YuqiaoMemoryPage({
    super.key,
    required this.recentExpressions,
    required this.favoriteExpressions,
    required this.expressionHabits,
    required this.personalObjects,
    required this.locationController,
    required this.personalizedLearningEnabled,
  });

  final List<String> recentExpressions;
  final List<String> favoriteExpressions;
  final List<ExpressionHabit> expressionHabits;
  final List<PersonalObject> personalObjects;
  final LocationRecommendationController locationController;
  final bool personalizedLearningEnabled;

  @override
  State<YuqiaoMemoryPage> createState() => _YuqiaoMemoryPageState();
}

class _YuqiaoMemoryPageState extends State<YuqiaoMemoryPage> {
  final FlutterTts _tts = FlutterTts();
  late Future<_MemoryInsightPageData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadMemoryData();
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    await _tts.stop();
    await _tts.speak(clean);
  }

  Future<_MemoryInsightPageData> _loadMemoryData() async {
    final termsFuture = ConversationTermStore().loadAll();
    final feedbackStore = CompanionFeedbackStore();
    final companionFuture = feedbackStore.topLearnedExpressions(limit: 8);
    final actionBiasFuture = feedbackStore.actionBiasForContextKeys(
      const ['conversation', 'stuck', 'camera', 'expression', 'favorite'],
    );
    return _MemoryInsightPageData(
      conversationTerms: await termsFuture,
      companionLearnedExpressions: await companionFuture,
      companionActionBias: await actionBiasFuture,
    );
  }

  void _showNodeDetail(MemoryInsightNode node) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _MemoryDetailSheet(
          title: node.detailTitle,
          subtitle: node.subtitle,
          lines: node.detailLines,
          speakText: node.speakText,
          onSpeak:
              node.speakText == null ? null : () => _speak(node.speakText!),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MemoryInsightPageData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _MemoryInsightPageData.empty;
        final insight = const MemoryInsightService().build(
          recentExpressions: widget.recentExpressions,
          favoriteExpressions: widget.favoriteExpressions,
          expressionHabits: widget.expressionHabits,
          personalObjects: widget.personalObjects,
          locationController: widget.locationController,
          conversationTerms: data.conversationTerms,
          companionLearnedExpressions: data.companionLearnedExpressions,
          companionActionBias: data.companionActionBias,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
        );
        return Scaffold(
          backgroundColor: const Color(0xFFF4F1EC),
          body: Stack(
            children: [
              const Positioned.fill(child: _MemorySoftBackground()),
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  children: [
                    _MemoryHeader(onBack: () => Navigator.of(context).pop()),
                    const SizedBox(height: 18),
                    _MemoryHeroCard(insight: insight),
                    const SizedBox(height: 16),
                    _MemoryNetworkCard(
                      nodes: insight.nodes,
                      onNodeTap: _showNodeDetail,
                    ),
                    const SizedBox(height: 16),
                    if (!insight.hasAnyMemory) const _MemoryEmptyCard(),
                    for (final card in insight.evidenceCards) ...[
                      _MemoryEvidenceSection(
                        card: card,
                        onSpeak: card.items.isEmpty
                            ? null
                            : () => _speak(_cleanDisplayItem(card.items.first)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _MemoryPrivacyNote(
                      personalizedLearningEnabled:
                          insight.personalizedLearningEnabled,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _cleanDisplayItem(String value) {
    return value.split('·').first.trim();
  }
}

class _MemoryHeader extends StatelessWidget {
  const _MemoryHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassIconButton(
          icon: CupertinoIcons.chevron_left,
          tooltip: '返回',
          onTap: onBack,
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '语桥记忆',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF3F3B37),
                ),
              ),
              SizedBox(height: 5),
              Text(
                '看看语桥正在如何理解你的表达习惯',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9C948C),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemoryHeroCard extends StatelessWidget {
  const _MemoryHeroCard({required this.insight});

  final MemoryInsightSnapshot insight;

  @override
  Widget build(BuildContext context) {
    final count = insight.learnedExpressionCount;
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD9CE), Color(0xFFD9E7FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEBA6A6).withValues(alpha: 0.22),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0 ? '语桥正在认识你' : '语桥已学会你的 $count 个常用表达',
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF3F3B37),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      insight.personalizedLearningEnabled
                          ? '这些证据来自你确认、收藏、播报和保存过的内容。'
                          : '个性化学习已关闭，当前仅展示本机已有记忆。',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8D867E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MemoryChip(
                label: '常用表达',
                active: _hasEvidence(
                  insight,
                  MemoryInsightNodeType.expression,
                  excludeTitle: '智能体学习',
                ),
              ),
              _MemoryChip(
                label: '帮助偏好',
                active: _hasEvidence(insight, MemoryInsightNodeType.agent),
              ),
              _MemoryChip(
                label: '地点习惯',
                active: _hasEvidence(insight, MemoryInsightNodeType.place),
              ),
              _MemoryChip(
                label: '个人物品',
                active: _hasEvidence(insight, MemoryInsightNodeType.object),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _hasEvidence(
    MemoryInsightSnapshot insight,
    MemoryInsightNodeType type, {
    String excludeTitle = '',
  }) {
    return insight.evidenceCards.any(
      (card) =>
          card.type == type &&
          card.title != excludeTitle &&
          card.items.isNotEmpty,
    );
  }
}

class _MemoryNetworkCard extends StatelessWidget {
  const _MemoryNetworkCard({
    required this.nodes,
    required this.onNodeTap,
  });

  final List<MemoryInsightNode> nodes;
  final ValueChanged<MemoryInsightNode> onNodeTap;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '记忆网络',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF494540),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 248,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final positions = _positionsFor(
                  nodes.length,
                  Size(constraints.maxWidth, constraints.maxHeight),
                );
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MemoryNetworkPainter(
                          positions: positions,
                          colors: nodes.map(_nodeColor).toList(),
                        ),
                      ),
                    ),
                    for (int i = 0; i < nodes.length; i++)
                      Positioned(
                        left: positions[i].dx - 45,
                        top: positions[i].dy - 38,
                        width: 90,
                        child: _MemoryNodeBubble(
                          node: nodes[i],
                          color: _nodeColor(nodes[i]),
                          onTap: () => onNodeTap(nodes[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static List<Offset> _positionsFor(int count, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    if (count <= 1) return [center];
    final radiusX = math.max(86.0, size.width * 0.34);
    final radiusY = size.height * 0.32;
    final result = <Offset>[center];
    for (int i = 1; i < count; i++) {
      final angle = -math.pi / 2 + (i - 1) * math.pi * 2 / (count - 1);
      result.add(
        Offset(
          center.dx + math.cos(angle) * radiusX,
          center.dy + math.sin(angle) * radiusY,
        ),
      );
    }
    return result;
  }
}

class _MemoryNodeBubble extends StatelessWidget {
  const _MemoryNodeBubble({
    required this.node,
    required this.color,
    required this.onTap,
  });

  final MemoryInsightNode node;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelf = node.type == MemoryInsightNodeType.self;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isSelf ? 66 : 56,
            height: isSelf ? 66 : 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: isSelf ? 0.94 : 0.82),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.84),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              _nodeIcon(node.type),
              color: Colors.white,
              size: isSelf ? 28 : 24,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            node.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: Color(0xFF4B4742),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            node.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9B948E),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryEvidenceSection extends StatelessWidget {
  const _MemoryEvidenceSection({
    required this.card,
    required this.onSpeak,
  });

  final MemoryEvidenceCard card;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _nodeColorType(card.type).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _nodeIcon(card.type),
              color: _nodeColorType(card.type),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF4B4742),
                        ),
                      ),
                    ),
                    if (onSpeak != null) _MiniSpeakButton(onTap: onSpeak!),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  card.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9C958D),
                  ),
                ),
                const SizedBox(height: 10),
                if (card.items.isEmpty)
                  Text(
                    card.emptyText,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB2ABA4),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: card.items.take(4).map((item) {
                      final cleanText = item.split('·').first.trim();
                      return _EvidencePill(
                        text: item,
                        symbolText: cleanText,
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidencePill extends StatelessWidget {
  const _EvidencePill({
    required this.text,
    required this.symbolText,
  });

  final String text;
  final String symbolText;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MulberrySymbolIcon(
            text: symbolText,
            size: 24,
            padding: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.36),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5B5650),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryEmptyCard extends StatelessWidget {
  const _MemoryEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _GlassPanel(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '还没有形成清晰记忆',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF4B4742),
              ),
            ),
            SizedBox(height: 8),
            Text(
              '继续使用补词、对话、拍照识物或收藏表达后，这里会自动出现真实的学习证据。',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8F8780),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryPrivacyNote extends StatelessWidget {
  const _MemoryPrivacyNote({required this.personalizedLearningEnabled});

  final bool personalizedLearningEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
      child: Text(
        personalizedLearningEnabled
            ? '这些记忆只保存在本机，可在“我的”里关闭个性化学习或清除记录。'
            : '个性化学习已关闭；语桥不会继续学习新的常用表达。',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: Color(0xFFAAA39C),
        ),
      ),
    );
  }
}

class _MemoryDetailSheet extends StatelessWidget {
  const _MemoryDetailSheet({
    required this.title,
    required this.subtitle,
    required this.lines,
    required this.speakText,
    required this.onSpeak,
  });

  final String title;
  final String subtitle;
  final List<String> lines;
  final String? speakText;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _GlassPanel(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D4CE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF3F3B37),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9B948D),
                ),
              ),
              const SizedBox(height: 14),
              for (final line in lines.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          CupertinoIcons.smallcircle_fill_circle,
                          size: 10,
                          color: Color(0xFFD2A6A2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5B5650),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (onSpeak != null && speakText != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onSpeak,
                    icon: const Icon(CupertinoIcons.speaker_2_fill, size: 18),
                    label: Text('播报“$speakText”'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7B92A8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryNetworkPainter extends CustomPainter {
  const _MemoryNetworkPainter({
    required this.positions,
    required this.colors,
  });

  final List<Offset> positions;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length <= 1) return;
    final center = positions.first;
    for (int i = 1; i < positions.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          colors: [
            colors.first.withValues(alpha: 0.22),
            colors[i].withValues(alpha: 0.36),
          ],
        ).createShader(Rect.fromPoints(center, positions[i]));
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(
          (center.dx + positions[i].dx) / 2,
          (center.dy + positions[i].dy) / 2 - 18,
          positions[i].dx,
          positions[i].dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MemoryNetworkPainter oldDelegate) {
    return oldDelegate.positions != positions || oldDelegate.colors != colors;
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.76)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7F8FA6).withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
              ),
              child: Icon(icon, color: const Color(0xFF5D6470), size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryChip extends StatelessWidget {
  const _MemoryChip({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFFFF0D8).withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.68)),
      ),
      child: Text(
        active ? '$label 已形成' : '$label 待学习',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: active ? const Color(0xFF8D6E4B) : const Color(0xFFA9A29B),
        ),
      ),
    );
  }
}

class _MiniSpeakButton extends StatelessWidget {
  const _MiniSpeakButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF7B92A8).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          CupertinoIcons.speaker_2_fill,
          size: 17,
          color: Color(0xFF6D8398),
        ),
      ),
    );
  }
}

class _MemorySoftBackground extends StatelessWidget {
  const _MemorySoftBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF5EB),
            Color(0xFFF2F6F8),
            Color(0xFFF7F1F4),
          ],
        ),
      ),
    );
  }
}

Color _nodeColor(MemoryInsightNode node) => _nodeColorType(node.type);

Color _nodeColorType(MemoryInsightNodeType type) {
  switch (type) {
    case MemoryInsightNodeType.self:
      return const Color(0xFFD8A7A7);
    case MemoryInsightNodeType.expression:
      return const Color(0xFF8CA0B3);
    case MemoryInsightNodeType.place:
      return const Color(0xFFD4B06A);
    case MemoryInsightNodeType.object:
      return const Color(0xFFA8B79A);
    case MemoryInsightNodeType.conversation:
      return const Color(0xFFB7A4C8);
    case MemoryInsightNodeType.agent:
      return const Color(0xFF86A9A0);
  }
}

IconData _nodeIcon(MemoryInsightNodeType type) {
  switch (type) {
    case MemoryInsightNodeType.self:
      return CupertinoIcons.person_fill;
    case MemoryInsightNodeType.expression:
      return CupertinoIcons.chat_bubble_text_fill;
    case MemoryInsightNodeType.place:
      return CupertinoIcons.location_fill;
    case MemoryInsightNodeType.object:
      return CupertinoIcons.cube_box_fill;
    case MemoryInsightNodeType.conversation:
      return CupertinoIcons.person_2_fill;
    case MemoryInsightNodeType.agent:
      return CupertinoIcons.wand_stars;
  }
}
