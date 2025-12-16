import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/project.dart';
import '../models/expense.dart';
import 'project_repository.dart';
import 'sample_data.dart';

/// Utility to ensure each signed-in user has a private demo project copy.
///
/// Creates (if missing) a Firestore document with id `demo-site-<uid>` in the
/// `projects` collection, owned by that user only. The user can freely edit
/// or delete their copy without impacting other users.
///
/// After creation it seeds in-memory sample repositories (tasks, stock, billing)
/// for that demo id using the same logic as other demo projects. Subsequent
/// calls are cheap (existence check only).
class DemoSeeder {
  DemoSeeder._();
  static final DemoSeeder instance = DemoSeeder._();

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  /// Ensure demo project exists for current user. Returns the project id or
  /// null if no signed-in user.
  Future<String?> ensureUserDemoProject() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null; // not signed in
    final id = 'demo-site-$uid';
    // Skip creation if user explicitly disabled demo via profile flag.
    try {
      final userDoc = await _fs.collection('users').doc(uid).get();
      final disableDemo = (userDoc.data() ?? const {})['disableDemo'] == true;
      if (disableDemo) {
        return null; // user opted out of demo project
      }
    } catch (_) {
      // silent – if profile cannot be read we'll attempt creation below
    }
    // Only create if missing to allow user to delete permanently.
    bool exists = false;
    try {
      final existing = await _fs.collection('projects').doc(id).get();
      exists = existing.exists;
    } catch (_) {
      // silent – treat as missing
    }
    if (!exists) {
      // Set via repository (merge on server). Avoid a separate read for membership.
    final now = DateTime.now();
    final project = Project(
      id: id,
      name: 'Demo Site',
      location: 'Demo',
      startDate: now.subtract(const Duration(days: 14)),
      endDate: now.add(const Duration(days: 90)),
      // Derived metrics now computed at runtime from subcollections; seed zero/defaults.
      progressPercent: 0,
      lateTasks: 0,
      incidentCount: 0,
      teamOnline: 0,
      teamTotal: 0,
      status: ProjectStatus.active,
      budgetTotal: sampleProject.budgetTotal,
      budgetSpent: null,
      description: 'Personal demo sandbox project for experimentation.',
    );
      await ProjectRepository.instance.create(project);
    } else {
      // If already exists we still return id but skip seeding logic below (markers already present).
    }

    // Seed Firestore subcollections exactly once (idempotent via marker field)
    try {
      final projRef = _fs.collection('projects').doc(id);
      final projSnap = await projRef.get();
      final data = projSnap.data() ?? const {};
      final seededV1 = data['seededDemoV1'] == true;
  final seededV2 = data['seededDemoV2'] == true; // new collections (initial flat structure)
  final chatNestedMigrated = data['chatNestedMigrated'] == true; // migration marker
      // Seed legacy (V1) collections if missing.
      if (!seededV1) {
        final batch = _fs.batch();
        // tasks
        final tasksCol = projRef.collection('tasks');
        for (final t in sampleTasks) {
          final doc = tasksCol.doc(t.id);
          batch.set(doc, {
            'name': t.name,
            'status': t.status.name,
            'assignee': t.assignee,
            'company': t.company,
            'startDate': t.startDate.toIso8601String(),
            'dueDate': t.dueDate.toIso8601String(),
            'priority': t.priority.name,
            'progress': t.progress,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        // stock
        final stockCol = projRef.collection('stock');
        for (final s in sampleStock) {
          final doc = stockCol.doc(s.id);
          batch.set(doc, {
            'name': s.name,
            'category': s.category,
            'quantity': s.quantity,
            'unit': s.unit,
            'supplier': s.supplier,
            'status': s.status.name,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        // expenses
        final expCol = projRef.collection('expenses');
        for (final e in _defaultExpenses()) {
          final doc = expCol.doc(e.id);
          batch.set(doc, {
            'number': e.number,
            'vendor': e.vendor,
            'paidDate': e.paidDate.toIso8601String(),
            'items': [
              for (final it in e.items)
                {
                  'name': it.name,
                  'qty': it.qty,
                  'unitPrice': it.unitPrice,
                },
            ],
            'taxRate': e.taxRate,
            'discount': e.discount,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        // forms (submissions): seed a couple of examples
        final formsCol = projRef.collection('forms');
        final nowIso = DateTime.now().toIso8601String();
        batch.set(formsCol.doc('sub-daily-${DateTime.now().millisecondsSinceEpoch}'), {
          'title': 'Daily Report • Today',
          'kind': 'dailyReport',
          'status': 'Submitted',
          'createdAt': nowIso,
          'updatedAt': nowIso,
        }, SetOptions(merge: true));
        batch.set(formsCol.doc('sub-incident-${DateTime.now().millisecondsSinceEpoch}'), {
          'title': 'Incident • Last week',
          'kind': 'incident',
          'status': 'Submitted',
          'createdAt': DateTime.now().subtract(const Duration(days: 7)).toIso8601String(),
          'updatedAt': nowIso,
        }, SetOptions(merge: true));
        // marker on project doc
        batch.set(projRef, {
          'seededDemoV1': true,
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        await batch.commit();
      }
      // Seed new (V2) collections: team, media, notifications.
      // (Chat seeding now uses nested structure directly; previous implementation used flat collections)
      if (!seededV2) {
        final batch2 = _fs.batch();
        // team members
        final teamCol = projRef.collection('team');
        for (final m in sampleTeamMembers) {
          batch2.set(teamCol.doc(m.id.toString()), {
            'id': m.id,
            'name': m.name,
            'role': m.role,
            if (m.phone != null) 'phone': m.phone,
            if (m.email != null) 'email': m.email,
            if (m.country != null) 'country': m.country,
            if (m.photoAsset != null) 'photoAsset': m.photoAsset,
            'isOnline': m.isOnline,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        // chat threads + messages (nested): projects/<id>/chats/<thread>/messages/<msg>
        final chatsCol = projRef.collection('chats');
        for (final th in sampleChats) {
          final thRef = chatsCol.doc(th.id);
          batch2.set(thRef, {
            'username': th.username,
            'lastMessage': th.lastMessage,
            'lastTime': th.lastTime.toIso8601String(),
            'unreadCount': th.unreadCount,
            'avatarAsset': th.avatarAsset,
            'isTeam': th.isTeam,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
          final msgs = sampleChatMessages[th.id];
          if (msgs != null) {
            for (final msg in msgs) {
              final msgRef = thRef.collection('messages').doc();
              batch2.set(msgRef, {
                'text': msg.text,
                'isMe': msg.isMe,
                'senderName': msg.senderName,
                if (msg.attachmentType != null) 'attachmentType': msg.attachmentType,
                if (msg.attachmentLabel != null) 'attachmentLabel': msg.attachmentLabel,
                if (msg.time != null) 'time': msg.time!.toIso8601String(),
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }, SetOptions(merge: true));
            }
          }
        }
        // media items
        final mediaCol = projRef.collection('media');
        for (final mi in sampleMedia) {
          batch2.set(mediaCol.doc(mi.id), {
            'id': mi.id,
            'name': mi.name,
            'type': mi.type.name,
            'date': mi.date.toIso8601String(),
            'uploader': mi.uploader,
            if (mi.taskId != null) 'taskId': mi.taskId,
            if (mi.thumbnailUrl != null) 'thumbnailUrl': mi.thumbnailUrl,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        // notifications
        final notifCol = projRef.collection('notifications');
        for (final n in sampleNotifications) {
          batch2.set(notifCol.doc(n.id.toString()), {
            'id': n.id,
            'message': n.message,
            'type': n.type,
            'date': n.date.toIso8601String(),
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        // marker update (flat V2 legacy marker retained for backward compatibility)
        batch2.set(projRef, {
          'seededDemoV2': true,
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        await batch2.commit();
      }
      // Migrate old flat chatThreads/chatMessages to nested if not yet migrated.
      if (seededV2 && !chatNestedMigrated) {
        try {
          final flatThreads = await projRef.collection('chatThreads').get();
          final nestedChats = await projRef.collection('chats').limit(1).get();
          if (flatThreads.docs.isNotEmpty && nestedChats.docs.isEmpty) {
            final batch3 = _fs.batch();
            for (final thDoc in flatThreads.docs) {
              final thData = thDoc.data();
              final thRef = projRef.collection('chats').doc(thDoc.id);
              batch3.set(thRef, {
                'username': thData['username'],
                'lastMessage': thData['lastMessage'],
                'lastTime': thData['lastTime'],
                'unreadCount': thData['unreadCount'],
                'avatarAsset': thData['avatarAsset'],
                'isTeam': thData['isTeam'],
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              }, SetOptions(merge: true));
              // messages
              final msgsFlat = await projRef.collection('chatMessages').where('threadId', isEqualTo: thDoc.id).get();
              for (final msgDoc in msgsFlat.docs) {
                final msgRef = thRef.collection('messages').doc();
                batch3.set(msgRef, {
                  'text': msgDoc['text'],
                  'isMe': msgDoc['isMe'],
                  'senderName': msgDoc['senderName'],
                  if (msgDoc.data().containsKey('attachmentType')) 'attachmentType': msgDoc['attachmentType'],
                  if (msgDoc.data().containsKey('attachmentLabel')) 'attachmentLabel': msgDoc['attachmentLabel'],
                  if (msgDoc.data().containsKey('time')) 'time': msgDoc['time'],
                  'createdAt': DateTime.now().toIso8601String(),
                  'updatedAt': DateTime.now().toIso8601String(),
                }, SetOptions(merge: true));
              }
            }
            // Mark migration
            batch3.set(projRef, {
              'chatNestedMigrated': true,
              'updatedAt': DateTime.now().toIso8601String(),
            }, SetOptions(merge: true));
            await batch3.commit();
            // Optional cleanup: remove flat collections now that nested copies exist.
            try {
              final flatThreadsCol = projRef.collection('chatThreads');
              final flatMsgsCol = projRef.collection('chatMessages');
              final flatThSnap = await flatThreadsCol.get();
              for (final d in flatThSnap.docs) {
                await d.reference.delete();
              }
              final flatMsgSnap = await flatMsgsCol.get();
              for (final d in flatMsgSnap.docs) {
                await d.reference.delete();
              }
            } catch (_) {
              // ignore cleanup errors
            }
          } else if (nestedChats.docs.isNotEmpty) {
            // Already using nested; mark migrated to prevent re-check.
            await projRef.set({
              'chatNestedMigrated': true,
              'updatedAt': DateTime.now().toIso8601String(),
            }, SetOptions(merge: true));
          }
        } catch (_) {
          // silent
        }
      }
    } catch (_) {
      // Silent: demo seeding of subcollections is best-effort.
    }
    return id;
  }
}

// Local copy of default expenses used for Firestore seeding.
List<Expense> _defaultExpenses() {
  final now = DateTime.now();
  return [
    Expense(
      id: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-001',
      number: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-001',
      vendor: 'Lumber Yard Co.',
      paidDate: DateTime(now.year, now.month, 2),
      items: [
        const ExpenseItem(name: 'Framing labor', qty: 12, unitPrice: 85),
        const ExpenseItem(name: 'Lumber materials', qty: 1, unitPrice: 1250),
      ],
      taxRate: 0.1,
      discount: 0,
    ),
    Expense(
      id: 'EXP-${now.year}${(now.month - 1).toString().padLeft(2, '0')}-019',
      number: 'EXP-${now.year}${(now.month - 1).toString().padLeft(2, '0')}-019',
      vendor: 'Electric Co',
      paidDate: DateTime(now.year, now.month - 1, 25),
      items: [
        const ExpenseItem(name: 'Electrical rough-in', qty: 20, unitPrice: 70),
      ],
      taxRate: 0.1,
      discount: 50,
    ),
    Expense(
      id: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-002',
      number: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-002',
      vendor: 'Inspection Services',
      paidDate: DateTime(now.year, now.month, 20),
      items: [
        const ExpenseItem(name: 'Site inspection', qty: 1, unitPrice: 300),
      ],
      taxRate: 0,
      discount: 0,
    ),
  ];
}
