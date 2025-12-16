import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

// Simple global overlay notice helper used across the app for short messages.
// Keeps a single notice active at a time to avoid stacking and avoids
// using Scaffold SnackBar (prevents Hero collisions during rapid navigation).
OverlayEntry? _currentNoticeEntry;
Timer? _currentNoticeTimer;

// Simple queue for notices that should be shown on the next page/frame
String? _pendingMessage;
Duration _pendingDuration = const Duration(milliseconds: 1100);
bool _pendingLiftAboveNav = true;

void queueOverlayNotice(String message,
    {Duration duration = const Duration(milliseconds: 1100),
    bool liftAboveNav = true}) {
  _pendingMessage = message;
  _pendingDuration = duration;
  _pendingLiftAboveNav = liftAboveNav;
}

void showQueuedOverlayNotice(BuildContext context) {
  final msg = _pendingMessage;
  if (msg == null) return;
  _pendingMessage = null;
  showOverlayNotice(context, msg,
      duration: _pendingDuration, liftAboveNav: _pendingLiftAboveNav);
}

void showOverlayNotice(BuildContext context, String message,
  {Duration duration = const Duration(milliseconds: 1100),
  // When true the notice is lifted above the bottom navigation bar.
  // When false the notice sits flush to the window insets / panel so it
  // matches in-panel placement (used by chat/forms sliding panels).
  bool liftAboveNav = true}) {
  // Remove any existing notice first.
  try {
    _currentNoticeTimer?.cancel();
  } catch (_) {}
  try {
    _currentNoticeEntry?.remove();
  } catch (_) {}
  _currentNoticeTimer = null;
  _currentNoticeEntry = null;

  final overlay = Overlay.of(context);

  _currentNoticeEntry = OverlayEntry(builder: (ctx) {
    final mq = MediaQuery.of(ctx);
    // Optionally lift the notice above the bottom navigation bar so it
    // doesn't overlap the global bottom nav. When the notice is shown
    // inside a sliding panel we pass `liftAboveNav: false` so it sits
    // inside the panel (matching chat placement).
    final double lift = liftAboveNav ? kBottomNavigationBarHeight : 0.0;
    final bottom = mq.viewPadding.bottom + mq.viewInsets.bottom + lift;
    return Positioned(
      right: 16,
      left: 16,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 160),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: ShapeDecoration(
                color: surfaceDark,
                shape: const StadiumBorder(),
                shadows: [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  });

  overlay.insert(_currentNoticeEntry!);
  _currentNoticeTimer = Timer(duration, () {
    try {
      _currentNoticeEntry?.remove();
    } catch (_) {}
    _currentNoticeEntry = null;
    _currentNoticeTimer = null;
  });
}
