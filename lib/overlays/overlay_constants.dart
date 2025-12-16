/// Centralized slide-in overlay constants (chat, notifications, team, etc.).
class OverlayConstants {
  OverlayConstants._();

  // Fractional edge zones (responsive gesture areas)
  static const double openEdgeFraction = 1;
  static const double closeEdgeFraction = 1;

  // Animation controller decision thresholds
  static const double openCommitValue =
      0.85; // controller.value < commit => open
  static const double closeCommitValue =
      0.25; // controller.value > commit => close

  // Durations (ms)
  static const int openDurationMs = 260;
  static const int closeDurationMs = 200;

  // Scrim
  static const double scrimMaxOpacity =
      0.35; // linear scaling (1 - controller.value)
}
