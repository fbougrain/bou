import 'package:flutter/material.dart';
import 'dart:async';
import '../data/sample_data.dart';
import '../models/project.dart';
import '../models/task.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../widgets/quick_stat_tile.dart';
import '../theme/app_icons.dart';
import '../widgets/highlighted_message.dart';
import '../widgets/overlay_notice.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.project});
  final Project? project;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fadeCtrl.forward());
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project ?? sampleProject;
    return FadeTransition(
      opacity: _fade,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            const Text(
              'Dashboard',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const _AiAssistantCard(),
            const SizedBox(height: 27),
            _ProgressSummaryRow(project: project),
            const SizedBox(height: 18),
            _QuickStatsGrid(project: project),
          ],
        ),
      ),
    );
  }
}

class _AiAssistantCard extends StatefulWidget {
  const _AiAssistantCard();
  @override
  State<_AiAssistantCard> createState() => _AiAssistantCardState();
}

class _AiSuggestion {
  final String id;
  final String category; // Weather / Schedule / Risk / Safety
  final String message;
  final List<String> highlights; // words/phrases to accentuate
  final Color accent;
  final List<String> actions; // suggested quick actions (placeholder)
  final double confidence; // retained internally though not shown now
  const _AiSuggestion({
    required this.id,
    required this.category,
    required this.message,
    required this.highlights,
    required this.accent,
    required this.actions,
    required this.confidence,
  });
}

class _AiAssistantCardState extends State<_AiAssistantCard> {
  late List<_AiSuggestion> _suggestions;
  int _index = 0;
  Timer? _autoTimer;
  double? _maxMessageHeight; // cache of the tallest message area
  double? _lastWidth; // width used for the cached height
  static const TextStyle _messageTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 14.5,
  );

  @override
  void initState() {
    super.initState();
    _buildSuggestions();
    _index = DateTime.now().minute % _suggestions.length;
    _startAutoCycle();
  }

  void _buildSuggestions() {
    _suggestions = [
      _AiSuggestion(
        id: 'weather_rain',
        category: 'Weather',
        message:
            'Rain expected mid next week. Finish interior wall paint early to ensure proper drying and avoid blistering.',
        highlights: ['Rain', 'paint', 'drying'],
        accent: accentConstruction,
        actions: ['Schedule', 'Remind'],
        confidence: 0.82,
      ),
      _AiSuggestion(
        id: 'risk_progress',
        category: 'Progress',
        message:
            'Current phase is 65% complete. Shift 1 crew from completed foundations to load-bearing walls to stay ahead.',
        highlights: ['65% complete', 'Shift 1 crew'],
        accent: accentTech,
        actions: ['Reassign', 'Details'],
        confidence: 0.76,
      ),
      _AiSuggestion(
        id: 'safety_zero',
        category: 'Safety',
        message:
            'Zero incidents this week. Consider a 5‑minute refresher tomorrow morning to maintain safety momentum.',
        highlights: ['Zero incidents', 'refresher'],
        accent: Colors.greenAccent.shade400,
        actions: ['Plan', 'Share'],
        confidence: 0.69,
      ),
      _AiSuggestion(
        id: 'logistics_cover',
        category: 'Logistics',
        message:
            'Ground humidity rising. Cover cement bags and rebar stacks tonight to prevent moisture absorption.',
        highlights: ['humidity', 'Cover cement'],
        accent: Colors.purpleAccent.shade200,
        actions: ['Checklist', 'Remind'],
        confidence: 0.74,
      ),
    ];
  }

  void _next() {
    setState(() {
      _index = (_index + 1) % _suggestions.length;
    });
    _restartAutoCycle();
  }

  void _startAutoCycle() {
    _autoTimer ??= Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      _next();
    });
  }

  void _restartAutoCycle() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _startAutoCycle();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _suggestions[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute content width inside the card (excluding card's horizontal padding)
        final contentWidth = constraints.maxWidth - (18 + 16);
        if (_lastWidth != contentWidth || _maxMessageHeight == null) {
          _maxMessageHeight = _computeMaxMessageHeight(contentWidth);
          _lastWidth = contentWidth;
        }
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: s.accent.withValues(alpha: 0.5),
              width: 1.2,
            ),
            gradient: LinearGradient(
              colors: [surfaceDark, const Color(0xFF1C2530)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: s.accent.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: s.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: s.accent.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Text(
                  s.category.toUpperCase(),
                  style: TextStyle(
                    color: s.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: _maxMessageHeight ?? 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: HighlightedMessage(
                    key: ValueKey(s.id),
                    text: s.message,
                    highlights: s.highlights,
                    accent: s.accent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final a in s.actions.take(2))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AiActionChip(
                        label: a,
                        accent: s.accent,
                        onTap: () {
                          // Use an overlay notice so the notification doesn't
                          // create a Hero (SnackBar) that can collide with
                          // quick navigation.
                          ScaffoldMessenger.of(context).clearSnackBars();
                          showOverlayNotice(context, '$a action (coming soon)');
                        },
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Next insight',
                    visualDensity: VisualDensity.compact,
                    onPressed: _next,
                    icon: Icon(AppIcons.refresh, color: s.accent, size: 20),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  double _computeMaxMessageHeight(double maxWidth) {
    double maxH = 0;
    final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: null);
    for (final sug in _suggestions) {
      tp.text = TextSpan(text: sug.message, style: _messageTextStyle);
      tp.layout(maxWidth: maxWidth);
      if (tp.size.height > maxH) maxH = tp.size.height;
    }
    // Add a tiny safety padding to account for highlight styling nuances.
    return maxH + 2;
  }
}

// moved HighlightedMessage & AiActionChip to lib/widgets/highlighted_message.dart

class _ProgressSummaryRow extends StatelessWidget {
  final Project project;
  const _ProgressSummaryRow({required this.project});

  @override
  Widget build(BuildContext context) {
    final tasksStream = FirebaseFirestore.instance
        .collection('projects')
        .doc(project.id)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tasksStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _DashboardLoading();
        }
        final docs = snapshot.data!.docs;
        final total = docs.length;
        int pendingCount = 0;
        int completedCount = 0;
        for (final doc in docs) {
          final status = _parseTaskStatus(doc.data()['status'] as String?);
          if (status == TaskStatus.completed) {
            completedCount++;
          } else {
            pendingCount++;
          }
        }
        final overall = total == 0
            ? project.progressPercent
            : ((completedCount / total) * 100).round();

        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: QuickStatTile.aspectRatio,
          ),
          children: [
            QuickStatTile(
              label: 'Overall Progress',
              value: '$overall%',
              color: Colors.white,
              dotColor: accentTech,
            ),
            QuickStatTile(
              label: 'Pending Tasks',
              value: '$pendingCount',
              color: Colors.white,
              dotColor: accentConstruction,
            ),
            QuickStatTile(
              label: 'Done',
              value: '$completedCount',
              color: Colors.white,
              dotColor: Colors.greenAccent.shade700,
            ),
          ],
        );
      },
    );
  }
}

// _MetricBox removed; _ProgressSummaryRow uses _QuickStatTile for full parity

class _QuickStatsGrid extends StatelessWidget {
  final Project project;
  const _QuickStatsGrid({required this.project});

  Stream<QuerySnapshot<Map<String, dynamic>>> _collection(String name) {
    return FirebaseFirestore.instance
        .collection('projects')
        .doc(project.id)
        .collection(name)
        .snapshots(includeMetadataChanges: true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _collection('tasks'),
      builder: (context, taskSnap) {
        if (!taskSnap.hasData) {
          return const _DashboardLoading();
        }
        final tasksDocs = taskSnap.data!.docs;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _collection('forms'),
          builder: (context, formSnap) {
            if (!formSnap.hasData) {
              return const _DashboardLoading();
            }
            final formDocs = formSnap.data!.docs;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _collection('team'),
              builder: (context, teamSnap) {
                if (!teamSnap.hasData) {
                  return const _DashboardLoading();
                }
                final teamDocs = teamSnap.data!.docs;
                final late = _lateCountFromDocs(tasksDocs);
                final incidents = _incidentCountFromForms(formDocs);
                final online = teamDocs.where((d) => (d.data()['isOnline'] as bool?) ?? false).length;
                final total = teamDocs.length;

                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: QuickStatTile.aspectRatio,
                  ),
                  children: [
                    QuickStatTile(
                      label: 'Late',
                      value: '$late',
                      color: Colors.white,
                      dotColor: Colors.redAccent.shade700,
                    ),
                    QuickStatTile(
                      label: 'Incidents',
                      value: '$incidents',
                      color: Colors.white,
                      dotColor: incidents == 0 ? Colors.greenAccent : Colors.redAccent.shade700,
                    ),
                    QuickStatTile(
                      label: 'Online',
                      value: total == 0 ? '$online' : '$online/$total',
                      color: Colors.white,
                      dotColor: Colors.greenAccent.shade400,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// Online display is now computed live inside _QuickStatsGrid.

TaskStatus _parseTaskStatus(String? raw) {
  switch (raw) {
    case 'completed':
      return TaskStatus.completed;
    case 'pending':
    default:
      return TaskStatus.pending;
  }
}

int _lateCountFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  int count = 0;
  for (final doc in docs) {
    final data = doc.data();
    final status = _parseTaskStatus(data['status'] as String?);
    if (status == TaskStatus.completed) continue;
    final dueRaw = data['dueDate'];
    DateTime due;
    if (dueRaw is Timestamp) {
      due = dueRaw.toDate();
    } else if (dueRaw is String) {
      due = DateTime.tryParse(dueRaw) ?? today;
    } else {
      due = today;
    }
    if (DateTime(due.year, due.month, due.day).isBefore(today)) {
      count++;
    }
  }
  return count;
}

int _incidentCountFromForms(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  int count = 0;
  for (final doc in docs) {
    final kind = (doc.data()['kind'] as String?) ?? '';
    if (kind.toLowerCase() == 'incident') {
      count++;
    }
  }
  return count;
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
      ),
    );
  }
}

// Using shared QuickStatTile from widgets to avoid duplication.
