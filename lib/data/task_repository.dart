import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/task.dart';
import 'mappers.dart';

/// Simple in-memory repository for tasks, scoped by projectId.
class TaskRepository {
  TaskRepository._();
  static final TaskRepository instance = TaskRepository._();

  final Map<String, List<TaskModel>> _byProject = {};
  final Map<String, StreamSubscription> _live = {};
  // Lazily access Firestore; if Firebase isn't initialized (e.g., in widget tests),
  // return null and operate in-memory only.
  FirebaseFirestore? get _fs {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Returns a live list for the given project.
  /// Do not mutate externally; prefer using provided methods.
  List<TaskModel> tasksFor(String projectId) => _byProject[projectId] ??= [];

  /// Seeds tasks only if there are none yet for the project.
  void seedIfEmpty(String projectId, List<TaskModel> seed) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    if (list.isEmpty && seed.isNotEmpty) {
      list.addAll(seed);
    }
  }

  void addTask(String projectId, TaskModel task, {bool insertOnTop = false}) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    if (insertOnTop) {
      list.insert(0, task);
    } else {
      list.add(task);
    }
    // Firestore write-through (best-effort, silent on failure)
    _writeTask(projectId, task);
  }

  void updateStatus(String projectId, String taskId, TaskStatus status) {
    final list = _byProject[projectId];
    if (list == null) return;
    final i = list.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final t = list[i];
    list[i] = TaskModel(
      id: t.id,
      name: t.name,
      status: status,
      assignee: t.assignee,
      company: t.company,
      startDate: t.startDate,
      dueDate: t.dueDate,
      priority: t.priority,
      progress: status == TaskStatus.completed ? 100 : 0,
    );
    // Firestore status update (best-effort)
    _updateTaskStatus(projectId, taskId, status);
  }

  int countAll(String projectId) => tasksFor(projectId).length;
  int countByStatus(String projectId, TaskStatus s) =>
      tasksFor(projectId).where((t) => t.status == s).length;

  // -------------------- Firestore Hydration --------------------
  Future<void> loadFromFirestore(String projectId) async {
    // Only attempt for demo or Firestore-backed projects (membership already handled by rules).
    try {
      final fs = _fs;
      if (fs == null) return;
      final col = fs.collection('projects').doc(projectId).collection('tasks');
      final snap = await col.get();
      if (snap.docs.isEmpty) return; // nothing remote yet
      final list = <TaskModel>[];
      for (final d in snap.docs) {
        list.add(TaskFirestore.fromMap(d.id, d.data()));
      }
      // Replace local only if empty to avoid overwriting unsaved session edits.
      final local = _byProject.putIfAbsent(projectId, () => []);
      if (local.isEmpty) {
        local.addAll(list);
      }
    } catch (_) {
      // Silent: offline or permissions; keep local state.
    }
  }

  // -------------------- Firestore Helpers --------------------
  /// Start a real-time listener for the project's tasks. Safe to call multiple times.
  void listenTo(String projectId) {
    if (_live.containsKey(projectId)) return;
    final fs = _fs;
    if (fs == null) return;
    final sub = fs
        .collection('projects')
        .doc(projectId)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      final list = <TaskModel>[];
      for (final d in snap.docs) {
        try {
          list.add(TaskFirestore.fromMap(d.id, d.data()));
        } catch (_) {}
      }
      _byProject[projectId] = list;
    }, onError: (_) {
      // Silently handle permission-denied errors (e.g., during account deletion)
    });
    _live[projectId] = sub;
  }

  void stopListening(String projectId) {
    _live.remove(projectId)?.cancel();
  }

  /// Cancel all active listeners across projects (used on sign-out).
  void stopAll() {
    for (final sub in _live.values) {
      try { sub.cancel(); } catch (_) {}
    }
    _live.clear();
  }

  Future<void> _writeTask(String projectId, TaskModel task) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final ref = fs.collection('projects').doc(projectId).collection('tasks').doc(task.id);
      await ref.set({
        ...task.toMap(),
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _updateTaskStatus(String projectId, String id, TaskStatus status) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final ref = fs.collection('projects').doc(projectId).collection('tasks').doc(id);
      await ref.set({
        'status': status.name,
        'progress': status == TaskStatus.completed ? 100 : 0,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
