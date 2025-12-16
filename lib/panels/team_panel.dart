import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../widgets/overlay_notice.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../models/team_member.dart';
import '../models/project.dart';
import '../data/sample_data.dart';
import '../data/team_repository.dart';
import '../data/mappers.dart';
import '../data/initial_data.dart' show isDemoProjectId;
import 'panel_scaffold.dart';

class TeamPanel extends StatefulWidget {
  const TeamPanel({
    super.key,
    required this.onClose,
    this.onProfileActiveChanged,
    required this.project,
    this.initialMemberUid,
    this.ownerUid,
  });
  final VoidCallback onClose;
  final ValueChanged<bool>?
  onProfileActiveChanged; // informs parent when profile subpage is active
  final Project project;
  final String? initialMemberUid; // If provided, open this member's profile on mount
  final String? ownerUid; // Project owner UID for instant ownership check
  @override
  State<TeamPanel> createState() => _TeamPanelState();
}

class _TeamPanelState extends State<TeamPanel> {

  // Centralized durations to easily tweak transition pacing.
  static const Duration _profileTransitionForward = Duration(milliseconds: 520);
  static const Duration _fadeElementDuration = Duration(milliseconds: 260);

  late final PageController _pageController;
  // Search controller (tasks-style search bar)
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    // Start live hydration of team subcollection for this project so the
    // panel can show up-to-date online/total counts.
    TeamRepository.instance.listenTo(widget.project.id);
    
    // If initialMemberUid is provided, open that member's profile after first frame
    if (widget.initialMemberUid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openProfileByUid(widget.initialMemberUid!);
      });
    }
  }
  
  Future<void> _openProfileByUid(String uid) async {
    try {
      final fs = FirebaseFirestore.instance;
      final teamDoc = await fs
          .collection('projects')
          .doc(widget.project.id)
          .collection('team')
          .doc(uid)
          .get();
      
      if (!teamDoc.exists || !mounted) return;
      
      final data = teamDoc.data()!;
      final member = TeamMemberFirestore.fromMap(data);
      await _openProfile(member);
    } catch (_) {
      // Silent fail
    }
  }

  @override
  void didUpdateWidget(covariant TeamPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent swapped projects while this panel instance is reused,
    // stop listening to the old project and start listening to the new one.
    if (oldWidget.project.id != widget.project.id) {
      try {
        TeamRepository.instance.stopListening(oldWidget.project.id);
      } catch (_) {}
      try {
        TeamRepository.instance.listenTo(widget.project.id);
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    TeamRepository.instance.stopListening(widget.project.id);
    super.dispose();
  }

  Future<void> _openProfile(TeamMember m, [String? memberUid]) async {
    // mark profile mode only for parent listeners
    _searchFocus.unfocus();
    _searchCtrl.clear();
    widget.onProfileActiveChanged?.call(true);
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: _profileTransitionForward,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ProfilePage(
            member: m,
            projectId: widget.project.id,
            ownerUid: widget.ownerUid,
            memberUid: memberUid,
          );
        },
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;
    // profile closed; notify parent
    widget.onProfileActiveChanged?.call(false);
  }

  // Close the root panel (no profile active). Also clear focus so typing stops.
  void _closeRootPanel() {
    FocusScope.of(context).unfocus();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return PanelScaffold(
      title: 'Team',
      onClose: _closeRootPanel,
      // Position the Add button like ProjectsPanel using the fab slot.
      fab: Transform.translate(
        offset: const Offset(-5, 5),
        child: _TeamAddButton(
          onTap: () async {
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: surfaceDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              builder: (ctx) => _InviteSheet(projectId: widget.project.id),
            );
          },
        ),
      ),
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, _) {
          // progress: 0 = list, 1 = profile
          double progress = 0;
          if (_pageController.hasClients &&
              _pageController.position.hasPixels) {
            final page =
                _pageController.page ?? _pageController.initialPage.toDouble();
            progress = page.clamp(0, 1);
          }
          final listFade = 1 - progress; // fade out list overlay elements
          return Stack(
            children: [
              PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Page 0: Team list
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _searchFocus.unfocus(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Always build search bar so it can fade instead of popping
                          IgnorePointer(
                            ignoring: progress > 0.001,
                            child: AnimatedOpacity(
                              duration: _fadeElementDuration,
                              opacity: listFade,
                              child: _SearchBar(
                                controller: _searchCtrl,
                                focusNode: _searchFocus,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Live online/total indicator for the current project.
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('projects')
                                .doc(widget.project.id)
                                .collection('team')
                                .snapshots(),
                            builder: (context, snap) {
                              int online = 0;
                              int total = 0;
                              if (snap.hasData) {
                                final docs = snap.data!.docs;
                                total = docs.length;
                                for (final d in docs) {
                                  final data = d.data();
                                  final isOn = (data['isOnline'] as bool?) ?? false;
                                  if (isOn) online++;
                                }
                              } else {
                                // fallback to repository
                                final repoMembers = TeamRepository.instance.membersFor(widget.project.id);
                                total = repoMembers.length;
                                online = repoMembers.where((m) => m.isOnline).length;
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.greenAccent.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Online $online/$total',
                                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('projects')
                                  .doc(widget.project.id)
                                  .collection('team')
                                  .orderBy('name')
                                  .snapshots(includeMetadataChanges: true),
                              builder: (context, snap) {
                                List<TeamMember> members;
                                if (snap.hasData) {
                                  members = snap.data!.docs
                                      .map((d) {
                                        try {
                                          return TeamMemberFirestore.fromMap(d.data());
                                        } catch (_) {
                                          return null;
                                        }
                                      })
                                      .whereType<TeamMember>()
                                      .toList();
                                } else {
                                  // Fallback to repository for demo/offline
                                  members = TeamRepository.instance.membersFor(widget.project.id);
                                  if (members.isEmpty && isDemoProjectId(widget.project.id)) {
                                    members = sampleTeamMembers;
                                  }
                                }
                                
                                final q = _searchCtrl.text.trim().toLowerCase();
                                final filtered = q.isEmpty
                                    ? members
                                    : members
                                          .where(
                                            (m) =>
                                                m.name.toLowerCase().contains(
                                                  q,
                                                ) ||
                                                m.role.toLowerCase().contains(
                                                  q,
                                                ),
                                          )
                                          .toList();
                                if (members.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      'No team members yet',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  );
                                }
                                if (filtered.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      'No members match your search',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  );
                                }
                                // Create a map of member name/email to document ID for instant lookup
                                final Map<String, String> memberUidMap = {};
                                if (snap.hasData) {
                                  for (final d in snap.data!.docs) {
                                    final data = d.data();
                                    final name = data['name'] as String?;
                                    final email = data['email'] as String?;
                                    if (name != null) {
                                      memberUidMap[name] = d.id;
                                      if (email != null) {
                                        memberUidMap[email] = d.id;
                                      }
                                    }
                                  }
                                }
                                
                                return Opacity(
                                  opacity: listFade.clamp(0, 1),
                                  child: Transform.translate(
                                    offset: Offset(40 * progress, 0),
                                    child: ListView.separated(
                                      itemCount: filtered.length,
                                      separatorBuilder: (context, _) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, i) {
                                        final member = filtered[i];
                                        final memberUid = memberUidMap[member.name] ?? memberUidMap[member.email ?? ''];
                                        return _MemberTile(
                                          member: member,
                                          onViewProfile: () => _openProfile(member, memberUid),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // FAB moved to PanelScaffold.fab above (matches ProjectsPanel)
            ],
          );
        },
      ),
    );
  }
}

class _TeamAddButton extends StatelessWidget {
  const _TeamAddButton({required this.onTap});
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
      child: const Icon(
        AppIcons.add,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onViewProfile});
  final TeamMember member;
  final VoidCallback onViewProfile;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Use member photoAsset when available, otherwise fall back to initials.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
              border: Border.all(color: borderDark),
            ),
            clipBehavior: Clip.antiAlias,
            child: member.photoAsset != null && member.photoAsset!.isNotEmpty
                ? ClipOval(
                    child: Image.asset(
                      member.photoAsset!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Center(
                        child: Text(
                          _initials(member.name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      _initials(member.name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Use a gesture detector for the view profile action to avoid
          // the default TextButton ripple/overlay ('click indicator').
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onViewProfile,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'View profile',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r"\s+"));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.nextId});
  final int nextId;
  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();

  final _countryCtrl = TextEditingController();

  String? _nameError;
  String? _roleError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();

    _countryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Member',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _nameCtrl,
              label: 'Full name',
              hasError: _nameError != null,
              onChanged: (v) {
                if (_nameError != null && v.trim().isNotEmpty) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 10),
            _textField(
              controller: _roleCtrl,
              label: 'Role',
              hasError: _roleError != null,
              onChanged: (v) {
                if (_roleError != null && v.trim().isNotEmpty) {
                  setState(() => _roleError = null);
                }
              },
            ),
            const SizedBox(height: 10),
            _textField(
              controller: _countryCtrl,
              label: 'Country',
              hasError: false,
              onChanged: (_) {},
            ),
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
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required bool hasError,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError ? Colors.redAccent : borderDark,
          width: 1.1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: InputBorder.none,
        ),
      ),
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final role = _roleCtrl.text.trim();

    final country = _countryCtrl.text.trim();
    bool hasError = false;
    _nameError = null;
    _roleError = null;
    if (name.isEmpty) {
      _nameError = 'Required';
      hasError = true;
    }
    if (role.isEmpty) {
      _roleError = 'Required';
      hasError = true;
    }
    setState(() {});
    if (hasError) return;
    // Unfocus any active text fields (search) so typing does not continue invisibly
    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      TeamMember(
        id: widget.nextId,
        name: name,
        role: role,

        country: country.isEmpty ? null : country,
        photoAsset: null,
        isOnline: true,
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.projectId});
  final String projectId;
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  String? _inviteLink;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Invite',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(
                () => _inviteLink = _generateLink(widget.projectId),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceDarker,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderDark, width: 1.1),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Row(
                  children: const [
                    Expanded(
                      child: Text(
                        'Invite via link',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      AppIcons.chevronRight,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_inviteLink != null) ...[
              const SizedBox(height: 14),
              const Text(
                'Share this link',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: surfaceDarker,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderDark, width: 1.0),
                ),
                padding: const EdgeInsets.only(bottom: 2, top: 2, left: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _inviteLink!,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(AppIcons.copy, color: Colors.white70, size: 22),
                      onPressed: () async {
                        final link = _inviteLink!;
                        final nav = Navigator.of(context);
                        Clipboard.setData(ClipboardData(text: link));
                        showOverlayNotice(
                          context,
                          'Link copied to clipboard',
                          liftAboveNav: false,
                        );
                        nav.pop();
                      },
                    ),
                  ],
                ),
              ),
            ],
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
                onPressed: () => Navigator.pop(context),
                child: const Text(
                      'Done',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _generateLink(String projectId) {
    // Deterministic per-project invite link (stable for same project)
    // Encoding kept simple for demo; later we can append a signed token.
    final slug = projectId.trim();
    return 'https://binaytech/join/$slug';
  }
}

class _MemberProfileView extends StatelessWidget {
  const _MemberProfileView({
    required this.member,
    required this.onSwipeBack,
    required this.projectId,
    required this.isOwner,
    required this.memberUid,
  });
  final TeamMember member;
  final VoidCallback onSwipeBack;
  final String projectId;
  final bool isOwner;
  final String? memberUid;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MemberHeroCard(member: member),
          const SizedBox(height: 24),
          _MemberInfoCard(
            member: member,
            projectId: projectId,
            isOwner: isOwner,
            memberUid: memberUid,
          ),
        ],
      ),
    );
  }
}

// Slide-in profile page that mirrors Chats' slide interaction and speed.
class _ProfilePage extends StatefulWidget {
  const _ProfilePage({
    required this.member,
    required this.projectId,
    this.ownerUid,
    this.memberUid,
  });
  final TeamMember member;
  final String projectId;
  final String? ownerUid;
  final String? memberUid; // Pre-fetched member UID for instant display

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragX = 0;
  bool _dragging = false;
  bool _isOwner = false;
  String? _memberUid;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() => setState(() {}));
    _checkOwnership(); // Now synchronous
  }

  void _checkOwnership() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    _isOwner = widget.ownerUid != null && currentUid != null && widget.ownerUid == currentUid;
    
    // Use pre-fetched memberUid if available, otherwise do async lookup
    _memberUid = widget.memberUid;
    
    // Only do async lookup if memberUid wasn't provided
    if (_memberUid == null) {
      _getMemberUid();
    }
    
    setState(() {});
  }
  
  Future<void> _getMemberUid() async {
    try {
      final fs = FirebaseFirestore.instance;
      final teamDocs = await fs
          .collection('projects')
          .doc(widget.projectId)
          .collection('team')
          .where('name', isEqualTo: widget.member.name)
          .limit(1)
          .get();
      
      if (teamDocs.docs.isNotEmpty) {
        _memberUid = teamDocs.docs.first.id;
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Silent fail
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, double width, {bool thenPop = false}) {
    final start = _dragX;
    final distance = (target - start).abs();
    final duration = Duration(
      milliseconds: (240 * (distance / width)).clamp(120, 240).toInt(),
    );
    _controller.duration = duration;
    _controller.reset();
    final tween = Tween<double>(
      begin: start,
      end: target,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    final anim = tween.animate(_controller);
    _controller.addListener(() => setState(() => _dragX = anim.value));
    _controller.forward().whenComplete(() {
      if (thenPop && mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            _controller.stop();
            _animateTo(width, width, thenPop: true);
          },
          child: GestureDetector(
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
            child: Transform.translate(
              offset: Offset(_dragX, 0),
              child: PanelScaffold(
                title: member.name,
                onClose: () {
                  _controller.stop();
                  _animateTo(width, width, thenPop: true);
                },
                child: _MemberProfileView(
                  member: member,
                  onSwipeBack: () {
                    _controller.stop();
                    _animateTo(width, width, thenPop: true);
                  },
                  projectId: widget.projectId,
                  isOwner: _isOwner,
                  memberUid: _memberUid,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MemberHeroCard extends StatelessWidget {
  const _MemberHeroCard({required this.member});
  final TeamMember member;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderDark, width: 1.1),
        gradient: const LinearGradient(
          colors: [surfaceDarker, surfaceDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MemberAvatar(name: member.name, photoAsset: member.photoAsset),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  member.role,
                  style: TextStyle(
                    color: neutralText.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, this.photoAsset});
  final String name;
  final String? photoAsset;
  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: Colors.white.withValues(alpha: 0.9),
      width: 2,
    );
    if (photoAsset != null && photoAsset!.isNotEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, border: border),
        clipBehavior: Clip.antiAlias,
        child: ClipOval(
          child: Image.asset(
            photoAsset!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Image.asset(
              'assets/profile_placeholder.jpg',
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(shape: BoxShape.circle, border: border),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
    );
  }

  String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r"\s+"));
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _MemberInfoCard extends StatelessWidget {
  const _MemberInfoCard({
    required this.member,
    required this.projectId,
    required this.isOwner,
    required this.memberUid,
  });
  final TeamMember member;
  final String projectId;
  final bool isOwner;
  final String? memberUid;
  
  Future<void> _kickMember(BuildContext context) async {
    if (memberUid == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          textAlign: TextAlign.center,
          'Kick Member',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              textAlign: TextAlign.center,
              'Are you sure you want to remove ${member.name} from this project?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: newaccentbackground,
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.95),
                    width: 1.6,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Kick Member',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      // Remove from project members array
      final fs = FirebaseFirestore.instance;
      final projectRef = fs.collection('projects').doc(projectId);
      
      await fs.runTransaction((tx) async {
        final snap = await tx.get(projectRef);
        if (!snap.exists) return;
        
        final data = snap.data()!;
        final members = (data['members'] as List?)?.cast<String>() ?? <String>[];
        if (!members.contains(memberUid)) return;
        
        // Remove from members array
        tx.update(projectRef, {
          'members': FieldValue.arrayRemove([memberUid]),
          'teamTotal': FieldValue.increment(-1),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        
        // Delete team document
        final teamRef = projectRef.collection('team').doc(memberUid);
        tx.delete(teamRef);
      });
      
      if (context.mounted) {
        Navigator.pop(context); // Close profile
        showOverlayNotice(context, 'Member removed from this project', liftAboveNav: false);
      }
    } catch (e) {
      if (context.mounted) {
        showOverlayNotice(context, 'Failed to remove member');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(AppIcons.profile.regular, 'Name', member.name),
          _divider(),
          _infoRow(AppIcons.title, 'Role', member.role),
          _divider(),
          if (member.phone != null && member.phone!.trim().isNotEmpty) ...[
            _infoRow(AppIcons.phone, 'Phone', member.phone!.trim()),
            _divider(),
          ],
          if (member.email != null && member.email!.trim().isNotEmpty) ...[
            _infoRow(AppIcons.mail, 'E-Mail', member.email!.trim()),
            _divider(),
          ],
          if (member.country != null) ...[
            _infoRow(AppIcons.location, 'Country', member.country!),
            _divider(),
          ],
          if (isOwner && memberUid != null) ...[
            // Don't show kick button if trying to kick yourself
            Builder(
              builder: (context) {
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                if (currentUid == null || currentUid == memberUid) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _kickMember(context),
                        child: const Text(
                          'Kick Member',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Icon(
            icon,
            color: neutralText.withValues(alpha: 0.85),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: neutralText.withValues(alpha: 0.55),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _divider() => Divider(
    height: 1,
    thickness: 1,
    color: borderDark.withValues(alpha: 0.35),
  );
}

// Tasks-style search bar (no filters button requested)
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.focusNode,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode focusNode;
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
              focusNode: focusNode,
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search',
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
