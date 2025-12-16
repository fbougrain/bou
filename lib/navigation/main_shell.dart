import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pages/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../pages/project_page.dart';
import '../models/project.dart';
import '../pages/media_page.dart';
import '../pages/profile_page.dart';
import '../pages/tasks_page.dart';
import '../pages/stock_page.dart';
import '../pages/forms_page.dart';
import '../pages/billing_page.dart';
import '../panels/chat_panel.dart';
import '../panels/notifications_panel.dart';
import '../panels/team_panel.dart';
import '../overlays/overlay_constants.dart';
import '../panels/projects_panel.dart';
// overlay_constants no longer needed directly here
import '../overlays/overlay_controller.dart';
import '../panels/widgets/animated_scrim.dart';
import '../data/profile_repository.dart';
import 'main_sections.dart';
import 'secondary_tabs.dart';
import 'main_bottom_nav.dart';
import '../widgets/appear_fade.dart';
import '../widgets/header_bar.dart';
import '../widgets/overlay_notice.dart' show showQueuedOverlayNotice, showOverlayNotice;
import '../data/initial_data.dart';
import '../data/task_repository.dart';
import '../data/stock_repository.dart';
import '../data/billing_repository.dart';
import '../data/forms_repository.dart';
import '../data/team_repository.dart';
import '../data/chat_repository.dart';
import '../data/media_repository.dart';
import '../data/notifications_repository.dart';
import '../data/project_repository.dart';
// sample_data removed (no longer needed at shell init for demo seeding)

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialProject});
  final Project? initialProject;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  // Key to compute local positions relative to the constrained mobile viewport
  final GlobalKey _shellAreaKey = GlobalKey();
  MainSection _section = MainSection.home;
  late final OverlayController _overlay;
  // Navigation animation direction: -1 (left), +1 (right), 0 (crossfade)
  int _navDir = 0;
  late Project _selectedProject = widget.initialProject ?? Project(
    id: 'demo-site-placeholder',
    name: 'Demo Site',
    location: 'Demo',
    startDate: DateTime.now().subtract(const Duration(days: 7)),
    endDate: DateTime.now().add(const Duration(days: 90)),
    progressPercent: 0,
    lateTasks: 0,
    incidentCount: 0,
    teamOnline: 0,
    teamTotal: 0,
    status: ProjectStatus.active,
    budgetTotal: null,
    budgetSpent: null,
    description: 'Personal sandbox project.',
  );
  String? _selectedProjectOwnerUid; // Cached ownerUid for instant access
  StreamSubscription<List<Project>>? _projectMembershipSub;

  // Right side overlays (chat/notifications/team)
  bool _openingRight = false;
  double? _openRightStart;
  bool _closingRight = false;
  double? _closeRightStart;
  bool _teamProfileActive =
      false; // when true, suppress right overlay close gestures
  bool _chatComposeActive =
      false; // when true, suppress right overlay close gestures for chats
  // Left side overlay (projects)
  bool _openingLeft = false;
  double? _openLeftStart;
  bool _closingLeft = false;
  double? _closeLeftStart;
  bool get _isProjects => _overlay.active == OverlayType.projects;

  // Pending direction-based open (used when both edge zones overlap, e.g. 100% width)
  bool _pendingDirectionalOpen = false;
  double? _pendingStartX;

  @override
  void initState() {
    super.initState();
    _overlay = OverlayController(vsync: this);
    // Seed initial in-memory repositories so pages show data regardless of navigation order.
  seedInitialDataForProjects([_selectedProject]);
    // Hydrate and start listeners for the initially selected project
    _hydrateAndListen(_selectedProject.id);
    _loadOwnerUid(_selectedProject.id);
  }
  
  Future<void> _loadOwnerUid(String projectId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId)
          .get();
      if (doc.exists && mounted) {
        _selectedProjectOwnerUid = doc.data()?['ownerUid'] as String?;
      }
    } catch (_) {
      // Silent fail
    }
  }

  @override
  void dispose() {
    _projectMembershipSub?.cancel();
    _overlay.dispose();
    super.dispose();
  }

  void _unfocusAndHideKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    // Hide software keyboard on mobile platforms; safe no-op on desktop.
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _openOverlay(OverlayType type) {
    // Ensure background inputs stop receiving text when an overlay opens
    _unfocusAndHideKeyboard();
    setState(() => _overlay.open(type));
  }

  void _closeOverlay() => setState(() => _overlay.close());
  bool get _overlayOpen => _overlay.active != null;

  void _goToSection(MainSection next) {
    if (next == _section) return;
    final oldIndex = _section.index;
    final newIndex = next.index;
    final dir = newIndex == oldIndex ? 0 : (newIndex > oldIndex ? 1 : -1);
    setState(() {
      _navDir = dir;
      _section = next;
    });
  }

  Widget _header(BuildContext context) => HeaderBar(
    projectName: _selectedProject.name,
    onOpenProjects: () => _openOverlay(OverlayType.projects),
    onOpenTeam: () => _openOverlay(OverlayType.team),
    onOpenNotifications: () => _openOverlay(OverlayType.notifications),
    onOpenChat: () => _openOverlay(OverlayType.chat),
  );

  Widget get _secondaryTabs =>
      SecondaryTabs(current: _section, onSelect: _goToSection);
  Widget get _bottomNav =>
      MainBottomNav(current: _section, onSelect: _goToSection);

  ValueKey<String> _pageKey(String suffix) =>
      ValueKey('${_selectedProject.id}::$suffix');

  Widget _currentPage() {
    final primary = [
      HomePage(key: _pageKey('home'), project: _selectedProject),
      ProjectPage(key: _pageKey('project'), project: _selectedProject),
      MediaPage(key: _pageKey('media'), project: _selectedProject),
      ProfilePage(key: _pageKey('profile')),
    ];
    if (_section.index < primary.length) return primary[_section.index];
    switch (_section) {
      case MainSection.tasks:
        return TasksPage(key: _pageKey('tasks'), project: _selectedProject);
      case MainSection.stocks:
        return StockPage(key: _pageKey('stocks'), project: _selectedProject);
      case MainSection.forms:
        return FormsPage(key: _pageKey('forms'), project: _selectedProject);
      case MainSection.billing:
        return BillingPage(key: _pageKey('billing'), project: _selectedProject);
      default:
        return const SizedBox.shrink();
    }
  }

  // Removed legacy dialog method; projects now a slide panel
  // Legacy dialog versions removed for notifications & team (now slide overlays).

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final double openEdge = width * OverlayConstants.openEdgeFraction;
        final double closeEdge = width * OverlayConstants.closeEdgeFraction;
        return Center(
          child: SizedBox(
            width: width,
            child: ClipRect(
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _overlay.animation,
                    builder: (context, _) {
                      // Block background interactions only while the overlay is not fully hidden.
                      // Using the animation value avoids relying on _active's nulling timing.
                      final overlayActive = _overlay.animation.value < 1.0;
                      return AbsorbPointer(
                        absorbing: overlayActive,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: (d) {
                            if (_overlayOpen) return;
                            // Convert global x to local x within the constrained viewport
                            double x = d.globalPosition.dx;
                            final box =
                                _shellAreaKey.currentContext?.findRenderObject()
                                    as RenderBox?;
                            if (box != null && box.hasSize) {
                              final left = box.localToGlobal(Offset.zero).dx;
                              x = d.globalPosition.dx - left;
                            }
                            final bool leftCandidate = x <= openEdge;
                            final bool rightCandidate = x >= width - openEdge;

                            OverlayType? sideToOpen;
                            bool openLeft = false;
                            bool openRight = false;

                            if (leftCandidate && rightCandidate) {
                              // Full overlap case. Defer choosing side until user indicates direction.
                              _pendingDirectionalOpen = true;
                              _pendingStartX = x;
                            } else if (leftCandidate) {
                              openLeft = true;
                            } else if (rightCandidate) {
                              openRight = true;
                            }

                            if (openLeft) {
                              sideToOpen = OverlayType.projects;
                              _openingLeft = true;
                              _openLeftStart = x;
                            } else if (openRight) {
                              sideToOpen = OverlayType.chat;
                              _openingRight = true;
                              _openRightStart = x;
                            }

                            if (sideToOpen != null) {
                              // Dismiss any focused text fields before beginning to open
                              _unfocusAndHideKeyboard();
                              _overlay.beginInteractiveOpen(sideToOpen);
                              _overlay.interactiveSetProgress(1.0);
                            }
                          },
                          onHorizontalDragUpdate: (d) {
                            if (_pendingDirectionalOpen) {
                              // Compute local move
                              final box =
                                  _shellAreaKey.currentContext
                                          ?.findRenderObject()
                                      as RenderBox?;
                              final current = (box != null && box.hasSize)
                                  ? d.globalPosition.dx -
                                        box.localToGlobal(Offset.zero).dx
                                  : d.globalPosition.dx;
                              final start = _pendingStartX ?? current;
                              final dx = current - start;
                              // Use small hysteresis so micro jiggle doesn't trigger.
                              const double dirThreshold = 6; // px
                              if (dx.abs() > dirThreshold) {
                                // Decide direction once.
                                _pendingDirectionalOpen = false;
                                if (dx > 0) {
                                  // Dragging right: open left-side (projects) panel
                                  _unfocusAndHideKeyboard();
                                  _openingLeft = true;
                                  _openLeftStart = start;
                                  _overlay.beginInteractiveOpen(
                                    OverlayType.projects,
                                  );
                                  _overlay.interactiveSetProgress(1.0);
                                } else {
                                  // Dragging left: open right-side (chat) panel
                                  _unfocusAndHideKeyboard();
                                  _openingRight = true;
                                  _openRightStart = start;
                                  _overlay.beginInteractiveOpen(
                                    OverlayType.chat,
                                  );
                                  _overlay.interactiveSetProgress(1.0);
                                }
                              } else {
                                return; // still determining direction
                              }
                            }
                            if (_openingLeft) {
                              final box =
                                  _shellAreaKey.currentContext
                                          ?.findRenderObject()
                                      as RenderBox?;
                              final current = (box != null && box.hasSize)
                                  ? d.globalPosition.dx -
                                        box.localToGlobal(Offset.zero).dx
                                  : d.globalPosition.dx;
                              final delta =
                                  current - (_openLeftStart ?? current);
                              double progress = delta / width;
                              if (progress < 0) progress = 0;
                              if (progress > 1) progress = 1;
                              setState(
                                () => _overlay.interactiveSetProgress(
                                  1 - progress,
                                ),
                              );
                            } else if (_openingRight) {
                              final box =
                                  _shellAreaKey.currentContext
                                          ?.findRenderObject()
                                      as RenderBox?;
                              final current = (box != null && box.hasSize)
                                  ? d.globalPosition.dx -
                                        box.localToGlobal(Offset.zero).dx
                                  : d.globalPosition.dx;
                              final delta =
                                  (_openRightStart ?? current) - current;
                              double progress = delta / width;
                              if (progress < 0) progress = 0;
                              if (progress > 1) progress = 1;
                              setState(
                                () => _overlay.interactiveSetProgress(
                                  1 - progress,
                                ),
                              );
                            }
                          },
                          onHorizontalDragEnd: (_) {
                            if (_pendingDirectionalOpen) {
                              // User released before establishing direction; just reset.
                              _pendingDirectionalOpen = false;
                              _pendingStartX = null;
                            }
                            if (_openingLeft || _openingRight) {
                              _overlay.commitOrRevertOpen();
                              _openingLeft = false;
                              _openingRight = false;
                              _pendingStartX = null;
                              setState(() {});
                            }
                          },
                          child: Scaffold(
                            key: _shellAreaKey,
                            body: SafeArea(
                              child: Column(
                                children: [
                                  _header(context),
                                  _secondaryTabs,
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeOutCubic,
                                      layoutBuilder:
                                          AnimatedSwitcher.defaultLayoutBuilder,
                                      transitionBuilder: (child, animation) {
                                        // Determine if this child is incoming based on the key
                                        final isIncoming =
                                            (child.key
                                                is ValueKey<MainSection>) &&
                                            (child.key as ValueKey<MainSection>)
                                                    .value ==
                                                _section;
                                        final curved = CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutCubic,
                                          reverseCurve: Curves.easeOutCubic,
                                        );
                                        // Slide direction depends on nav direction and whether child is incoming/outgoing
                                        Offset beginOffset;
                                        if (_navDir == 0) {
                                          beginOffset = const Offset(0, 0);
                                        } else if (isIncoming) {
                                          // Incoming comes from the side of travel
                                          beginOffset = Offset(
                                            _navDir > 0 ? 0.12 : -0.12,
                                            0,
                                          );
                                        } else {
                                          // Outgoing exits opposite side
                                          beginOffset = Offset(
                                            _navDir > 0 ? -0.12 : 0.12,
                                            0,
                                          );
                                        }
                                        final slide = Tween<Offset>(
                                          begin: beginOffset,
                                          end: Offset.zero,
                                        ).animate(curved);
                                        // Use the provided animation for both incoming and outgoing;
                                        // for outgoing, AnimatedSwitcher supplies a reverse animation automatically.
                                        final fade = curved;
                                        return FadeTransition(
                                          opacity: fade,
                                          child: SlideTransition(
                                            position: slide,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: KeyedSubtree(
                                        key: ValueKey<MainSection>(_section),
                                        child: Builder(
                                          builder: (context) {
                                            final page = _currentPage();
                                            if (_section ==
                                                MainSection.profile) {
                                              // Profile already has an internal fade; keep a single wrapper.
                                              return AppearFade(child: page);
                                            }
                                            // Double on-appear fade for non-profile pages to match Profile's softer feel.
                                            return AppearFade(
                                              child: AppearFade(child: page),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            bottomNavigationBar: _bottomNav,
                          ),
                        ),
                      );
                    },
                  ),
                  AnimatedScrim(
                    controller: _overlay.animation,
                    chatOpen: _overlayOpen,
                    onTap: _closeOverlay,
                  ),
                  if (_overlayOpen || _openingLeft || _openingRight)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _overlay.animation,
                        builder: (context, _) {
                          final v = _overlay.animation.value;
                          final dx = (_isProjects ? -1 : 1) * width * v;
                          return Focus(
                            autofocus: true,
                            canRequestFocus: true,
                            child: Transform.translate(
                              offset: Offset(dx, 0),
                              child: Stack(
                                children: [
                                  _buildActivePanel(),
                                  if ((_overlayOpen ||
                                          _overlay.animation.value < 1.0) &&
                                      !_isProjects &&
                                      !_teamProfileActive &&
                                      !_chatComposeActive)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      width: closeEdge,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragStart: (d) {
                                          if (_overlay.animation.isAnimating) {
                                            (_overlay.animation
                                                    as AnimationController)
                                                .stop();
                                          }
                                          if (_overlay.animation.value == 0) {
                                            _closingRight = true;
                                            final box =
                                                _shellAreaKey.currentContext
                                                        ?.findRenderObject()
                                                    as RenderBox?;
                                            final current =
                                                (box != null && box.hasSize)
                                                ? d.globalPosition.dx -
                                                      box
                                                          .localToGlobal(
                                                            Offset.zero,
                                                          )
                                                          .dx
                                                : d.globalPosition.dx;
                                            _closeRightStart = current;
                                          }
                                        },
                                        onHorizontalDragUpdate: (d) {
                                          if (_closingRight) {
                                            final box =
                                                _shellAreaKey.currentContext
                                                        ?.findRenderObject()
                                                    as RenderBox?;
                                            final current =
                                                (box != null && box.hasSize)
                                                ? d.globalPosition.dx -
                                                      box
                                                          .localToGlobal(
                                                            Offset.zero,
                                                          )
                                                          .dx
                                                : d.globalPosition.dx;
                                            final delta =
                                                current -
                                                (_closeRightStart ?? current);
                                            double progress = delta / width;
                                            if (progress < 0) progress = 0;
                                            if (progress > 1) progress = 1;
                                            setState(
                                              () => _overlay.updateDragClose(
                                                progress,
                                              ),
                                            );
                                          }
                                        },
                                        onHorizontalDragEnd: (_) {
                                          if (_closingRight) {
                                            _closingRight = false;
                                            _overlay.commitOrRevertClose();
                                            setState(() {});
                                          }
                                        },
                                      ),
                                    ),
                                  if ((_overlayOpen ||
                                          _overlay.animation.value < 1.0) &&
                                      _isProjects)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      width: closeEdge,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragStart: (d) {
                                          if (_overlay.animation.isAnimating) {
                                            (_overlay.animation
                                                    as AnimationController)
                                                .stop();
                                          }
                                          if (_overlay.animation.value == 0) {
                                            _closingLeft = true;
                                            final box =
                                                _shellAreaKey.currentContext
                                                        ?.findRenderObject()
                                                    as RenderBox?;
                                            final current =
                                                (box != null && box.hasSize)
                                                ? d.globalPosition.dx -
                                                      box
                                                          .localToGlobal(
                                                            Offset.zero,
                                                          )
                                                          .dx
                                                : d.globalPosition.dx;
                                            _closeLeftStart = current;
                                          }
                                        },
                                        onHorizontalDragUpdate: (d) {
                                          if (_closingLeft) {
                                            final box =
                                                _shellAreaKey.currentContext
                                                        ?.findRenderObject()
                                                    as RenderBox?;
                                            final current =
                                                (box != null && box.hasSize)
                                                ? d.globalPosition.dx -
                                                      box
                                                          .localToGlobal(
                                                            Offset.zero,
                                                          )
                                                          .dx
                                                : d.globalPosition.dx;
                                            final delta =
                                                (_closeLeftStart ?? current) -
                                                current; // drag left
                                            double progress = delta / width;
                                            if (progress < 0) progress = 0;
                                            if (progress > 1) progress = 1;
                                            setState(
                                              () => _overlay.updateDragClose(
                                                progress,
                                              ),
                                            );
                                          }
                                        },
                                        onHorizontalDragEnd: (_) {
                                          if (_closingLeft) {
                                            _closingLeft = false;
                                            _overlay.commitOrRevertClose();
                                            setState(() {});
                                          }
                                        },
                                      ),
                                    ),
                                ],
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
        );
      },
    );
  }

  Widget _buildActivePanel() {
    switch (_overlay.active) {
      case OverlayType.notifications:
        return NotificationsPanel(
          onClose: _closeOverlay,
          projectId: _selectedProject.id,
          ownerUid: _selectedProjectOwnerUid,
        );
      case OverlayType.team:
        return TeamPanel(
          onClose: _closeOverlay,
          project: _selectedProject,
          ownerUid: _selectedProjectOwnerUid,
          onProfileActiveChanged: (active) {
            setState(() => _teamProfileActive = active);
          },
        );
      case OverlayType.chat:
        return ChatPanel(
          onClose: _closeOverlay,
          projectId: _selectedProject.id,
          projectName: _selectedProject.name,
          onComposeActiveChanged: (active) {
            setState(() => _chatComposeActive = active);
          },
        );
      case OverlayType.projects:
        return ProjectsPanel(
          onClose: _closeOverlay,
            onProjectSelected: (project) {
              // Seed repositories for the newly selected project if needed
              final oldId = _selectedProject.id;
              _stopAllListeners(oldId);
              seedInitialDataForProjects([project]);
              setState(() => _selectedProject = project);
              _hydrateAndListen(project.id);
              _loadOwnerUid(project.id);
              _persistLastProjectId(project.id);
              // Navigate to the Home page for the selected project
              _goToSection(MainSection.home);
              _closeOverlay();
              // If a notice was queued from the panel (e.g., created/left), show it on the new page
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) showQueuedOverlayNotice(context);
              });
            },
        );
      case null:
        return const SizedBox.shrink();
    }
  }
  Future<void> _hydrateAndListen(String projectId) async {
    try {
      await TaskRepository.instance.loadFromFirestore(projectId);
      await StockRepository.instance.loadFromFirestore(projectId);
      await BillingRepository.instance.loadFromFirestore(projectId);
      await FormsRepository.instance.loadFromFirestore(projectId);
      await TeamRepository.instance.loadFromFirestore(projectId);
      await ChatRepository.instance.loadFromFirestore(projectId);
      await MediaRepository.instance.loadFromFirestore(projectId);
      await NotificationsRepository.instance.loadFromFirestore(projectId);
      TaskRepository.instance.listenTo(projectId);
      StockRepository.instance.listenTo(projectId);
      BillingRepository.instance.listenTo(projectId);
      FormsRepository.instance.listenTo(projectId);
      TeamRepository.instance.listenTo(projectId);
      ChatRepository.instance.listenTo(projectId);
      MediaRepository.instance.listenTo(projectId);
      NotificationsRepository.instance.listenTo(projectId);
      
      // Listen for membership changes - if current user is removed, forward to nearby project
      _projectMembershipSub?.cancel();
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        // Listen to user's projects list instead of the project document
        // This way we can detect when the current project is no longer in the list
        _projectMembershipSub = ProjectRepository.instance.myProjects().listen((projects) {
          if (!mounted) return;
          // Check if current project is still in the user's projects list
          final stillMember = projects.any((p) => p.id == _selectedProject.id);
          if (!stillMember) {
            // Current user was removed from this project, find another project
            _forwardToNearbyProject(projects);
          }
        }, onError: (_) {
          // Silently handle permission errors
        });
      }
    } catch (_) {
      // StreamBuilder handles updates automatically, no need to force rebuild
    }
  }
  
  Future<void> _forwardToNearbyProject(List<Project>? projectsList) async {
    try {
      if (projectsList == null || projectsList.isEmpty) {
        // If no projects provided, try to get them
        projectsList = await ProjectRepository.instance.myProjects().first;
      }
      if (projectsList.isEmpty) return;
      
      // Find a project that's not the current one
      final otherProject = projectsList.firstWhere(
        (p) => p.id != _selectedProject.id,
        orElse: () => projectsList!.first,
      );
      
      if (mounted && otherProject.id != _selectedProject.id) {
        // Switch to the nearby project
        final oldId = _selectedProject.id;
        _stopAllListeners(oldId);
        seedInitialDataForProjects([otherProject]);
        setState(() => _selectedProject = otherProject);
        _hydrateAndListen(otherProject.id);
        _loadOwnerUid(otherProject.id);
        _persistLastProjectId(otherProject.id);
        _goToSection(MainSection.home);
        
        // Show notice
        showOverlayNotice(
          context,
          'You were removed from the project',
          duration: const Duration(milliseconds: 2000),
          liftAboveNav: true,
        );
      }
    } catch (_) {
      // Silent fail
    }
  }

  void _stopAllListeners(String projectId) {
    _projectMembershipSub?.cancel();
    _projectMembershipSub = null;
    TaskRepository.instance.stopListening(projectId);
    StockRepository.instance.stopListening(projectId);
    BillingRepository.instance.stopListening(projectId);
    FormsRepository.instance.stopListening(projectId);
    TeamRepository.instance.stopListening(projectId);
    ChatRepository.instance.stopListening(projectId);
    MediaRepository.instance.stopListening(projectId);
    NotificationsRepository.instance.stopListening(projectId);
  }

  Future<void> _persistLastProjectId(String id) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      // Don't persist if account deletion is in progress
      if (ProfileRepository.instance.isDeleting) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'lastProjectId': id,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
