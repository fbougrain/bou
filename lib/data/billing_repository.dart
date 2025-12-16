import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense.dart';
import 'mappers.dart';

/// A minimal in-memory repository for expenses per project.
/// Not persisted; enough to share totals across pages during app lifetime.
class BillingRepository {
  BillingRepository._();
  static final BillingRepository instance = BillingRepository._();

  final Map<String, List<Expense>> _byProject = {};
  final Map<String, StreamSubscription> _live = {};
  // Lazily access Firestore; return null in tests when Firebase isn't initialized.
  FirebaseFirestore? get _fs {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  List<Expense> expensesFor(String projectId) =>
      _byProject[projectId] ?? const [];

  void seedIfEmpty(String projectId, List<Expense> sample) {
    if (_byProject.containsKey(projectId)) return;
    final sorted = List.of(sample)
      ..sort((a, b) => b.paidDate.compareTo(a.paidDate));
    _byProject[projectId] = sorted;
  }

  void addExpense(String projectId, Expense expense) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    list.insert(0, expense);
    _writeExpense(projectId, expense); // Firestore write-through for demo
  }

  double totalPaid(String projectId) =>
      expensesFor(projectId).fold(0, (a, e) => a + e.total);

  // -------------------- Firestore Hydration --------------------
  Future<void> loadFromFirestore(String projectId) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final col = fs.collection('projects').doc(projectId).collection('expenses');
      final snap = await col.get();
      if (snap.docs.isEmpty) return;
      final remote = <Expense>[];
      for (final d in snap.docs) {
        remote.add(ExpenseFirestore.fromMap(d.id, d.data()));
      }
      final local = _byProject.putIfAbsent(projectId, () => []);
      if (local.isEmpty) {
        // Keep most recent first (already sorted by paidDate descending server-side? Safely resort)
        remote.sort((a, b) => b.paidDate.compareTo(a.paidDate));
        local.addAll(remote);
      }
    } catch (_) {
      // Silent: offline or permissions.
    }
  }

  Future<void> _writeExpense(String projectId, Expense expense) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final ref = fs.collection('projects').doc(projectId).collection('expenses').doc(expense.id);
      await ref.set({
        ...expense.toMap(),
        'createdAt': DateTime.now().toIso8601String(),
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
        .collection('expenses')
        .orderBy('paidDate', descending: true)
        .snapshots()
        .listen((snap) {
      final list = <Expense>[];
      for (final d in snap.docs) {
        try {
          list.add(ExpenseFirestore.fromMap(d.id, d.data()));
        } catch (_) {}
      }
      list.sort((a, b) => b.paidDate.compareTo(a.paidDate));
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
}
