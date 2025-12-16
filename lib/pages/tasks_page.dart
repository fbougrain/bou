import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/sample_data.dart';
import '../data/initial_data.dart';
import '../models/task.dart';
import '../models/project.dart';
import '../models/team_member.dart';
import '../data/task_repository.dart';
import '../data/mappers.dart';
import '../data/team_repository.dart';
import '../data/profile_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../widgets/platform_date_picker.dart';
import '../widgets/team_multi_picker.dart';
import '../widgets/status_picker.dart';

enum _TaskTab { open, completed, all }

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.project});
  final Project? project;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage>
    with SingleTickerProviderStateMixin {
  _TaskTab _tab = _TaskTab.open;
  final TextEditingController _searchCtrl = TextEditingController();
  // Filters/Sort
  bool _showOnlyMine = false;
  String? _assigneeFilter; // null = any
  _SortKind _sort =
      _SortKind.repoOrder; // default: preserve repo order (newest first)

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

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

  List<TaskModel> _applyFilters(List<TaskModel> source) {
    Iterable<TaskModel> x = source;
    switch (_tab) {
      case _TaskTab.open:
        x = x.where((t) => t.status == TaskStatus.pending);
        break;
      case _TaskTab.completed:
        x = x.where((t) => t.status == TaskStatus.completed);
        break;
      case _TaskTab.all:
        break;
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      x = x.where(
        (t) =>
            t.name.toLowerCase().contains(q) ||
            t.assignee.toLowerCase().contains(q),
      );
    }
    if (_assigneeFilter != null && _assigneeFilter!.isNotEmpty) {
      x = x.where((t) => t.assignee == _assigneeFilter);
    }
    if (_showOnlyMine) {
      // Placeholder: use assigneeFilter with a fixed "me" value.
      x = x.where((t) => t.assignee == 'Omar Farhat');
    }
    final list = x.toList();
    if (_sort != _SortKind.repoOrder) {
      list.sort((a, b) {
        switch (_sort) {
          case _SortKind.dueAsc:
            return a.dueDate.compareTo(b.dueDate);
          case _SortKind.dueDesc:
            return b.dueDate.compareTo(a.dueDate);
          case _SortKind.assigneeAsc:
            return a.assignee.compareTo(b.assignee);
          case _SortKind.assigneeDesc:
            return b.assignee.compareTo(a.assignee);
          case _SortKind.repoOrder:
            return 0; // preserve repo insertion order
        }
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project ?? sampleProject;
    return FadeTransition(
      opacity: _fade,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .doc(project.id)
            .collection('tasks')
            .orderBy('createdAt', descending: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final tasks = snapshot.data!.docs
                .map((d) => TaskFirestore.fromMap(d.id, d.data()))
                .toList();
            return _buildTaskScaffold(project, tasks);
          }
          // Fallback to repository for demo/offline
          final repoTasks = TaskRepository.instance.tasksFor(project.id);
          if (repoTasks.isNotEmpty) {
            return _buildTaskScaffold(project, repoTasks);
          }
          // Show loading indicator if no data yet
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _TaskLoadingIndicator();
          }
          return _buildTaskScaffold(project, []);
        },
      ),
    );
  }

  Widget _buildTaskScaffold(Project project, List<TaskModel> source) {
    final tasks = _applyFilters(source);
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                const Text(
                  'Tasks',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                _SearchBar(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  onFiltersTap: _openFilters,
                ),
                const SizedBox(height: 10),
                _SegmentedTabs(
                  current: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: tasks.isEmpty
                      ? _EmptyState(
                          title: _tab == _TaskTab.open
                              ? 'No Open Tasks'
                              : _tab == _TaskTab.completed
                                  ? 'No Completed Tasks'
                                  : 'No Tasks',
                          message:
                              'You currently have no ${_tab == _TaskTab.open ? 'Open ' : _tab == _TaskTab.completed ? 'Completed ' : ''}Tasks.\n',
                        )
                      : ListView.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _TaskCard(
                            task: tasks[i],
                            onChangeStatus: (newStatus) {
                              final t = tasks[i];
                              TaskRepository.instance.updateStatus(
                                project.id,
                                t.id,
                                newStatus,
                              );
                              setState(() {});
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: _AddButton(onTap: _openAddTask),
        ),
      ],
    );
  }

  List<TeamMember> _filterOutCurrentUser(List<TeamMember> members) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final currentEmail = ProfileRepository.instance.profile.email;
    if (currentUid == null && currentEmail.isEmpty) return members;
    
    return members.where((m) {
      // Match by email to filter out current user
      // Note: For Firestore members, the document ID is the uid, but since we're
      // getting from repository here, we match by email
      if (currentEmail.isNotEmpty && m.email != null && m.email == currentEmail) {
        return false;
      }
      return true;
    }).toList();
  }

  void _openFilters() async {
    // Gate sample members by demo project id: real Firestore projects must not
    // show static sample names.
    final project = widget.project ?? sampleProject;
    final isDemo = isDemoProjectId(project.id);
    final allMembers = isDemo
        ? sampleTeamMembers
        : TeamRepository.instance.membersFor(project.id);
    final members = _filterOutCurrentUser(allMembers);
    await showModalBottomSheet(
      context: context,
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (_) => _FiltersSheet(
        showOnlyMine: _showOnlyMine,
        assignee: _assigneeFilter,
        sort: _sort,
        members: members,
        onChanged: (mine, assignee, sort) {
          setState(() {
            _showOnlyMine = mine;
            _assigneeFilter = assignee;
            _sort = sort;
          });
        },
      ),
    );
  }

  void _openAddTask() async {
    // Gate sample members for assignee picker.
    final project = widget.project ?? sampleProject;
    final isDemo = isDemoProjectId(project.id);
    final allMembers = isDemo
        ? sampleTeamMembers
        : TeamRepository.instance.membersFor(project.id);
    final members = _filterOutCurrentUser(allMembers);
    final created = await showModalBottomSheet<TaskModel>(
      isScrollControlled: true,
      context: context,
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (_) => _AddTaskSheet(members: members),
    );
    if (created != null) {
      final project = widget.project ?? sampleProject;
      TaskRepository.instance.addTask(project.id, created, insertOnTop: true);
      setState(() {});
    }
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onFiltersTap,
  });
  final TextEditingController controller;
  final VoidCallback onFiltersTap;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.only(left: 12, right: 8),
      height: 44,
      child: Row(
        children: [
          const Icon(AppIcons.search, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Filters',
            onPressed: widget.onFiltersTap,
            icon: const Icon(AppIcons.options, color: Colors.white70, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.current, required this.onChanged});
  final _TaskTab current;
  final ValueChanged<_TaskTab> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _SegmentChip(
            label: 'Open',
            selected: current == _TaskTab.open,
            onTap: () => onChanged(_TaskTab.open),
          ),
          _Divider(),
          _SegmentChip(
            label: 'Completed',
            selected: current == _TaskTab.completed,
            onTap: () => onChanged(_TaskTab.completed),
          ),
          _Divider(),
          _SegmentChip(
            label: 'All',
            selected: current == _TaskTab.all,
            onTap: () => onChanged(_TaskTab.all),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(vertical: 4),
    color: borderDark,
  );
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onChangeStatus});
  final TaskModel task;
  final ValueChanged<TaskStatus> onChangeStatus;
  @override
  Widget build(BuildContext context) {
    final on = task.status == TaskStatus.completed
        ? Colors.greenAccent.shade400
        : accentConstruction;
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 48,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: on,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(AppIcons.person, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      task.assignee,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(AppIcons.calender, size: 20, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      _dateString(task.dueDate),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit status',
            icon: const Icon(AppIcons.edit, color: Colors.white70, size: 18),
            onPressed: () async {
              final picked = await showStatusPicker(context, current: task.status);
              if (picked != null) onChangeStatus(picked);
            },
          ),
        ],
      ),
    );
  }

  String _dateString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _TaskLoadingIndicator extends StatelessWidget {
  const _TaskLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.checkmark, size: 58, color: Colors.white60),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
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
    );
  }
}

// -------------------- Filters Sheet --------------------
enum _SortKind { repoOrder, dueAsc, dueDesc, assigneeAsc, assigneeDesc }

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.showOnlyMine,
    required this.assignee,
    required this.sort,
    required this.members,
    required this.onChanged,
  });
  final bool showOnlyMine;
  final String? assignee;
  final _SortKind sort;
  final List<TeamMember> members; // demo-only members list (empty for real projects)
  final void Function(bool mine, String? assignee, _SortKind sort) onChanged;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late bool _mine = widget.showOnlyMine;
  String? _assignee;
  late _SortKind _sort = widget.sort;

  @override
  void initState() {
    super.initState();
    _assignee = widget.assignee;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Filters',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(
                switchTheme: const SwitchThemeData(
                  thumbColor: WidgetStatePropertyAll(newaccent),
                  trackColor: WidgetStatePropertyAll(newaccentbackground),
                ),
              ),
              child: SwitchListTile(
                value: _mine,
                onChanged: (v) => setState(() => _mine = v),
                title: const Text(
                  'Only my tasks',
                  style: TextStyle(color: Colors.white),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 6),
            _AssigneeField(
              value: _assignee,
              onPick: (v) => setState(() => _assignee = v),
              members: widget.members,
            ),
            const SizedBox(height: 12),
            _SortField(value: _sort, onPick: (v) => setState(() => _sort = v)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: newaccentbackground,
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: newaccent.withValues(alpha: 0.95),
                    width: 1.6,
                  ),
                  elevation: 6,
                  shadowColor: newaccent.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  widget.onChanged(_mine, _assignee, _sort);
                  Navigator.pop(context);
                },
                child: const Text(
                      'Apply',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssigneeField extends StatelessWidget {
  const _AssigneeField({required this.value, required this.onPick, required this.members});
  final String? value;
  final ValueChanged<String?> onPick;
  final List<TeamMember> members;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: const Text('Assignee', style: TextStyle(color: Colors.white70)),
      subtitle: Text(
        value ?? 'Any',
        style: const TextStyle(color: Colors.white),
      ),
      trailing: const Icon(
        AppIcons.chevronDown,
        color: Colors.white70,
        size: 18,
      ),
      onTap: () async {
        // Open the same Select assignees sheet (multi-picker) so the UI and
        // navigation match exactly. We only keep a single assignee for the
        // Filters state: when the user taps Apply in the multi-picker we
        // set the filter to the first selected name (or null if none).
        final picked = await showModalBottomSheet<List<TeamMember>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          builder: (_) => TeamMultiPicker(
              title: 'Select assignees',
              members: members,
              initiallySelectedNames:
                  value == null ? <String>[] : [value!],
            ),
        );
        if (picked != null && picked.isNotEmpty) {
          onPick(picked.first.name);
        } else {
          onPick(null);
        }
      },
    );
  }
}

// -------------------- Multi-assignee field & picker (mirrors Forms) --------------------
class _MultiAssigneesField extends StatelessWidget {
  const _MultiAssigneesField({
    required this.label,
    required this.selected,
    required this.onAddOrEdit,
    required this.onRemove,
    this.error = false,
    this.onTap,
  });
  final String label;
  final List<String> selected;
  final FutureOr<void> Function() onAddOrEdit;
  final ValueChanged<String> onRemove;
  final bool error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PickerInputField(
          label: label,
          value: selected.isEmpty ? '' : '${selected.length} selected',
          icon: AppIcons.chevronDown,
          error: error,
          onTap: () async {
            onTap?.call();
            await onAddOrEdit();
          },
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in selected)
                _RemovableChip(label: name, onRemove: () => onRemove(name)),
            ],
          ),
        ],
      ],
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: newaccentbackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(AppIcons.close, color: Colors.white70, size: 14),
          ),
        ],
      ),
    );
  }
}



class _SortField extends StatelessWidget {
  const _SortField({required this.value, required this.onPick});
  final _SortKind value;
  final ValueChanged<_SortKind> onPick;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: const Text('Sort', style: TextStyle(color: Colors.white70)),
      subtitle: Text(
        _sortName(value),
        style: const TextStyle(color: Colors.white),
      ),
      trailing: const Icon(
        AppIcons.chevronDown,
        color: Colors.white70,
        size: 18,
      ),
      onTap: () async {
        final result = await showSingleChoicePicker<_SortKind>(
          context,
          items: _SortKind.values,
          current: value,
          title: 'Sort',
          labelBuilder: (k) => _sortName(k),
        );
        if (result != null) onPick(result);
      },
    );
  }
}

String _sortName(_SortKind k) {
  switch (k) {
    case _SortKind.repoOrder:
      return 'Newest first';
    case _SortKind.dueAsc:
      return 'Due Date ascending';
    case _SortKind.dueDesc:
      return 'Due Date descending';
    case _SortKind.assigneeAsc:
      return 'Assignee A→Z';
    case _SortKind.assigneeDesc:
      return 'Assignee Z→A';
  }
}

// _SortPicker removed — replaced by generic showSingleChoicePicker in status_picker.dart

// -------------------- Add Task Sheet --------------------
class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({required this.members});
  final List<TeamMember> members; // demo-only members list (empty for real projects)
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  bool _duePicked = false;
  TaskStatus? _status;
  final List<String> _assignees = [];
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  final TextEditingController _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  // Inline error state for the Task name field
  bool _nameError = false;
  // Picker error states
  bool _statusError = false;
  bool _assigneesError = false;
  bool _dueError = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    'Add task',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Task name',
                  controller: _nameCtrl,
                  error: _nameError,
                  onTap: () => setState(() => _nameError = false),
                ),
                const SizedBox(height: 12),
                _StatusField(
                  value: _status,
                  error: _statusError,
                  onTap: () => setState(() => _statusError = false),
                  onPick: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 12),
                _MultiAssigneesField(
                  label: 'Assignee',
                  selected: _assignees,
                  error: _assigneesError,
                  onTap: () => setState(() => _assigneesError = false),
                  onAddOrEdit: () async {
                    final picked = await showModalBottomSheet<List<TeamMember>>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (_) => TeamMultiPicker(
                        title: 'Select assignees',
                        members: widget.members,
                        initiallySelectedNames: _assignees,
                      ),
                    );
                    if (picked != null) {
                      setState(() {
                        _assignees
                          ..clear()
                          ..addAll(picked.map((m) => m.name));
                      });
                    }
                  },
                  onRemove: (name) => setState(() => _assignees.remove(name)),
                ),
                const SizedBox(height: 12),
                _PickerInputField(
                  label: 'Due date',
                  value: _duePicked ? _dateLong(_dueDate) : '',
                  icon: AppIcons.calender,
                  error: _dueError,
                  onTap: () async {
                    setState(() => _dueError = false);
                    final now = DateTime.now();
                    final picked = await pickPlatformDate(
                      context,
                      initialDate: _dueDate,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                      title: 'Due date',
                    );
                    if (picked != null) {
                      setState(() {
                        _dueDate = picked;
                        _duePicked = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      // Match the floating add button visual style for consistency
                      backgroundColor: newaccentbackground,
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: newaccent.withValues(alpha: 0.95),
                        width: 1.6,
                      ),
                      elevation: 6,
                      shadowColor: newaccent.withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text(
                      'Save',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    // Validate required text fields (inline UX)
    final missingName = _nameCtrl.text.trim().isEmpty;
    final missingStatus = _status == null;
    final missingAssignees = _assignees.isEmpty;
    final missingDue = !_duePicked;
    if (missingName || missingStatus || missingAssignees || missingDue) {
      setState(() {
        _nameError = missingName;
        _statusError = missingStatus;
        _assigneesError = missingAssignees;
        _dueError = missingDue;
      });
      return;
    }
    final model = TaskModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      status: _status!,
      assignee: _assignees.join(', '),
      startDate: DateTime.now(),
      dueDate: _dueDate,
      priority: TaskPriority.medium,
      progress: (_status ?? TaskStatus.pending) == TaskStatus.completed
          ? 100
          : 0,
    );
    Navigator.pop(context, model);
  }

  String _dateLong(DateTime d) {
    // Simple long-ish date without intl dependency here.
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final m = months[d.month - 1];
    return '$m ${d.day}, ${d.year}';
  }
}

class _StatusField extends StatelessWidget {
  const _StatusField({
    required this.value,
    required this.onPick,
    this.error = false,
    this.onTap,
  });
  final TaskStatus? value;
  final ValueChanged<TaskStatus> onPick;
  final bool error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : (value == TaskStatus.pending ? 'Open' : 'Completed');
    return _PickerInputField(
      label: 'Status',
      value: text,
      icon: AppIcons.chevronDown,
      error: error,
      onTap: () async {
        onTap?.call();
        final result = await showStatusPicker(context, current: value);
        if (result != null) onPick(result);
      },
    );
  }
}

// StatusPicker moved to lib/widgets/status_picker.dart and exposed via showStatusPicker


// Removed legacy _PickerTile in favor of floating-label _PickerInputField for consistency

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.error = false,
    this.onTap,
  });
  final String label;
  final TextEditingController controller;
  final bool error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
      maxLines: 1,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelBehavior: error
            ? FloatingLabelBehavior.always
            : FloatingLabelBehavior.auto,
        hintText: error ? 'Required' : null,
        hintStyle: const TextStyle(color: Colors.redAccent),
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
  filled: true,
  fillColor: surfaceDarker,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : borderDark,
            width: error ? 1.2 : 1.1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : borderDark,
            width: error ? 1.2 : 1.1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error
                ? Colors.redAccent
                : newaccent.withValues(alpha: 0.95),
            width: error ? 1.3 : 1.6,
          ),
        ),
      ),
    );
  }
}

class _PickerInputField extends StatefulWidget {
  const _PickerInputField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.error = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final FutureOr<void> Function() onTap;
  final bool error;

  @override
  State<_PickerInputField> createState() => _PickerInputFieldState();
}

class _PickerInputFieldState extends State<_PickerInputField> {
  // transient flag to show accent-focused border when the user taps the picker
  bool _tapped = false;

  Future<void> _handleTap() async {
    // Show accent border while the provided onTap Future is active (modal open).
    setState(() {
      _tapped = true;
    });
    final res = widget.onTap.call();
    if (res is Future) {
      try {
        await res;
      } catch (_) {
        // Ignore errors from the caller; ensure we clear the focus state.
      }
    }
    if (!mounted) return;
    setState(() => _tapped = false);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.value.trim().isEmpty;
    final hasError = widget.error;
    final effectiveFocus = !hasError && _tapped;
    return GestureDetector(
      onTap: () => _handleTap(),
      child: InputDecorator(
        isFocused: effectiveFocus,
        isEmpty: isEmpty,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          floatingLabelBehavior: hasError
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          hintText: hasError ? 'Required' : null,
          hintStyle: const TextStyle(color: Colors.redAccent),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          filled: true,
          fillColor: surfaceDarker,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: hasError ? Colors.redAccent : borderDark,
              width: hasError ? 1.2 : 1.1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: hasError ? Colors.redAccent : borderDark,
              width: hasError ? 1.2 : 1.1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: hasError
                  ? Colors.redAccent
                  : newaccent.withValues(alpha: 0.95),
              width: hasError ? 1.3 : 1.6,
            ),
          ),
          suffixIcon: Icon(widget.icon, color: Colors.white70, size: 18),
        ),
        child: isEmpty
            ? const SizedBox.shrink()
            : Text(widget.value, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
