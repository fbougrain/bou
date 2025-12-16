import 'package:flutter/material.dart';
import '../../overlays/overlay_constants.dart';

/// Generic animated scrim for slide-in overlays.
class AnimatedScrim extends StatelessWidget {
  const AnimatedScrim({
    super.key,
    required this.controller,
    required this.chatOpen,
    required this.onTap,
  });
  final Animation<double> controller;
  final bool chatOpen; // true when any overlay is logically open
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Render scrim only while overlay is animating in or visible.
    if (!chatOpen && controller.value >= 1.0) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final opacity =
            (1 - controller.value) * OverlayConstants.scrimMaxOpacity;
        if (opacity <= 0) return const SizedBox.shrink();
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(color: Colors.black.withValues(alpha: opacity)),
          ),
        );
      },
    );
  }
}
