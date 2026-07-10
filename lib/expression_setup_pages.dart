part of 'main.dart';

class ExpressionPreference {
  const ExpressionPreference({
    this.preferredCandidateCount = 2,
    this.displayMode = 'mixed',
    this.imageScale = 1.0,
  });

  final int preferredCandidateCount;
  final String displayMode;
  final double imageScale;

  int get effectiveCandidateCount =>
      preferredCandidateCount.clamp(2, 6).toInt();
  double get effectiveImageScale => imageScale.clamp(0.85, 1.55).toDouble();

  String get summary {
    final countLabel = switch (effectiveCandidateCount) {
      2 => '少',
      4 => '标准',
      6 => '多',
      _ => '$effectiveCandidateCount 个',
    };
    final modeLabel = switch (displayMode) {
      'largeText' => '大文字',
      'imageFirst' => '图片优先',
      _ => '图文一起',
    };
    final imageLabel = switch (effectiveImageScale) {
      <= 0.9 => '小图标',
      >= 1.45 => '特大图标',
      >= 1.2 => '大图标',
      _ => '标准图标',
    };
    return '$countLabel · $modeLabel · $imageLabel';
  }

  Map<String, dynamic> toJson() => {
        'preferredCandidateCount': effectiveCandidateCount,
        'displayMode': displayMode,
        'imageScale': effectiveImageScale,
      };

  static ExpressionPreference fromJson(Map<String, dynamic> json) {
    final count = json['preferredCandidateCount'];
    final mode = json['displayMode'];
    final scale = json['imageScale'];
    return ExpressionPreference(
      preferredCandidateCount: count is int ? count.clamp(2, 6).toInt() : 2,
      displayMode: mode is String && mode.isNotEmpty ? mode : 'mixed',
      imageScale:
          scale is num ? scale.toDouble().clamp(0.85, 1.55).toDouble() : 1.0,
    );
  }
}

class SupportProfile {
  const SupportProfile({
    this.completed = false,
    this.difficulties = const ['找词'],
    this.scenes = const ['家里'],
    this.cuePreferences = const ['图片'],
    this.trainingMinutes = 3,
    this.candidateCount = 2,
    this.needsFamilyAssist = false,
    this.rememberChoices = true,
    this.createdAt,
  });

  final bool completed;
  final List<String> difficulties;
  final List<String> scenes;
  final List<String> cuePreferences;
  final int trainingMinutes;
  final int candidateCount;
  final bool needsFamilyAssist;
  final bool rememberChoices;
  final DateTime? createdAt;

  bool get prefersImages =>
      cuePreferences.contains('图片') ||
      difficulties.contains('看字写字') ||
      difficulties.contains('听懂别人');
  bool get prefersLargeText =>
      cuePreferences.contains('文字') || difficulties.contains('听懂别人');
  bool get needsLargeTouchTargets =>
      difficulties.contains('手部操作') || cuePreferences.contains('大按钮');

  ExpressionPreference toExpressionPreference() {
    final displayMode = prefersImages
        ? 'imageFirst'
        : prefersLargeText
            ? 'largeText'
            : 'mixed';
    final imageScale = needsLargeTouchTargets
        ? 1.55
        : prefersImages
            ? 1.35
            : 1.0;
    final effectiveCount =
        difficulties.contains('听懂别人') || needsLargeTouchTargets
            ? 2
            : candidateCount;
    return ExpressionPreference(
      preferredCandidateCount: effectiveCount.clamp(2, 6).toInt(),
      displayMode: displayMode,
      imageScale: imageScale,
    );
  }

  SupportProfile copyWith({
    bool? completed,
    List<String>? difficulties,
    List<String>? scenes,
    List<String>? cuePreferences,
    int? trainingMinutes,
    int? candidateCount,
    bool? needsFamilyAssist,
    bool? rememberChoices,
    DateTime? createdAt,
  }) {
    return SupportProfile(
      completed: completed ?? this.completed,
      difficulties: difficulties ?? this.difficulties,
      scenes: scenes ?? this.scenes,
      cuePreferences: cuePreferences ?? this.cuePreferences,
      trainingMinutes: trainingMinutes ?? this.trainingMinutes,
      candidateCount: candidateCount ?? this.candidateCount,
      needsFamilyAssist: needsFamilyAssist ?? this.needsFamilyAssist,
      rememberChoices: rememberChoices ?? this.rememberChoices,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'completed': completed,
        'difficulties': difficulties,
        'scenes': scenes,
        'cuePreferences': cuePreferences,
        'trainingMinutes': trainingMinutes,
        'candidateCount': candidateCount,
        'needsFamilyAssist': needsFamilyAssist,
        'rememberChoices': rememberChoices,
        'createdAt': createdAt?.toIso8601String(),
      };

  static SupportProfile fromJson(Map<String, dynamic> json) {
    List<String> readStringList(String key, List<String> fallback) {
      final raw = json[key];
      if (raw is List) {
        final values = raw.whereType<String>().where((item) {
          return item.trim().isNotEmpty;
        }).toList();
        if (values.isNotEmpty) return values;
      }
      return fallback;
    }

    final createdRaw = json['createdAt'];
    return SupportProfile(
      completed: json['completed'] == true,
      difficulties: readStringList('difficulties', const ['找词']),
      scenes: readStringList('scenes', const ['家里']),
      cuePreferences: readStringList('cuePreferences', const ['图片']),
      trainingMinutes: json['trainingMinutes'] is int
          ? (json['trainingMinutes'] as int).clamp(3, 10).toInt()
          : 3,
      candidateCount: json['candidateCount'] is int
          ? (json['candidateCount'] as int).clamp(2, 6).toInt()
          : 2,
      needsFamilyAssist: json['needsFamilyAssist'] == true,
      rememberChoices: json['rememberChoices'] != false,
      createdAt: createdRaw is String ? DateTime.tryParse(createdRaw) : null,
    );
  }
}

class _YuqiaoLoadingPage extends StatelessWidget {
  const _YuqiaoLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F2EA),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF5F8DF7)),
      ),
    );
  }
}

class SupportProfileSetupPage extends StatefulWidget {
  const SupportProfileSetupPage({
    super.key,
    required this.initialProfile,
    required this.onCompleted,
  });

  final SupportProfile initialProfile;
  final Future<void> Function(SupportProfile profile) onCompleted;

  @override
  State<SupportProfileSetupPage> createState() =>
      _SupportProfileSetupPageState();
}

class _SupportProfileSetupPageState extends State<SupportProfileSetupPage> {
  static const List<String> _difficultyOptions = [
    '找词',
    '听懂别人',
    '看字写字',
    '发音',
    '手部操作',
    '不确定',
  ];
  static const List<String> _sceneOptions = [
    '家里',
    '医院',
    '康复训练',
    '超市',
    '电话',
    '社交',
    '出门交通',
    '紧急求助',
  ];
  static const List<String> _cueOptions = [
    '图片',
    '文字',
    '语音',
    '拼音',
    '手写',
    '大按钮',
  ];

  late SupportProfile _profile;
  int _step = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
  }

  void _toggleListValue(
    List<String> current,
    String value,
    ValueChanged<List<String>> update,
  ) {
    final updated = current.contains(value)
        ? current.where((item) => item != value).toList()
        : [...current, value];
    update(updated.isEmpty ? [value] : updated);
  }

  void _next() {
    if (_step < 4) {
      setState(() => _step += 1);
      return;
    }
    _complete();
  }

  void _previous() {
    if (_step <= 0 || _isSaving) return;
    setState(() => _step -= 1);
  }

  Future<void> _complete() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    await widget.onCompleted(_profile);
    if (mounted) setState(() => _isSaving = false);
  }

  String get _stepTitle => switch (_step) {
        0 => '你现在最需要帮助的是？',
        1 => '最常在哪些地方使用？',
        2 => '哪种提示更容易看懂？',
        3 => '每次表达给多少选择？',
        _ => '语桥会这样适应你',
      };

  String get _stepSubtitle => switch (_step) {
        0 => '可以多选，不需要判断类型，只告诉语桥哪里最费劲。',
        1 => '这些场景会影响常用表达和候选内容。',
        2 => '后续候选卡片会按这个偏好调整图像、文字和点击区域。',
        3 => '少一点更轻松，多一点选择更充分。',
        _ => '完成后仍然可以在设置里修改表达偏好。',
      };

  Widget _buildMultiChoiceStep({
    required List<String> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in options)
          _SupportProfileChip(
            label: option,
            selected: selected.contains(option),
            onTap: () => setState(() {
              _toggleListValue(selected, option, onChanged);
            }),
          ),
      ],
    );
  }

  Widget _buildCandidateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '候选数量',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2C2D31),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final count in const [2, 4, 6]) ...[
              _ChoicePill(
                label: '$count 个',
                selected: _profile.candidateCount == count,
                onTap: () => setState(() {
                  _profile = _profile.copyWith(candidateCount: count);
                }),
              ),
              if (count != 6) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          '每次训练多久',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2C2D31),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final minutes in const [3, 5, 10]) ...[
              _ChoicePill(
                label: '$minutes 分钟',
                selected: _profile.trainingMinutes == minutes,
                onTap: () => setState(() {
                  _profile = _profile.copyWith(trainingMinutes: minutes);
                }),
              ),
              if (minutes != 10) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 22),
        _SupportSwitchTile(
          title: '需要家属协助配置',
          subtitle: '之后可以请家属帮忙添加常用词和个人物品',
          value: _profile.needsFamilyAssist,
          onChanged: (value) => setState(() {
            _profile = _profile.copyWith(needsFamilyAssist: value);
          }),
        ),
      ],
    );
  }

  List<String> _adaptationLines() {
    final preference = _profile.toExpressionPreference();
    return [
      '默认每次显示 ${preference.effectiveCandidateCount} 个候选',
      switch (preference.displayMode) {
        'imageFirst' => '候选会优先显示更大的图标',
        'largeText' => '候选会优先显示更醒目的文字',
        _ => '候选会保持图文平衡',
      },
      switch (preference.effectiveImageScale) {
        >= 1.45 => '点击区域和图标会明显放大',
        >= 1.2 => '图标会比默认更大',
        _ => '图标保持标准大小',
      },
      '训练节奏默认 ${_profile.trainingMinutes} 分钟',
      _profile.needsFamilyAssist ? '保留家属协助入口' : '先使用个人轻量配置',
    ];
  }

  Widget _buildSummaryStep() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '完成后，界面会马上变化',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF26282D),
                ),
              ),
              const SizedBox(height: 12),
              for (final line in _adaptationLines()) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: Color(0xFF5F8DF7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A4B50),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SupportSwitchTile(
          title: '允许语桥记住我的选择',
          subtitle: '开启后，系统会学习常用表达；关闭则只保留本次基础设置',
          value: _profile.rememberChoices,
          onChanged: (value) => setState(() {
            _profile = _profile.copyWith(rememberChoices: value);
          }),
        ),
      ],
    );
  }

  Widget _buildStepBody() {
    return switch (_step) {
      0 => _buildMultiChoiceStep(
          options: _difficultyOptions,
          selected: _profile.difficulties,
          onChanged: (items) =>
              _profile = _profile.copyWith(difficulties: items),
        ),
      1 => _buildMultiChoiceStep(
          options: _sceneOptions,
          selected: _profile.scenes,
          onChanged: (items) => _profile = _profile.copyWith(scenes: items),
        ),
      2 => _buildMultiChoiceStep(
          options: _cueOptions,
          selected: _profile.cuePreferences,
          onChanged: (items) =>
              _profile = _profile.copyWith(cuePreferences: items),
        ),
      3 => _buildCandidateStep(),
      _ => _buildSummaryStep(),
    };
  }

  Widget _buildAnimatedStepBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return currentChild ?? const SizedBox.shrink();
      },
      transitionBuilder: (child, animation) {
        final childStep = (child.key as ValueKey<int>).value;
        final forward = childStep >= _step;
        final offset = Tween<Offset>(
          begin: Offset(forward ? 0.08 : -0.08, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: SingleChildScrollView(
        key: ValueKey<int>(_step),
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 4),
        child: _buildStepBody(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_step + 1) / 5;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F0E7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFD7B0), Color(0xFFFFECCF)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD7A86E).withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF26282D),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    '表达支持档案',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF26282D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.76),
                color: const Color(0xFF2E3038),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: math.max(
                390.0,
                MediaQuery.sizeOf(context).height -
                    MediaQuery.paddingOf(context).vertical -
                    238,
              ),
              child: _PreferenceCard(
                title: _stepTitle,
                subtitle: _stepSubtitle,
                fillChild: true,
                child: _buildAnimatedStepBody(),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving || _step == 0 ? null : _previous,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: const Color(0xFF4A4B50),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      '上一步',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _next,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF2E3038),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFF2E3038).withValues(alpha: 0.38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      _isSaving ? '正在保存' : (_step == 4 ? '开始使用语桥' : '下一步'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
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

class _SupportProfileChip extends StatelessWidget {
  const _SupportProfileChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF5F8DF7) : const Color(0xFFF7F5F1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF5F8DF7)
                : Colors.white.withValues(alpha: 0.78),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF5F8DF7).withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : const Color(0xFF4A4B50),
          ),
        ),
      ),
    );
  }
}

class _SupportSwitchTile extends StatelessWidget {
  const _SupportSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2C2D31),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A8782),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF5F8DF7),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class ExpressionPreferencePage extends StatefulWidget {
  const ExpressionPreferencePage({
    super.key,
    required this.initialPreference,
  });

  final ExpressionPreference initialPreference;

  @override
  State<ExpressionPreferencePage> createState() =>
      _ExpressionPreferencePageState();
}

class _ExpressionPreferencePageState extends State<ExpressionPreferencePage> {
  late int _candidateCount;
  late String _displayMode;
  late double _imageScale;

  @override
  void initState() {
    super.initState();
    _candidateCount = widget.initialPreference.effectiveCandidateCount;
    _displayMode = widget.initialPreference.displayMode;
    _imageScale = widget.initialPreference.effectiveImageScale;
  }

  void _save() {
    Navigator.of(context).pop(
      ExpressionPreference(
        preferredCandidateCount: _candidateCount,
        displayMode: _displayMode,
        imageScale: _imageScale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2EA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          children: [
            Row(
              children: [
                _RoundIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    '表达偏好',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF26282D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '设置补词时每一组显示多少个候选，以及候选卡片中文字和图像的呈现方式。',
              style: TextStyle(
                fontSize: 16,
                height: 1.45,
                color: Color(0xFF7A7C82),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            _PreferenceCard(
              title: '每组候选数量',
              subtitle: '少一点更轻松，多一点选择更充分',
              child: Row(
                children: [
                  _ChoicePill(
                    label: '2 个',
                    selected: _candidateCount == 2,
                    onTap: () => setState(() => _candidateCount = 2),
                  ),
                  const SizedBox(width: 10),
                  _ChoicePill(
                    label: '4 个',
                    selected: _candidateCount == 4,
                    onTap: () => setState(() => _candidateCount = 4),
                  ),
                  const SizedBox(width: 10),
                  _ChoicePill(
                    label: '6 个',
                    selected: _candidateCount == 6,
                    onTap: () => setState(() => _candidateCount = 6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PreferenceCard(
              title: '图片大小',
              subtitle: '调大后，补词和对话候选里的图标会占据更多空间',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44 * _imageScale,
                        height: 44 * _imageScale,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFE2C8),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.touch_app_rounded,
                          size: 26 * _imageScale,
                          color: Color(0xFF26282D),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          switch (_imageScale) {
                            <= 0.9 => '小图标',
                            >= 1.45 => '特大图标',
                            >= 1.2 => '大图标',
                            _ => '标准图标',
                          },
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF26282D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF5F8DF7),
                      inactiveTrackColor: const Color(0xFFDADCE3),
                      thumbColor: const Color(0xFF5F8DF7),
                      overlayColor:
                          const Color(0xFF5F8DF7).withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: _imageScale,
                      min: 0.85,
                      max: 1.55,
                      divisions: 7,
                      onChanged: (value) => setState(() {
                        _imageScale = double.parse(value.toStringAsFixed(2));
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PreferenceCard(
              title: '显示方式',
              subtitle: '影响候选卡片里文字和图像的侧重',
              child: Column(
                children: [
                  _ModeRow(
                    title: '大文字',
                    subtitle: '文字更醒目，适合快速点选',
                    selected: _displayMode == 'largeText',
                    onTap: () => setState(() => _displayMode = 'largeText'),
                  ),
                  const SizedBox(height: 10),
                  _ModeRow(
                    title: '图文一起',
                    subtitle: '文字和图标保持平衡',
                    selected: _displayMode == 'mixed',
                    onTap: () => setState(() => _displayMode = 'mixed'),
                  ),
                  const SizedBox(height: 10),
                  _ModeRow(
                    title: '图片优先',
                    subtitle: '更依赖图像和符号辅助理解',
                    selected: _displayMode == 'imageFirst',
                    onTap: () => setState(() => _displayMode = 'imageFirst'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFF5F8DF7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: const Text(
                  '保存偏好',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.fillChild = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool fillChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6F6558).withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2C2D31),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Color(0xFF8A8782),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (fillChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF5F8DF7) : const Color(0xFFF4F1EC),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : const Color(0xFF4A4B50),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: const Color(0xFF4B4D54)),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8EFFD) : const Color(0xFFF7F5F1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF7EA3F8)
                : Colors.white.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color:
                  selected ? const Color(0xFF5F8DF7) : const Color(0xFFAAA59E),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2F3035),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: Color(0xFF8C8984),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
