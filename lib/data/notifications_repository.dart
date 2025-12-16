import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_notification.dart';
import 'mappers.dart';

/// Simple repository for per-project app notifications.
class NotificationsRepository {
  NotificationsRepository._();
  static final NotificationsRepository instance = NotificationsRepository._();

  final Map<String, List<AppNotification>> _byProject = {};
  final Map<String, _CombinedSubscription> _live = {};

  FirebaseFirestore? get _fs {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  List<AppNotification> notificationsFor(String projectId) =>
      _byProject[projectId] ??= [];

  void seedIfEmpty(String projectId, List<AppNotification> seed) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    if (list.isEmpty && seed.isNotEmpty) list.addAll(seed);
  }

  void add(String projectId, AppNotification n, {bool insertOnTop = true}) {
    final list = _byProject.putIfAbsent(projectId, () => []);
    if (insertOnTop) {
      list.insert(0, n);
    } else {
      list.add(n);
    }
    _write(projectId, n);
  }

  Future<void> loadFromFirestore(String projectId) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final col = fs.collection('projects').doc(projectId).collection('notifications');
      final snap = await col.get();
      if (snap.docs.isEmpty) return;
      final remote = <AppNotification>[];
      for (final d in snap.docs) {
        remote.add(AppNotificationFirestore.fromMap(d.id, d.data()));
      }
      remote.sort((a, b) => b.date.compareTo(a.date));
      final local = _byProject.putIfAbsent(projectId, () => []);
      if (local.isEmpty) local.addAll(remote);
    } catch (_) {
      // silent
    }
  }

  Future<void> _write(String projectId, AppNotification n) async {
    try {
      final fs = _fs;
      if (fs == null) return;
      final ref = fs.collection('projects').doc(projectId).collection('notifications').doc(n.id.toString());
      await ref.set(AppNotificationFirestore(n).toMap(), SetOptions(merge: true));
    } catch (_) {}
  }

  void listenTo(String projectId) {
    if (_live.containsKey(projectId)) return;
    final fs = _fs;
    if (fs == null) return;
    
    final notificationsRef = fs
        .collection('projects')
        .doc(projectId)
        .collection('notifications');
    
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    
    // Query 1: Non-report notifications (all users see these)
    final nonReportStream = notificationsRef
        .where('type', isNotEqualTo: 'report')
        .orderBy('type')
        .orderBy('date', descending: true)
        .snapshots();
    
    // Query 2: Report notifications only for current user (owner only)
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? reportSub;
    
    final Map<String, AppNotification> notificationsMap = {};
    
    void updateCache() {
      final list = notificationsMap.values.toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      _byProject[projectId] = list;
    }
    
    final nonReportSub = nonReportStream.listen((snap) {
      for (final d in snap.docs) {
        try {
          notificationsMap[d.id] = AppNotificationFirestore.fromMap(d.id, d.data());
        } catch (_) {}
      }
      updateCache();
    }, onError: (_) {
      // Silently handle permission-denied errors
    });
    
    if (currentUid != null) {
      final reportStream = notificationsRef
          .where('type', isEqualTo: 'report')
          .where('targetUid', isEqualTo: currentUid)
          .snapshots();
      
      reportSub = reportStream.listen((snap) {
        for (final d in snap.docs) {
          try {
            notificationsMap[d.id] = AppNotificationFirestore.fromMap(d.id, d.data());
          } catch (_) {}
        }
        updateCache();
      }, onError: (_) {
        // Silently handle permission-denied errors
      });
    }
    
    // Store both subscriptions (we'll cancel both when stopping)
    _live[projectId] = _CombinedSubscription(nonReportSub, reportSub);
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

// Helper class to manage combined subscriptions
class _CombinedSubscription {
  final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> nonReportSub;
  final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? reportSub;
  
  _CombinedSubscription(this.nonReportSub, this.reportSub);
  
  void cancel() {
    nonReportSub.cancel();
    reportSub?.cancel();
  }
}
