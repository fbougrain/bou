import 'package:flutter/material.dart';
import '../theme/colors.dart';

class DualProgressRing extends StatelessWidget {
  final double progress; // 0..1
  final double time; // 0..1
  final Color progressColor;
  final Color timeColor;
  const DualProgressRing({
    super.key,
    required this.progress,
    required this.time,
    this.progressColor = accentTech,
    this.timeColor = newaccent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size.square(148),
            painter: _RingPainter(
              progress: time,
              color: timeColor.withValues(alpha: 0.55),
              stroke: 10,
            ),
          ),
          CustomPaint(
            size: const Size.square(148),
            painter: _RingPainter(
              progress: progress,
              color: progressColor,
              stroke: 14,
              cap: StrokeCap.round,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PHYSICAL',
                  style: TextStyle(
                    color: neutralText.withValues(alpha: 0.55),
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(time * 100).toStringAsFixed(0)}% TIME',
                  style: TextStyle(
                    color: newaccent.withValues(alpha: 0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;
  final StrokeCap cap;
  _RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
    this.cap = StrokeCap.butt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final start = -90 * 3.1415926535 / 180;
    final sweep = 2 * 3.1415926535 * progress.clamp(0, 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = cap
      ..shader = LinearGradient(
        colors: [color, color.withValues(alpha: 0.25)],
      ).createShader(rect);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFF1C2530);
    final radius = size.width / 2;
    canvas.drawCircle(rect.center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: rect.center, radius: radius),
      start,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}
