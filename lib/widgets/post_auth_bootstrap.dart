import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/demo_seeder.dart';
import '../data/project_repository.dart';
import '../data/profile_repository.dart';
import '../models/project.dart';
import '../navigation/main_shell.dart';
import '../data/initial_data.dart' show isDemoProjectId;

/// Small bootstrap layer after auth & profile setup:
/// - Ensures the user-specific demo project exists (id `demo-site-<uid>`)
/// - Listens to user's projects stream and picks the demo project when ready
/// - Seeds local sample repositories (tasks, stock, billing) for that demo
/// Then hands off to the normal `MainShell` with the demo project selected.
class PostAuthBootstrap extends StatefulWidget {
  const PostAuthBootstrap({super.key});
  @override
  State<PostAuthBootstrap> createState() => _PostAuthBootstrapState();
}

class _PostAuthBootstrapState extends State<PostAuthBootstrap> {
  StreamSubscription<List<Project>>? _sub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Project? _activeProject; // last active (demo or real)
  bool _error = false;
  String? _lastProjectId; // persisted preference (user doc lastProjectId)

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    try {
      await DemoSeeder.instance.ensureUserDemoProject();
      // Load last active project preference (best-effort)
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          _lastProjectId = userDoc.data()?['lastProjectId'] as String?;
          // Also subscribe to changes so selection persists across rebuilds
          _userDocSub = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots()
              .listen((snap) {
            final v = snap.data()?['lastProjectId'] as String?;
            if (mounted) setState(() => _lastProjectId = v);
          });
        }
      } catch (_) {}
      _sub = ProjectRepository.instance.myProjects().listen(
        (projects) async {
        // Determine active project using persisted id if available and prefer non-demo projects by default
        Project active;
        if (projects.isEmpty) {
          active = Project(
            id: 'placeholder-project',
            name: 'Project',
            location: 'Site',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(const Duration(days: 30)),
            progressPercent: 0,
            lateTasks: 0,
            incidentCount: 0,
            teamOnline: 0,
            teamTotal: 0,
            status: ProjectStatus.active,
          );
        } else {
          final pref = _lastProjectId;
          if (pref != null) {
            final match = projects.where((p) => p.id == pref);
            if (match.isNotEmpty) {
              active = match.first;
            } else {
              // Fallback: prefer first non-demo if available, else first
              final nonDemo = projects.where((p) => !isDemoProjectId(p.id));
              active = nonDemo.isNotEmpty ? nonDemo.first : projects.first;
            }
          } else {
            // No preference yet: prefer first non-demo if available, else first
            final nonDemo = projects.where((p) => !isDemoProjectId(p.id));
            active = nonDemo.isNotEmpty ? nonDemo.first : projects.first;
          }
        }
        if (mounted) {
          setState(() {
            _activeProject = active;
            // Don't set _hydrating - skip hydration, StreamBuilders handle data loading directly
            // This eliminates the reload page/spinner on hot restart
          });
        }
        // Skip all loadFromFirestore calls - StreamBuilders in pages handle data fetching directly
        // This gives "no spinner but instant data" experience
        try {
          if (projects.isNotEmpty) {
            _persistLastProjectId(active.id);
          }
        } catch (_) {}
        },
        onError: (error) {
          // Silently handle permission-denied errors (e.g., during account deletion)
          // This prevents unhandled exceptions from crashing the app
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Failed to initialize demo project'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = false;
                    _activeProject = null;
                  });
                  _begin();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final project = _activeProject;
    if (project == null) {
      // Only show loading if we don't have a project yet (waiting for stream)
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // No hydration needed - StreamBuilders in pages handle data loading directly
    // This eliminates the reload page/spinner
    return MainShell(initialProject: project);
  }
}
