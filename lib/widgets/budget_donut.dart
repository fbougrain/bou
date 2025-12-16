import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/colors.dart';

class BudgetDonut extends StatelessWidget {
  final double spent;
  final double total;
  final double ratio; // 0..1
  final NumberFormat currency;
  const BudgetDonut({
    super.key,
    required this.spent,
    required this.total,
    required this.ratio,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (total - spent).clamp(0, total);
    final ratioLabel = '${(ratio * 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderDark, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: CustomPaint(
              painter: _DonutPainter(ratio: ratio, color: accentTech),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ratioLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'USED',
                      style: TextStyle(
                        color: neutralText.withValues(alpha: 0.55),
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _budgetLine(
                  label: 'Spent',
                  value: currency.format(spent),
                  color: accentTech,
                ),
                const SizedBox(height: 14),
                _budgetLine(
                  label: 'Remaining',
                  value: currency.format(remaining),
                  color: Colors.greenAccent.shade400,
                ),
                const SizedBox(height: 20),
                Text(
                  'Total: ${currency.format(total)}',
                  style: TextStyle(
                    color: neutralText.withValues(alpha: 0.6),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetLine({
    required String label,
    required String value,
    required Color color,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: neutralText.withValues(alpha: 0.56),
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Container(
            width: 46,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _DonutPainter extends CustomPainter {
  final double ratio; // 0..1
  final Color color;
  _DonutPainter({required this.ratio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = 18.0;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFF1C2530);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [color, color.withValues(alpha: 0.15)],
      ).createShader(rect);
    final center = rect.center;
    final radius = size.width / 2 - stroke / 2;
    canvas.drawCircle(center, radius, bg);
    final sweep = 2 * 3.1415926535 * ratio.clamp(0, 1);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.1415926535 / 2,
      sweep,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.ratio != ratio || old.color != color;
}
