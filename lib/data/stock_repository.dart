import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stock_item.dart';
import 'mappers.dart';

/// In-memory stock repository, scoped by projectId.
class StockRepository {
  StockRepository._();
  static final StockRepository instance = StockRepository._();

  final Map<String, List<StockItem>> _byProject = {};
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

  /// Stream of projectIds that changed. Subscribe to know when items are added/updated.
  Stream<String> get changes => _changes.stream;

  List<StockItem> itemsFor(String projectId) => _byProject[projectId] ??= [];

  void seedIfEmpty(String projectId, List<StockItem> seed) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    if (list.isEmpty && seed.isNotEmpty) list.addAll(seed);
    // Notify listeners even for seeding so UIs refresh when app initializes
    _changes.add(projectId);
  }

  void addItem(String projectId, StockItem item, {bool insertOnTop = false}) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    if (insertOnTop) {
      list.insert(0, item);
    } else {
      list.add(item);
    }
    _changes.add(projectId);
    _writeItem(projectId, item); // Firestore write-through (demo only for now)
  }

  void updateItem(String projectId, StockItem item) {
    final list = _byProject[projectId];
    if (list == null) return;
    final i = list.indexWhere((e) => e.id == item.id);
    if (i != -1) list[i] = item;
    _changes.add(projectId);
    _writeItem(projectId, item);
  }

  // -------------------- Firestore Hydration --------------------
  Future<void> loadFromFirestore(String projectId) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final col = fs.collection('projects').doc(projectId).collection('stock');
      final snap = await col.get();
      if (snap.docs.isEmpty) return;
      final remote = <StockItem>[];
      for (final d in snap.docs) {
        remote.add(StockFirestore.fromMap(d.id, d.data()));
      }
      final local = _byProject.putIfAbsent(projectId, () => []);
      if (local.isEmpty) {
        local.addAll(remote);
        _changes.add(projectId);
      }
    } catch (_) {
      // Silent failure: keep local.
    }
  }

  Future<void> _writeItem(String projectId, StockItem item) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final ref = fs.collection('projects').doc(projectId).collection('stock').doc(item.id);
      await ref.set({
        ...item.toMap(),
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
        .collection('stock')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      final list = <StockItem>[];
      for (final d in snap.docs) {
        try {
          list.add(StockFirestore.fromMap(d.id, d.data()));
        } catch (_) {}
      }
      _byProject[projectId] = list;
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
