import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../widgets/overlay_notice.dart';
import '../theme/app_icons.dart';
import '../widgets/platform_date_picker.dart';
import '../widgets/status_picker.dart';
import '../data/sample_data.dart';
import '../data/initial_data.dart';
import '../data/team_repository.dart';
import '../data/profile_repository.dart';
import '../data/mappers.dart';
import '../models/project.dart';
import '../models/form_models.dart';
import '../data/forms_repository.dart';
import '../panels/panel_scaffold.dart';
import '../widgets/team_multi_picker.dart';
import '../models/team_member.dart';

class FormsPage extends StatefulWidget {
  const FormsPage({super.key, this.project, this.insidePanel = false});
  final Project? project;
  // When true the page is hosted inside a sliding panel and notices should
  // use in-panel placement (do not lift above the global bottom nav).
  final bool insidePanel;

  @override
  State<FormsPage> createState() => _FormsPageState();
}

class _FormsPageState extends State<FormsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  final TextEditingController _searchCtrl = TextEditingController();

  _FormsTab _tab = _FormsTab.templates;
  final List<FormTemplate> _templates = const [
    FormTemplate(
      id: 'tmpl_daily',
      name: 'Daily Site Report',
      category: 'Operations',
      kind: FormKind.dailyReport,
      description: 'Weather, crew, work performed, issues',
    ),
    FormTemplate(
      id: 'tmpl_incident',
      name: 'Incident / Near-Miss',
      category: 'Safety',
      kind: FormKind.incident,
      description: 'Incident details, severity and corrective actions',
    ),
    FormTemplate(
      id: 'tmpl_safety',
      name: 'Safety Inspection',
      category: 'Safety',
      kind: FormKind.safetyInspection,
      description: 'Checklist, findings and priority',
    ),
    FormTemplate(
      id: 'tmpl_material',
      name: 'Material Request',
      category: 'Procurement',
      kind: FormKind.materialRequest,
      description: 'Items, quantities and needed by date',
    ),
  ];

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
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project ?? sampleProject;
    // Templates are static, so we can render them immediately
    // Submissions come from Firestore stream
    return FadeTransition(
      opacity: _fade,
      child: _tab == _FormsTab.templates
          ? _buildFormsScaffold(_templates, [])
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('projects')
                  .doc(project.id)
                  .collection('forms')
                  .orderBy('createdAt', descending: true)
                  .snapshots(includeMetadataChanges: true),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final submissions = snapshot.data!.docs
                      .map((d) => FormSubmissionFirestore.fromMap(d.id, d.data()))
                      .toList();
                  return _buildFormsScaffold(_templates, submissions);
                }
                // Fallback to repository for demo/offline
                final repoSubs = FormsRepository.instance.submissionsFor(project.id);
                if (repoSubs.isNotEmpty) {
                  return _buildFormsScaffold(_templates, repoSubs);
                }
                // Show loading indicator if no data yet
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _FormsLoadingIndicator();
                }
                return _buildFormsScaffold(_templates, []);
              },
            ),
    );
  }

  List<FormTemplate> _filteredTemplates() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _templates;
    return _templates
        .where(
          (t) =>
              t.name.toLowerCase().contains(q) ||
              (t.category?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  List<FormSubmission> _filteredSubmissions(List<FormSubmission> submissions) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return submissions;
    return submissions
        .where((s) => s.title.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildFormsScaffold(List<FormTemplate> templates, List<FormSubmission> submissions) {
    final filteredTemplates = _filteredTemplates();
    final filteredSubs = _filteredSubmissions(submissions);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (context.findAncestorWidgetOfExactType<PanelScaffold>() == null) ...[
              const Text(
                'Forms',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _SearchBar(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _SegmentedTabs(
              current: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _tab == _FormsTab.templates
                  ? (filteredTemplates.isEmpty
                        ? const _EmptyTemplates()
                        : ListView.separated(
                            itemCount: filteredTemplates.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _TemplateCard(
                              template: filteredTemplates[i],
                              onStart: _openStartForm,
                            ),
                          ))
                  : (filteredSubs.isEmpty
                        ? const _EmptySubmissions()
                        : ListView.separated(
                            itemCount: filteredSubs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) =>
                                _SubmissionCard(sub: filteredSubs[i]),
                          )),
            ),
          ],
        ),
      ),
    );
  }

  List<TeamMember> _filterOutCurrentUser(List<TeamMember> members) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final currentEmail = ProfileRepository.instance.profile.email;
    if (currentUid == null && currentEmail.isEmpty) return members;
    
    return members.where((m) {
      // Match by email to filter out current user
      if (currentEmail.isNotEmpty && m.email != null && m.email == currentEmail) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openStartForm(FormTemplate t) async {
    // Determine member source: demo projects get sample members; real Firestore projects get none.
  final proj = widget.project; // null when not launched from a specific project
    final isDemo = proj == null ? true : isDemoProjectId(proj.id);
  final allMembers = isDemo
    ? sampleTeamMembers
    : TeamRepository.instance.membersFor(proj.id);
  final members = _filterOutCurrentUser(allMembers);
    switch (t.kind) {
      case FormKind.dailyReport:
        final result = await showModalBottomSheet<FormSubmission>(
          isScrollControlled: true,
          context: context,
          backgroundColor: surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          builder: (_) => _DailyReportSheet(template: t, members: members),
        );
        if (result != null) _addSubmission(result);
        break;
      case FormKind.incident:
        final result = await showModalBottomSheet<FormSubmission>(
          isScrollControlled: true,
          context: context,
          backgroundColor: surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          builder: (_) => _IncidentSheet(template: t, members: members),
        );
        if (result != null) _addSubmission(result);
        break;
      case FormKind.safetyInspection:
      case FormKind.materialRequest:
        ScaffoldMessenger.of(context).clearSnackBars();
        showOverlayNotice(
          context,
          'Template (coming soon)',
          // When this page is shown inside a panel we don't lift above the
          // bottom nav so placement matches chat panel notices.
          liftAboveNav: !widget.insidePanel,
        );
        break;
    }
  }

  void _addSubmission(FormSubmission sub) {
    final projectId = (widget.project)?.id ?? 'global';
    FormsRepository.instance.addSubmission(projectId, sub);
    // Stream will update automatically
  }
}

// -------------------- Models (local) --------------------
enum _FormsTab { templates, submissions }

// moved local form models to lib/models/form_models.dart

// -------------------- UI pieces --------------------
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
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
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search templates or submissions',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.current, required this.onChanged});
  final _FormsTab current;
  final ValueChanged<_FormsTab> onChanged;
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
            label: 'Templates',
            selected: current == _FormsTab.templates,
            onTap: () => onChanged(_FormsTab.templates),
          ),
          _Divider(),
          _SegmentChip(
            label: 'Submissions',
            selected: current == _FormsTab.submissions,
            onTap: () => onChanged(_FormsTab.submissions),
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

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onStart});
  final FormTemplate template;
  final ValueChanged<FormTemplate> onStart;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  template.description ?? (template.category ?? ''),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF191B1B),
              foregroundColor: Colors.white,
              side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
              elevation: 6,
              shadowColor: newaccent.withValues(alpha: 0.10),
            ),
            onPressed: () => onStart(template),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.sub});
  final FormSubmission sub;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_kindName(sub.kind)} • ${_dateShort(sub.createdAt)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          _StatusChip(label: sub.status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final isSubmitted = label.toLowerCase() == 'submitted';
    final color = isSubmitted
        ? const Color(0xFF34D399)
        : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyTemplates extends StatelessWidget {
  const _EmptyTemplates();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No templates match your search',
        style: TextStyle(color: Colors.white60),
      ),
    );
  }
}

class _EmptySubmissions extends StatelessWidget {
  const _EmptySubmissions();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No submissions yet',
        style: TextStyle(color: Colors.white60),
      ),
    );
  }
}

class _FormsLoadingIndicator extends StatelessWidget {
  const _FormsLoadingIndicator();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
      ),
    );
  }
}

// -------------------- Form Sheets --------------------
class _DailyReportSheet extends StatefulWidget {
  const _DailyReportSheet({required this.template, required this.members});
  final FormTemplate template;
  final List<TeamMember> members; // demo-only members (empty for real projects)
  @override
  State<_DailyReportSheet> createState() => _DailyReportSheetState();
}

class _DailyReportSheetState extends State<_DailyReportSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  bool _datePicked = false;
  final _projectCtrl = TextEditingController();
  final _weatherCtrl = TextEditingController();
  final _workCtrl = TextEditingController();
  final _issuesCtrl = TextEditingController();
  // Crew multi-select from team members
  final List<String> _crew = [];
  // Inline error flags for text fields
  bool _projectError = false;
  bool _weatherError = false;
  bool _workError = false;
  bool _issuesError = false;
  // Picker error flags
  bool _dateError = false;
  bool _crewError = false;

  @override
  void dispose() {
    _projectCtrl.dispose();
    _weatherCtrl.dispose();
    _workCtrl.dispose();
    _issuesCtrl.dispose();
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
                    'Daily Site Report',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PickerInputField(
                  label: 'Date',
                  value: _datePicked ? _dateString(_date) : '',
                  icon: AppIcons.calender,
                  error: _dateError,
                  onTap: () async {
                    setState(() => _dateError = false);
                    final now = DateTime.now();
                    final picked = await pickPlatformDate(
                      context,
                      initialDate: _date,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                      title: 'Date',
                    );
                    if (picked != null) {
                      setState(() {
                        _date = picked;
                        _datePicked = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                _TextField(
                  label: 'Project / Location',
                  controller: _projectCtrl,
                  error: _projectError,
                  onTap: () => setState(() => _projectError = false),
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Weather',
                  controller: _weatherCtrl,
                  error: _weatherError,
                  onTap: () => setState(() => _weatherError = false),
                ),
                const SizedBox(height: 12),
                _MultiMemberField(
                  label: 'Crew on site',
                  selected: _crew,
                  error: _crewError,
                  onTap: () => setState(() => _crewError = false),
                  onAddOrEdit: () async {
                    final picked = await showModalBottomSheet<List<TeamMember>>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (_) => TeamMultiPicker(
                        title: 'Select crew on site',
                        members: widget.members,
                        initiallySelectedNames: _crew,
                      ),
                    );
                    if (picked != null) {
                      setState(() {
                        _crew
                          ..clear()
                          ..addAll(picked.map((m) => m.name));
                      });
                    }
                  },
                  onRemove: (name) => setState(() => _crew.remove(name)),
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Work performed',
                  controller: _workCtrl,
                  maxLines: 3,
                  error: _workError,
                  onTap: () => setState(() => _workError = false),
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Delays / Issues',
                  controller: _issuesCtrl,
                  maxLines: 3,
                  error: _issuesError,
                  onTap: () => setState(() => _issuesError = false),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      // Match floating add button visuals for consistency
                      backgroundColor: newaccentbackground,
                      foregroundColor: Colors.white,
                      side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
                      elevation: 6,
                      shadowColor: newaccent.withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text(
                      'Submit',
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
    final missingProject = _projectCtrl.text.trim().isEmpty;
    final missingWeather = _weatherCtrl.text.trim().isEmpty;
    final missingWork = _workCtrl.text.trim().isEmpty;
    final missingIssues = _issuesCtrl.text.trim().isEmpty;
    final hasCrew = _crew.isNotEmpty;
    final hasDate = _datePicked;
    setState(() {
      _projectError = missingProject;
      _weatherError = missingWeather;
      _workError = missingWork;
      _issuesError = missingIssues;
      _dateError = !hasDate;
      _crewError = !hasCrew;
    });
    if (missingProject ||
        missingWeather ||
        missingWork ||
        missingIssues ||
        !hasCrew ||
        !hasDate) {
      return;
    }
    final sub = FormSubmission(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Daily Report • ${_dateString(_date)}',
      kind: FormKind.dailyReport,
      status: 'Submitted',
      createdAt: DateTime.now(),
    );
    Navigator.pop(context, sub);
  }
}

class _IncidentSheet extends StatefulWidget {
  const _IncidentSheet({required this.template, required this.members});
  final FormTemplate template;
  final List<TeamMember> members; // demo-only members (empty for real projects)
  @override
  State<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<_IncidentSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  bool _datePicked = false;
  final _locationCtrl = TextEditingController();
  String? _severity; // Inline placeholder until user selects
  final _descCtrl = TextEditingController();
  final _actionsCtrl = TextEditingController();
  final List<String> _people = [];
  // Inline error flags for text fields
  bool _locationError = false;
  bool _descError = false;
  bool _actionsError = false;
  // Picker error flags
  bool _dateError = false;
  bool _peopleError = false;
  bool _severityError = false;

  @override
  void dispose() {
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _actionsCtrl.dispose();
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
                    'Incident / Near-Miss',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PickerInputField(
                  label: 'Date',
                  value: _datePicked ? _dateString(_date) : '',
                  icon: AppIcons.calender,
                  error: _dateError,
                  onTap: () async {
                    setState(() => _dateError = false);
                    final now = DateTime.now();
                    final picked = await pickPlatformDate(
                      context,
                      initialDate: _date,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                      title: 'Date',
                    );
                    if (picked != null) {
                      setState(() {
                        _date = picked;
                        _datePicked = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Location',
                  controller: _locationCtrl,
                  error: _locationError,
                  onTap: () => setState(() => _locationError = false),
                ),
                const SizedBox(height: 12),
                _MultiMemberField(
                  label: 'People involved',
                  selected: _people,
                  error: _peopleError,
                  onTap: () => setState(() => _peopleError = false),
                  onAddOrEdit: () async {
                    final picked = await showModalBottomSheet<List<TeamMember>>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (_) => TeamMultiPicker(
                        title: 'Select people involved',
                        members: widget.members,
                        initiallySelectedNames: _people,
                      ),
                    );
                    if (picked != null) {
                      setState(() {
                        _people
                          ..clear()
                          ..addAll(picked.map((m) => m.name));
                      });
                    }
                  },
                  onRemove: (name) => setState(() => _people.remove(name)),
                ),
                const SizedBox(height: 12),
                _PickerInputField(
                  label: 'Severity',
                  value: _severity ?? '',
                  icon: AppIcons.chevronDown,
                  error: _severityError,
                  onTap: () async {
                    setState(() => _severityError = false);
                    final picked = await showSingleChoicePicker<String>(
                      context,
                      items: const ['Minor', 'Moderate', 'Major'],
                      current: _severity,
                      title: 'Severity',
                      labelBuilder: (s) => s,
                    );
                    if (picked != null) {
                      setState(() {
                        _severity = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Description',
                  controller: _descCtrl,
                  maxLines: 3,
                  error: _descError,
                  onTap: () => setState(() => _descError = false),
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Corrective actions',
                  controller: _actionsCtrl,
                  maxLines: 3,
                  error: _actionsError,
                  onTap: () => setState(() => _actionsError = false),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      // Match floating add button visuals for consistency
                      backgroundColor: newaccentbackground,
                      foregroundColor: Colors.white,
                      side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
                      elevation: 6,
                      shadowColor: newaccent.withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text(
                      'Submit',
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
    final missingLocation = _locationCtrl.text.trim().isEmpty;
    final missingDesc = _descCtrl.text.trim().isEmpty;
    final missingActions = _actionsCtrl.text.trim().isEmpty;
    final hasPeople = _people.isNotEmpty;
    final hasSeverity = _severity != null;
    final hasDate = _datePicked;
    setState(() {
      _locationError = missingLocation;
      _descError = missingDesc;
      _actionsError = missingActions;
      _peopleError = !hasPeople;
      _severityError = !hasSeverity;
      _dateError = !hasDate;
    });
    if (missingLocation ||
        missingDesc ||
        missingActions ||
        !hasPeople ||
        !hasSeverity ||
        !hasDate) {
      return;
    }
    final sub = FormSubmission(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Incident • ${_dateString(_date)}',
      kind: FormKind.incident,
      status: 'Submitted',
      createdAt: DateTime.now(),
    );
    Navigator.pop(context, sub);
  }
}

// -------------------- Multi member picker & field --------------------
class _MultiMemberField extends StatelessWidget {
  const _MultiMemberField({
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



// -------------------- Shared small widgets --------------------
// Severity picker replaced by generic showSingleChoicePicker<String>.
// Removed legacy _PickerTile in favor of floating-label _PickerInputField for consistency

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.error = false,
    this.onTap,
  });
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
      maxLines: maxLines,
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

// Floating-label picker input to mirror TextField behavior
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
  bool _tapped = false;

  Future<void> _handleTap() async {
    setState(() => _tapped = true);
    try {
      final res = widget.onTap();
      if (res is Future) await res;
    } finally {
      if (mounted) setState(() => _tapped = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.value.trim().isEmpty;
    return GestureDetector(
      onTap: _handleTap,
      child: InputDecorator(
        isFocused: _tapped,
        isEmpty: isEmpty,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          floatingLabelBehavior: widget.error
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          hintText: widget.error ? 'Required' : null,
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
              color: widget.error ? Colors.redAccent : borderDark,
              width: widget.error ? 1.2 : 1.1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.error ? Colors.redAccent : borderDark,
              width: widget.error ? 1.2 : 1.1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.error
                  ? Colors.redAccent
                  : newaccent.withValues(alpha: 0.95),
              width: widget.error ? 1.3 : 1.6,
            ),
          ),
          suffixIcon: Icon(widget.icon, color: Colors.white70, size: 20),
        ),
        child: isEmpty
            ? const SizedBox.shrink()
            : Text(widget.value, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

// Dropdown styled like _TextField, with hint text shown inside the field until a value is chosen.
// Removed legacy dropdown input in favor of picker tiles for consistency

// Removed legacy _DropdownField in favor of inline-hint _DropdownInputField

String _kindName(FormKind k) {
  switch (k) {
    case FormKind.dailyReport:
      return 'Daily Report';
    case FormKind.incident:
      return 'Incident';
    case FormKind.safetyInspection:
      return 'Safety Inspection';
    case FormKind.materialRequest:
      return 'Material Request';
  }
}

String _dateString(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _dateShort(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
