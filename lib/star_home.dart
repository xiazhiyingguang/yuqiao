import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'location_recommendation.dart'; // TODO: 调试用，以后删除
import 'location_memory_pages.dart';
import 'my_test.dart' as profile_ui;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
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
        savedPlaceCount: 0,
        onLocationRecommendationChanged: (_) {},
        onPersonalizedLearningChanged: (_) {},
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

class MainInterfaceScreen extends StatefulWidget {
  final VoidCallback onStuck;
  final VoidCallback onCamera;
  final VoidCallback onConversation;
  final VoidCallback onVocabulary;
  final bool locationRecommendationEnabled;
  final bool personalizedLearningEnabled;
  final int savedWordCount;
  final int savedPlaceCount;
  final int savedPersonalObjectCount;
  final ValueChanged<bool> onLocationRecommendationChanged;
  final ValueChanged<bool> onPersonalizedLearningChanged;
  final VoidCallback onClearPersonalizedLearningData;
  final VoidCallback onClearPlaceData;
  final LocationRecommendationController? locationController; // TODO: 调试用，以后删除
  final FavoriteWordCallback? onFavoriteSaved;
  final VoidCallback? onOpenPersonalObjects;

  const MainInterfaceScreen({
    super.key,
    required this.onStuck,
    required this.onCamera,
    required this.onConversation,
    required this.onVocabulary,
    required this.locationRecommendationEnabled,
    required this.personalizedLearningEnabled,
    this.savedWordCount = 0,
    required this.savedPlaceCount,
    this.savedPersonalObjectCount = 0,
    required this.onLocationRecommendationChanged,
    required this.onPersonalizedLearningChanged,
    required this.onClearPersonalizedLearningData,
    required this.onClearPlaceData,
    this.locationController,
    this.onFavoriteSaved,
    this.onOpenPersonalObjects,
  });

  @override
  State<MainInterfaceScreen> createState() => _MainInterfaceScreenState();
}

class _MainInterfaceScreenState extends State<MainInterfaceScreen>
    with TickerProviderStateMixin {
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
  int _currentPage = 1;
  String _userName = '朋友';
  double _pointerDownX = 0;
  double _pointerDownY = 0;

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
    _pageController = PageController(initialPage: 1);

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
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _springController.dispose();
    _starIdleController.dispose();
    super.dispose();
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
          '✨ 小星星正在打开「${feature.label}」功能界面',
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

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FBFF), Color(0xFFEFF5FF), Color(0xFFF7F2EA)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Listener(
                  onPointerDown: (e) {
                    _pointerDownX = e.position.dx;
                    _pointerDownY = e.position.dy;
                  },
                  onPointerUp: (e) {
                    final dx = e.position.dx - _pointerDownX;
                    final dy = e.position.dy - _pointerDownY;
                    if (dx.abs() > 80 && dx.abs() > dy.abs() * 2) {
                      if (dx < 0 && _currentPage < 2) {
                        _goToPage(_currentPage + 1);
                      } else if (dx > 0 && _currentPage > 0) {
                        _goToPage(_currentPage - 1);
                      }
                    }
                  },
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: [
                      _buildPlaceholderPage('表达', '常用表达和快捷入口'),
                      RepaintBoundary(child: _buildHomePage()),
                      RepaintBoundary(child: _buildSettingsPage()),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
                child: RepaintBoundary(
                  child: GlassBottomNavigationBar(
                    currentPage: _currentPage,
                    onTap: _goToPage,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderPage(String title, String subtitle) {
    return Stack(
      children: [
        const Positioned.fill(
          child: RepaintBoundary(
            child: LiquidBackgroundDecorations(),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ],
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
      onLocationRecommendationChanged: widget.onLocationRecommendationChanged,
      onPersonalizedLearningChanged: widget.onPersonalizedLearningChanged,
      onClearPersonalizedLearningData: widget.onClearPersonalizedLearningData,
      unconfirmedPlaceCount: unconfirmedCount,
      onNameChanged: (newName) {
        setState(() => _userName = newName);
      },
      onOpenLocationMemory: () {
        if (controller == null) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaceMemoryManagementPage(
              controller: controller,
              onFavoriteSaved: widget.onFavoriteSaved,
            ),
          ),
        );
      },
      onOpenPersonalObjects: widget.onOpenPersonalObjects,
    );
  }

  Future<void> _confirmClearPlaceData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除地点记录？'),
        content: const Text('这会删除本机保存的地点和地点词汇使用次数，操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onClearPlaceData();
  }

  // TODO: 调试方法，以后删除
  Future<void> _showLocationDebugInfo(BuildContext context) async {
    final ctrl = widget.locationController;
    if (ctrl == null) return;

    await ctrl.refreshLocationContext(force: true);
    if (!context.mounted) return;

    final places = ctrl.debugPlaces;
    final usages = ctrl.debugWordUsages;
    final currentPlace = ctrl.currentPlace;
    final currentSemantic = ctrl.currentSemantic;
    final enabled = ctrl.enabled;
    final lastError = ctrl.lastLocationError;
    final recognitionError = ctrl.lastPlaceRecognitionError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '📍 地点数据调试',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              _debugSection('状态', [
                '定位功能：${enabled ? "已开启" : "已关闭"}',
                '高德识别：${ctrl.automaticPlaceRecognitionAvailable ? "已配置" : "未配置 Key"}',
                '已记录地点数：${places.length}',
                '词汇使用记录数：${usages.length}',
                '当前地点：${currentPlace?.name ?? "无"}',
                if (currentSemantic != null)
                  '识别类型：${currentSemantic.type}（${currentSemantic.poiName ?? "无 POI 名称"}）',
                if (lastError != null) '最后错误：$lastError',
                if (recognitionError != null) '高德识别错误：$recognitionError',
              ]),
              const SizedBox(height: 16),
              if (places.isEmpty)
                const Text(
                  '暂无地点数据。请先在上方开启"地点词汇推荐"，然后使用 App 一段时间后回来查看。',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              for (final place in places) ...[
                _buildPlaceCard(place, usages),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _debugSection(String title, List<String> lines) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceCard(PlaceCluster place, List<PlaceWordUsage> allUsages) {
    final placeUsages = allUsages.where((u) => u.placeId == place.id).toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.location_fill,
                  size: 16, color: Color(0xFF267D70)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  place.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (place.id == widget.locationController?.currentPlace?.id)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('当前',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF34C759),
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '坐标：${place.latitude.toStringAsFixed(6)}, ${place.longitude.toStringAsFixed(6)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            '半径：${place.radiusMeters.round()}m · 访问 ${place.visitCount} 次',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (place.placeType != null)
            Text(
              '地点类型：${place.placeType} · ${place.poiName ?? "未识别 POI"}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          Text(
            '创建：${place.createdAt.toString().substring(0, 19)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (placeUsages.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('地点词汇：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: placeUsages.take(20).map((u) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${u.wordText} (${u.count})',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final interactionTop = math.max(148.0, height * 0.20);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: LiquidBackgroundDecorations(),
              ),
            ),
            Positioned(
              top: 8,
              left: 24,
              right: 24,
              child: RepaintBoundary(
                child: HeaderWidget(userName: _userName),
              ),
            ),
            if (widget.locationController != null)
              Positioned(
                top: 76,
                left: 22,
                right: 22,
                child: CurrentPlaceStatusCard(
                  controller: widget.locationController!,
                ),
              ),
            Positioned(
              top: interactionTop,
              bottom: 0,
              left: 0,
              right: 0,
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
                                child: SpriteWidget(
                                  mood: _isAnyBubbleNearStar
                                      ? SpriteMood.nearTarget
                                      : SpriteMood.idle,
                                  isBlinking: t < 0.055,
                                  animationValue: t,
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
}

class HeaderWidget extends StatelessWidget {
  final String userName;
  const HeaderWidget({super.key, this.userName = '朋友'});

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '早安';
    if (hour >= 11 && hour < 14) return '午安';
    if (hour >= 14 && hour < 18) return '下午好';
    return '晚安';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
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

    // 稳定的椭圆柔阴影：避免 Android 真机对复杂 Path 阴影的渲染伪影。
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

    // 外侧暖色柔光，让星星更立体，但不画刺眼弧线。
    final outerGlowPaint = Paint()
      ..color = const Color(0xFFFFCF6A).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path.shift(const Offset(0, 2)), outerGlowPaint);

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        // 中心偏白，向外逐渐过渡到黄中偏橙，避免整体发淡。
        center: Alignment(-0.10 + wave * 0.01, -0.12),
        radius: 0.98,
        colors: const [
          Color(0xFFFFFEF4), // 中心暖白
          Color(0xFFFFF2B8), // 浅奶黄
          Color(0xFFFFD65E), // 明亮黄
          Color(0xFFFFB43F), // 黄中偏橙
          Color(0xFFF29B2E), // 边缘橙黄厚度
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

    // 顶部液态柔光：只保留柔和亮面，不画成明显弧线。
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

    // 右下方轻微暖阴影，只保留厚度感，不产生脏线。
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

    // 依然是标准五角星结构：5 个外角 + 5 个内凹点。
    // 只给很小的比例差，保证灵动但不会变成一团花形。
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

      // 只让星星身体向右微倾，脸部保持正向，避免表情跟着歪。
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
    // 五个角更圆润：外角加大圆角，内凹点也略微放软。
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
    // 这版不再画硬折线。内部折痕改成极淡的软面，避免出现线条阴影。
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

    // 中心泛白：面积略集中，让“中间更淡、更白”，但不形成白圈。
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
    // 液态玻璃风格白边：外侧柔光 + 清晰白边 + 内侧暖色折射。
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

    // 眼睛保持两个小黑点。
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
    CupertinoIcons.text_bubble,
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
                // 滑动的液态玻璃椭圆指示器（纯背景，无图标）
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
                // 三个图标（始终可见）
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

class FeatureDetailPage extends StatelessWidget {
  final FeatureConfig feature;

  const FeatureDetailPage({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF2D3),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF8EA), Color(0xFFFFE9C1), Color(0xFFFDE1BD)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              const Positioned.fill(child: SoftBackgroundDecorations()),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GlassIconButton(
                      icon: CupertinoIcons.chevron_left,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 42),
                    Center(
                      child: GlassFeatureIcon(
                        icon: feature.icon,
                        color: feature.color,
                      ),
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
                        '这里是「${feature.label}」功能界面',
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
            ],
          ),
        ),
      ),
    );
  }

  String _featureDescription(String label) {
    switch (label) {
      case '聊天':
        return '可以在这里接入 AI 对话、语音输入、聊天记录、智能陪伴等功能。';
      case '拍照':
        return '可以在这里接入相机、相册上传、图片识别、拍照分析等功能。';
      case '日程':
        return '可以在这里接入日历、待办事项、提醒、每日计划等功能。';
      case '工具':
        return '可以在这里接入快捷工具、智能模板、效率组件、常用入口等功能。';
      default:
        return '这是一个预留功能页面。';
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
