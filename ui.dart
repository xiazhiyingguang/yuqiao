import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

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
      ),
    );
  }
}

enum SpriteMood {
  idle,
  nearTarget,
}

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

  const MainInterfaceScreen({
    super.key,
    required this.onStuck,
    required this.onCamera,
    required this.onConversation,
    required this.onVocabulary,
  });

  @override
  State<MainInterfaceScreen> createState() => _MainInterfaceScreenState();
}

class _MainInterfaceScreenState extends State<MainInterfaceScreen>
    with TickerProviderStateMixin {
  final List<Offset> _baseOffsets = const [
    Offset(-90, -130),
    Offset(90, -130),
    Offset(-90, 130),
    Offset(90, 130),
  ];

  final List<Offset> _dragDisplacements = [
    Offset.zero,
    Offset.zero,
    Offset.zero,
    Offset.zero,
  ];

  int? _springingIndex;

  late final AnimationController _springController;
  late Animation<Offset> _springAnimation;
  late final AnimationController _idleController;

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

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _springController.dispose();
    _idleController.dispose();
    super.dispose();
  }

  void _runSpringAnimation(Offset releaseOffset, int index) {
    _springingIndex = index;
    _springAnimation = _springController.drive(
      Tween<Offset>(
        begin: releaseOffset,
        end: Offset.zero,
      ),
    );

    _springController.reset();
    _springController.animateWith(
      SpringSimulation(
        const SpringDescription(
          mass: 1.0,
          stiffness: 130.0,
          damping: 12.0,
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9EED9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF7EA),
              Color(0xFFFEEAD2),
              Color(0xFFFDE1BD),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: SoftBackgroundDecorations(),
                  ),

                  const Positioned(
                    top: 10,
                    left: 24,
                    right: 24,
                    child: StatusBarSimulator(),
                  ),

                  const Positioned(
                    top: 54,
                    left: 24,
                    right: 24,
                    child: HeaderWidget(),
                  ),

                  const Positioned(
                    top: 155,
                    left: 40,
                    right: 40,
                    child: InstructionBanner(),
                  ),

                  Positioned(
                    top: 200,
                    bottom: 110,
                    left: 0,
                    right: 0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: DashedConnectorPainter(),
                            ),
                          ),
                        ),

                        Center(
                          child: AnimatedBuilder(
                            animation: _idleController,
                            builder: (context, child) {
                              final wave = math.sin(
                                _idleController.value * 2 * math.pi,
                              );
                              final shadowScale = 1.0 - (wave * 0.08);
                              final shadowOpacity = 0.25 - (wave * 0.05);

                              return Transform.scale(
                                scale: shadowScale,
                                child: Container(
                                  width: 140,
                                  height: 20,
                                  margin: const EdgeInsets.only(top: 120),
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFE2B079)
                                            .withValues(alpha: shadowOpacity),
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
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _springController,
                              _idleController,
                            ]),
                            builder: (context, child) {
                              final t = _idleController.value;

                              final bobbingY =
                                  math.sin(t * 2 * math.pi) * 8.0;
                              final driftX =
                                  math.cos(t * 2 * math.pi) * 3.0;
                              final idleTilt =
                                  math.sin(t * 2 * math.pi) * 0.04;
                              final breathingScale =
                                  1.0 + math.sin(t * 2 * math.pi) * 0.02;

                              final isBlinking = t < 0.05;
                              final mood = _isAnyBubbleNearStar
                                  ? SpriteMood.nearTarget
                                  : SpriteMood.idle;

                              return Transform.translate(
                                offset: Offset(driftX, bobbingY),
                                child: Transform.rotate(
                                  angle: idleTilt,
                                  child: Transform.scale(
                                    scale: breathingScale,
                                    child: SpriteWidget(
                                      mood: mood,
                                      isBlinking: isBlinking,
                                      animationValue: t,
                                    ),
                                  ),
                                ),
                              );
                            },
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

                  const Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: GlassBottomNavigationBar(),
                  ),

                  Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 120,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
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

class StatusBarSimulator extends StatelessWidget {
  const StatusBarSimulator({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '9:41',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        Row(
          children: const [
            Icon(Icons.signal_cellular_alt, size: 14, color: Colors.black),
            SizedBox(width: 4),
            Icon(CupertinoIcons.wifi, size: 14, color: Colors.black),
            SizedBox(width: 4),
            Icon(Icons.battery_full_rounded, size: 18, color: Colors.black),
          ],
        ),
      ],
    );
  }
}

class HeaderWidget extends StatelessWidget {
  const HeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '早安，朋友',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3E3121),
                  ),
                ),
                SizedBox(width: 4),
                Text('✨', style: TextStyle(fontSize: 18)),
              ],
            ),
            SizedBox(height: 6),
            Text(
              '今天也要元气满满哦~',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Color(0xFF8F7A65),
              ),
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.bell,
                    color: Color(0xFF6B5A49),
                    size: 22,
                  ),
                  Positioned(
                    top: 11,
                    right: 11,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFB03A),
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

class InstructionBanner extends StatelessWidget {
  const InstructionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF2D3).withValues(alpha: 0.55),
          border: Border.all(
            color: const Color(0xFFFFEAC0).withValues(alpha: 0.6),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✨', style: TextStyle(fontSize: 11)),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                '拖动功能球到小精灵，快速打开功能',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF916C3E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(width: 6),
            Text('✨', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
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
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isHighlighted
                        ? iconColor.withValues(alpha: 0.4)
                        : const Color(0xFFE2B27E).withValues(alpha: 0.12),
                    blurRadius: isHighlighted ? 18 : 10,
                    spreadRadius: isHighlighted ? 2 : 0,
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(41),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.65),
                        Colors.white.withValues(alpha: 0.15),
                      ],
                      stops: const [0.1, 0.9],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.65),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          iconColor.withValues(alpha: 0.85),
                          iconColor.withValues(alpha: 0.55),
                        ],
                      ).createShader(bounds),
                      child: Icon(
                        icon,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
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
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF3E3121),
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
      width: 104,
      height: 104,
      child: CustomPaint(
        painter: PuffyStarPainter(
          mood: mood,
          isBlinking: isBlinking,
          animationValue: animationValue,
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
    final cy = size.height / 2;
    final wave = math.sin(animationValue * 2 * math.pi);

    final path = _buildRoundedStarPath(size, wave);

    final shadowOffset = 6.0 + wave * 1.5;
    final shadowBlur = 14.0 + wave * 2.0;

    canvas.drawShadow(
      path.shift(Offset(0, shadowOffset)),
      const Color(0xFFD48418).withValues(alpha: 0.65),
      shadowBlur,
      true,
    );

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.25 + wave * 0.02, -0.25 + wave * 0.01),
        radius: 0.85,
        colors: const [
          Color(0xFFFFFDE8),
          Color(0xFFFFDF63),
          Color(0xFFF99D1C),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, bodyPaint);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawPath(path, edgePaint);

    final specularPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(cx - 25, cy - 35, 20, 10))
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(cx - 20, cy - 25);
    canvas.rotate(-math.pi / 6);
    canvas.drawOval(const Rect.fromLTWH(-10, -5, 22, 9), specularPaint);
    canvas.restore();

    final eyeY = cy - size.height * 0.05;
    final leftEyeX = cx - size.width * 0.14;
    final rightEyeX = cx + size.width * 0.14;
    final eyeRadius = size.width * 0.046;

    void drawBlush(Offset center) {
      final blushPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFF6B76).withValues(alpha: 0.45),
            const Color(0xFFFF6B76).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 11));

      canvas.drawCircle(center, 11, blushPaint);
    }

    drawBlush(Offset(leftEyeX - 4, eyeY + 11));
    drawBlush(Offset(rightEyeX + 4, eyeY + 11));

    if (mood == SpriteMood.idle) {
      _drawIdleFace(
        canvas: canvas,
        size: size,
        leftEyeX: leftEyeX,
        rightEyeX: rightEyeX,
        eyeY: eyeY,
        eyeRadius: eyeRadius,
        cx: cx,
        cy: cy,
      );
    } else {
      _drawExcitedFace(
        canvas: canvas,
        size: size,
        leftEyeX: leftEyeX,
        rightEyeX: rightEyeX,
        eyeY: eyeY,
        eyeRadius: eyeRadius,
        cx: cx,
        cy: cy,
      );
    }
  }

  Path _buildRoundedStarPath(Size size, double wave) {
    final center = Offset(size.width / 2, size.height / 2);

    final outerBase = size.width * 0.45;
    final innerBase = size.width * 0.31;

    final points = <Offset>[];
    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final isOuter = i.isEven;

      final wobble = math.sin(animationValue * 2 * math.pi + i * 0.75) *
          size.width *
          0.012;

      final radius = (isOuter ? outerBase : innerBase) + wobble + wave * 0.6;

      points.add(
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      );
    }

    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );

      if (i == 0) {
        path.moveTo(mid.dx, mid.dy);
      } else {
        path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
    }

    path.close();
    return path;
  }

  void _drawIdleFace({
    required Canvas canvas,
    required Size size,
    required double leftEyeX,
    required double rightEyeX,
    required double eyeY,
    required double eyeRadius,
    required double cx,
    required double cy,
  }) {
    final eyePaint = Paint()
      ..color = const Color(0xFF382413)
      ..style = PaintingStyle.fill;

    if (isBlinking) {
      final blinkPaint = Paint()
        ..color = const Color(0xFF382413)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.8
        ..strokeCap = StrokeCap.round;

      final leftBlinkRect = Rect.fromCenter(
        center: Offset(leftEyeX, eyeY),
        width: eyeRadius * 2,
        height: eyeRadius * 1.5,
      );
      final rightBlinkRect = Rect.fromCenter(
        center: Offset(rightEyeX, eyeY),
        width: eyeRadius * 2,
        height: eyeRadius * 1.5,
      );

      canvas.drawArc(leftBlinkRect, 0, math.pi, false, blinkPaint);
      canvas.drawArc(rightBlinkRect, 0, math.pi, false, blinkPaint);
    } else {
      canvas.drawCircle(Offset(leftEyeX, eyeY), eyeRadius, eyePaint);
      canvas.drawCircle(Offset(rightEyeX, eyeY), eyeRadius, eyePaint);

      final mainLightPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(leftEyeX + eyeRadius * 0.25, eyeY - eyeRadius * 0.25),
        eyeRadius * 0.36,
        mainLightPaint,
      );
      canvas.drawCircle(
        Offset(rightEyeX + eyeRadius * 0.25, eyeY - eyeRadius * 0.25),
        eyeRadius * 0.36,
        mainLightPaint,
      );

      final subLightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(
        Offset(leftEyeX - eyeRadius * 0.35, eyeY + eyeRadius * 0.35),
        eyeRadius * 0.18,
        subLightPaint,
      );
      canvas.drawCircle(
        Offset(rightEyeX - eyeRadius * 0.35, eyeY + eyeRadius * 0.35),
        eyeRadius * 0.18,
        subLightPaint,
      );
    }

    final mouthPaint = Paint()
      ..color = const Color(0xFF382413)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round;

    final mouthRect = Rect.fromCenter(
      center: Offset(cx, cy + size.height * 0.025),
      width: size.width * 0.18,
      height: size.height * 0.09,
    );

    canvas.drawArc(mouthRect, 0, math.pi, false, mouthPaint);
  }

  void _drawExcitedFace({
    required Canvas canvas,
    required Size size,
    required double leftEyeX,
    required double rightEyeX,
    required double eyeY,
    required double eyeRadius,
    required double cx,
    required double cy,
  }) {
    _drawSparkleEye(canvas, Offset(leftEyeX, eyeY), eyeRadius * 1.6);
    _drawSparkleEye(canvas, Offset(rightEyeX, eyeY), eyeRadius * 1.6);

    final mouthRect = Rect.fromCenter(
      center: Offset(cx, cy + size.height * 0.045),
      width: size.width * 0.18,
      height: size.height * 0.16,
    );

    canvas.drawOval(mouthRect, Paint()..color = const Color(0xFF382413));

    canvas.save();
    canvas.clipPath(Path()..addOval(mouthRect));

    final tonguePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFFFFACBC),
          Color(0xFFFF607C),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(cx, cy + size.height * 0.11),
          radius: size.width * 0.08,
        ),
      );

    canvas.drawCircle(
      Offset(cx, cy + size.height * 0.11),
      size.width * 0.08,
      tonguePaint,
    );

    canvas.restore();
  }

  void _drawSparkleEye(Canvas canvas, Offset center, double size) {
    final path = Path();
    final half = size / 2;

    path.moveTo(center.dx, center.dy - half);
    path.quadraticBezierTo(center.dx, center.dy, center.dx + half, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + half);
    path.quadraticBezierTo(center.dx, center.dy, center.dx - half, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - half);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF382413)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant PuffyStarPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.isBlinking != isBlinking ||
        oldDelegate.animationValue != animationValue;
  }
}

class DashedConnectorPainter extends CustomPainter {
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
  const GlassBottomNavigationBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(42),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(42),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(42),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTabItem(
                    icon: CupertinoIcons.compass,
                    label: '发现',
                    isActive: false,
                  ),
                  const SizedBox(width: 72),
                  _buildTabItem(
                    icon: CupertinoIcons.person,
                    label: '我的',
                    isActive: false,
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            top: -14,
            bottom: 0,
            child: CenterHomeBubble(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required String label,
    required bool isActive,
  }) {
    final color = isActive ? const Color(0xFFC0833F) : const Color(0xFF6B5A49);

    return SizedBox(
      width: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class CenterHomeBubble extends StatelessWidget {
  const CenterHomeBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        const Color(0xFFECC186).withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(31),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0.35),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFECA02D),
                          Color(0xFFD47C10),
                        ],
                      ).createShader(bounds),
                      child: const Icon(
                        CupertinoIcons.house_fill,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        const Text(
          '首页',
          style: TextStyle(
            fontSize: 11.5,
            color: Color(0xFFC0833F),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class FeatureDetailPage extends StatelessWidget {
  final FeatureConfig feature;

  const FeatureDetailPage({
    super.key,
    required this.feature,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF2D3),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF8EA),
              Color(0xFFFFE9C1),
              Color(0xFFFDE1BD),
            ],
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

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

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

  const GlassFeatureIcon({
    super.key,
    required this.icon,
    required this.color,
  });

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
            child: Icon(
              icon,
              size: 64,
              color: Colors.white,
            ),
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
    return CustomPaint(
      painter: SoftBackgroundPainter(),
    );
  }
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
