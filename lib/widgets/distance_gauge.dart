import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An animated circular arc gauge that fills as [value] increases toward [maxValue].
/// Auto-scales [maxValue] when [autoScale] is true.
class DistanceGauge extends StatefulWidget {
  final double value;
  final double maxValue;
  final bool autoScale;
  final String label;
  final String unit;
  final Color arcColor;
  final Color trackColor;
  final double strokeWidth;

  const DistanceGauge({
    super.key,
    required this.value,
    this.maxValue = 1000.0,
    this.autoScale = true,
    required this.label,
    required this.unit,
    this.arcColor = const Color(0xFF00E5FF),
    this.trackColor = const Color(0xFF263238),
    this.strokeWidth = 16.0,
  });

  @override
  State<DistanceGauge> createState() => _DistanceGaugeState();
}

class _DistanceGaugeState extends State<DistanceGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousFraction = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(DistanceGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final max = _resolveMax();
    final newFraction = (widget.value / max).clamp(0.0, 1.0);
    _animation = Tween<double>(
      begin: _previousFraction,
      end: newFraction,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _previousFraction = newFraction;
    _controller
      ..reset()
      ..forward();
  }

  double _resolveMax() {
    if (!widget.autoScale) return widget.maxValue;
    // Round up to next clean milestone
    const milestones = [
      100.0,
      500.0,
      1000.0,
      5000.0,
      10000.0,
      50000.0,
      100000.0,
    ];
    for (final m in milestones) {
      if (widget.value < m) return m;
    }
    return widget.value * 1.2;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return CustomPaint(
          painter: _GaugePainter(
            fraction: _animation.value,
            arcColor: widget.arcColor,
            trackColor: widget.trackColor,
            strokeWidth: widget.strokeWidth,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.unit,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color arcColor;
  final Color trackColor;
  final double strokeWidth;

  const _GaugePainter({
    required this.fraction,
    required this.arcColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth;

    const startAngle = math.pi * 0.75; // 135°
    const sweepFull = math.pi * 1.5; // 270°

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, startAngle, sweepFull, false, trackPaint);

    if (fraction > 0) {
      canvas.drawArc(rect, startAngle, sweepFull * fraction, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.arcColor != arcColor ||
      old.strokeWidth != strokeWidth;
}
