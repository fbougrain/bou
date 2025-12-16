import 'package:flutter/material.dart';
import '../theme/colors.dart';

class QuickStatTile extends StatelessWidget {
  // Shared aspect ratio used by grids that contain QuickStatTile so the
  // tile sizing stays consistent across pages. Use `QuickStatTile.aspectRatio`
  // when creating SliverGridDelegateWithFixedCrossAxisCount.
  static const double aspectRatio = 1.10;
  final String label;
  final String value;
  final Color color;
  final Color? dotColor;
  const QuickStatTile({
    required this.label,
    required this.value,
    required this.color,
    this.dotColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderDark, width: 1.1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: LayoutBuilder(builder: (context, constraints) {
          final bounded = constraints.maxHeight.isFinite;
          return Column(
            // In bounded layouts (Grid tiles) we want the number anchored to the
            // bottom like the original Home card. When unbounded (e.g. inside a
            // scrollable Column) using Spacer causes a RenderFlex error — so we
            // conditionally use Spacer only when the incoming height is finite.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dotColor != null)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (dotColor != null) const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: neutralText.withValues(alpha: 0.7),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              // When we have a bounded height (grid tile) push the number to the
              // bottom for the original appearance; otherwise use fixed gap.
              if (bounded) const Spacer() else const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }),
      );
}
