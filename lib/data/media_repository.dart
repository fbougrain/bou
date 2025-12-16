import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/media_item.dart';
import 'mappers.dart';

/// In-memory media repository per project with Firestore hydration/write-through.
class MediaRepository {
	MediaRepository._();
	static final MediaRepository instance = MediaRepository._();

	final Map<String, List<MediaItem>> _byProject = {};
  final Map<String, StreamSubscription> _live = {};

	FirebaseFirestore? get _fs {
		try {
			return FirebaseFirestore.instance;
		} catch (_) {
			return null;
		}
	}

	List<MediaItem> itemsFor(String projectId) => _byProject[projectId] ??= [];

	void seedIfEmpty(String projectId, List<MediaItem> seed) {
		final list = _byProject.putIfAbsent(projectId, () => []);
		if (list.isEmpty && seed.isNotEmpty) list.addAll(seed);
	}

	void addItem(String projectId, MediaItem item, {bool insertOnTop = true}) {
		final list = _byProject.putIfAbsent(projectId, () => []);
		if (insertOnTop) {
			list.insert(0, item);
		} else {
			list.add(item);
		}
		_writeItem(projectId, item);
	}

	Future<void> loadFromFirestore(String projectId) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final col = fs.collection('projects').doc(projectId).collection('media');
			final snap = await col.get();
			if (snap.docs.isEmpty) return;
			final remote = <MediaItem>[];
			for (final d in snap.docs) {
				remote.add(MediaItemFirestore.fromMap(d.id, d.data()));
			}
			// Sort by date desc
			remote.sort((a, b) => b.date.compareTo(a.date));
			final local = _byProject.putIfAbsent(projectId, () => []);
			if (local.isEmpty) local.addAll(remote);
		} catch (_) {
			// silent
		}
	}

	Future<void> _writeItem(String projectId, MediaItem item) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final ref = fs.collection('projects').doc(projectId).collection('media').doc(item.id);
			await ref.set(MediaItemFirestore(item).toMap(), SetOptions(merge: true));
		} catch (_) {}
	}

	void listenTo(String projectId) {
		if (_live.containsKey(projectId)) return;
		final fs = _fs;
		if (fs == null) return;
		final sub = fs
				.collection('projects')
				.doc(projectId)
				.collection('media')
				.orderBy('date', descending: true)
				.snapshots()
				.listen((snap) {
			final list = <MediaItem>[];
			for (final d in snap.docs) {
				try {
					list.add(MediaItemFirestore.fromMap(d.id, d.data()));
				} catch (_) {}
			}
			list.sort((a, b) => b.date.compareTo(a.date));
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
