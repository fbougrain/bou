import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/money.dart';
import '../data/mappers.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/expense.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../utils/schedule_status.dart';
import '../widgets/budget_donut.dart';
import '../widgets/quick_stat_tile.dart';
import '../data/billing_repository.dart';
import '../data/task_repository.dart';
import '../data/forms_repository.dart';
import '../models/form_models.dart';
import '../data/stock_repository.dart';
import '../models/stock_item.dart';
// stock models used indirectly via StockRepository and stock_row_tile
// stock row widget intentionally not used in snapshot aggregation
import '../panels/panel_scaffold.dart';
import 'stock_page.dart';
import 'forms_page.dart';

class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.project});
  final Project project;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}
 

class _ProjectPageState extends State<ProjectPage>
    with TickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _timeTween;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  Project get p => widget.project; // shorthand — use the provided project (no sample fallback)

  // Use whole-day (midnight) normalization for schedule/time calculations
  DateTime get _today => DateTime.now();
  DateTime get _todayDateOnly =>
      DateTime(_today.year, _today.month, _today.day);
  DateTime get _startDateOnly =>
      DateTime(p.startDate.year, p.startDate.month, p.startDate.day);
  DateTime get _endDateOnly =>
      DateTime(p.endDate.year, p.endDate.month, p.endDate.day);
  int get _totalDurationDays =>
      _endDateOnly.difference(_startDateOnly).inDays.clamp(1, 100000);
  int get _elapsedDays => _todayDateOnly.isBefore(_startDateOnly)
      ? 0
      : _todayDateOnly.isAfter(_endDateOnly)
      ? _totalDurationDays
      : _todayDateOnly.difference(_startDateOnly).inDays;
  int get _remainingDays =>
      (_totalDurationDays - _elapsedDays).clamp(0, _totalDurationDays);
  double get _timeElapsedRatio => _elapsedDays / _totalDurationDays;

  // schedule color logic now handled inline in hero variance pill

  String _statusLabel(ProjectStatus s) {
    switch (s) {
      case ProjectStatus.completed:
        return 'Completed';
      case ProjectStatus.active:
        return 'Active';
    }
  }

 

  Color _statusColor(ProjectStatus s) {
    switch (s) {
      case ProjectStatus.completed:
        return Colors.greenAccent.shade700;
      case ProjectStatus.active:
        return Colors.greenAccent;
    }
  }

  @override
  void initState() {
  super.initState();
  _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _timeTween = Tween<double>(begin: 0, end: _timeElapsedRatio).animate(curve);
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    // Stagger start slightly after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anim.forward();
      _fadeCtrl.forward();
    });
  }

  double _taskProgressRatio(List<TaskModel> tasks) {
    if (tasks.isEmpty) return 0.0;
    final completed = tasks.where((t) => t.status == TaskStatus.completed).length;
    return (completed / tasks.length).clamp(0.0, 1.0);
  }

  int _allTasks(List<TaskModel> tasks) => tasks.length;
  int _completedTasks(List<TaskModel> tasks) =>
      tasks.where((t) => t.status == TaskStatus.completed).length;

  @override
  void dispose() {
    _anim.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Widget _buildProjectContent(
    List<TaskModel> tasks,
    List<Expense> expenses,
    List<FormSubmission> forms,
    List<StockItem> stock,
  ) {
    final dateFmt = DateFormat('d MMM', 'en_US');
    final currency = Money.formatter;
    final total = p.budgetTotal ?? 0;
    final spent = expenses.fold<double>(0, (a, e) => a + e.total);
    final progressRatio = _taskProgressRatio(tasks);
    final scheduleVariancePct = ((progressRatio - _timeElapsedRatio) * 100).toStringAsFixed(1);
    final usedRatio = total <= 0 ? 0.0 : (spent / total).clamp(0.0, 1.0);
    
    // Create new tweens with current data values for smooth animation
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    final progressTween = Tween<double>(begin: 0, end: progressRatio).animate(curve);
    final budgetTween = Tween<double>(begin: 0, end: usedRatio).animate(curve);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 120),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heroHeader(
              tasks: tasks,
              progress: progressTween.value,
              time: _timeTween.value,
              variancePct: scheduleVariancePct,
            ),
            const SizedBox(height: 18),
            _sectionLabel('KEY METRICS'),
            const SizedBox(height: 12),
            _ProjectKeyMetrics(projectId: p.id, tasks: tasks, forms: forms),
            const SizedBox(height: 30),
            _sectionLabel('BUDGET'),
            const SizedBox(height: 12),
            BudgetDonut(
              spent: spent,
              total: total,
              ratio: budgetTween.value,
              currency: currency,
            ),
            const SizedBox(height: 34),
            _formsSnapshotSection(forms),
            const SizedBox(height: 18),
            _stockSnapshotSection(stock),
            const SizedBox(height: 18),
            _sectionLabel('TIMELINE'),
            const SizedBox(height: 14),
            _LeanTimeline(
              startLabel: dateFmt.format(p.startDate),
              endLabel: dateFmt.format(p.endDate),
              todayLabel: dateFmt.format(_today),
              timeElapsed: _timeTween.value,
              progress: progressTween.value,
            ),
            if (p.description != null) ...[
              const SizedBox(height: 38),
              _sectionLabel('DESCRIPTION'),
              const SizedBox(height: 10),
              Text(
                p.description!,
                style: TextStyle(
                  color: neutralText.withValues(alpha: 0.78),
                  fontSize: 13.5,
                  height: 1.32,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .doc(p.id)
            .collection('tasks')
            .orderBy('createdAt', descending: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, taskSnap) {
          final tasks = taskSnap.hasData
              ? taskSnap.data!.docs
                  .map((d) => TaskFirestore.fromMap(d.id, d.data()))
                  .toList()
              : TaskRepository.instance.tasksFor(p.id);
          
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('projects')
                .doc(p.id)
                .collection('expenses')
                .orderBy('paidDate', descending: true)
                .snapshots(includeMetadataChanges: true),
            builder: (context, expenseSnap) {
              final expenses = expenseSnap.hasData
                  ? expenseSnap.data!.docs
                      .map((d) => ExpenseFirestore.fromMap(d.id, d.data()))
                      .toList()
                  : BillingRepository.instance.expensesFor(p.id);
              
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('projects')
                    .doc(p.id)
                    .collection('forms')
                    .orderBy('createdAt', descending: true)
                    .snapshots(includeMetadataChanges: true),
                builder: (context, formSnap) {
                  final forms = formSnap.hasData
                      ? formSnap.data!.docs
                          .map((d) => FormSubmissionFirestore.fromMap(d.id, d.data()))
                          .toList()
                      : FormsRepository.instance.submissionsFor(p.id);
                  
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('projects')
                        .doc(p.id)
                        .collection('stock')
                        .orderBy('updatedAt', descending: true)
                        .snapshots(includeMetadataChanges: true),
                    builder: (context, stockSnap) {
                      final stock = stockSnap.hasData
                          ? stockSnap.data!.docs
                              .map((d) => StockFirestore.fromMap(d.id, d.data()))
                              .toList()
                          : StockRepository.instance.itemsFor(p.id);
                      
                      return _buildProjectContent(tasks, expenses, forms, stock);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // legacy header & section title removed after redesign
  // Stock snapshot section: shows a compact list of stock items for this project.
  Widget _stockSnapshotSection(List<StockItem> items) {
    // Aggregate counts by status and show three compact stat tiles (zero when empty)
    final okCount = items.where((it) => it.status == StockStatus.ok).length;
    final lowCount = items.where((it) => it.status == StockStatus.low).length;
    final depletedCount = items.where((it) => it.status == StockStatus.depleted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _sectionLabel('STOCKS SNAPSHOT'),
        const SizedBox(height: 12),
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: QuickStatTile(
                    label: StockStatus.ok.label,
                    value: okCount.toString(),
                    color: Colors.white,
                    dotColor: StockStatus.ok.chipColor(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickStatTile(
                    label: StockStatus.low.label,
                    value: lowCount.toString(),
                    color: Colors.white,
                    dotColor: StockStatus.low.chipColor(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickStatTile(
                    label: StockStatus.depleted.label,
                    value: depletedCount.toString(),
                    color: Colors.white,
                    dotColor: StockStatus.depleted.chipColor(),
                  ),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        transitionDuration: const Duration(milliseconds: 520),
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (ctx, animation, secondaryAnimation) {
                          return _SlidingPanel(
                            title: 'Inventory',
                            fab: Transform.translate(
                              offset: const Offset(-5, 5),
                              child: ElevatedButton(
                                onPressed: () async {
                                  final created = await showAddStockSheet(context);
                                  if (created != null) {
                                    StockRepository.instance.addItem(p.id, created, insertOnTop: true);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF191B1B),
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
                                  elevation: 6,
                                  shadowColor: newaccent.withValues(alpha: 0.10),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(56, 56),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Icon(AppIcons.add, color: Colors.white, size: 24),
                              ),
                            ),
                            child: StockPage(project: p),
                          );
                        },
                        transitionsBuilder: (ctx, animation, secondary, child) {
                          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: surfaceDark,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: borderDark, width: 1),
                    ),
                    child: Text(
                      'View all inventory',
                      style: TextStyle(
                        color: neutralText.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _formsSnapshotSection(List<FormSubmission> subs) {
    final count = subs.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _sectionLabel('FORMS SNAPSHOT'),
        const SizedBox(height: 12),
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: QuickStatTile(
                    label: 'Submissions',
                    value: count.toString(),
                    color: Colors.white,
                    dotColor: accentTech,
                  ),
                ),
              ],
            ),
            if (count > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        transitionDuration: const Duration(milliseconds: 520),
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (ctx, animation, secondaryAnimation) {
                          return _SlidingPanel(title: 'Forms', child: FormsPage(project: p, insidePanel: true));
                        },
                        transitionsBuilder: (ctx, animation, secondary, child) {
                          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: surfaceDark,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: borderDark, width: 1),
                    ),
                    child: Text(
                      'View all submissions',
                      style: TextStyle(
                        color: neutralText.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ProjectKeyMetrics extends StatelessWidget {
  final String projectId;
  final List<TaskModel> tasks;
  final List<FormSubmission> forms;
  
  const _ProjectKeyMetrics({
    required this.projectId,
    required this.tasks,
    required this.forms,
  });

  int _allTasks(List<TaskModel> tasks) => tasks.length;
  int _completedTasks(List<TaskModel> tasks) => tasks.where((t) => t.status == TaskStatus.completed).length;
  int _inProgressTasks(List<TaskModel> tasks) => tasks.where((t) => t.status == TaskStatus.pending).length;
  int _lateCount(List<TaskModel> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return tasks.where((t) {
      if (t.status == TaskStatus.completed) return false;
      final due = t.dueDate;
      return DateTime(due.year, due.month, due.day).isBefore(today);
    }).length;
  }
  int _incidentCount(List<FormSubmission> forms) {
    return forms.where((f) => f.kind == FormKind.incident).length;
  }

  @override
  Widget build(BuildContext context) {
    final total = _allTasks(tasks);
    final done = _completedTasks(tasks);
    final pending = _inProgressTasks(tasks);
    final overall = total == 0 ? 0 : ((done / total) * 100).round();
    final late = _lateCount(tasks);
    final incidents = _incidentCount(forms);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId)
          .collection('team')
          .snapshots(includeMetadataChanges: true),
      builder: (context, teamSnap) {
        String onlineValue;
        if (teamSnap.hasData) {
          final teamDocs = teamSnap.data!.docs;
          final online = teamDocs.where((d) => (d.data()['isOnline'] as bool?) ?? false).length;
          final teamTotal = teamDocs.length;
          onlineValue = teamTotal == 0 ? '$online' : '$online/$teamTotal';
        } else {
          // Fallback while loading
          onlineValue = '0';
        }

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
              value: pending.toString(),
              color: Colors.white,
              dotColor: accentConstruction,
            ),
            QuickStatTile(
              label: 'Done',
              value: done.toString(),
              color: Colors.white,
              dotColor: Colors.greenAccent.shade700,
            ),
            QuickStatTile(
              label: 'Late',
              value: late.toString(),
              color: Colors.white,
              dotColor: Colors.redAccent.shade700,
            ),
            QuickStatTile(
              label: 'Incidents',
              value: incidents.toString(),
              color: Colors.white,
              dotColor: incidents == 0
                  ? Colors.greenAccent
                  : Colors.redAccent.shade700,
            ),
            QuickStatTile(
              label: 'Online',
              value: onlineValue,
              color: Colors.white,
              dotColor: Colors.greenAccent.shade400,
            ),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );
}

// --- New Aesthetic Components ---



// removed internal ring and donut widgets (now imported from lib/widgets)

class _LeanTimeline extends StatelessWidget {
  final String startLabel;
  final String endLabel;
  final String todayLabel;
  final double timeElapsed;
  final double progress;
  const _LeanTimeline({
    required this.startLabel,
    required this.endLabel,
    required this.todayLabel,
    required this.timeElapsed,
    required this.progress,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderDark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                startLabel,
                style: TextStyle(
                  color: neutralText.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
              Text(
                endLabel,
                style: TextStyle(
                  color: neutralText.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48, // increased to prevent date label clipping
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final timeW = (timeElapsed.clamp(0, 1)) * w;
                final progW = (progress.clamp(0, 1)) * w;
                // Ensure the date label stays within horizontal bounds (approx width 46-52)
                final labelLeft = (timeW - 4).clamp(0, w - 56);
                return Stack(
                  children: [
                    // Base bar background
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C2530),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    // Time elapsed overlay
                    Positioned(
                      left: 0,
                      child: Container(
                        width: timeW,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.shade400,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    // Physical progress overlay
                    Positioned(
                      left: 0,
                      child: Container(
                        width: progW,
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentTech,
                              accentTech.withValues(alpha: 0.40),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    // Today marker + label
                    Positioned(
                      left: labelLeft.toDouble(),
                      top: 5,
                      child: Column(
                        children: [
                          Container(
                            width: 2,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            todayLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _LegendDot(color: accentTech, label: 'Progress'),
              const SizedBox(width: 18),
              _LegendDot(
                color: Colors.greenAccent.shade400,
                label: 'Time',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Hero Header & Helpers ---

extension on _ProjectPageState {

  Widget _heroHeader({
    required List<TaskModel> tasks,
    required double progress,
    required double time,
    required String variancePct,
  }) {
    // Task-based drift: expected completed tasks by now vs actual completed
    final sched = computeScheduleByTasks(
      totalTasks: _allTasks(tasks),
      completedTasks: _completedTasks(tasks),
      timeElapsedRatio: _timeElapsedRatio,
    );
    String varianceLabel = 'On Track';
    Color varianceColor = accentTech;
    switch (sched.trend) {
      case ScheduleTrend.ahead:
        varianceLabel = 'Ahead';
        varianceColor = Colors.greenAccent.shade400;
        break;
      case ScheduleTrend.behind:
        varianceLabel = 'Behind';
        varianceColor = Colors.redAccent.shade400;
        break;
      case ScheduleTrend.onTrack:
        varianceLabel = 'On Track';
        varianceColor = accentTech;
        break;
    }
    // Deterministic two-line split by words (if 2+ words)
    final words = p.name.split(RegExp(r"\s+"));
    String firstLine = p.name;
    String secondLine = '';
    if (words.length >= 2) {
      final split = (words.length / 2).ceil();
      firstLine = words.sublist(0, split).join(' ');
      secondLine = words.sublist(split).join(' ');
    }
  // layout is fixed; we no longer swap based on isBehind

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title: exactly two lines when name has 2+ words
              Text(firstLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.05)),
              if (secondLine.isNotEmpty) ...[
                const SizedBox(height: 10), // larger gap before second line
                Text(secondLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.05)),
              ],
              // increased gap between title block and location per request
              const SizedBox(height: 16),
              Row(children: [
                if (p.location != null) ...[
                  Icon(AppIcons.location, size: 15, color: neutralText.withValues(alpha: 0.55)),
                  const SizedBox(width: 4),
                  Text(p.location!, style: TextStyle(color: neutralText.withValues(alpha: 0.7), fontSize: 12.5, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),
                ],
                  // variance pill next to location (as requested in screenshot)
                  _pill(text: varianceLabel, color: varianceColor.withValues(alpha: 0.18), border: varianceColor.withValues(alpha: 0.4), textColor: varianceColor),
              ]),
            ],
          ),
        ),

        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(label: _statusLabel(p.status), color: _statusColor(p.status)),
            const SizedBox(height: 8),
            // days left (always)
            _pill(text: '${_remainingDays}d left'),
          ],
        ),
      ],
    );
  }

  Widget _pill({
    required String text,
    Color? color,
    Color? border,
    Color? textColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color ?? surfaceDark,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border ?? borderDark, width: 1),
    ),
    child: Text(
      text,
          style: TextStyle(
            color: textColor ?? neutralText.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
    ),
  );


 

  






  // section label helper
  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: TextStyle(
        color: neutralText.withValues(alpha: 0.72),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );
}

// small legend dot used by timeline (top-level helper)
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  // ignore: use_super_parameters
  const _LegendDot({Key? key, required this.color, required this.label}) : super(key: key);
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: neutralText.withValues(alpha: 0.65),
              fontSize: 11.5,
            ),
          ),
        ],
      );
}

// Generic sliding panel wrapper used for panels that should be dismissible
// by horizontal swipe (matches Chat/Composer behavior). This mirrors the
// pattern used elsewhere so the user can slide the panel off-screen to close it.
class _SlidingPanel extends StatefulWidget {
  const _SlidingPanel({required this.title, required this.child, this.fab});
  final String title;
  final Widget child;
  final Widget? fab; // optional FAB to render in the panel scaffold

  @override
  State<_SlidingPanel> createState() => _SlidingPanelState();
}

class _SlidingPanelState extends State<_SlidingPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragX = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, double width, {bool thenPop = false}) {
    final start = _dragX;
    final distance = (target - start).abs();
    final duration = Duration(milliseconds: (240 * (distance / width)).clamp(120, 240).toInt());
    _controller.duration = duration;
    _controller.reset();
    final tween = Tween<double>(begin: start, end: target).chain(CurveTween(curve: Curves.easeOutCubic));
    final anim = tween.animate(_controller);
    _controller.addListener(() => setState(() => _dragX = anim.value));
    _controller.forward().whenComplete(() async {
      if (thenPop && mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _dragging = true;
            _controller.stop();
          },
          onHorizontalDragUpdate: (details) {
            if (!_dragging) return;
            setState(() {
              _dragX = (_dragX + details.delta.dx).clamp(0.0, width);
            });
          },
          onHorizontalDragEnd: (details) {
            if (!_dragging) return;
            _dragging = false;
            final vx = details.primaryVelocity ?? 0;
            final progress = _dragX / width;
            final shouldPop = progress > 0.33 || vx > 800;
            if (shouldPop) {
              _animateTo(width, width, thenPop: true);
            } else {
              _animateTo(0, width);
            }
          },
          child: Stack(
            children: [
              // Scrim fades in as you drag
              IgnorePointer(
                child: Opacity(
                  opacity: (_dragX / width).clamp(0.0, 1.0) * 0.25,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              Transform.translate(
                offset: Offset(_dragX, 0),
                child: PanelScaffold(
                  title: widget.title,
                  onClose: () {
                    _controller.stop();
                    _animateTo(width, width, thenPop: true);
                  },
                  side: PanelSide.right,
                  fab: widget.fab,
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
