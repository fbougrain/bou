import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'main_sections.dart';

class SecondaryTabs extends StatelessWidget {
  const SecondaryTabs({
    super.key,
    required this.current,
    required this.onSelect,
    this.visible = true,
  });
  final MainSection current;
  final ValueChanged<MainSection> onSelect;
  final bool
  visible; // controls fade when switching away from secondary context

  static const double _barWidth = 60;
  static const double _barHeight = 3;
  static const Duration _duration = Duration(milliseconds: 220);
  static const Curve _curve = Curves.easeOutCubic;

  List<(MainSection, String)> get _tabs => const [
    (MainSection.tasks, 'Tasks'),
    (MainSection.stocks, 'Stocks'),
    (MainSection.forms, 'Forms'),
    (MainSection.billing, 'Billing'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabs = _tabs;
        final count = tabs.length;
        final slotWidth = constraints.maxWidth / count;
        final rawIndex = tabs.indexWhere((t) => t.$1 == current);
        final bool isSecondary =
            rawIndex != -1; // only true if actually one of the secondary tabs
        final selIndex = rawIndex == -1
            ? 0
            : rawIndex; // safe fallback for geometry (not rendered when !isSecondary)
        final targetLeft = selIndex * slotWidth + (slotWidth - _barWidth) / 2;

        // For stretch: compute distance from previous frame using an implicit animation via TweenAnimationBuilder around bar.

        return Container(
          height: 70,
          decoration: const BoxDecoration(
            color: backgroundDark,
            border: Border(bottom: BorderSide(color: borderDark)),
          ),
          padding: const EdgeInsets.only(top: 6),
          child: Stack(
            children: [
              // Only show animated stretch bar when actually on a secondary tab
              if (visible && isSecondary)
                _AnimatedStretchBar(
                  left: targetLeft,
                  slotWidth: slotWidth,
                  baseWidth: _barWidth,
                  height: _barHeight,
                  duration: _duration,
                  curve: _curve,
                  color: newaccent,
                  fade: true,
                ),
              Row(
                children: [
                  for (final (section, label) in tabs)
                    Expanded(
                      child: InkWell(
                        onTap: () => onSelect(section),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: _duration,
                            curve: _curve,
                            style: TextStyle(
                              color: current == section
                                  ? navActive
                                  : navInactive,
                              fontWeight: current == section
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 15,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Internal animated underline that stretches based on travel distance between old and new positions.
class _AnimatedStretchBar extends StatefulWidget {
  const _AnimatedStretchBar({
    required this.left,
    required this.slotWidth,
    required this.baseWidth,
    required this.height,
    required this.duration,
    required this.curve,
    required this.color,
    required this.fade,
  });
  final double left;
  final double slotWidth;
  final double baseWidth;
  final double height;
  final Duration duration;
  final Curve curve;
  final Color color;
  final bool fade;

  @override
  State<_AnimatedStretchBar> createState() => _AnimatedStretchBarState();
}

class _AnimatedStretchBarState extends State<_AnimatedStretchBar>
    with SingleTickerProviderStateMixin {
  late double _prevLeft;
  late double _currentLeft;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _prevLeft = widget.left;
    _currentLeft = widget.left;
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedStretchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.left != _currentLeft) {
      _prevLeft = _currentLeft;
      _currentLeft = widget.left;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.curve.transform(_controller.value);
        // Interpolate left position
        final left = _prevLeft + (_currentLeft - _prevLeft) * t;
        final travel = (_currentLeft - _prevLeft).abs();
        // Stretch proportion (max 70% of travel), shrink back as t approaches 1.
        final stretchPhase = (1 - (t - 0.5).abs() * 2).clamp(
          0.0,
          1.0,
        ); // peaks at t=0.5
        final extra = travel * 0.8 * stretchPhase;
        final width = widget.baseWidth + extra;
        final centerAdjustedLeft =
            left -
            (width - widget.baseWidth) /
                2; // keep visual center around travel path
        final opacity = widget.fade ? 1.0 : 0.0;
        return Positioned(
          left: centerAdjustedLeft,
          bottom: 0,
          width: width,
          height: widget.height,
          child: Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }
}
