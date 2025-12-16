import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/form_models.dart';
import 'mappers.dart';

class FormsRepository {
  FormsRepository._();
  static final FormsRepository instance = FormsRepository._();

  final Map<String, List<FormSubmission>> _subsByProject = {};
  final StreamController<String> _changes = StreamController<String>.broadcast();
  final Map<String, StreamSubscription> _live = {};
  // Lazily access Firestore; return null when Firebase isn't initialized (tests)
  FirebaseFirestore? get _fs {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Stream of projectIds that changed. Subscribe to know when submissions are added.
  Stream<String> get changes => _changes.stream;

  List<FormSubmission> submissionsFor(String projectId) =>
      _subsByProject[projectId] ??= [];

  void addSubmission(
    String projectId,
    FormSubmission sub, {
    bool insertOnTop = true,
  }) {
    final list = _subsByProject.putIfAbsent(projectId, () => []);
    // Guard against inadvertent duplicates (e.g. optimistic insert followed by
    // a second UI event re‑emitting the same submission, or a race where the
    // caller invokes addSubmission twice). We key uniqueness by the stable
    // FormSubmission.id which is also used as the Firestore document id.
    final existingIndex = list.indexWhere((e) => e.id == sub.id);
    if (existingIndex != -1) {
      // Optionally we could merge/update fields; for now we no-op to avoid
      // creating a visible duplicate in the UI list.
      return;
    }
    if (insertOnTop) {
      list.insert(0, sub);
    } else {
      list.add(sub);
    }
    _changes.add(projectId);
    _writeSubmission(projectId, sub);
  }

  // -------------------- Firestore Hydration --------------------
  Future<void> loadFromFirestore(String projectId) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final col = fs.collection('projects').doc(projectId).collection('forms');
      final snap = await col.get();
      if (snap.docs.isEmpty) return;
      final remote = <FormSubmission>[];
      for (final d in snap.docs) {
        remote.add(FormSubmissionFirestore.fromMap(d.id, d.data()));
      }
      final local = _subsByProject.putIfAbsent(projectId, () => []);
      // Always reconcile to avoid accumulating duplicates when hydration
      // happens after optimistic inserts. Prefer the remote set as source of
      // truth, keeping order newest first by createdAt.
      remote.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // De-duplicate by id while preserving order.
      final seen = <String>{};
      final merged = <FormSubmission>[];
      for (final s in [...remote, ...local]) {
        if (seen.add(s.id)) merged.add(s);
      }
      // Keep newest-first ordering
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _subsByProject[projectId] = merged;
      _changes.add(projectId);
    } catch (_) {
      // Silent
    }
  }

  Future<void> _writeSubmission(String projectId, FormSubmission sub) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final ref = fs.collection('projects').doc(projectId).collection('forms').doc(sub.id);
      await ref.set({
        ...sub.toMap(),
        'createdAt': sub.createdAt.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void listenTo(String projectId) {
    if (_live.containsKey(projectId)) return;
    final fs = _fs;
    if (fs == null) return;
    final sub = fs
        .collection('projects')
        .doc(projectId)
        .collection('forms')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      final remote = <FormSubmission>[];
      for (final d in snap.docs) {
        try {
          remote.add(FormSubmissionFirestore.fromMap(d.id, d.data()));
        } catch (_) {}
      }
      // Merge with any existing local (optimistic) entries, dedup by id.
      final local = _subsByProject[projectId] ?? const <FormSubmission>[];
      final seen = <String>{};
      final merged = <FormSubmission>[];
      for (final s in [...remote, ...local]) {
        if (seen.add(s.id)) merged.add(s);
      }
      // Ensure newest first
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _subsByProject[projectId] = merged;
      _changes.add(projectId);
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
}
