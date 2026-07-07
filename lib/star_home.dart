import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'location_recommendation.dart'; // TODO: 璋冭瘯鐢紝浠ュ悗鍒犻櫎
import 'location_memory_pages.dart';
import 'my_test.dart' as profile_ui;
import 'rehab_training.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFFF7F2EA),
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Star Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: '.SF Pro Text',
        scaffoldBackgroundColor: const Color(0xFFFFF2D3),
      ),
      home: MainInterfaceScreen(
        onStuck: () {},
        onCamera: () {},
        onConversation: () {},
        onVocabulary: () {},
        locationRecommendationEnabled: false,
        personalizedLearningEnabled: true,
        autoStuckDetectionEnabled: false,
        expressionPreferenceSummary: '少 · 图文一起 · 正常',
        savedPlaceCount: 0,
        onLocationRecommendationChanged: (_) {},
        onPersonalizedLearningChanged: (_) {},
        onLearningProfileChanged: () async {},
        onAutoStuckDetectionChanged: (_) {},
        onOpenExpressionPreferences: () {},
        onClearPersonalizedLearningData: () {},
        onClearPlaceData: () {},
      ),
    );
  }
}

enum SpriteMood { idle, nearTarget }

class FeatureConfig {
  final String label;
  final IconData icon;
  final Color color;

  const FeatureConfig({
    required this.label,
    required this.icon,
    required this.color,
  });
}

const List<FeatureConfig> kFeatures = [
  FeatureConfig(
    label: '补词',
    icon: CupertinoIcons.chat_bubble_2_fill,
    color: Color(0xFF7A93FF),
  ),
  FeatureConfig(
    label: '拍照',
    icon: CupertinoIcons.camera_fill,
    color: Color(0xFF8294FF),
  ),
  FeatureConfig(
    label: '对话',
    icon: CupertinoIcons.mic_fill,
    color: Color(0xFF8B8EFF),
  ),
  FeatureConfig(
    label: '词库',
    icon: CupertinoIcons.book_fill,
    color: Color(0xFF909CFF),
  ),
];

class StarPhrase {
  const StarPhrase({
    required this.text,
    required this.icon,
    required this.color,
  });

  final String text;
  final IconData icon;
  final Color color;
}

const List<StarPhrase> kStarPhrases = [
  StarPhrase(
    text: '是',
    icon: Icons.check_circle_rounded,
    color: Color(0xFF7A9E9F),
  ),
  StarPhrase(
    text: '不是',
    icon: Icons.cancel_rounded,
    color: Color(0xFFD77F8B),
  ),
  StarPhrase(
    text: '请慢一点',
    icon: Icons.speed_rounded,
    color: Color(0xFF8D9DC2),
  ),
  StarPhrase(
    text: '请再说一次',
    icon: Icons.replay_rounded,
    color: Color(0xFFD7A86E),
  ),
  StarPhrase(
    text: '我想喝水',
    icon: Icons.local_drink_rounded,
    color: Color(0xFF4E8FD8),
  ),
  StarPhrase(
    text: '我不舒服',
    icon: Icons.favorite_rounded,
    color: Color(0xFFD08C60),
  ),
];

class MainInterfaceScreen extends StatefulWidget {
  final VoidCallback onStuck;
  final VoidCallback onCamera;
  final VoidCallback onConversation;
  final VoidCallback onVocabulary;
  final bool locationRecommendationEnabled;
  final bool personalizedLearningEnabled;
  final bool autoStuckDetectionEnabled;
  final String expressionPreferenceSummary;
  final int savedWordCount;
  final int savedPlaceCount;
  final int savedPersonalObjectCount;
  final ValueChanged<bool> onLocationRecommendationChanged;
  final ValueChanged<bool> onPersonalizedLearningChanged;
  final Future<void> Function() onLearningProfileChanged;
  final ValueChanged<bool> onAutoStuckDetectionChanged;
  final VoidCallback onOpenExpressionPreferences;
  final VoidCallback onClearPersonalizedLearningData;
  final VoidCallback onClearPlaceData;
  final LocationRecommendationController?
      locationController; // TODO: 璋冭瘯鐢紝浠ュ悗鍒犻櫎
  final FavoriteWordCallback? onFavoriteSaved;
  final FavoriteWordCallback? onStarPhraseSpoken;
  final VoidCallback? onOpenYuqiaoMemory;
  final VoidCallback? onOpenPersonalObjects;

  const MainInterfaceScreen({
    super.key,
    required this.onStuck,
    required this.onCamera,
    required this.onConversation,
    required this.onVocabulary,
    required this.locationRecommendationEnabled,
    required this.personalizedLearningEnabled,
    required this.autoStuckDetectionEnabled,
    required this.expressionPreferenceSummary,
    this.savedWordCount = 0,
    required this.savedPlaceCount,
    this.savedPersonalObjectCount = 0,
    required this.onLocationRecommendationChanged,
    required this.onPersonalizedLearningChanged,
    required this.onLearningProfileChanged,
    required this.onAutoStuckDetectionChanged,
    required this.onOpenExpressionPreferences,
    required this.onClearPersonalizedLearningData,
    required this.onClearPlaceData,
    this.locationController,
    this.onFavoriteSaved,
    this.onStarPhraseSpoken,
    this.onOpenYuqiaoMemory,
    this.onOpenPersonalObjects,
  });

  @override
  State<MainInterfaceScreen> createState() => _MainInterfaceScreenState();
}

class _MainInterfaceScreenState extends State<MainInterfaceScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<Offset> _baseOffsets = const [
    Offset(-95, -95),
    Offset(95, -95),
    Offset(-95, 95),
    Offset(95, 95),
  ];

  final List<Offset> _dragDisplacements = [
    Offset.zero,
    Offset.zero,
    Offset.zero,
    Offset.zero,
  ];

  int? _springingIndex;

  late final AnimationController _springController;
  late final AnimationController _starIdleController;
  late Animation<Offset> _springAnimation;
  late final PageController _pageController;
  final FlutterTts _starTts = FlutterTts();
  Map<String, RehabTrainingProgress> _trainingProgress = const {};
  int _trainingWordCount = 0;
  int _currentPage = 1;
  final String _userName = '朋友';
  double _pointerDownX = 0;
  double _pointerDownY = 0;
  bool _isDraggingFeatureBubble = false;
  bool _appInForeground = true;

  final double _targetThreshold = 65.0;

  bool get _isAnyBubbleNearStar {
    for (int i = 0; i < 4; i++) {
      final currentPos = _baseOffsets[i] + _dragDisplacements[i];
      if (currentPos.distance < _targetThreshold) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: 1);
    unawaited(_starTts.setLanguage('zh-CN'));
    unawaited(_starTts.setSpeechRate(0.42));
    _trainingWordCount = RehabTrainingDeck.words().length;
    unawaited(_loadTrainingProgress());

    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _springAnimation = const AlwaysStoppedAnimation<Offset>(Offset.zero);

    _springController.addListener(() {
      final index = _springingIndex;
      if (index == null || !mounted) return;

      setState(() {
        _dragDisplacements[index] = _springAnimation.value;
      });
    });

    _starIdleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4600),
    );
    _syncStarIdleAnimation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _springController.dispose();
    _starIdleController.dispose();
    unawaited(_starTts.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    if (_appInForeground == inForeground) return;
    _appInForeground = inForeground;
    if (!inForeground) {
      _springController.stop();
    }
    _syncStarIdleAnimation();
  }

  void _syncStarIdleAnimation() {
    final shouldAnimate = _appInForeground && _currentPage == 1;
    if (shouldAnimate) {
      if (!_starIdleController.isAnimating) {
        _starIdleController.repeat();
      }
    } else if (_starIdleController.isAnimating) {
      _starIdleController.stop();
    }
  }

  Future<void> _loadTrainingProgress() async {
    final progress = await RehabTrainingStore().loadAll();
    if (!mounted) return;
    setState(() => _trainingProgress = progress);
  }

  Future<void> _openRehabTraining({
    RehabTrainingMode mode = RehabTrainingMode.mixed,
  }) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => RehabTrainingPage(
          initialMode: mode,
          onLearningProfileChanged: widget.onLearningProfileChanged,
        ),
      ),
    );
    await _loadTrainingProgress();
    await widget.onLearningProfileChanged();
  }

  Future<void> _openRehabTrainingSummary() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => const RehabTrainingSummaryPage(),
      ),
    );
    await _loadTrainingProgress();
  }

  void _runSpringAnimation(Offset releaseOffset, int index) {
    _springingIndex = index;
    _springAnimation = _springController.drive(
      Tween<Offset>(begin: releaseOffset, end: Offset.zero),
    );

    _springController.reset();
    _springController.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 130.0, damping: 12.0),
        0.0,
        1.0,
        0.0,
      ),
    );
  }

  void _openFeaturePage(FeatureConfig feature) {
    HapticFeedback.mediumImpact();
    switch (feature.label) {
      case '补词':
        widget.onStuck();
        return;
      case '拍照':
        widget.onCamera();
        return;
      case '对话':
        widget.onConversation();
        return;
      case '词库':
        widget.onVocabulary();
        return;
      default:
        return;
    }
  }

  void _triggerQuickAction(FeatureConfig feature) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '打开${feature.label}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        duration: const Duration(milliseconds: 650),
        backgroundColor: feature.color.withValues(alpha: 0.92),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _openFeaturePage(feature);
    });
  }

  Future<void> _openStarSpeakBoard() async {
    HapticFeedback.lightImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .22),
      builder: (sheetContext) {
        return _StarSpeakSheet(
          phrases: kStarPhrases,
          onSpeak: _speakStarPhrase,
          onMore: () {
            Navigator.of(sheetContext).pop();
            widget.onVocabulary();
          },
          onContactFamily: () {
            Navigator.of(sheetContext).pop();
            _showFamilyContactPlaceholder();
          },
        );
      },
    );
  }

  Future<void> _speakStarPhrase(StarPhrase phrase) async {
    final text = phrase.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    await _starTts.stop();
    await _starTts.speak(text);
    await (widget.onStarPhraseSpoken ?? widget.onFavoriteSaved)?.call(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '已播报：$text',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          duration: const Duration(milliseconds: 850),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E3038).withValues(alpha: .92),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  void _showFamilyContactPlaceholder() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            '联系家人功能需要先配置联系人',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E3038).withValues(alpha: .92),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _syncStarIdleAnimation();
  }

  void _goToPage(int page) {
    if (page == _currentPage || page < 0 || page > 2) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildHomePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final systemPadding = MediaQuery.viewPaddingOf(context);
        final headerTop = systemPadding.top + 18;
        final locationTop = systemPadding.top + 86;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: LiquidBackgroundDecorations(),
              ),
            ),
            Positioned(
              top: headerTop,
              left: 24,
              right: 24,
              child: RepaintBoundary(
                child: HeaderWidget(userName: _userName),
              ),
            ),
            if (widget.locationController != null)
              Positioned(
                top: locationTop,
                left: 22,
                right: 22,
                child: CurrentPlaceStatusCard(
                  controller: widget.locationController!,
                ),
              ),
            Positioned.fill(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: DashedConnectorPainter(),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedBuilder(
                      animation: _starIdleController,
                      builder: (context, child) {
                        final wave = math.sin(
                          _starIdleController.value * math.pi * 2,
                        );
                        return Transform.scale(
                          scale: 1.0 - wave * 0.05,
                          child: Container(
                            width: 140,
                            height: 20,
                            margin: const EdgeInsets.only(top: 120),
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE2B079).withValues(
                                    alpha: 0.18 - wave * 0.03,
                                  ),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Center(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _starIdleController,
                        builder: (context, child) {
                          final t = _starIdleController.value;
                          final bobbingY = math.sin(t * math.pi * 2) * 7;
                          final driftX = math.cos(t * math.pi * 2) * 2.5;
                          final tilt = math.sin(t * math.pi * 2) * 0.035;
                          final scale = 1.0 + math.sin(t * math.pi * 2) * 0.018;

                          return Transform.translate(
                            offset: Offset(driftX, bobbingY),
                            child: Transform.rotate(
                              angle: tilt,
                              child: Transform.scale(
                                scale: scale,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _openStarSpeakBoard,
                                  child: SpriteWidget(
                                    mood: _isAnyBubbleNearStar
                                        ? SpriteMood.nearTarget
                                        : SpriteMood.idle,
                                    isBlinking: t < 0.055,
                                    animationValue: t,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  for (int i = 0; i < kFeatures.length; i++)
                    _buildDraggableBubble(
                      index: i,
                      feature: kFeatures[i],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDraggableBubble({
    required int index,
    required FeatureConfig feature,
  }) {
    final currentPos = _baseOffsets[index] + _dragDisplacements[index];
    final distanceToStar = currentPos.distance;
    final isNearStar = distanceToStar < _targetThreshold;

    return Center(
      child: Transform.translate(
        offset: currentPos,
        child: GestureDetector(
          onPanStart: (_) {
            setState(() {
              _isDraggingFeatureBubble = true;
              _springingIndex = null;
              _springController.stop();
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _dragDisplacements[index] += details.delta;
            });
          },
          onPanEnd: (_) {
            final releaseOffset = _dragDisplacements[index];

            if (isNearStar) {
              _runSpringAnimation(releaseOffset, index);
              _triggerQuickAction(feature);
            } else {
              _runSpringAnimation(releaseOffset, index);
            }
            _isDraggingFeatureBubble = false;
          },
          onPanCancel: () {
            _isDraggingFeatureBubble = false;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedScale(
              scale: isNearStar ? 1.18 : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              child: GlassBubble(
                icon: feature.icon,
                iconColor: feature.color,
                label: feature.label,
                isHighlighted: isNearStar,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRehabTrainingEntryPage() {
    final practiced = _trainingProgress.values
        .where((item) => item.totalCount > 0)
        .toList(growable: false);
    final todayCount =
        practiced.where((item) => item.practicedOn(DateTime.now())).length;
    final masteredCount =
        practiced.where((item) => item.masteryLevel >= 3).length;
    final dueCount = practiced.where((item) => item.isDueForReview).length;
    final learningScore = _trainingProgress.values.fold<double>(
      0,
      (sum, item) => sum + (item.masteryLevel / 5).clamp(0.0, 1.0),
    );
    final progressValue = _trainingWordCount <= 0
        ? 0.0
        : (learningScore / _trainingWordCount).clamp(0.0, 1.0);

    return Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(
            child: LiquidBackgroundDecorations(),
          ),
        ),
        Positioned(
          top: 72,
          right: -46,
          child: _GardenGlowOrb(
            size: 168,
            color: const Color(0xFFB8D8BA),
          ),
        ),
        Positioned(
          bottom: 88,
          left: -38,
          child: _GardenGlowOrb(
            size: 132,
            color: const Color(0xFFF0D6A8),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7A9E9F).withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .72),
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.leaf_arrow_circlepath,
                        color: Color(0xFF6F9293),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '词语花园',
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.02,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2E3038),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '把常用词一点点养熟',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF7D8490),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: Center(
                    child: _TrainingDashboardRing(
                      progress: progressValue,
                      todayCount: todayCount,
                      masteredCount: masteredCount,
                      dueCount: dueCount,
                      totalCount: _trainingWordCount,
                      onTap: () => _openRehabTraining(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _GardenActionButton(
                        icon: CupertinoIcons.play_fill,
                        title: '开始练习',
                        color: const Color(0xFF7A9E9F),
                        onTap: () => _openRehabTraining(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GardenActionButton(
                        icon: CupertinoIcons.arrow_counterclockwise_circle_fill,
                        title: '常错复习',
                        color: const Color(0xFFD7A86E),
                        onTap: () => _openRehabTraining(
                          mode: RehabTrainingMode.weakReview,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _GardenActionButton(
                        icon: CupertinoIcons.cube_box_fill,
                        title: '个人物品',
                        color: const Color(0xFF8D9DC2),
                        onTap: () => _openRehabTraining(
                          mode: RehabTrainingMode.personalObjects,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GardenActionButton(
                        icon: CupertinoIcons.speaker_2_fill,
                        title: '听理解',
                        color: const Color(0xFF4E8FD8),
                        onTap: () => _openRehabTraining(
                          mode: RehabTrainingMode.listening,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _GardenActionButton(
                        icon: CupertinoIcons.chart_pie_fill,
                        title: '学习总结',
                        color: const Color(0xFFD7A86E),
                        onTap: _openRehabTrainingSummary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    final controller = widget.locationController;
    final unconfirmedCount = controller != null
        ? controller.places.where((p) => !p.isUserConfirmed).length
        : 0;

    return profile_ui.YuqiaoPersonalCenter(
      name: _userName,
      wordCount: widget.savedWordCount,
      placeCount: widget.savedPlaceCount,
      personalObjectCount: widget.savedPersonalObjectCount,
      locationRecommendationEnabled: widget.locationRecommendationEnabled,
      personalizedLearningEnabled: widget.personalizedLearningEnabled,
      autoStuckDetectionEnabled: widget.autoStuckDetectionEnabled,
      expressionPreferenceSummary: widget.expressionPreferenceSummary,
      onLocationRecommendationChanged: widget.onLocationRecommendationChanged,
      onPersonalizedLearningChanged: widget.onPersonalizedLearningChanged,
      onAutoStuckDetectionChanged: widget.onAutoStuckDetectionChanged,
      onOpenExpressionPreferences: widget.onOpenExpressionPreferences,
      onClearPersonalizedLearningData: widget.onClearPersonalizedLearningData,
      onOpenLocationMemory: controller == null
          ? () {}
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlaceMemoryManagementPage(
                    controller: controller,
                    onFavoriteSaved: widget.onFavoriteSaved,
                  ),
                ),
              );
            },
      onOpenYuqiaoMemory: widget.onOpenYuqiaoMemory,
      onOpenPersonalObjects: widget.onOpenPersonalObjects,
      unconfirmedPlaceCount: unconfirmedCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Color(0xFFF7F2EA),
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBody: true,
        backgroundColor: const Color(0xFFF7F2EA),
        body: Stack(
          children: [
            Listener(
              onPointerDown: (event) {
                _pointerDownX = event.position.dx;
                _pointerDownY = event.position.dy;
              },
              onPointerUp: (event) {
                if (_isDraggingFeatureBubble) return;
                final dx = event.position.dx - _pointerDownX;
                final dy = event.position.dy - _pointerDownY;
                if (dx.abs() > 80 && dx.abs() > dy.abs() * 2) {
                  if (dx < 0) {
                    _goToPage(_currentPage + 1);
                  } else {
                    _goToPage(_currentPage - 1);
                  }
                }
              },
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: _onPageChanged,
                children: [
                  _buildRehabTrainingEntryPage(),
                  _buildHomePage(),
                  _buildSettingsPage(),
                ],
              ),
            ),
            Positioned(
              left: 28,
              right: 28,
              bottom: bottomInset + 8,
              child: GlassBottomNavigationBar(
                currentPage: _currentPage,
                onTap: _goToPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarSpeakSheet extends StatefulWidget {
  const _StarSpeakSheet({
    required this.phrases,
    required this.onSpeak,
    required this.onMore,
    required this.onContactFamily,
  });

  final List<StarPhrase> phrases;
  final Future<void> Function(StarPhrase phrase) onSpeak;
  final VoidCallback onMore;
  final VoidCallback onContactFamily;

  @override
  State<_StarSpeakSheet> createState() => _StarSpeakSheetState();
}

class _StarSpeakSheetState extends State<_StarSpeakSheet> {
  String _speakingText = '';

  Future<void> _handleSpeak(StarPhrase phrase) async {
    if (_speakingText.isNotEmpty) return;
    setState(() => _speakingText = phrase.text);
    try {
      await widget.onSpeak(phrase);
    } finally {
      if (mounted) {
        setState(() => _speakingText = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(14, 0, 14, math.max(12.0, bottomInset + 8)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .82),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: .88)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7E8BA3).withValues(alpha: .20),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
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
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE2A8),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFB43F)
                                  .withValues(alpha: .18),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF2E3038),
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '星语',
                              style: TextStyle(
                                fontSize: 26,
                                height: 1.05,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF2E3038),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '选一句你想说的话',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7D8490),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.phrases.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.52,
                    ),
                    itemBuilder: (context, index) {
                      final phrase = widget.phrases[index];
                      return _StarPhraseCard(
                        phrase: phrase,
                        speaking: _speakingText == phrase.text,
                        disabled: _speakingText.isNotEmpty &&
                            _speakingText != phrase.text,
                        onTap: () => _handleSpeak(phrase),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StarBoardActionButton(
                          icon: Icons.apps_rounded,
                          label: '更多表达',
                          onTap: widget.onMore,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StarBoardActionButton(
                          icon: Icons.contact_phone_rounded,
                          label: '联系家人',
                          onTap: widget.onContactFamily,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarPhraseCard extends StatelessWidget {
  const _StarPhraseCard({
    required this.phrase,
    required this.speaking,
    required this.disabled,
    required this.onTap,
  });

  final StarPhrase phrase;
  final bool speaking;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: speaking ? 1.035 : 1,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFFF0F1F4)
                : phrase.color.withValues(alpha: speaking ? .25 : .16),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color:
                  speaking ? phrase.color : Colors.white.withValues(alpha: .84),
              width: speaking ? 2.2 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: phrase.color.withValues(alpha: speaking ? .22 : .10),
                blurRadius: speaking ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: disabled ? .50 : .78),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: .9)),
                ),
                child: Icon(
                  speaking ? Icons.volume_up_rounded : phrase.icon,
                  color: disabled
                      ? const Color(0xFF9AA0AA)
                      : const Color(0xFF2E3038),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  phrase.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: phrase.text.length <= 2 ? 26 : 21,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    color: disabled
                        ? const Color(0xFF9AA0AA)
                        : const Color(0xFF2E3038),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarBoardActionButton extends StatelessWidget {
  const _StarBoardActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5F1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .86)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF4E5A6A)),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF4E5A6A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeaderWidget extends StatelessWidget {
  final String userName;
  const HeaderWidget({super.key, this.userName = '朋友'});

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '早安';
    if (hour >= 11 && hour < 14) return '午安';
    if (hour >= 14 && hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()}，$userName',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '选择一个入口，语桥会跟着你的节奏来',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF7D8896),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 48,
          height: 48,
          child: LiquidGlassSurface(
            radius: 18,
            opacity: 0.50,
            blur: 18,
            thickness: 22,
            tintColor: const Color(0xFFE7F2FF),
            child: SizedBox.expand(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.bell,
                    color: Color(0xFF425064),
                    size: 22,
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF9F0A),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LiquidGlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final double opacity;
  final double blur;
  final double thickness;
  final Color? tintColor;
  final EdgeInsetsGeometry? padding;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.opacity = 0.45,
    this.blur = 16,
    this.thickness = 18,
    this.tintColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final themeTint = Theme.of(context).colorScheme.primaryContainer;
    final tint = Color.lerp(
      tintColor ?? const Color(0xFFD9ECFF),
      themeTint,
      0.18,
    )!;
    final effectiveBlur = blur <= 0 ? 0.0 : blur + thickness * 0.04;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        enabled: effectiveBlur > 0,
        filter: ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: opacity + 0.10),
                Color.lerp(Colors.white, tint, 0.22)!
                    .withValues(alpha: opacity * 0.72),
                tint.withValues(alpha: opacity * 0.36),
              ],
              stops: const [0.0, 0.56, 1.0],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
              width: 1.05,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: LiquidGlassOpticsPainter(
                      radius: radius,
                      tint: tint,
                      opacity: opacity,
                      thickness: thickness,
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class LiquidGlassOpticsPainter extends CustomPainter {
  final double radius;
  final Color tint;
  final double opacity;
  final double thickness;

  const LiquidGlassOpticsPainter({
    required this.radius,
    required this.tint,
    required this.opacity,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.clipRRect(rrect);

    final movingHighlight = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.95, -0.95),
        end: const Alignment(0.80, 0.85),
        colors: [
          Colors.white.withValues(alpha: 0.24),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.36, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.4), movingHighlight);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..color = tint.withValues(alpha: 0.12);
    canvas.drawRRect(rrect.deflate(1.4), edgePaint);

    final blobPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.12),
          tint.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(
            size.width * 0.32,
            size.height * 0.20,
          ),
          radius: size.shortestSide * 0.55,
        ),
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.35, size.height * 0.22),
        width: size.width * 0.82,
        height: size.height * 0.42,
      ),
      blobPaint,
    );
  }

  @override
  bool shouldRepaint(covariant LiquidGlassOpticsPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.tint != tint ||
        oldDelegate.opacity != opacity ||
        oldDelegate.thickness != thickness;
  }
}

class GlassBubble extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isHighlighted;

  const GlassBubble({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: isHighlighted ? 96 : 88,
              height: isHighlighted ? 96 : 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isHighlighted
                        ? iconColor.withValues(alpha: 0.32)
                        : const Color(0xFF7AA7D8).withValues(alpha: 0.12),
                    blurRadius: isHighlighted ? 30 : 18,
                    spreadRadius: isHighlighted ? 3 : 0,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 78,
              height: 78,
              child: LiquidGlassSurface(
                radius: 39,
                opacity: isHighlighted ? 0.58 : 0.44,
                blur: 16,
                thickness: isHighlighted ? 24 : 18,
                tintColor: iconColor.withValues(alpha: 0.45),
                child: Center(
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        iconColor.withValues(alpha: 0.98),
                        const Color(0xFF3478F6).withValues(alpha: 0.66),
                      ],
                    ).createShader(bounds),
                    child: Icon(icon, size: 32, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF273241),
          ),
        ),
      ],
    );
  }
}

class SpriteWidget extends StatelessWidget {
  final SpriteMood mood;
  final bool isBlinking;
  final double animationValue;

  const SpriteWidget({
    super.key,
    required this.mood,
    required this.isBlinking,
    required this.animationValue,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      height: 188,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: CustomPaint(
          painter: PuffyStarPainter(
            mood: mood,
            isBlinking: isBlinking,
            animationValue: animationValue,
          ),
        ),
      ),
    );
  }
}

class PuffyStarPainter extends CustomPainter {
  final SpriteMood mood;
  final bool isBlinking;
  final double animationValue;

  PuffyStarPainter({
    required this.mood,
    required this.isBlinking,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 4;
    final wave = math.sin(animationValue * 2 * math.pi);

    final points = _buildFivePointStarPoints(size, wave, Offset(cx, cy));
    final path = _buildRoundedFivePointStarPath(points, size);
    final foldCenter = Offset(
      cx - size.width * 0.012,
      cy + size.height * 0.012,
    );

    // 绋冲畾鐨勬き鍦嗘煍闃村奖锛氶伩鍏?Android 鐪熸満瀵瑰鏉?Path 闃村奖鐨勬覆鏌撲吉褰便€?
    final floorShadowPaint = Paint()
      ..color = const Color(0xFFE0A64A).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 5, cy + size.height * 0.39),
        width: size.width * 0.66,
        height: size.height * 0.18,
      ),
      floorShadowPaint,
    );

    // 澶栦晶鏆栬壊鏌斿厜锛岃鏄熸槦鏇寸珛浣擄紝浣嗕笉鐢诲埡鐪煎姬绾裤€?
    final outerGlowPaint = Paint()
      ..color = const Color(0xFFFFCF6A).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path.shift(const Offset(0, 2)), outerGlowPaint);

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        // 涓績鍋忕櫧锛屽悜澶栭€愭笎杩囨浮鍒伴粍涓亸姗欙紝閬垮厤鏁翠綋鍙戞贰銆?
        center: Alignment(-0.10 + wave * 0.01, -0.12),
        radius: 0.98,
        colors: const [
          Color(0xFFFFFEF4), // 涓績鏆栫櫧
          Color(0xFFFFF2B8), // 娴呭ザ榛?
          Color(0xFFFFD65E), // 鏄庝寒榛?
          Color(0xFFFFB43F), // 榛勪腑鍋忔
          Color(0xFFF29B2E), // 杈圭紭姗欓粍鍘氬害
        ],
        stops: const [0.0, 0.18, 0.48, 0.78, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bodyPaint);

    canvas.save();
    canvas.clipPath(path);

    _drawPuffyFacets(
      canvas: canvas,
      size: size,
      points: points,
      center: foldCenter,
    );

    // 椤堕儴娑叉€佹煍鍏夛細鍙繚鐣欐煍鍜屼寒闈紝涓嶇敾鎴愭槑鏄惧姬绾裤€?
    final topLightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.28, -0.42),
        radius: 0.58,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawCircle(
      Offset(cx - size.width * 0.16, cy - size.height * 0.22),
      size.width * 0.34,
      topLightPaint,
    );

    // 鍙充笅鏂硅交寰殩闃村奖锛屽彧淇濈暀鍘氬害鎰燂紝涓嶄骇鐢熻剰绾裤€?
    final lowerShadePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.48, 0.58),
        radius: 0.78,
        colors: [
          const Color(0xFFC87B18).withValues(alpha: 0.13),
          const Color(0xFFC87B18).withValues(alpha: 0.045),
          const Color(0xFFC87B18).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawCircle(
      Offset(cx + size.width * 0.24, cy + size.height * 0.23),
      size.width * 0.46,
      lowerShadePaint,
    );

    canvas.restore();

    _drawLiquidGlassRim(canvas, path);

    _drawSimpleFace(
      canvas: canvas,
      size: size,
      cx: cx,
      cy: cy,
      isExcited: mood == SpriteMood.nearTarget,
    );
  }

  List<Offset> _buildFivePointStarPoints(
    Size size,
    double wave,
    Offset center,
  ) {
    final outerBase = size.width * 0.425;
    final innerBase = size.width * 0.235;

    // 渚濈劧鏄爣鍑嗕簲瑙掓槦缁撴瀯锛? 涓瑙?+ 5 涓唴鍑圭偣銆?
    // 鍙粰寰堝皬鐨勬瘮渚嬪樊锛屼繚璇佺伒鍔ㄤ絾涓嶄細鍙樻垚涓€鍥㈣姳褰€?
    const outerScale = [1.02, 0.98, 1.00, 0.97, 1.03];
    const innerScale = [0.98, 1.02, 0.99, 1.01, 0.98];

    final points = <Offset>[];
    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final isOuter = i.isEven;
      final scale = isOuter ? outerScale[i ~/ 2] : innerScale[i ~/ 2];
      final breath = math.sin(animationValue * 2 * math.pi + i * 0.55) *
          size.width *
          0.003;
      final radius =
          (isOuter ? outerBase : innerBase) * scale + breath + wave * 0.18;

      final rawPoint = Offset(
        math.cos(angle) * radius,
        math.sin(angle) * radius,
      );

      // 鍙鏄熸槦韬綋鍚戝彸寰€撅紝鑴搁儴淇濇寔姝ｅ悜锛岄伩鍏嶈〃鎯呰窡鐫€姝€?
      const bodyTilt = 0.15;
      final tiltedPoint = Offset(
        math.cos(bodyTilt) * rawPoint.dx - math.sin(bodyTilt) * rawPoint.dy,
        math.sin(bodyTilt) * rawPoint.dx + math.cos(bodyTilt) * rawPoint.dy,
      );

      points.add(center + tiltedPoint);
    }
    return points;
  }

  Path _buildRoundedFivePointStarPath(List<Offset> points, Size size) {
    Offset pointToward(Offset from, Offset to, double distance) {
      final vector = to - from;
      final length = vector.distance;
      if (length == 0) return from;
      final safeDistance = math.min(distance, length * 0.44);
      return from + vector / length * safeDistance;
    }

    final path = Path();
    // 浜斾釜瑙掓洿鍦嗘鼎锛氬瑙掑姞澶у渾瑙掞紝鍐呭嚬鐐逛篃鐣ュ井鏀捐蒋銆?
    final outerCorner = size.width * 0.110;
    final innerCorner = size.width * 0.070;

    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      final previous = points[(i - 1 + points.length) % points.length];
      final next = points[(i + 1) % points.length];
      final smoothDistance = i.isEven ? outerCorner : innerCorner;

      final start = pointToward(current, previous, smoothDistance);
      final end = pointToward(current, next, smoothDistance);

      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }

      path.quadraticBezierTo(current.dx, current.dy, end.dx, end.dy);
    }

    path.close();
    return path;
  }

  void _drawPuffyFacets({
    required Canvas canvas,
    required Size size,
    required List<Offset> points,
    required Offset center,
  }) {
    // 杩欑増涓嶅啀鐢荤‖鎶樼嚎銆傚唴閮ㄦ姌鐥曟敼鎴愭瀬娣＄殑杞潰锛岄伩鍏嶅嚭鐜扮嚎鏉￠槾褰便€?
    for (int i = 0; i < 5; i++) {
      final outerIndex = i * 2;
      final leftInner =
          points[(outerIndex - 1 + points.length) % points.length];
      final outer = points[outerIndex];
      final rightInner = points[(outerIndex + 1) % points.length];

      final facet = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(leftInner.dx, leftInner.dy)
        ..quadraticBezierTo(outer.dx, outer.dy, rightInner.dx, rightInner.dy)
        ..close();

      final isUpperFacet = i == 0 || i == 4;
      final facetPaint = Paint()
        ..color = isUpperFacet
            ? Colors.white.withValues(alpha: 0.020)
            : const Color(0xFFD89226).withValues(alpha: 0.014)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.1);
      canvas.drawPath(facet, facetPaint);
    }

    // 涓績娉涚櫧锛氶潰绉暐闆嗕腑锛岃鈥滀腑闂存洿娣°€佹洿鐧解€濓紝浣嗕笉褰㈡垚鐧藉湀銆?
    final centerGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.40),
          const Color(0xFFFFF6D6).withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.36, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: size.width * 0.27),
      );
    canvas.drawCircle(center, size.width * 0.27, centerGlowPaint);
  }

  void _drawLiquidGlassRim(Canvas canvas, Path path) {
    // 娑叉€佺幓鐠冮鏍肩櫧杈癸細澶栦晶鏌斿厜 + 娓呮櫚鐧借竟 + 鍐呬晶鏆栬壊鎶樺皠銆?
    final outerRimGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    canvas.drawPath(path, outerRimGlowPaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.62);
    canvas.drawPath(path, rimPaint);

    final innerWarmPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFE8).withValues(alpha: 0.34);
    canvas.drawPath(path, innerWarmPaint);
  }

  void _drawSimpleFace({
    required Canvas canvas,
    required Size size,
    required double cx,
    required double cy,
    required bool isExcited,
  }) {
    final facePaint = Paint()
      ..color = const Color(0xFF141414)
      ..style = PaintingStyle.fill;

    final eyeY = cy - size.height * 0.105;
    final eyeGap = size.width * 0.112;
    final eyeRadius = isExcited ? size.width * 0.038 : size.width * 0.034;

    // 鐪肩潧淇濇寔涓や釜灏忛粦鐐广€?
    canvas.drawCircle(Offset(cx - eyeGap, eyeY), eyeRadius, facePaint);
    canvas.drawCircle(Offset(cx + eyeGap, eyeY), eyeRadius, facePaint);

    final mouthPaint = Paint()
      ..color = const Color(0xFF141414)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isExcited ? 4.2 : 3.8
      ..strokeCap = StrokeCap.round;

    final mouthRect = Rect.fromCenter(
      center: Offset(cx, cy + size.height * 0.010),
      width: isExcited ? size.width * 0.235 : size.width * 0.215,
      height: isExcited ? size.height * 0.150 : size.height * 0.135,
    );

    canvas.drawArc(mouthRect, 0, math.pi, false, mouthPaint);
  }

  @override
  bool shouldRepaint(covariant PuffyStarPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.isBlinking != isBlinking ||
        oldDelegate.animationValue != animationValue;
  }
}

class DashedConnectorPainter extends CustomPainter {
  const DashedConnectorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.save();
    canvas.translate(cx, cy);

    _drawDashedCurve(
      canvas,
      paint,
      const Offset(-30, -30),
      const Offset(-90, -130),
      true,
    );
    _drawDashedCurve(
      canvas,
      paint,
      const Offset(30, -30),
      const Offset(90, -130),
      false,
    );
    _drawDashedCurve(
      canvas,
      paint,
      const Offset(-30, 30),
      const Offset(-90, 130),
      false,
    );
    _drawDashedCurve(
      canvas,
      paint,
      const Offset(30, 30),
      const Offset(90, 130),
      true,
    );

    canvas.restore();
  }

  void _drawDashedCurve(
    Canvas canvas,
    Paint paint,
    Offset start,
    Offset end,
    bool reverseControl,
  ) {
    final controlX = (start.dx + end.dx) / 2 + (reverseControl ? -15 : 15);
    final controlY = (start.dy + end.dy) / 2 + (reverseControl ? 15 : -15);
    final control = Offset(controlX, controlY);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0.0;
      const dashLength = 4.0;
      const spaceLength = 4.0;

      while (distance < metric.length) {
        final nextDistance = distance + dashLength;
        final segment = metric.extractPath(distance, nextDistance);
        canvas.drawPath(segment, paint);
        distance = nextDistance + spaceLength;
      }
    }

    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx - 6, end.dy + 2)
      ..lineTo(end.dx + 2, end.dy - 6)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlassBottomNavigationBar extends StatelessWidget {
  final int currentPage;
  final ValueChanged<int> onTap;

  const GlassBottomNavigationBar({
    super.key,
    required this.currentPage,
    required this.onTap,
  });

  static const _icons = [
    CupertinoIcons.leaf_arrow_circlepath,
    CupertinoIcons.house_fill,
    CupertinoIcons.person,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: LiquidGlassSurface(
        radius: 42,
        opacity: 0.46,
        // Keep the translucent glass treatment without resampling a large
        // profile photo on every animation frame.
        blur: 0,
        thickness: 22,
        tintColor: const Color(0xFFE8F2FF),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final itemWidth = totalWidth / 3;
            const indicatorWidth = 68.0;
            const indicatorHeight = 46.0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 婊戝姩鐨勬恫鎬佺幓鐠冩き鍦嗘寚绀哄櫒锛堢函鑳屾櫙锛屾棤鍥炬爣锛?
                Positioned(
                  top: (62 - indicatorHeight) / 2,
                  left: (itemWidth - indicatorWidth) / 2,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: itemWidth * currentPage),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, offset, child) => Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    ),
                    child: Container(
                      width: indicatorWidth,
                      height: indicatorHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23),
                        color: const Color(0xFF3478F6).withValues(alpha: 0.12),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF3478F6).withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 涓変釜鍥炬爣锛堝缁堝彲瑙侊級
                Positioned.fill(
                  child: Row(
                    children: List.generate(3, (index) {
                      final isActive = currentPage == index;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => onTap(index),
                          child: Center(
                            child: Icon(
                              _icons[index],
                              size: 22,
                              color: isActive
                                  ? const Color(0xFF3478F6)
                                  : const Color(0xFF667386),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GardenActionButton extends StatelessWidget {
  const _GardenActionButton({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .76)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .14),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingDashboardRing extends StatelessWidget {
  const _TrainingDashboardRing({
    required this.progress,
    required this.todayCount,
    required this.masteredCount,
    required this.dueCount,
    required this.totalCount,
    required this.onTap,
  });

  final double progress;
  final int todayCount;
  final int masteredCount;
  final int dueCount;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final targetProgress = progress.clamp(0.0, 1.0);
    final isComplete = totalCount > 0 && masteredCount >= totalCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 270,
        height: 270,
        child: CustomPaint(
          painter: _TrainingRingPainter(
            progress: targetProgress,
            isComplete: isComplete,
          ),
          child: Center(
            child: Container(
              width: 196,
              height: 196,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .72),
                border: Border.all(color: Colors.white.withValues(alpha: .84)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7A9E9F).withValues(alpha: .14),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${(targetProgress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 46,
                      height: .95,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2E3038),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    totalCount <= 0
                        ? '还没有词汇'
                        : '已掌握 $masteredCount / $totalCount',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6F9293),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RingMetric(label: '今日', value: '$todayCount'),
                      Container(
                        width: 1,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: const Color(0xFFE0E4EA),
                      ),
                      _RingMetric(label: '复习', value: '$dueCount'),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7A9E9F).withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '轻点开始练习',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF6F9293),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingMetric extends StatelessWidget {
  const _RingMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2E3038),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFF8A8D98),
          ),
        ),
      ],
    );
  }
}

class _TrainingRingPainter extends CustomPainter {
  const _TrainingRingPainter({
    required this.progress,
    required this.isComplete,
  });

  final double progress;
  final bool isComplete;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 16;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final safeProgress = isComplete ? 1.0 : progress.clamp(0.0, 1.0);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .62);
    canvas.drawCircle(center, radius, basePaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF7A9E9F),
          Color(0xFFD7A86E),
          Color(0xFFD7A0A9),
        ],
      ).createShader(rect);
    if (safeProgress >= .999) {
      canvas.drawCircle(center, radius, progressPaint);
    } else if (safeProgress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * safeProgress,
        false,
        progressPaint,
      );
    }

    final dotBasePaint = Paint()..color = Colors.white.withValues(alpha: .84);
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + math.pi * 2 * (i / 8);
      final point = center +
          Offset(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
          );
      canvas.drawCircle(
        point,
        4.3,
        dotBasePaint,
      );
    }

    if (safeProgress > 0) {
      final endAngle = -math.pi / 2 + math.pi * 2 * safeProgress;
      final endPoint = center +
          Offset(
            math.cos(endAngle) * radius,
            math.sin(endAngle) * radius,
          );
      canvas.drawCircle(
        endPoint,
        7.0,
        Paint()..color = Colors.white.withValues(alpha: .92),
      );
      canvas.drawCircle(
        endPoint,
        4.8,
        Paint()..color = const Color(0xFF7A9E9F),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrainingRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isComplete != isComplete;
  }
}

class _GardenGlowOrb extends StatelessWidget {
  const _GardenGlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: .22),
              color.withValues(alpha: .08),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureDetailPage extends StatelessWidget {
  final FeatureConfig feature;
  final VoidCallback onClose;

  const FeatureDetailPage({
    super.key,
    required this.feature,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              feature.color.withValues(alpha: 0.16),
              const Color(0xFFFFF8EA),
              const Color(0xFFEAF4FF),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GlassIconButton(
                  icon: CupertinoIcons.chevron_left,
                  onTap: onClose,
                ),
                const SizedBox(height: 32),
                Center(
                  child: Icon(feature.icon, size: 82, color: feature.color),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    feature.label,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3E3121),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '轻点${feature.label}开始使用',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8F7A65),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1.4,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _featureDescription(feature.label),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.65,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B5A49),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _featureDescription(String label) {
    switch (label) {
      case '补词':
        return '选择表达方向和关键词，语桥会整理成可确认、可播报的句子。';
      case '拍照':
        return '拍下眼前物品，语桥会识别内容并给出更贴近场景的表达。';
      case '对话':
        return '记录当前对话语境，帮助理解对方的话，也在卡住时给出表达提示。';
      case '词库':
        return '整理常用表达、图文词汇和个人物品，让表达选择越来越贴近自己。';
      default:
        return '选择一个功能入口开始使用。';
    }
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.white.withValues(alpha: 0.38),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1.2,
                ),
              ),
              child: Icon(icon, color: const Color(0xFF6B5A49)),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassFeatureIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const GlassFeatureIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.95),
                color.withValues(alpha: 0.62),
              ],
            ).createShader(bounds),
            child: Icon(icon, size: 64, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class SoftBackgroundDecorations extends StatelessWidget {
  const SoftBackgroundDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: SoftBackgroundPainter());
  }
}

class LiquidBackgroundDecorations extends StatelessWidget {
  const LiquidBackgroundDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: LiquidBackgroundPainter());
  }
}

class LiquidBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void drawGlow({
      required Offset center,
      required double radius,
      required Color color,
      required double alpha,
    }) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }

    drawGlow(
      center: Offset(size.width * 0.18, size.height * 0.12),
      radius: size.width * 0.62,
      color: Colors.white,
      alpha: 0.78,
    );
    drawGlow(
      center: Offset(size.width * 0.84, size.height * 0.20),
      radius: size.width * 0.48,
      color: const Color(0xFFBBD7FF),
      alpha: 0.32,
    );
    drawGlow(
      center: Offset(size.width * 0.08, size.height * 0.78),
      radius: size.width * 0.46,
      color: const Color(0xFFFFDDA8),
      alpha: 0.28,
    );
    drawGlow(
      center: Offset(size.width * 0.95, size.height * 0.82),
      radius: size.width * 0.42,
      color: const Color(0xFFD7F1FF),
      alpha: 0.26,
    );

    final ribbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.46);

    final ribbon = Path()
      ..moveTo(-20, size.height * 0.32)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.20,
        size.width * 0.48,
        size.height * 0.52,
        size.width + 20,
        size.height * 0.36,
      );
    canvas.drawPath(ribbon, ribbonPaint);

    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.62);
    final points = [
      Offset(size.width * 0.16, size.height * 0.28),
      Offset(size.width * 0.82, size.height * 0.31),
      Offset(size.width * 0.22, size.height * 0.66),
      Offset(size.width * 0.74, size.height * 0.72),
    ];
    for (final point in points) {
      canvas.drawCircle(point, 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SoftBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void drawRadial({
      required Offset center,
      required double radius,
      required Color color,
      required double alpha,
    }) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }

    drawRadial(
      center: Offset(size.width * 0.18, size.height * 0.05),
      radius: size.width * 0.48,
      color: Colors.white,
      alpha: 0.68,
    );

    drawRadial(
      center: Offset(size.width * 0.70, size.height * 0.42),
      radius: size.width * 0.46,
      color: const Color(0xFFFFD870),
      alpha: 0.19,
    );

    drawRadial(
      center: Offset(size.width * 0.96, size.height * 0.52),
      radius: size.width * 0.18,
      color: const Color(0xFF91E1FF),
      alpha: 0.16,
    );

    drawRadial(
      center: Offset(size.width * 0.96, size.height * 0.54),
      radius: size.width * 0.15,
      color: const Color(0xFFE3A2FF),
      alpha: 0.12,
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFFD35A).withValues(alpha: 0.16);

    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(size.width * 0.35, size.height * 0.83),
        18.0 + i * 14,
        ringPaint,
      );
    }

    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    final sparklePoints = [
      Offset(size.width * 0.08, size.height * 0.25),
      Offset(size.width * 0.16, size.height * 0.53),
      Offset(size.width * 0.90, size.height * 0.37),
      Offset(size.width * 0.82, size.height * 0.70),
      Offset(size.width * 0.56, size.height * 0.72),
    ];

    for (final point in sparklePoints) {
      _drawSparkle(canvas, point, 3.2, sparklePaint);
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * 0.25,
        center.dy - radius * 0.25,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.25,
        center.dy + radius * 0.25,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.25,
        center.dy + radius * 0.25,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.25,
        center.dy - radius * 0.25,
        center.dx,
        center.dy - radius,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
