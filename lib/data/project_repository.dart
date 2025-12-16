import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'initial_data.dart' show isDemoProjectId;

import '../models/project.dart';
import 'team_repository.dart';
import 'profile_repository.dart';
import 'chat_repository.dart';
import 'report_repository.dart';
import '../models/team_member.dart';
import '../models/chat_thread.dart';
import '../models/chat_message.dart';

/// Firestore repository for Projects.
///
/// Structure:
/// - projects/{projectId}
///   name, location, startDate, endDate, status, budgetTotal, budgetSpent,
///   description, progressPercent, lateTasks, incidentCount, teamOnline, teamTotal,
///   members: [uid, ...], createdAt, updatedAt, version
class ProjectRepository {
  ProjectRepository._();
  static final ProjectRepository instance = ProjectRepository._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('projects');

  /// Stream the current user's projects (by membership array contains uid).
  /// Handles permission errors gracefully (e.g., during account deletion).
  Stream<List<Project>> myProjects() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _col.where('members', arrayContains: uid).snapshots().map(
      (snap) => snap.docs.map((d) => _fromDoc(d.id, d.data())).toList(),
    ).handleError((error, stackTrace) {
      // Silently handle permission-denied errors (e.g., during account deletion)
      // This prevents unhandled exceptions from crashing the app
      // Note: handleError doesn't emit values, but prevents unhandled exceptions
    }, test: (error) {
      // Only catch permission-denied errors
      return error.toString().contains('permission-denied');
    });
  }

  /// Create a new project (caller provides core fields). Adds the current user as member.
  /// Returns the fully realized Project with its final unique id (auto-generated for non-demo projects).
  Future<Project> create(Project p) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return p; // not signed in; return unchanged (demo/local usage)
    // Preserve explicit demo id pattern so seeder & rules remain stable; otherwise generate a Firestore auto id.
    final isDemo = isDemoProjectId(p.id);
    final docRef = isDemo ? _col.doc(p.id) : _col.doc(); // auto id when not demo
    final finalId = docRef.id;
    final now = DateTime.now().toIso8601String();
    // Store original human-readable slug derived from name for easier manual querying (optional field).
    final slug = _slugify(p.name);
    // Persist user's lastProjectId BEFORE creating the project to avoid a race where bootstrap
    // re-selects an older project (e.g., demo) on the first membership stream update.
    try {
      // Don't persist if account deletion is in progress
      if (ProfileRepository.instance.isDeleting) return p;
      await _fs.collection('users').doc(uid).set({
        'lastProjectId': finalId,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (_) {
      // Silent; panel will attempt to persist again after creation.
    }
    await docRef.set({
      ..._toMap(p),
      'slug': slug,
      // Track owner and ensure creator is a member too.
      'ownerUid': uid,
      'members': [uid],
      'createdAt': now,
      'updatedAt': now,
      'version': 1,
    }, SetOptions(merge: true));
    // Add the creator to the team's subcollection so the Team panel shows them.
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
        // Use a project/avatar placeholder for now; replace with real photo upload later.
        photoAsset: 'assets/profile_placeholder.jpg',
        isOnline: true,
      );
  // Persist the team member under the creator's auth uid so the doc can
  // be removed later using the uid as the document id (consistent with
  // how joinById persists members).
  TeamRepository.instance.addMemberWithDoc(finalId, uid, tm);
    } catch (_) {
      // Non-critical; project was created successfully even if team write fails.
    }
    // Create team conversation for the project
    try {
      await _ensureTeamConversation(finalId, p.name);
    } catch (_) {
      // Non-critical; project was created successfully even if team chat creation fails.
    }
    // Return a new Project instance reflecting the final id.
    return Project(
      id: finalId,
      name: p.name,
      location: p.location,
      startDate: p.startDate,
      endDate: p.endDate,
      progressPercent: p.progressPercent,
      lateTasks: p.lateTasks,
      incidentCount: p.incidentCount,
      teamOnline: p.teamOnline,
      teamTotal: p.teamTotal,
      status: p.status,
      budgetTotal: p.budgetTotal,
      budgetSpent: p.budgetSpent,
      description: p.description,
      createdAt: DateTime.tryParse(now),
    );
  }

  /// Update project fields; preserves members.
  Future<void> update(Project p) async {
    final id = p.id.isNotEmpty ? p.id : _slugify(p.name);
    await _col.doc(id).set({
      ..._toMap(p),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Join by known project id (slug). Adds current uid to members if exists.
  Future<bool> joinById(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final ref = _col.doc(id);
    try {
      // Try to perform a transaction that adds the uid to members and
      // increments the teamTotal to keep the visible counts in sync.
      final success = await _fs.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return false;
        final data = snap.data()!;
        final members = (data['members'] as List?)?.cast<String>() ?? <String>[];
        if (members.contains(uid)) return true; // already a member
        tx.update(ref, {
          'members': FieldValue.arrayUnion([uid]),
          'teamTotal': FieldValue.increment(1),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        return true;
      });

      if (success) {
        // Add a minimal TeamMember record for the new user in the project's team
        try {
          // Build a TeamMember using the current user's profile when available
          final profile = ProfileRepository.instance.profile;
          final memberId = DateTime.now().millisecondsSinceEpoch.remainder(1000000000);
          final tm = TeamMember(
            id: memberId,
            name: profile.name.isNotEmpty ? profile.name : uid.substring(0, 6),
            role: profile.title.isNotEmpty ? profile.title : 'Member',
            email: profile.email.isNotEmpty ? profile.email : null,
            phone: profile.phone.isNotEmpty ? profile.phone : null,
            country: profile.country.isNotEmpty ? profile.country : null,
            // Ensure a placeholder avatar is present for all members
            photoAsset: 'assets/profile_placeholder.jpg',
            isOnline: false,
          );
          // Persist the team member under the auth uid so it can be removed easily later
          TeamRepository.instance.addMemberWithDoc(id, uid, tm);
        } catch (_) {
          // Ignore failures writing team member; join succeeded and members array updated.
        }
        // Ensure team conversation exists (user is automatically part of it)
        try {
          final projectData = await ref.get();
          final projectName = projectData.data()?['name'] as String? ?? 'Project';
          await _ensureTeamConversation(id, projectName);
        } catch (_) {
          // Non-critical; user joined successfully even if team chat creation fails.
        }
        return true;
      }
      return false;
    } on FirebaseException catch (e) {
      // If the transaction failed due to missing doc, return false; if it failed due
      // to permission-denied, fall back to a best-effort update (arrayUnion only).
      if (e.code == 'not-found') return false;
      try {
        await ref.update({
          'members': FieldValue.arrayUnion([uid]),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        // best-effort team member add locally
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
          TeamRepository.instance.addMemberWithDoc(id, uid, tm);
        } catch (_) {}
        // Ensure team conversation exists (user is automatically part of it)
        try {
          final projectData = await ref.get();
          final projectName = projectData.data()?['name'] as String? ?? 'Project';
          await _ensureTeamConversation(id, projectName);
        } catch (_) {
          // Non-critical; user joined successfully even if team chat creation fails.
        }
        return true;
      } catch (_) {
        rethrow;
      }
    }
  }

  /// Leave membership of the project; does not delete project.
  Future<void> leave(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = _col.doc(id);
    try {
      // Perform a transaction that deletes the team/{uid} doc and removes the
      // user from the project's members array atomically. Doing both in the
      // same transaction ensures Firestore security rules that require the
      // requester to be a project member for subcollection writes are satisfied
      // (the get within the transaction observes the pre-update state).
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final data = snap.data()!;
        final members = (data['members'] as List?)?.cast<String>() ?? <String>[];
        if (!members.contains(uid)) return; // not a member

        // Delete the team document for this user (doc id == uid) under the
        // project's team subcollection.
        final teamRef = _col.doc(id).collection('team').doc(uid);
        try {
          tx.delete(teamRef);
        } catch (_) {
          // Ignore – deletion may not be necessary or fail; we'll still update project.
        }

        final currentTotal = (data['teamTotal'] as num?)?.toInt() ?? 0;
        final newTotal = (currentTotal - 1) < 0 ? 0 : (currentTotal - 1);
        tx.update(ref, {
          'members': FieldValue.arrayRemove([uid]),
          'teamTotal': newTotal,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      });
    } on FirebaseException catch (_) {
      // Fallback: try to delete the team doc first while still a member, then
      // perform a best-effort arrayRemove on the project doc.
      try {
        await TeamRepository.instance.deleteMemberDoc(id, uid);
      } catch (_) {}
      try {
        await ref.set({
          'members': FieldValue.arrayRemove([uid]),
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Can the current user leave this project according to app rules?
  /// Business rule: user must belong to 2+ projects to leave one (cannot
  /// be left with zero projects). Server rules still allow the write; this
  /// method is for UI blocking.
  Future<bool> canLeave(String projectId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final snap = await _col.where('members', arrayContains: uid).limit(2).get();
    final count = snap.size;
    if (count == 0) return false; // not a member anywhere
    if (count == 1) return false; // only one project => cannot leave
    return true;
  }

  /// Delete all known subcollections under a project by batching deletes.
  /// This is a best-effort client-side recursive delete. It requires that the
  /// caller is still authorized to write/delete the project's subcollections
  /// (i.e., a current project member or owner). It will attempt to delete
  /// the following subcollections: team, tasks, stock, forms, expenses, media,
  /// notifications and chats (including chat messages and readBy subcollections).
  Future<void> _deleteAllSubcollections(String projectId) async {
  final fs = _fs;
    final root = _col.doc(projectId);

    Future<void> deleteCollection(CollectionReference colRef) async {
      const batchSize = 300;
      while (true) {
        final snap = await colRef.limit(batchSize).get();
        if (snap.docs.isEmpty) break;
        final batch = fs.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }

    // Known top-level subcollections
    final topSubs = ['team', 'tasks', 'stock', 'forms', 'expenses', 'media', 'notifications'];
    for (final name in topSubs) {
      try {
  final col = root.collection(name);
  await deleteCollection(col);
      } catch (_) {}
    }

    // Chats: need to delete messages and readBy subcollections per chat document
    try {
      final chatsCol = root.collection('chats');
      final chatSnap = await chatsCol.get();
      for (final chatDoc in chatSnap.docs) {
        try {
          // Delete messages subcollection
          final messagesCol = chatDoc.reference.collection('messages');
          await deleteCollection(messagesCol);
        } catch (_) {}
        try {
          // Delete readBy subcollection (per-user unread tracking)
          final readByCol = chatDoc.reference.collection('readBy');
          await deleteCollection(readByCol);
        } catch (_) {}
        try {
          // Delete the chat document itself
          await chatDoc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Project _fromDoc(String id, Map<String, dynamic> data) {
  DateTime parseDate(String key) {
      final v = data[key];
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

  ProjectStatus parseStatus(String? s) {
      switch (s) {
        case 'completed':
          return ProjectStatus.completed;
        case 'active':
        default:
          return ProjectStatus.active;
      }
    }

    return Project(
      id: id,
      name: (data['name'] as String?) ?? id,
      location: data['location'] as String?,
  startDate: parseDate('startDate'),
  endDate: parseDate('endDate'),
      progressPercent: (data['progressPercent'] as num?)?.toInt() ?? 0,
      lateTasks: (data['lateTasks'] as num?)?.toInt() ?? 0,
      incidentCount: (data['incidentCount'] as num?)?.toInt() ?? 0,
      teamOnline: (data['teamOnline'] as num?)?.toInt() ?? 0,
      teamTotal: (data['teamTotal'] as num?)?.toInt() ?? 0,
  status: parseStatus(data['status'] as String?),
      budgetTotal: (data['budgetTotal'] as num?)?.toDouble(),
      budgetSpent: (data['budgetSpent'] as num?)?.toDouble(),
      description: data['description'] as String?,
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? ''),
    );
  }

  String _slugify(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '')
    .trim();

  /// Can the current user delete this project? Allowed only if requester
  /// is the last remaining member (owner or sole member).
  Future<bool> canDelete(String projectId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _col.doc(projectId).get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    final members = (data['members'] as List?)?.cast<String>() ?? const <String>[];
    return members.length == 1 && members.first == uid;
  }

  /// Delete the project document (will succeed only if Firestore rules permit).
  Future<void> delete(String id) async {
    // If deleting a demo project, mark the user profile so demo isn't auto re-created.
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null && isDemoProjectId(id)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'disableDemo': true, 'updatedAt': DateTime.now().toIso8601String()}, SetOptions(merge: true));
      }
    } catch (_) {
      // silent – failure only means demo might appear again next boot
    }
    // Remove all subcollections first to avoid orphaned data.
    try { await _deleteAllSubcollections(id); } catch (_) {}
    // Delete all reports for this project
    try { await ReportRepository.instance.deleteReportsForProject(id); } catch (_) {}
    await _col.doc(id).delete();
  }

  /// Fetch a single project by id.
  Future<Project?> getById(String id) async {
    final d = await _col.doc(id).get();
    if (!d.exists) return null;
    return _fromDoc(d.id, d.data()!);
  }

  // --- Helper methods ---

  /// Ensures a team conversation exists for the project. Creates it if it doesn't exist.
  Future<void> _ensureTeamConversation(String projectId, String projectName) async {
    try {
      final chatsRef = _col.doc(projectId).collection('chats');
      final teamThreadRef = chatsRef.doc('team');
      final teamThreadSnap = await teamThreadRef.get();
      
      if (!teamThreadSnap.exists) {
        // Create team conversation using repository (which handles Firestore writes)
        final now = DateTime.now();
        final teamThread = ChatThread(
          id: 'team',
          username: 'Team – $projectName',
          lastMessage: 'Welcome! Share updates and files here.',
          lastTime: now,
          unreadCount: 0,
          avatarAsset: 'assets/projectpicplaceholder.jpg',
          isTeam: true,
        );
        
        // Create thread via repository (writes to Firestore)
        ChatRepository.instance.createThread(projectId, teamThread);
        
        // Add welcome message via repository (writes to Firestore)
        // System message has no senderUid (isMe will be false for all users)
        ChatRepository.instance.addMessage(
          projectId,
          'team',
          ChatMessage(
            text: 'Welcome! Share updates and files here.',
            isMe: false,
            senderName: 'System',
            senderUid: null, // System message, no sender
            time: now,
          ),
        );
      }
    } catch (_) {
      // Silent failure - non-critical
    }
  }

  // --- Mapping helpers ---

  Map<String, Object?> _toMap(Project p) => {
        'name': p.name,
        'location': p.location,
        'startDate': p.startDate.toIso8601String(),
        'endDate': p.endDate.toIso8601String(),
        'status': p.status.name,
        'budgetTotal': p.budgetTotal,
        'budgetSpent': p.budgetSpent,
        'description': p.description,
        'progressPercent': p.progressPercent,
        'lateTasks': p.lateTasks,
        'incidentCount': p.incidentCount,
        'teamOnline': p.teamOnline,
        'teamTotal': p.teamTotal,
      };
}
