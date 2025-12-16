import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'panel_scaffold.dart';
import '../data/notifications_repository.dart';
import '../data/mappers.dart';
import '../models/app_notification.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../models/team_member.dart';
import '../widgets/overlay_notice.dart';

class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({
    super.key,
    required this.onClose,
    this.projectId,
    this.ownerUid,
  });
  final VoidCallback onClose;
  final String? projectId; // optional; if null shows generic empty state
  final String? ownerUid; // optional; if provided, ownership check is instant
  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  bool _isOwner = false;
  
  @override
  void initState() {
    super.initState();
    // Instant ownership check if ownerUid is provided, otherwise check async
    if (widget.ownerUid != null) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      _isOwner = currentUid != null && widget.ownerUid == currentUid;
    } else if (widget.projectId != null) {
      _checkOwnership();
    }
  }
  
  Future<void> _checkOwnership() async {
    try {
      final fs = FirebaseFirestore.instance;
      final projectDoc = await fs
          .collection('projects')
          .doc(widget.projectId!)
          .get();
      
      if (!projectDoc.exists) return;
      
      final ownerUid = projectDoc.data()?['ownerUid'] as String?;
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      _isOwner = ownerUid != null && currentUid != null && ownerUid == currentUid;
      
      if (mounted) setState(() {});
    } catch (_) {
      // Silent fail
    }
  }
  
  Widget _buildNotificationsList(
    List<AppNotification> items,
    Map<String, Map<String, dynamic>>? docMap,
  ) {
    // Filter out report notifications if user is not owner
    final filteredItems = items.where((n) {
      if (n.type == 'report' && !_isOwner) {
        return false; // Hide report notifications from non-owners
      }
      return true;
    }).toList();
    return filteredItems.isEmpty
        ? const Center(
            child: Text(
              'No notifications yet',
              style: TextStyle(color: Colors.white70),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: filteredItems.length,
            separatorBuilder: (_, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final n = filteredItems[i];
              final docData = docMap?[n.id.toString()];
              return _buildNotificationItem(context, n, docData);
            },
          );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    AppNotification n,
    Map<String, dynamic>? docData,
  ) {
    // Check if this is a report notification by checking the notification data
    final isReport = n.type == 'report';
    
    if (isReport && widget.projectId != null && docData != null) {
      return _buildReportNotification(context, n, docData);
    }
    
              return Container(
                decoration: BoxDecoration(
                  color: surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderDark, width: 1.1),
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel(n.type),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      n.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _timeLabel(n.date),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              );
  }

  Widget _buildReportNotification(
    BuildContext context,
    AppNotification n,
    Map<String, dynamic> data,
  ) {
    final reporterName = data['reporterName'] as String? ?? 'Unknown';
    final reportedUserName = data['reportedUserName'] as String?;
    final reporterUid = data['reporterUid'] as String?;
    final reportedUserUid = data['reportedUserUid'] as String?;
    final reason = data['reason'] as String? ?? '';
    final messageText = data['messageText'] as String?;
    
    return Container(
          decoration: BoxDecoration(
            color: surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderDark, width: 1.1),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REPORT',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildClickableName(
                    context,
                    reporterName,
                    reporterUid,
                    Colors.blueAccent,
                  ),
                  const Text(
                    ' reported ',
                    style: TextStyle(color: Colors.white70, fontSize: 14.5),
                  ),
                  if (reportedUserName != null)
                    _buildClickableName(
                      context,
                      reportedUserName,
                      reportedUserUid,
                      Colors.red,
                    )
                  else
                    const Text(
                      'content',
                      style: TextStyle(color: Colors.white70, fontSize: 14.5),
                    ),
                ],
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Reason: $reason',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (messageText != null && messageText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: surfaceDarker,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderDark),
                  ),
                  child: Text(
                    messageText,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _timeLabel(n.date),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildClickableName(
    BuildContext context,
    String name,
    String? uid,
    Color color,
  ) {
    return GestureDetector(
      onTap: uid != null && widget.projectId != null
          ? () => _openMemberProfile(context, uid)
          : null,
      child: Text(
        name,
        style: TextStyle(
          color: color,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _openMemberProfile(BuildContext context, String uid) async {
    if (widget.projectId == null) return;
    
    try {
      // Get team member by UID
      final fs = FirebaseFirestore.instance;
      final teamDoc = await fs
          .collection('projects')
          .doc(widget.projectId)
          .collection('team')
          .doc(uid)
          .get();
      
      if (!teamDoc.exists || !context.mounted) return;
      
      final data = teamDoc.data()!;
      final member = TeamMemberFirestore.fromMap(data);
      
      // Open profile directly using the same navigation pattern as TeamPanel
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 520),
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            return _MemberProfilePage(
              member: member,
              projectId: widget.projectId!,
              memberUid: uid,
              ownerUid: widget.ownerUid,
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
    } catch (_) {
      // Silent fail
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.projectId == null) {
      return PanelScaffold(
        title: 'Notifications',
        onClose: widget.onClose,
        child: _buildNotificationsList(const [], null),
      );
    }
    
    return PanelScaffold(
      title: 'Notifications',
      onClose: widget.onClose,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .doc(widget.projectId)
            .collection('notifications')
            .orderBy('date', descending: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          List<AppNotification> items;
          Map<String, Map<String, dynamic>>? docMap;
          
          if (snapshot.hasData) {
            // Stream has data - use it (even if empty, that's the real state)
            items = snapshot.data!.docs
                .map((d) => AppNotificationFirestore.fromMap(d.id, d.data()))
                .toList();
            // Pass document snapshots for report notifications
            docMap = <String, Map<String, dynamic>>{};
            for (final doc in snapshot.data!.docs) {
              docMap[doc.id] = doc.data();
            }
          } else if (snapshot.hasError) {
            // On error, try repository fallback
            items = NotificationsRepository.instance.notificationsFor(widget.projectId!);
            docMap = null;
          } else {
            // Waiting or no data yet, use repository as fallback for instant loading
            items = NotificationsRepository.instance.notificationsFor(widget.projectId!);
            docMap = null;
          }
          
          return _buildNotificationsList(items, docMap);
        },
      ),
    );
  }

  String _typeLabel(String raw) {
    switch (raw) {
      case 'schedule':
        return 'SCHEDULE';
      case 'billing':
        return 'BILLING';
      case 'stock':
        return 'STOCK';
      default:
        return raw.toUpperCase();
    }
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt).inMinutes;
    if (diff < 1) return 'Just now';
    if (diff < 60) return '${diff}m ago';
    final hours = now.difference(dt).inHours;
    if (hours < 24) return '${hours}h ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// Profile page widget for opening member profiles from notifications
class _MemberProfilePage extends StatefulWidget {
  const _MemberProfilePage({
    required this.member,
    required this.projectId,
    required this.memberUid,
    this.ownerUid,
  });
  final TeamMember member;
  final String projectId;
  final String memberUid;
  final String? ownerUid; // Project owner UID for instant ownership check

  @override
  State<_MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<_MemberProfilePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragX = 0;
  bool _dragging = false;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() => setState(() {}));
    _checkOwnership();
  }

  void _checkOwnership() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    _isOwner = widget.ownerUid != null && currentUid != null && widget.ownerUid == currentUid;
    setState(() {});
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
                child: _NotificationMemberProfileView(
                  member: member,
                  projectId: widget.projectId,
                  isOwner: _isOwner,
                  memberUid: widget.memberUid,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationMemberProfileView extends StatelessWidget {
  const _NotificationMemberProfileView({
    required this.member,
    required this.projectId,
    required this.isOwner,
    required this.memberUid,
  });
  final TeamMember member;
  final String projectId;
  final bool isOwner;
  final String memberUid;
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationMemberHeroCard(member: member),
          const SizedBox(height: 24),
          _NotificationMemberInfoCard(
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

class _NotificationMemberHeroCard extends StatelessWidget {
  const _NotificationMemberHeroCard({required this.member});
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
          _NotificationMemberAvatar(name: member.name, photoAsset: member.photoAsset),
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

class _NotificationMemberAvatar extends StatelessWidget {
  const _NotificationMemberAvatar({required this.name, this.photoAsset});
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

class _NotificationMemberInfoCard extends StatelessWidget {
  const _NotificationMemberInfoCard({
    required this.member,
    required this.projectId,
    required this.isOwner,
    required this.memberUid,
  });
  final TeamMember member;
  final String projectId;
  final bool isOwner;
  final String memberUid;
  
  Future<void> _kickMember(BuildContext context) async {
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
      final fs = FirebaseFirestore.instance;
      final projectRef = fs.collection('projects').doc(projectId);
      
      await fs.runTransaction((tx) async {
        final snap = await tx.get(projectRef);
        if (!snap.exists) return;
        
        final data = snap.data()!;
        final members = (data['members'] as List?)?.cast<String>() ?? <String>[];
        if (!members.contains(memberUid)) return;
        
        tx.update(projectRef, {
          'members': FieldValue.arrayRemove([memberUid]),
          'teamTotal': FieldValue.increment(-1),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        
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
          if (isOwner) ...[
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
