import 'package:flutter/material.dart';
import 'overlay_constants.dart';

enum OverlayType { chat, notifications, team, projects }

/// Controller encapsulating state + animation for slide-in overlays.
class OverlayController {
  OverlayController({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: Duration(milliseconds: OverlayConstants.openDurationMs),
        value: 1.0, // hidden
      );

  final AnimationController _controller;
  OverlayType? _active;

  Animation<double> get animation => _controller;
  OverlayType? get active => _active;
  bool get isOpen => _active != null && _controller.value < 1.0;
  bool get fullyOpen => _active != null && _controller.value == 0.0;

  void dispose() => _controller.dispose();

  void open(OverlayType type) {
    if (_active == type && fullyOpen) return;
    _controller.stop();
    if (_active == null) {
      _controller.value = 1.0; // start hidden
    }
    _active = type;
    _animateTo(0);
  }

  void close() => _animateTo(1.0);

  void _animateTo(double target) {
    final durationMs = target == 0
        ? OverlayConstants.openDurationMs
        : OverlayConstants.closeDurationMs;
    _controller
        .animateTo(
          target,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (target == 1.0) _active = null;
        });
  }

  // Drag helpers (open from right edge, close from left edge).
  void updateDragOpen(double progressReversed) {
    // progressReversed = 1 -> hidden, 0 -> open; clamp externally
    _controller.value = progressReversed;
  }

  void updateDragClose(double progress) {
    // progress = 0 open, 1 hidden
    _controller.value = progress;
  }

  bool shouldCommitOpen() =>
      _controller.value < OverlayConstants.openCommitValue;
  bool shouldCommitClose() =>
      _controller.value > OverlayConstants.closeCommitValue;

  // --- New explicit interactive helpers (for cleaner gesture code) ---
  void beginInteractiveOpen(OverlayType type) {
    if (_active != type) {
      _active = type;
      _controller.value = 1.0; // start hidden state for that overlay
    }
    _controller.stop();
  }

  void interactiveSetProgress(double progressReversed) {
    // progressReversed: 1 hidden -> 0 open
    if (progressReversed < 0) progressReversed = 0;
    if (progressReversed > 1) progressReversed = 1;
    _controller.value = progressReversed;
  }

  void commitOrRevertOpen() {
    if (shouldCommitOpen()) {
      _animateTo(0);
    } else {
      _animateTo(1.0);
    }
  }

  void commitOrRevertClose() {
    if (shouldCommitClose()) {
      _animateTo(1.0);
    } else {
      _animateTo(0);
    }
  }
}
