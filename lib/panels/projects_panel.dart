import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import 'package:flutter/services.dart';
import '../utils/money.dart';
import 'panel_scaffold.dart';
import '../models/project.dart' show Project, ProjectStatus;
import '../widgets/platform_date_picker.dart';
import '../widgets/status_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../data/project_images.dart';
import '../widgets/overlay_notice.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import '../data/project_repository.dart';
import '../data/initial_data.dart' show isDemoProjectId;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/profile_repository.dart';
import '../data/team_repository.dart';
import '../data/chat_repository.dart';
import '../models/team_member.dart';
import '../models/chat_thread.dart';

class ProjectsPanel extends StatefulWidget {
  const ProjectsPanel({
    super.key,
    required this.onClose,
    required this.onProjectSelected,
  });
  final VoidCallback onClose;
  final ValueChanged<Project> onProjectSelected;
  static void debugResetProjects() => _ProjectsPanelState._resetDemoData();
  @override
  State<ProjectsPanel> createState() => _ProjectsPanelState();
}

class _ProjectsPanelState extends State<ProjectsPanel> {
  static const _imagePath = 'assets/projectpicplaceholder.jpg';

  bool _useFirestore = false;
  StreamSubscription<List<Project>>? _fsSub;
  List<Project> _fsProjects = const [];
  static final Set<String> _optimisticallyRemoved = {};

  static List<_ProjectView> _projects = [];
  static Map<String, _ProjectView> _catalog = {};

  static void _resetDemoData() {
    _projects = [];
    _catalog = {};
  }

  @override
  void initState() {
    super.initState();
    try {
      _useFirestore = Firebase.apps.isNotEmpty;
    } catch (_) {
      _useFirestore = false;
    }
    if (_useFirestore) {
      _fsSub = ProjectRepository.instance.myProjects().listen((projects) {
        if (!mounted) return;
        final filtered = projects.where((p) => !_optimisticallyRemoved.contains(p.id)).toList();
        _optimisticallyRemoved.removeWhere((id) => !projects.any((p) => p.id == id));
        setState(() {
          _fsProjects = filtered;
        });
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _fsSub?.cancel();
    super.dispose();
  }

  Future<void> _pickProjectImage(int index, ImageSource source) async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        setState(() {
          _projects[index] = _projects[index].copyWith(imageBytes: bytes);
          // Also update global store so other panels (e.g., Chats) reflect the change.
          ProjectImages.instance.set(_projects[index].name, bytes);
        });
      }
    } on MissingPluginException catch (e) {
      if (!mounted) return;
      showOverlayNotice(
        context,
        "Image pick unavailable. Restart app. (${e.message})",
        duration: const Duration(milliseconds: 2400),
      );
    } catch (e) {
      if (!mounted) return;
      showOverlayNotice(
        context,
        'Failed to pick image: $e',
        duration: const Duration(milliseconds: 2000),
      );
    }
  }

  void _showImageOptions(int index) {
    final hasImage = _projects[index].imageBytes != null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(AppIcons.camera, color: Colors.white),
                title: const Text('Take photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProjectImage(index, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(AppIcons.folderOpen, color: Colors.white),
                title: const Text('Choose from library', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProjectImage(index, ImageSource.gallery);
                },
              ),
              if (hasImage)
                ListTile(
                  leading: const Icon(AppIcons.delete, color: Colors.redAccent),
                  title: const Text('Remove photo', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    setState(() {
                      _projects[index] = _projects[index].copyWith(clearImage: true);
                      ProjectImages.instance.clear(_projects[index].name);
                    });
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFs = _useFirestore;
  final List<Project> fsListRaw = isFs ? _fsProjects : const <Project>[];
  final List<Project> fsList = (() {
    if (!isFs) return const <Project>[];
    final filtered = fsListRaw.where((p) => !_optimisticallyRemoved.contains(p.id));
    final demo = filtered.where((p) => isDemoProjectId(p.id));
    final rest = filtered.where((p) => !isDemoProjectId(p.id)).toList()
      ..sort((a, b) {
        final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aCreated.compareTo(bCreated); // older first
      });
    return [...demo, ...rest];
  })();
  final Set<String> fsIdsLower = fsList.map((p) => p.id.toLowerCase()).toSet();
  final List<_ProjectView> demoList = _projects.where((v) {
    final idLower = v.toProject().id.toLowerCase();
    return !fsIdsLower.contains(idLower);
  }).toList();
  final int listLength = isFs ? (demoList.length + fsList.length) : demoList.length;
    return PanelScaffold(
      title: 'Projects',
      onClose: widget.onClose,
      side: PanelSide.left,
      fab: SizedBox(
        width: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: const Offset(-5, 5),
                child: _AddButton(
                  onTap: () async {
                    final created = await showModalBottomSheet<_ProjectView>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (ctx) => const _AddProjectSheet(),
                    );
                    if (!context.mounted) return;
                    if (created != null) {
                      final newProj = created.toProject();
                      final newId = newProj.id.toLowerCase();
                      final newName = newProj.name.trim().toLowerCase();
                      if (isFs) {
                        final fsNames = fsList.map((p) => p.name.trim().toLowerCase());
                        final fsIds = fsList.map((p) => p.id.toLowerCase());
                        final demoNames = demoList.map((v) => v.name.trim().toLowerCase());
                        final demoIds = demoList.map((v) => v.toProject().id.toLowerCase());
                        final nameExists = fsNames.contains(newName) || demoNames.contains(newName);
                        final idExists = fsIds.contains(newId) || demoIds.contains(newId);
                        if (nameExists || idExists) {
                          showOverlayNotice(
                            context,
                            nameExists ? 'Project name already exists' : 'Project id already exists',
                            duration: const Duration(milliseconds: 1800),
                            liftAboveNav: false,
                          );
                          return;
                        }
                      } else {
                        final names = _projects.map((v) => v.name.trim().toLowerCase());
                        final ids = _projects.map((v) => v.toProject().id.toLowerCase());
                        final nameExists = names.contains(newName);
                        final idExists = ids.contains(newId);
                        if (nameExists || idExists) {
                          showOverlayNotice(
                            context,
                            nameExists ? 'Project name already exists' : 'Project id already exists',
                            duration: const Duration(milliseconds: 1800),
                            liftAboveNav: false,
                          );
                          return;
                        }
                      }
                      if (isFs) {
                        try {
                          final pInput = created.toProject();
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) return;
                          final fs = FirebaseFirestore.instance;
                          final docRef = fs.collection('projects').doc();
                          final finalId = docRef.id;
                          final now = DateTime.now().toIso8601String();
                          
                          try {
                            // Don't persist if account deletion is in progress
                            if (!ProfileRepository.instance.isDeleting) {
                            await fs.collection('users').doc(uid).set({
                              'lastProjectId': finalId,
                              'updatedAt': now,
                            }, SetOptions(merge: true));
                            }
                          } catch (_) {}
                          
                          await docRef.set({
                            'name': pInput.name,
                            'location': pInput.location ?? '',
                            'startDate': pInput.startDate.toIso8601String(),
                            'endDate': pInput.endDate.toIso8601String(),
                            'status': pInput.status.toString().split('.').last,
                            'budgetTotal': pInput.budgetTotal,
                            'budgetSpent': pInput.budgetSpent,
                            'description': pInput.description ?? '',
                            'progressPercent': pInput.progressPercent,
                            'lateTasks': pInput.lateTasks,
                            'incidentCount': pInput.incidentCount,
                            'teamOnline': 0,
                            'teamTotal': 0,
                            'ownerUid': uid,
                            'members': [uid],
                            'createdAt': now,
                            'updatedAt': now,
                            'version': 1,
                          });
                          
                          final optimisticProject = Project(
                            id: finalId,
                            name: pInput.name,
                            location: pInput.location,
                            startDate: pInput.startDate,
                            endDate: pInput.endDate,
                            progressPercent: pInput.progressPercent,
                            lateTasks: pInput.lateTasks,
                            incidentCount: pInput.incidentCount,
                            teamOnline: 0,
                            teamTotal: 0,
                            status: pInput.status,
                            budgetTotal: pInput.budgetTotal,
                            budgetSpent: pInput.budgetSpent,
                            description: pInput.description,
                            createdAt: DateTime.tryParse(now),
                          );
                          
                          if (!mounted) return;
                          await _persistLastProjectPreference(finalId);
                          widget.onProjectSelected(optimisticProject);
                          if (!context.mounted) return;
                          showOverlayNotice(
                            context,
                            'Project created',
                            duration: const Duration(milliseconds: 1200),
                            liftAboveNav: true,
                          );
                          
                          Future(() async {
                            try {
                              final profile = ProfileRepository.instance.profile;
                              final memberId = DateTime.now().millisecondsSinceEpoch.remainder(1000000000);
                              final tm = TeamMember(
                                id: memberId,
                                name: profile.name.isNotEmpty ? profile.name : uid.substring(0, 6),
                                role: profile.title.isNotEmpty ? profile.title : 'Owner',
                                email: profile.email.isNotEmpty ? profile.email : null,
                                phone: profile.phone.isNotEmpty ? profile.phone : null,
                                country: profile.country.isNotEmpty ? profile.country : null,
                                photoAsset: 'assets/profile_placeholder.jpg',
                                isOnline: true,
                              );
                              TeamRepository.instance.addMemberWithDoc(finalId, uid, tm);
                            } catch (_) {}
                            
                            try {
                              final chatsRef = fs.collection('projects').doc(finalId).collection('chats');
                              final teamThreadRef = chatsRef.doc('team');
                              final teamThreadSnap = await teamThreadRef.get();
                              
                              if (!teamThreadSnap.exists) {
                                final teamThread = ChatThread(
                                  id: 'team',
                                  username: 'Team – ${pInput.name}',
                                  lastMessage: 'Welcome! Share updates and files here.',
                                  lastTime: DateTime.now(),
                                  unreadCount: 0,
                                  avatarAsset: 'assets/projectpicplaceholder.jpg',
                                  isTeam: true,
                                );
                                ChatRepository.instance.createThread(finalId, teamThread);
                              }
                            } catch (_) {}
                          });
                        } catch (e) {
                          if (!context.mounted) return;
                          showOverlayNotice(
                            context,
                            'Failed to create: $e',
                            duration: const Duration(seconds: 2),
                          );
                        }
                      } else {
                        // Demo/local mode: add and immediately navigate to new project's homepage
                        final proj = created.toProject();
                        setState(() {
                          _projects.add(created);
                          _catalog[proj.id] = created;
                        });
                        // Persist preference early (best-effort) so if user later signs in / bootstrap runs it prefers this
                        await _persistLastProjectPreference(proj.id);
                        // Select after setState so navigation logic can seed/hydrate using the full data
                        widget.onProjectSelected(proj);
                      }
                    }
                  },
                ),
              ),
            ),
            Positioned(
              bottom: 76, // Add button height (56) + 20px gap
              left: 0,
              right: 0,
              child: Transform.translate(
                offset: const Offset(-5, 5),
                child: _JoinButton(
                  onTap: () async {
                    final link = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (ctx) => const _JoinProjectSheet(),
                    );
                    if (!context.mounted) return;
                    if (link != null && link.trim().isNotEmpty) {
                      final canonicalSlug = link.split('/').last.trim();
                      final slug = canonicalSlug;
                      if (slug.isEmpty) return;
                      if (isFs) {
                        final fsIds = fsList.map((p) => p.id.toLowerCase()).toSet();
                        final demoIds = demoList.map((v) => v.toProject().id.toLowerCase());
                        if (fsIds.contains(canonicalSlug.toLowerCase()) || demoIds.contains(canonicalSlug.toLowerCase())) {
                          showOverlayNotice(
                            context,
                            'Project already joined',
                            duration: const Duration(milliseconds: 1600),
                            liftAboveNav: false,
                          );
                          return;
                        }
                        try {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) return;
                          final fs = FirebaseFirestore.instance;
                          final docRef = fs.collection('projects').doc(slug);
                          
                          // Update members array immediately (this allows us to read the project)
                          try {
                            await docRef.update({
                              'members': FieldValue.arrayUnion([uid]),
                              'updatedAt': DateTime.now().toIso8601String(),
                            });
                          } on FirebaseException {
                            // If update fails, show error and return
                            if (!context.mounted) return;
                            showOverlayNotice(
                              context,
                              'Project dont exist / Invalid link',
                              duration: const Duration(milliseconds: 1800),
                              liftAboveNav: false,
                            );
                            return;
                          } catch (_) {
                            if (!context.mounted) return;
                            showOverlayNotice(
                              context,
                              'Project dont exist / Invalid link',
                              duration: const Duration(milliseconds: 1800),
                              liftAboveNav: false,
                            );
                            return;
                          }

                          // Try to read the project immediately after adding to members
                          Project? optimisticProject;
                          try {
                            optimisticProject = await ProjectRepository.instance.getById(slug);
                          } catch (_) {
                            // If read fails, try once more after a brief delay
                            try {
                              await Future.delayed(const Duration(milliseconds: 100));
                              optimisticProject = await ProjectRepository.instance.getById(slug);
                            } catch (_) {
                              optimisticProject = null;
                            }
                          }

                          if (optimisticProject != null) {
                            // Navigate immediately with optimistic project
                            if (!context.mounted) return;
                            await _persistLastProjectPreference(slug);
                            if (!context.mounted) return;
                            widget.onProjectSelected(optimisticProject);
                            if (!context.mounted) return;
                            showOverlayNotice(
                              context,
                              'Project joined',
                              duration: const Duration(milliseconds: 1200),
                              liftAboveNav: true,
                            );
                            
                            // Complete remaining setup in background (non-blocking)
                            // Add team member and ensure team conversation exists
                            Future(() async {
                              try {
                                final profile = ProfileRepository.instance.profile;
                                final memberId = DateTime.now().millisecondsSinceEpoch.remainder(1000000000);
                                final tm = TeamMember(
                                  id: memberId,
                                  name: profile.name.isNotEmpty ? profile.name : uid.substring(0, 6),
                                  role: profile.title.isNotEmpty ? profile.title : 'Member',
                                  email: profile.email.isNotEmpty ? profile.email : null,
                                  phone: profile.phone.isNotEmpty ? profile.phone : null,
                                  country: profile.country.isNotEmpty ? profile.country : null,
                                  photoAsset: 'assets/profile_placeholder.jpg',
                                  isOnline: false,
                                );
                                TeamRepository.instance.addMemberWithDoc(slug, uid, tm);
                              } catch (_) {}
                              
                              // Ensure team conversation exists
                              try {
                                final projectData = await docRef.get();
                                final projectName = projectData.data()?['name'] as String? ?? 'Project';
                                final chatsRef = fs.collection('projects').doc(slug).collection('chats');
                                final teamThreadRef = chatsRef.doc('team');
                                final teamThreadSnap = await teamThreadRef.get();
                                
                                if (!teamThreadSnap.exists) {
                                  final teamThread = ChatThread(
                                    id: 'team',
                                    username: 'Team – $projectName',
                                    lastMessage: 'Welcome! Share updates and files here.',
                                    lastTime: DateTime.now(),
                                    unreadCount: 0,
                                    avatarAsset: 'assets/projectpicplaceholder.jpg',
                                    isTeam: true,
                                  );
                                  ChatRepository.instance.createThread(slug, teamThread);
                                }
                              } catch (_) {}
                              
                              // Update teamTotal in background
                              try {
                                await docRef.update({
                                  'teamTotal': FieldValue.increment(1),
                                });
                              } catch (_) {}
                            });
                            return;
                          }

                          // Fallback: if we couldn't read the project, wait for stream
                          // This should rarely happen, but handle it gracefully
                          final completer = Completer<Project?>();
                          late StreamSubscription<List<Project>> sub;
                          sub = ProjectRepository.instance.myProjects().listen((projects) {
                            final matches = projects.where((p) => p.id == slug).toList();
                            if (matches.isNotEmpty) {
                              completer.complete(matches.first);
                              sub.cancel();
                            }
                          }, onError: (_) {
                            completer.complete(null);
                            sub.cancel();
                          });

                          Project? found;
                          try {
                            found = await completer.future.timeout(const Duration(seconds: 3));
                          } catch (_) {
                            found = null;
                          } finally {
                            await sub.cancel();
                          }

                          if (found != null) {
                            try {
                              await _persistLastProjectPreference(found.id);
                            } catch (_) {}
                            if (!context.mounted) return;
                            widget.onProjectSelected(found);
                            showOverlayNotice(
                              context,
                              'Project joined',
                              duration: const Duration(milliseconds: 1200),
                              liftAboveNav: true,
                            );
                          } else {
                            if (!context.mounted) return;
                            showOverlayNotice(
                              context,
                              'Project joined (loading details...)',
                              duration: const Duration(milliseconds: 1200),
                              liftAboveNav: true,
                            );
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          showOverlayNotice(
                            context,
                            'Project dont exist / Invalid link',
                            duration: const Duration(milliseconds: 1800),
                            liftAboveNav: false,
                          );
                        }
                      } else {
                        // Prevent duplicate join
                        final ids = {for (final p in _projects) p.toProject().id};
                        if (ids.contains(slug)) {
                          showOverlayNotice(
                            context,
                            'Project already joined',
                            duration: const Duration(milliseconds: 1600),
                            liftAboveNav: false,
                          );
                          return;
                        }
                        final canonical = _catalog[slug];
                        if (canonical == null) {
                          showOverlayNotice(
                            context,
                            'Invalid or unknown project link',
                            duration: const Duration(milliseconds: 2000),
                            liftAboveNav: false,
                          );
                          return;
                        }
                        final joined = canonical.copyWith(readOnly: true);
                        setState(() => _projects.insert(0, joined));
                        widget.onProjectSelected(_projects.first.toProject());
                      }
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: (isFs ? (fsList.isEmpty && demoList.isEmpty) : demoList.isEmpty)
            ? const Center(
                child: Text(
                  'No projects yet',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : ListView.separated(
                itemCount: listLength,
                separatorBuilder: (_, unused) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _ProjectCard(
          data: isFs
            ? (i < demoList.length
              ? demoList[i]
              : _fromProject(fsList[i - demoList.length]))
            : demoList[i],
                  onTap: () => widget.onProjectSelected(
                    isFs
                        ? (i < demoList.length
                            ? demoList[i].toProject()
                            : fsList[i - demoList.length])
                        : demoList[i].toProject(),
                  ),
          onChangeImage: isFs
            ? (i < demoList.length
              ? () {
                  final id = demoList[i].toProject().id.toLowerCase();
                  final idx = _projects.indexWhere((v) => v.toProject().id.toLowerCase() == id);
                  if (idx != -1) _showImageOptions(idx);
                }
              : () => _showImageOptionsFs(fsList[i - demoList.length]))
            : () => _showImageOptions(i),
                  onEdit: () async {
                    final result = await showModalBottomSheet<_EditAction>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: surfaceDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (ctx) {
                        final bool itemIsFs = isFs && i >= demoList.length;
                        final _ProjectView view = itemIsFs
                            ? _fromProject(fsList[i - demoList.length])
                            : demoList[i];
                        return _EditProjectSheet(
                          initial: view,
                          canLeave: listLength > 1,
                          readOnly: false,
                        );
                      },
                    );
                    if (!context.mounted) return; // Guard BuildContext after async gap
                    if (result == null) return;
                    if (result.leave) {
                      if (isFs && i >= demoList.length) {
                        try {
                          final fsIndex = i - demoList.length;
                          final id = fsList[fsIndex].id;
                          final repo = ProjectRepository.instance;
                          // Pre-select neighbor project (next if available, else previous) before deletion to avoid
                          // lingering listeners hitting a now-deleted project's subcollections (permission-denied spam).
                          Project? neighbor;
                          final visible = [
                            ...demoList.map((v) => v.toProject()),
                            ...fsList,
                          ];
                          if (visible.length > 1) {
                            if (i + 1 < visible.length) {
                              neighbor = visible[i + 1];
                            } else if (i - 1 >= 0) {
                              neighbor = visible[i - 1];
                            }
                          }
                          
                          // Check if last user before navigation to determine notice message
                          final lastUser = await repo.canDelete(id);
                          
                          // Optimistically remove from local state immediately for instant UI update
                          setState(() {
                            _optimisticallyRemoved.add(id);
                            final indexToRemove = _fsProjects.indexWhere((p) => p.id == id);
                            if (indexToRemove != -1) {
                              _fsProjects = List.from(_fsProjects)..removeAt(indexToRemove);
                            }
                          });
                          
                          if (neighbor != null) {
                            widget.onProjectSelected(neighbor);
                          }
                          
                          // Show notice immediately after navigation (optimistic UI)
                          if (!context.mounted) return;
                          showOverlayNotice(
                            context,
                            lastUser ? 'Project deleted' : 'Project left',
                            duration: const Duration(milliseconds: 1200),
                            liftAboveNav: true,
                          );
                          
                          // Perform deletion/leave in background - stream will update when complete
                          if (lastUser) {
                            repo.delete(id).catchError((e) {
                              // If deletion fails, remove from optimistic set so stream can restore it
                              if (!mounted) return;
                              final ctx = context;
                              if (!ctx.mounted) return;
                              setState(() {
                                _optimisticallyRemoved.remove(id);
                              });
                              if (!ctx.mounted) return;
                              showOverlayNotice(
                                ctx,
                                'Failed to delete: $e',
                                duration: const Duration(seconds: 2),
                              );
                            });
                          } else {
                            repo.leave(id).catchError((e) {
                              // If leave fails, remove from optimistic set so stream can restore it
                              if (!mounted) return;
                              final ctx = context;
                              if (!ctx.mounted) return;
                              setState(() {
                                _optimisticallyRemoved.remove(id);
                              });
                              if (!ctx.mounted) return;
                              showOverlayNotice(
                                ctx,
                                'Failed to leave: $e',
                                duration: const Duration(seconds: 2),
                              );
                            });
                          }
                          // Stream will update when operation completes; optimistic update already done
                        } catch (e) {
                          // Maintain quiet UX; only surface when truly unexpected
                          showOverlayNotice(
                            context,
                            'Failed to leave: $e',
                            duration: const Duration(milliseconds: 1800),
                            liftAboveNav: false,
                          );
                        }
                      } else {
                        // Leaving a demo project in either mode only affects local demo list
                        // i is the combined visible index; find the actual index in _projects by id
                        final idLower = demoList[i].toProject().id.toLowerCase();
                        final demoIndex = _projects.indexWhere((v) => v.toProject().id.toLowerCase() == idLower);
                        if (demoIndex != -1) {
                          // Compute neighbor before removal
                          Project? neighbor;
                          final visible = [
                            ...demoList.map((v) => v.toProject()),
                            ...fsList,
                          ];
                          if (visible.length > 1) {
                            if (i + 1 < visible.length) {
                              neighbor = visible[i + 1];
                            } else if (i - 1 >= 0) {
                              neighbor = visible[i - 1];
                            }
                          }
                          if (neighbor != null) {
                            widget.onProjectSelected(neighbor);
                          }
                          setState(() => _projects.removeAt(demoIndex));
                        }
                      }
                      return;
                    }
                    final updated = result.updated;
                    if (updated != null) {
                      if (isFs && i >= demoList.length) {
                        try {
                          final original = fsList[i - demoList.length];
                          final p = Project(
                            id: original.id,
                            name: updated.name,
                            location: updated.location,
                            startDate: updated.startDate ?? original.startDate,
                            endDate: updated.endDate ?? original.endDate,
                            progressPercent: original.progressPercent,
                            lateTasks: original.lateTasks,
                            incidentCount: original.incidentCount,
                            teamOnline: original.teamOnline,
                            teamTotal: original.teamTotal,
                            status: updated.status,
                            budgetTotal: updated.budgetTotal,
                            budgetSpent: original.budgetSpent,
                            description: updated.description,
                          );
                          await ProjectRepository.instance.update(p);
                          if (!context.mounted) return; // Safe context usage after async call
                          showOverlayNotice(
                            context,
                            'Project updated',
                            duration: const Duration(milliseconds: 1200),
                            liftAboveNav: false,
                          );
                        } catch (e) {
                          showOverlayNotice(
                            context,
                            'Update failed: $e',
                            duration: const Duration(milliseconds: 1800),
                            liftAboveNav: false,
                          );
                        }
                      } else {
                        // Update a demo project locally (preserve image bytes)
                        final idLower = demoList[i].toProject().id.toLowerCase();
                        final demoIndex = _projects.indexWhere((v) => v.toProject().id.toLowerCase() == idLower);
                        if (demoIndex != -1) {
                          setState(() => _projects[demoIndex] = updated.copyWith(
                                imageBytes: _projects[demoIndex].imageBytes,
                              ));
                        }
                      }
                    }
                  },
                ),
              ),
      ),
    );
  }

  // Map a Firestore Project to the local view model for rendering
  _ProjectView _fromProject(Project p) {
    return _ProjectView(
      name: p.name,
      image: _imagePath,
      imageBytes: ProjectImages.instance.get(p.name),
      location: p.location,
      startDate: p.startDate,
      endDate: p.endDate,
      status: p.status,
      budgetTotal: p.budgetTotal,
      description: p.description,
      readOnly: false,
    );
  }

  // Firestore mode image handler stores in-memory only via ProjectImages.
  void _showImageOptionsFs(Project p) {
    // Find index in current list by id to reuse existing sheet
    final idx = _fsProjects.indexWhere((e) => e.id == p.id);
    if (idx == -1) return;
    _showImageOptions(idx);
  }

  /// Best-effort persistence of the user's last selected project *before* the
  /// Firestore projects stream emits the new list, so that the bootstrap layer
  /// immediately prefers the freshly created project instead of reverting to
  /// the previous (e.g. demo) project due to a race between writes.
  Future<void> _persistLastProjectPreference(String id) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return; // Not signed in (demo/local usage)
      // Don't persist if account deletion is in progress
      if (ProfileRepository.instance.isDeleting) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'lastProjectId': id,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Silent: inability to persist preference only risks a one-time fallback selection.
    }
  }
}

class _ProjectView {
  final String name;
  final String image;
  final Uint8List? imageBytes;
  final String? location;
  final DateTime? startDate;
  final DateTime? endDate;
  final ProjectStatus status;
  final double? budgetTotal; // estimated total
  final String? description;
  // True when joined via link; editing is disabled (only leave allowed)
  final bool readOnly;
  const _ProjectView({
    required this.name,
    required this.image,
    this.imageBytes,
    this.location,
    this.startDate,
    this.endDate,
    this.status = ProjectStatus.active,
    this.budgetTotal,
    this.description,
    this.readOnly = false,
  });

  _ProjectView copyWith({
    String? name,
    String? image,
    Uint8List? imageBytes,
    bool clearImage = false,
    String? location,
    DateTime? startDate,
    DateTime? endDate,
    ProjectStatus? status,
    double? budgetTotal,
    String? description,
    bool? readOnly,
  }) {
    return _ProjectView(
      name: name ?? this.name,
      image: image ?? this.image,
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      budgetTotal: budgetTotal ?? this.budgetTotal,
      description: description ?? this.description,
      readOnly: readOnly ?? this.readOnly,
    );
  }

  Project toProject() {
    final now = DateTime.now();
    final start = startDate ?? now;
    final end = endDate ?? DateTime(now.year, now.month + 3, now.day);
    // Generate a simple id slug from name
    final id = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
    return Project(
      id: id.isEmpty ? 'project' : id,
      name: name,
      location: location,
      startDate: start,
      endDate: end,
      progressPercent: 0,
      lateTasks: 0,
      incidentCount: 0,
      teamOnline: 0,
      teamTotal: 1,
      status: status,
      budgetTotal: budgetTotal,
      budgetSpent: null,
      description: description,
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.data, required this.onTap, this.onEdit, this.onChangeImage});
  final _ProjectView data;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeImage;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Slightly larger than the compact version but not the previous large change
        height: 84,
        decoration: BoxDecoration(
          color: surfaceDark,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderDark, width: 1.1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left picture circle: use ClipOval for a strict circular mask while
            // keeping a circular border from the container decoration.
            GestureDetector(
              onTap: onChangeImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderDark, width: 1.0),
                    ),
                    child: ClipOval(
                      child: data.imageBytes != null
                          ? Image.memory(
                              data.imageBytes!,
                              fit: BoxFit.cover,
                              width: 60,
                              height: 60,
                            )
                          : Image.asset(
                              data.image,
                              fit: BoxFit.cover,
                              width: 60,
                              height: 60,
                              errorBuilder: (context, error, stack) => Image.asset(
                                'assets/profile_placeholder.jpg',
                                fit: BoxFit.cover,
                                width: 60,
                                height: 60,
                              ),
                            ),
                    ),
                  ),
                  if (onChangeImage != null)
                    Container(
                      decoration: BoxDecoration(
                        color: newaccentbackground.withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: newaccent, width: 1),
                      ),
                      padding: const EdgeInsets.all(4),
                      margin: const EdgeInsets.only(right: 1, bottom: 1),
                      child: const Icon(
                        AppIcons.edit,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            // Title & subtitle
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    data.location?.isNotEmpty == true
                        ? data.location!
                        : 'Tap to open',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Edit icon in a small rounded container (balanced with new size)
            if (onEdit != null)
              SizedBox(
                width: 46,
                height: 46,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: onEdit,
                  icon: const Icon(
                    AppIcons.edit,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
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

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.onTap});
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
      child: const Icon(AppIcons.joinProjectLink, color: Colors.white, size: 24),
    );
  }
}

class _JoinProjectSheet extends StatefulWidget {
  const _JoinProjectSheet();
  @override
  State<_JoinProjectSheet> createState() => _JoinProjectSheetState();
}

class _JoinProjectSheetState extends State<_JoinProjectSheet> {
  final _linkCtrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _linkCtrl.dispose();
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
            const Center(
              child: Text(
                'Join Project',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _linkCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: InputDecoration(
                labelText: 'Project link',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: _error ? 'Link required' : 'Paste project link here',
                hintStyle: TextStyle(color: _error ? Colors.redAccent : Colors.white54),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                filled: true,
                fillColor: surfaceDarker,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _error ? Colors.redAccent : borderDark, width: _error ? 1.2 : 1.1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _error ? Colors.redAccent : borderDark, width: _error ? 1.2 : 1.1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _error ? Colors.redAccent : newaccent.withValues(alpha: 0.95), width: _error ? 1.3 : 1.6),
                ),
              ),
              onTap: () => setState(() => _error = false),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: newaccentbackground,
                  foregroundColor: Colors.white,
                  side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
                  elevation: 6,
                  shadowColor: newaccent.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final link = _linkCtrl.text.trim();
                  if (link.isEmpty) {
                    setState(() => _error = true);
                    return;
                  }
                  Navigator.pop(context, link);
                },
                child: const Text(
                  'Join',
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


class _AddProjectSheet extends StatefulWidget {
  const _AddProjectSheet();
  @override
  State<_AddProjectSheet> createState() => _AddProjectSheetState();
}

class _AddProjectSheetState extends State<_AddProjectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _budgetTotalCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  ProjectStatus? _status;

  // Date picker validation state (non-Form fields)
  String? _startDateError;
  String? _endDateError;
  // Status validation state
  bool _statusError = false;

  // Inline error flags for text fields
  bool _nameError = false;
  bool _descError = false;
  bool _locationError = false;
  bool _budgetError = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _budgetTotalCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // Removed legacy read-only helpers; edit sheet uses dedicated _ReadOnlyRow widget.


  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Center(
                  child: Text(
                    'Add Project',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _InlineTextField(
                label: 'Project name',
                controller: _nameCtrl,
                error: _nameError,
                onTap: () => setState(() => _nameError = false),
              ),
              const SizedBox(height: 12),
              _InlineTextField(
                label: 'Description',
                controller: _descCtrl,
                maxLines: 4,
                error: _descError,
                onTap: () => setState(() => _descError = false),
              ),
              const SizedBox(height: 12),
              _InlineTextField(
                label: 'Location',
                controller: _locationCtrl,
                error: _locationError,
                onTap: () => setState(() => _locationError = false),
              ),
              const SizedBox(height: 10),
              // Dates
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PickerField(
                          label: 'Start date',
                          value: _startDate == null
                              ? ''
                              : _formatDate(_startDate!),
                          hasError: _startDateError != null,
                          onTap: () async {
                            // Clear error visuals immediately on tap/open
                            if (_startDateError != null) {
                              setState(() => _startDateError = null);
                            }
                            final now = DateTime.now();
                            final picked = await pickPlatformDate(
                              context,
                              initialDate: _startDate ?? now,
                              firstDate: DateTime(now.year - 10),
                              lastDate: DateTime(now.year + 10, 12, 31),
                              title: 'Start date',
                            );
                            if (picked != null) {
                              setState(() {
                                _startDate = picked;
                                _startDateError = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PickerField(
                          label: 'Estimated end date',
                          value: _endDate == null ? '' : _formatDate(_endDate!),
                          hasError: _endDateError != null,
                          onTap: () async {
                            // Clear error visuals immediately on tap/open
                            if (_endDateError != null) {
                              setState(() => _endDateError = null);
                            }
                            final now = DateTime.now();
                            final picked = await pickPlatformDate(
                              context,
                              initialDate: _endDate ?? _startDate ?? now,
                              firstDate: DateTime(now.year - 10),
                              lastDate: DateTime(now.year + 10, 12, 31),
                              title: 'Estimated end date',
                            );
                            if (picked != null) {
                              setState(() {
                                _endDate = picked;
                                _endDateError = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Estimated budget total
              _NumberField(
                controller: _budgetTotalCtrl,
                label: 'Estimated budget total (USD)',
                decimal: true,
                error: _budgetError,
                onTap: () => setState(() => _budgetError = false),
                validator: (_) => null,
              ),
              const SizedBox(height: 10),
              // Status – mirror Tasks Add Task field (floating label + picker)
              _ProjectStatusField(
                label: 'Status',
                value: _status,
                hasError: _statusError,
                onTapClearError: () => setState(() => _statusError = false),
                onPick: (v) => setState(() => _status = v),
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
                  onPressed: () {
                    // Inline validate text fields first
                    final nameEmpty = _nameCtrl.text.trim().isEmpty;
                    final descEmpty = _descCtrl.text.trim().isEmpty;
                    final locationEmpty = _locationCtrl.text.trim().isEmpty;
                    final budgetEmpty = _budgetTotalCtrl.text.trim().isEmpty;
                    _nameError = nameEmpty;
                    _descError = descEmpty;
                    _locationError = locationEmpty;
                    _budgetError = budgetEmpty;
                    // Evaluate all required picker fields in one pass
                    _startDateError = _startDate == null ? 'Required' : null;
                    _endDateError = _endDate == null ? 'Required' : null;
                    _statusError = _status == null;
                    setState(() {});
                    // Block early if any text or picker errors are present
                    if (nameEmpty ||
                        descEmpty ||
                        locationEmpty ||
                        budgetEmpty ||
                        _startDateError != null ||
                        _endDateError != null ||
                        _statusError) {
                      return;
                    }

                    // Validate number field via Form after visual checks
                    if (!_formKey.currentState!.validate()) return;
                    final name = _nameCtrl.text.trim();
                    final location = _locationCtrl.text.trim();
                    final desc = _descCtrl.text.trim();
                    final total =
                        double.tryParse(
                          _budgetTotalCtrl.text.replaceAll(',', '').trim(),
                        ) ??
                        0;
                    Navigator.pop(
                      context,
                      _ProjectView(
                        name: name,
                        image: _ProjectsPanelState._imagePath,
                        imageBytes: null,
                        location: location,
                        startDate: _startDate,
                        endDate: _endDate,
                        status: _status ?? ProjectStatus.active,
                        budgetTotal: total,
                        description: desc,
                      ),
                    );
                  },
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
    );
  }

  String _formatDate(DateTime d) {
    // Keep it simple: d MMM yyyy
    return '${d.day.toString().padLeft(2, '0')} ${_month3(d.month)} ${d.year}';
  }

  String _month3(int m) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(m - 1).clamp(0, 11)];
  }

  static String _statusLabelStatic(ProjectStatus s) {
    switch (s) {
      case ProjectStatus.completed:
        return 'Completed';
      case ProjectStatus.active:
        return 'Active';
    }
  }
}

class _ProjectStatusField extends StatefulWidget {
  const _ProjectStatusField({
    required this.label,
    required this.value,
    required this.onPick,
    this.hasError = false,
    this.onTapClearError,
  });
  final String label;
  final ProjectStatus? value;
  final ValueChanged<ProjectStatus> onPick;
  final bool hasError;
  final VoidCallback? onTapClearError;

  @override
  State<_ProjectStatusField> createState() => _ProjectStatusFieldState();
}

class _ProjectStatusFieldState extends State<_ProjectStatusField> {
  bool _tapped = false;

  Future<void> _handleTap() async {
    widget.onTapClearError?.call();
    setState(() => _tapped = true);
    try {
      final result = await showProjectStatusPicker(context, current: widget.value);
      if (result != null) widget.onPick(result);
    } finally {
      if (mounted) setState(() => _tapped = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.value == null
        ? ''
        : _AddProjectSheetState._statusLabelStatic(widget.value!);
    return GestureDetector(
      onTap: _handleTap,
      child: InputDecorator(
        isFocused: _tapped,
        isEmpty: text.trim().isEmpty,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          floatingLabelBehavior: widget.hasError
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
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
              color: widget.hasError ? Colors.redAccent : borderDark,
              width: widget.hasError ? 1.2 : 1.1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.hasError ? Colors.redAccent : borderDark,
              width: widget.hasError ? 1.2 : 1.1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.hasError
                  ? Colors.redAccent
                  : newaccent.withValues(alpha: 0.95),
              width: widget.hasError ? 1.3 : 1.6,
            ),
          ),
          hintText: widget.hasError ? 'Required' : null,
          hintStyle: const TextStyle(color: Colors.redAccent),
          suffixIcon: const Icon(
            AppIcons.chevronDown,
            color: Colors.white70,
            size: 18,
          ),
        ),
        child: text.trim().isEmpty
            ? const SizedBox.shrink()
            : Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

// Project status picker replaced by shared picker in `lib/widgets/status_picker.dart`.
// The old `_ProjectStatusPicker` implementation was removed to avoid duplicate code.

class _InlineTextField extends StatelessWidget {
  const _InlineTextField({
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
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: error ? Colors.redAccent : borderDark,
        width: error ? 1.2 : 1.1,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: error
            ? Colors.redAccent
            : newaccent.withValues(alpha: 0.95),
        width: error ? 1.3 : 1.6,
      ),
    );
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onTap: onTap,
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelBehavior: error
            ? FloatingLabelBehavior.always
            : FloatingLabelBehavior.auto,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        filled: true,
        fillColor: surfaceDarker,
        hintText: error ? 'Required' : null,
        hintStyle: const TextStyle(color: Colors.redAccent),
        border: enabledBorder,
        enabledBorder: enabledBorder,
        focusedBorder: focusedBorder,
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProjectSheet extends StatefulWidget {
  const _EditProjectSheet({required this.initial, this.canLeave = true, this.readOnly = false});
  final _ProjectView initial;
  final bool canLeave;
  final bool readOnly;
  @override
  State<_EditProjectSheet> createState() => _EditProjectSheetState();
}

class _EditAction {
  const _EditAction({this.updated, this.leave = false});
  final _ProjectView? updated;
  final bool leave;
}

class _EditProjectSheetState extends State<_EditProjectSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _budgetTotalCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _startDate;
  DateTime? _endDate;
  ProjectStatus _status = ProjectStatus.active;

  String? _startDateError;
  String? _endDateError;

  // Inline error flags (mirror Add Project UX)
  bool _nameError = false;
  bool _descError = false;
  bool _locationError = false;
  bool _budgetError = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.name);
    _locationCtrl = TextEditingController(text: widget.initial.location ?? '');
    _budgetTotalCtrl = TextEditingController(
      text: (widget.initial.budgetTotal ?? '').toString(),
    );
    _descCtrl = TextEditingController(text: widget.initial.description ?? '');
    _startDate = widget.initial.startDate;
    _endDate = widget.initial.endDate;
    _status = widget.initial.status;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _budgetTotalCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Edit Project',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.readOnly) ...[
                _ReadOnlyRow(label: 'Name', value: widget.initial.name),
                if (widget.initial.description?.isNotEmpty == true)
                  _ReadOnlyRow(label: 'Description', value: widget.initial.description!),
                if (widget.initial.location?.isNotEmpty == true)
                  _ReadOnlyRow(label: 'Location', value: widget.initial.location!),
                if (widget.initial.startDate != null)
                  _ReadOnlyRow(label: 'Start date', value: _formatDate(widget.initial.startDate!)),
                if (widget.initial.endDate != null)
                  _ReadOnlyRow(label: 'Estimated end date', value: _formatDate(widget.initial.endDate!)),
                _ReadOnlyRow(label: 'Status', value: _status == ProjectStatus.active ? 'Active' : 'Completed'),
                if (widget.initial.budgetTotal != null)
                  _ReadOnlyRow(label: 'Estimated budget total (USD)', value: Money.format(widget.initial.budgetTotal!)),
              ] else ...[
                _InlineTextField(
                  label: 'Project name',
                  controller: _nameCtrl,
                  error: _nameError,
                  onTap: () => setState(() => _nameError = false),
                ),
                const SizedBox(height: 10),
                _InlineTextField(
                  label: 'Description',
                  controller: _descCtrl,
                  maxLines: 4,
                  error: _descError,
                  onTap: () => setState(() => _descError = false),
                ),
                const SizedBox(height: 10),
                _InlineTextField(
                  label: 'Location',
                  controller: _locationCtrl,
                  error: _locationError,
                  onTap: () => setState(() => _locationError = false),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PickerField(
                            label: 'Start date',
                            value: _startDate == null ? '—' : _formatDate(_startDate!),
                            hasError: _startDateError != null,
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await pickPlatformDate(
                                context,
                                initialDate: _startDate ?? now,
                                firstDate: DateTime(now.year - 10),
                                lastDate: DateTime(now.year + 10, 12, 31),
                                title: 'Start date',
                              );
                              if (picked != null) {
                                setState(() {
                                  _startDate = picked;
                                  _startDateError = null;
                                  if (_endDate != null && _endDate!.isBefore(_startDate!)) {
                                    _endDateError = 'End date must be after start date';
                                  } else {
                                    _endDateError = null;
                                  }
                                });
                              }
                            },
                          ),
                          if (_startDateError != null) ...[
                            const SizedBox(height: 6),
                            const Text('Start date is required', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PickerField(
                            label: 'Estimated end date',
                            value: _endDate == null ? '—' : _formatDate(_endDate!),
                            hasError: _endDateError != null,
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await pickPlatformDate(
                                context,
                                initialDate: _endDate ?? _startDate ?? now,
                                firstDate: DateTime(now.year - 10),
                                lastDate: DateTime(now.year + 10, 12, 31),
                                title: 'Estimated end date',
                              );
                              if (picked != null) {
                                setState(() {
                                  _endDate = picked;
                                  if (_startDate == null) {
                                    _startDateError = 'Start date is required';
                                  } else if (_endDate!.isBefore(_startDate!)) {
                                    _endDateError = 'End date must be after start date';
                                  } else {
                                    _endDateError = null;
                                  }
                                });
                              }
                            },
                          ),
                          if (_endDateError != null) ...[
                            const SizedBox(height: 6),
                            Text(_endDateError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _NumberField(
                  controller: _budgetTotalCtrl,
                  label: 'Estimated budget total (USD)',
                  decimal: true,
                  error: _budgetError,
                  onTap: () => setState(() => _budgetError = false),
                  validator: (_) => null,
                ),
                const SizedBox(height: 10),
                _ProjectStatusField(
                  label: 'Status',
                  value: _status,
                  onPick: (v) => setState(() => _status = v),
                ),
              ],
              const SizedBox(height: 14),
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
                  onPressed: () {
                    // Inline validate text fields first
                    final nameEmpty = _nameCtrl.text.trim().isEmpty;
                    final descEmpty = _descCtrl.text.trim().isEmpty;
                    final locationEmpty = _locationCtrl.text.trim().isEmpty;
                    final budgetEmpty = _budgetTotalCtrl.text.trim().isEmpty;
                    _nameError = nameEmpty;
                    _descError = descEmpty;
                    _locationError = locationEmpty;
                    _budgetError = budgetEmpty;
                    setState(() {});
                    if (nameEmpty ||
                        descEmpty ||
                        locationEmpty ||
                        budgetEmpty) {
                      return;
                    }

                    // Validate number field via Form
                    if (!_formKey.currentState!.validate()) return;
                    _startDateError = null;
                    _endDateError = null;
                    if (_startDate == null) {
                      _startDateError = 'Start date is required';
                    }
                    if (_endDate == null) {
                      _endDateError = 'Estimated end date is required';
                    }
                    if (_startDate != null &&
                        _endDate != null &&
                        _endDate!.isBefore(_startDate!)) {
                      _endDateError = 'End date must be after start date';
                    }
                    setState(() {});
                    if (_startDateError != null || _endDateError != null) {
                      return;
                    }
                    final name = _nameCtrl.text.trim();
                    final location = _locationCtrl.text.trim();
                    final desc = _descCtrl.text.trim();
                    final total =
                        double.tryParse(
                          _budgetTotalCtrl.text.replaceAll(',', '').trim(),
                        ) ??
                        0;
                    Navigator.pop(
                      context,
                      _EditAction(
                        updated: _ProjectView(
                          name: name,
                          image: widget.initial.image,
                          imageBytes: widget.initial.imageBytes,
                          location: location,
                          startDate: _startDate,
                          endDate: _endDate,
                          status: _status,
                          budgetTotal: total,
                          description: desc,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                      'Save changes',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                ),
              ),
              const SizedBox(height: 10),
              // Leave project action
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: widget.canLeave
                      ? () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: surfaceDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        title: const Text(
                          textAlign: TextAlign.center,
                          'Leave this project?',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              textAlign: TextAlign.center,
                              "You won't see this project in your list anymore.",
                              style: TextStyle(color: Colors.white70),
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
                                    width: 0.8,
                                  ),
                                  elevation: 6,
                                  shadowColor: Colors.redAccent.withValues(alpha: 0.10),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Leave project',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (confirmed == true) {
                      if (!context.mounted) return;
                      Navigator.pop(context, const _EditAction(leave: true));
                    }
                  }
                      : null,
                  icon: const Icon(AppIcons.logout, size: 18),
                  label: const Text(
                    'Leave project',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (!widget.canLeave) ...[
                const SizedBox(height: 8),
                const Text(
                  'At least one project is required. You cannot leave the last project.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')} ${_month3(d.month)} ${d.year}';
  }

  String _month3(int m) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(m - 1).clamp(0, 11)];
  }
}

class _PickerField extends StatefulWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.hasError = false,
  });
  final String label;
  final String value;
  final FutureOr<void> Function() onTap;
  final bool hasError;
  @override
  State<_PickerField> createState() => _PickerFieldState();
}

class _PickerFieldState extends State<_PickerField> {
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
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: widget.hasError ? Colors.redAccent : borderDark,
        width: widget.hasError ? 1.2 : 1.1,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: widget.hasError
            ? Colors.redAccent
            : newaccent.withValues(alpha: 0.95),
        width: widget.hasError ? 1.3 : 1.6,
      ),
    );
    return GestureDetector(
      onTap: _handleTap,
      child: InputDecorator(
        isFocused: _tapped,
        isEmpty: isEmpty,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          floatingLabelBehavior: widget.hasError
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          filled: true,
          fillColor: surfaceDarker,
          border: enabledBorder,
          enabledBorder: enabledBorder,
          focusedBorder: focusedBorder,
          hintText: widget.hasError ? 'Required' : null,
          hintStyle: const TextStyle(color: Colors.redAccent),
          suffixIcon: const Icon(
            AppIcons.calender,
            color: Colors.white70,
            size: 20,
          ),
        ),
        child: isEmpty
            ? const SizedBox.shrink()
            : Text(
                widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

// removed old Stateless _NumberField in favor of a stateful one that formats values
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.decimal,
    this.error = false,
    this.onTap,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final bool decimal;
  final bool error;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(_handleFocusChange);
    // Initial format if there's a value and not focused
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focus.hasFocus) {
        _formatToMoney();
      }
    });
  }

  void _handleFocusChange() {
    if (_focus.hasFocus) {
      // Strip commas and trailing decimal zeros for clean editing
      final raw = widget.controller.text.replaceAll(',', '').trim();
      String cleaned = raw;
      if (cleaned.contains('.')) {
        // Remove trailing zeros from the fractional part and any trailing dot
        cleaned = cleaned.replaceFirst(RegExp(r'\.?0+$'), '');
      }
      widget.controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    } else {
      _formatToMoney();
    }
  }

  void _formatToMoney() {
    final raw = widget.controller.text.replaceAll(',', '').trim();
    if (raw.isEmpty) return;
    final value = double.tryParse(raw);
    if (value == null) return;
    final formatted = Money.format(value);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocusChange);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: widget.error ? Colors.redAccent : borderDark,
        width: widget.error ? 1.2 : 1.1,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: widget.error
            ? Colors.redAccent
            : newaccent.withValues(alpha: 0.95),
        width: widget.error ? 1.3 : 1.6,
      ),
    );
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      style: const TextStyle(color: Colors.white),
      focusNode: _focus,
      onTap: widget.onTap,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: widget.decimal
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
              TextInputFormatter.withFunction((oldValue, newValue) {
                final text = newValue.text;
                final dotCount = '.'.allMatches(text).length;
                if (dotCount > 1) return oldValue; // prevent multiple dots
                return newValue;
              }),
            ]
          : <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelBehavior: widget.error
            ? FloatingLabelBehavior.always
            : FloatingLabelBehavior.auto,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        filled: true,
        fillColor: surfaceDarker,
        hintText: widget.error ? 'Required' : null,
        hintStyle: const TextStyle(color: Colors.redAccent),
        border: enabledBorder,
        enabledBorder: enabledBorder,
        focusedBorder: focusedBorder,
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.3),
        ),
      ),
    );
  }
}

// _FormTextField removed; Edit/Add sheets now use _InlineTextField for text inputs
