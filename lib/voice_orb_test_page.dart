import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class VoiceOrbTestPage extends StatelessWidget {
  const VoiceOrbTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Stack(
        children: [
          const Positioned.fill(child: _TestBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topLeft,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6B8FB8).withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      CupertinoIcons.chevron_left,
                      color: Color(0xFF243043),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Center(
            child: VoiceRecordingView(
              isRecording: true,
              title: 'Voice Activated',
            ),
          ),
        ],
      ),
    );
  }
}

class _TestBackdrop extends StatelessWidget {
  const _TestBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF9FCFF),
            Color(0xFFDDEBFF),
            Color(0xFFFFF0C9),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _TestBackdropPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TestBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF69C6FF).withValues(alpha: 0.22),
      const Color(0xFFFFC85B).withValues(alpha: 0.26),
      const Color(0xFFFF7AA9).withValues(alpha: 0.18),
    ];
    final centers = [
      Offset(size.width * 0.18, size.height * 0.25),
      Offset(size.width * 0.82, size.height * 0.34),
      Offset(size.width * 0.52, size.height * 0.78),
    ];

    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [colors[i], colors[i].withValues(alpha: 0)],
        ).createShader(
          Rect.fromCircle(center: centers[i], radius: size.width * 0.42),
        );
      canvas.drawCircle(centers[i], size.width * 0.42, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class VoiceRecordingView extends StatefulWidget {
  final bool isRecording;
  final String title;

  const VoiceRecordingView({
    super.key,
    this.isRecording = true,
    this.title = 'Voice Activated',
  });

  @override
  State<VoiceRecordingView> createState() => _VoiceRecordingViewState();
}

class _VoiceRecordingViewState extends State<VoiceRecordingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    if (widget.isRecording) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VoiceRecordingView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isRecording && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isRecording && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = math.min(screenWidth - 48, 360.0);

    return Container(
      width: cardWidth,
      height: cardWidth * 1.34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(42),
        border: Border.all(color: const Color(0xFFECECEC), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          const Spacer(flex: 15),
          SizedBox(
            width: cardWidth * 0.60,
            height: cardWidth * 0.60,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: VoiceOrbPainter(
                    progress: _controller.value,
                    isRecording: widget.isRecording,
                  ),
                );
              },
            ),
          ),
          const Spacer(flex: 5),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: Color(0xFF1D1D1F),
            ),
          ),
          const Spacer(flex: 8),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return VoiceDotsIndicator(
                progress: _controller.value,
                isRecording: widget.isRecording,
              );
            },
          ),
          const Spacer(flex: 10),
        ],
      ),
    );
  }
}

class VoiceOrbPainter extends CustomPainter {
  final double progress;
  final bool isRecording;

  VoiceOrbPainter({
    required this.progress,
    required this.isRecording,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = isRecording ? progress : 0.0;

    final cx = size.width / 2;
    final cy = size.height / 2;

    final wave1 = math.sin(t * math.pi * 2);
    final wave2 = math.sin(t * math.pi * 2 + math.pi * 0.65);
    final wave3 = math.cos(t * math.pi * 2 + math.pi * 0.35);

    final orbRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: size.width * 0.82,
      height: size.height * 0.82,
    );

    final clipPath = Path()..addOval(orbRect);

    // 外部整体雾气
    final outerHaloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF7F8).withValues(alpha: 0.92),
          const Color(0xFFFFE6EB).withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.56, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(cx, cy),
          radius: size.width * 0.50,
        ),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);

    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.45,
      outerHaloPaint,
    );

    // 更柔和的白边光效
    final outerRingGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final outerRingSoft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.16);

    canvas.drawOval(orbRect.inflate(1.5), outerRingGlow);
    canvas.drawOval(orbRect, outerRingSoft);

    canvas.save();
    canvas.clipPath(clipPath);

    // 底层球体底色
    final basePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          -0.05 + wave2 * 0.02,
          -0.08 + wave1 * 0.02,
        ),
        radius: 0.98,
        colors: [
          Colors.white.withValues(alpha: 0.98),
          const Color(0xFFFFF5F6).withValues(alpha: 0.95),
          const Color(0xFFFFE9EE).withValues(alpha: 0.82),
          const Color(0xFFFFD8E2).withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.10),
        ],
        stops: const [0.0, 0.26, 0.55, 0.84, 1.0],
      ).createShader(orbRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawOval(orbRect, basePaint);

    // ========= 内部 3 个大模糊圆（增强律动） =========

    _drawLargeBlurOrb(
      canvas,
      rect: Rect.fromCenter(
        center: Offset(
          cx - size.width * 0.05 + wave1 * 18,
          cy - size.height * 0.06 + wave2 * 14,
        ),
        width: orbRect.width * (0.94 + wave1 * 0.04),
        height: orbRect.height * (0.94 + wave2 * 0.04),
      ),
      colors: [
        const Color(0xFFFF3A9A).withValues(alpha: 0.58),
        const Color(0xFFFF7BAA).withValues(alpha: 0.32),
        Colors.white.withValues(alpha: 0.0),
      ],
      blurSigma: 22,
    );

    _drawLargeBlurOrb(
      canvas,
      rect: Rect.fromCenter(
        center: Offset(
          cx + size.width * 0.05 + wave2 * 20,
          cy - size.height * 0.01 + wave3 * 15,
        ),
        width: orbRect.width * (0.92 + wave2 * 0.04),
        height: orbRect.height * (0.92 + wave3 * 0.04),
      ),
      colors: [
        const Color(0xFFFF6B6B).withValues(alpha: 0.42),
        const Color(0xFFFFB0A8).withValues(alpha: 0.24),
        Colors.white.withValues(alpha: 0.0),
      ],
      blurSigma: 22,
    );

    _drawLargeBlurOrb(
      canvas,
      rect: Rect.fromCenter(
        center: Offset(
          cx + size.width * 0.01 + wave3 * 16,
          cy + size.height * 0.06 + wave1 * 13,
        ),
        width: orbRect.width * (0.90 + wave3 * 0.04),
        height: orbRect.height * (0.90 + wave1 * 0.04),
      ),
      colors: [
        const Color(0xFFFFD4DB).withValues(alpha: 0.44),
        const Color(0xFFFFE0E5).withValues(alpha: 0.22),
        Colors.white.withValues(alpha: 0.0),
      ],
      blurSigma: 22,
    );

    // 中央微白提亮
    final centerGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(
            cx + size.width * 0.02,
            cy + size.height * 0.02,
          ),
          radius: size.width * 0.22,
        ),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    canvas.drawCircle(
      Offset(
        cx + size.width * 0.02,
        cy + size.height * 0.02,
      ),
      size.width * 0.20,
      centerGlowPaint,
    );

    // ========= 内阴影 =========
    final innerShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.065)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawOval(
      orbRect.shift(const Offset(10, 12)).inflate(12),
      innerShadowPaint,
    );

    // 内侧高光
    final innerHighlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    canvas.drawOval(
      orbRect.shift(const Offset(-8, -8)).inflate(8),
      innerHighlightPaint,
    );

    canvas.restore();
  }

  void _drawLargeBlurOrb(
    Canvas canvas, {
    required Rect rect,
    required List<Color> colors,
    required double blurSigma,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, -0.15),
        radius: 0.96,
        colors: colors,
        stops: const [0.0, 0.64, 1.0],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(covariant VoiceOrbPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isRecording != isRecording;
  }
}

class VoiceDotsIndicator extends StatelessWidget {
  final double progress;
  final bool isRecording;

  const VoiceDotsIndicator({
    super.key,
    required this.progress,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    const dotCount = 9;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(dotCount, (index) {
        final activeIndex = isRecording
            ? ((progress * dotCount * 1.4).floor() % dotCount)
            : 0;

        final distance = (index - activeIndex).abs();
        final wrappedDistance = math.min(distance, dotCount - distance);
        final strength = isRecording
            ? (1.0 - wrappedDistance * 0.32).clamp(0.0, 1.0)
            : 0.0;

        final dotSize = 7.0 + strength * 1.6;
        final opacity = 0.08 + strength * 0.85;

        final color = Color.lerp(
          const Color(0xFFE8EAED),
          const Color(0xFF1D2430),
          strength,
        )!.withValues(alpha: opacity);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: dotSize,
          height: dotSize,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );
      }),
    );
  }
}
