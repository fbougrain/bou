/// Trend classification for project schedule vs. time.
enum ScheduleTrend { ahead, onTrack, behind }

/// Result of schedule evaluation using days-based drift.
class ScheduleResult {
  final ScheduleTrend trend;
  final int driftDays; // positive=ahead, negative=behind
  const ScheduleResult({required this.trend, required this.driftDays});
}

/// Compute schedule status using days-based drift with a deadband (buffer) in days.
/// - progressRatio: 0..1 physical progress
/// - startDate/endDate: planned schedule
/// - today: defaults to DateTime.now()
/// - bufferDays: tolerance around 0 (default 2 days)
ScheduleResult computeScheduleByDays({
  required double progressRatio,
  required DateTime startDate,
  required DateTime endDate,
  DateTime? today,
  int bufferDays = 2,
}) {
  // Normalize to date-only (midnight) to compute using whole days
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  final s = dateOnly(startDate);
  final e = dateOnly(endDate);
  final now = dateOnly(today ?? DateTime.now());

  final totalDays = e.difference(s).inDays.clamp(1, 100000);
  final elapsedDays = now.isBefore(s)
      ? 0
      : now.isAfter(e)
      ? totalDays
      : now.difference(s).inDays;
  final timeElapsedRatio = elapsedDays / totalDays;
  final driftDays = ((progressRatio - timeElapsedRatio) * totalDays).round();
  if (driftDays >= bufferDays) {
    return ScheduleResult(trend: ScheduleTrend.ahead, driftDays: driftDays);
  } else if (driftDays <= -bufferDays) {
    return ScheduleResult(trend: ScheduleTrend.behind, driftDays: driftDays);
  } else {
    return ScheduleResult(trend: ScheduleTrend.onTrack, driftDays: driftDays);
  }
}

/// Compute schedule classification using task counts instead of days.
///
/// Logic: expectedCompleted = round(timeElapsedRatio * totalTasks)
/// delta = completedTasks - expectedCompleted
/// - if delta >= bufferTasks => ahead
/// - if delta <= -bufferTasks => behind
/// - otherwise => onTrack
ScheduleResult computeScheduleByTasks({
  required int totalTasks,
  required int completedTasks,
  required double timeElapsedRatio,
  int bufferTasks = 2,
}) {
  // Guard against zero/invalid totals
  if (totalTasks <= 0) return const ScheduleResult(trend: ScheduleTrend.onTrack, driftDays: 0);

  final expected = (timeElapsedRatio * totalTasks).round();
  final delta = completedTasks - expected; // positive => ahead in tasks

  if (delta >= bufferTasks) {
    return ScheduleResult(trend: ScheduleTrend.ahead, driftDays: delta);
  } else if (delta <= -bufferTasks) {
    return ScheduleResult(trend: ScheduleTrend.behind, driftDays: delta);
  } else {
    return ScheduleResult(trend: ScheduleTrend.onTrack, driftDays: delta);
  }
}
