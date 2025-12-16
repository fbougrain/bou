import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/team_member.dart';
import 'mappers.dart';

/// In-memory repository for team members per project with best-effort
/// Firestore hydration and write-through (demo projects only for writes).
class TeamRepository {
	TeamRepository._();
	static final TeamRepository instance = TeamRepository._();

	final Map<String, List<TeamMember>> _byProject = {};
  final Map<String, StreamSubscription> _live = {};

	FirebaseFirestore? get _fs {
		try {
			return FirebaseFirestore.instance;
		} catch (_) {
			return null;
		}
	}

	List<TeamMember> membersFor(String projectId) => _byProject[projectId] ??= [];

	void seedIfEmpty(String projectId, List<TeamMember> seed) {
		final list = _byProject.putIfAbsent(projectId, () => []);
		if (list.isEmpty && seed.isNotEmpty) list.addAll(seed);
	}

	void addMember(String projectId, TeamMember m) {
		final list = _byProject.putIfAbsent(projectId, () => []);
		list.add(m);
		_writeMember(projectId, m);
	}

	/// Add a team member and persist it to Firestore using an explicit
	/// document id (commonly the user's auth uid). This lets callers later
	/// delete the member document by uid when the user leaves.
	void addMemberWithDoc(String projectId, String docId, TeamMember m) {
		final list = _byProject.putIfAbsent(projectId, () => []);
		list.add(m);
		_writeMemberWithDocId(projectId, docId, m);
	}

	Future<void> deleteMemberDoc(String projectId, String docId) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final ref = fs.collection('projects').doc(projectId).collection('team').doc(docId);
			final snap = await ref.get();
			if (snap.exists) {
				try {
					final data = snap.data();
					if (data != null) {
						try {
							final tm = TeamMemberFirestore.fromMap(data);
							final list = _byProject[projectId];
							if (list != null) {
								list.removeWhere((e) => e.name == tm.name && (tm.email == null || e.email == tm.email));
							}
						} catch (_) {}
					}
				} catch (_) {}
			}
			await ref.delete();
		} catch (_) {}
	}

	Future<void> loadFromFirestore(String projectId) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final col = fs.collection('projects').doc(projectId).collection('team');
			final snap = await col.get();
			if (snap.docs.isEmpty) return;
			final remote = <TeamMember>[];
			for (final d in snap.docs) {
				remote.add(TeamMemberFirestore.fromMap(d.data()));
			}
			final local = _byProject.putIfAbsent(projectId, () => []);
			if (local.isEmpty) local.addAll(remote);
		} catch (_) {
			// silent
		}
	}

	Future<void> _writeMember(String projectId, TeamMember m) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final ref = fs.collection('projects').doc(projectId).collection('team').doc(m.id.toString());
			await ref.set(m.toMap(), SetOptions(merge: true));
		} catch (_) {}
	}

	Future<void> _writeMemberWithDocId(String projectId, String docId, TeamMember m) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final ref = fs.collection('projects').doc(projectId).collection('team').doc(docId);
			final map = m.toMap();
			// Include the uid in the stored document so server/clients can reason about it.
			map['uid'] = docId;
			await ref.set(map, SetOptions(merge: true));
		} catch (_) {}
	}

	void listenTo(String projectId) {
		if (_live.containsKey(projectId)) return;
		final fs = _fs;
		if (fs == null) return;
		final sub = fs
				.collection('projects')
				.doc(projectId)
				.collection('team')
				.orderBy('name')
				.snapshots()
				.listen((snap) {
			final list = <TeamMember>[];
			for (final d in snap.docs) {
				try {
					list.add(TeamMemberFirestore.fromMap(d.data()));
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
}
