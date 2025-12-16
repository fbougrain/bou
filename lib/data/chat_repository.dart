import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_thread.dart';
import '../models/chat_message.dart';
import 'mappers.dart';

/// Repository for chat threads and (recent) messages per project.
/// Stores messages in-memory for the session; writes new threads/messages
/// to Firestore for demo projects. Hydration loads threads and the latest
/// N messages per thread (currently all as a single fetch path for simplicity).
class ChatRepository {
	ChatRepository._();
	static final ChatRepository instance = ChatRepository._();

  final Map<String, List<ChatThread>> _threadsByProject = {};
	final Map<String, Map<String, List<ChatMessage>>> _messagesByProject = {};
  final Map<String, StreamSubscription> _liveThreads = {};
  final Map<String, Map<String, StreamSubscription>> _liveMessages = {};
  String? _currentlyOpenThreadKey; // Format: "projectId_threadId"

	FirebaseFirestore? get _fs {
		try {
			return FirebaseFirestore.instance;
		} catch (_) {
			return null;
		}
	}

	String? get _currentUserUid {
		try {
			return FirebaseAuth.instance.currentUser?.uid;
		} catch (_) {
			return null;
		}
	}

	List<ChatThread> threadsFor(String projectId) => _threadsByProject[projectId] ??= [];
	List<ChatMessage> messagesFor(String projectId, String threadId) {
		final byThread = _messagesByProject.putIfAbsent(projectId, () => {});
		return byThread[threadId] ??= [];
	}

	void seedIfEmpty(String projectId, List<ChatThread> threads, Map<String, List<ChatMessage>> seedMessages) {
		final list = _threadsByProject.putIfAbsent(projectId, () => []);
		if (list.isEmpty && threads.isNotEmpty) list.addAll(threads);
		final msgMap = _messagesByProject.putIfAbsent(projectId, () => {});
		if (msgMap.isEmpty && seedMessages.isNotEmpty) {
			seedMessages.forEach((k, v) => msgMap[k] = List.of(v));
		}
	}

	ChatThread createThread(String projectId, ChatThread t) {
		final list = _threadsByProject.putIfAbsent(projectId, () => []);
		list.add(t);
		_writeThread(projectId, t);
		return t;
	}

	void addMessage(String projectId, String threadId, ChatMessage m) {
		final msgs = messagesFor(projectId, threadId);
		msgs.add(m);
		// Update thread preview
		final threads = threadsFor(projectId);
		final idx = threads.indexWhere((t) => t.id == threadId);
		if (idx != -1) {
			final current = threads[idx];
			// Check if message is from current user using senderUid, not isMe
			// (isMe is computed per-user, but senderUid is the actual sender)
			final currentUid = _currentUserUid;
			final isFromCurrentUser = m.senderUid != null && currentUid != null && m.senderUid == currentUid;
			// System messages (senderUid == null) should not increment unread count
			// They're informational and shouldn't be marked as unread for anyone
			final isSystemMessage = m.senderUid == null;
			final newUnread = isSystemMessage 
				? current.unreadCount  // System messages don't increment unread
				: (isFromCurrentUser ? current.unreadCount : (current.unreadCount + 1));
			threads[idx] = ChatThread(
				id: current.id,
				username: current.username,
				lastMessage: m.text.isEmpty && m.attachmentType != null
						? (m.attachmentLabel ?? '${m.attachmentType![0].toUpperCase()}${m.attachmentType!.substring(1)} attachment')
						: m.text,
				lastTime: m.time ?? DateTime.now(),
				unreadCount: newUnread,
				avatarAsset: current.avatarAsset,
				isTeam: current.isTeam,
			);
			_writeThread(projectId, threads[idx]); // update preview info
		}
		_writeMessage(projectId, threadId, m);
	}


	/// Marks a thread as read for the current user by storing lastReadTime in per-user subcollection.
	/// This allows per-user unread tracking without affecting other users.
	void markThreadRead(String projectId, String threadId) async {
		final currentUid = _currentUserUid;
		if (currentUid == null) return;
		
		try {
			final fs = _fs;
			if (fs != null) {
				// Store lastReadTime in per-user subcollection: chats/{threadId}/readBy/{userId}
				final readByRef = fs
					.collection('projects')
					.doc(projectId)
					.collection('chats')
					.doc(threadId)
					.collection('readBy')
					.doc(currentUid);
				
				await readByRef.set({
					'lastReadTime': DateTime.now().toIso8601String(),
					'updatedAt': DateTime.now().toIso8601String(),
				}, SetOptions(merge: true));
			}
		} catch (_) {
			// Silent failure
		}
		
		// Recalculate unread count immediately (will be 0 since we just set lastReadTime to now)
		final messages = messagesFor(projectId, threadId);
		await _recalculateUnreadCount(projectId, threadId, messages);
	}

	/// Marks a thread as currently open and marks it as read (updates lastReadTime)
	/// This ensures unread count disappears immediately when user enters the conversation
	void setThreadOpen(String projectId, String threadId) {
		_currentlyOpenThreadKey = '${projectId}_$threadId';
		// Mark as read when opening - unread count will be recalculated to 0
		markThreadRead(projectId, threadId);
	}

	/// Marks a thread as closed and marks it as read (updates lastReadTime)
	/// This ensures unread count resets to 0 when user closes the conversation
	void clearThreadOpen(String projectId, String threadId) {
		_currentlyOpenThreadKey = null;
		// Mark as read when closing - unread count will be recalculated to 0
		markThreadRead(projectId, threadId);
	}

	/// Checks if a thread is currently open (being viewed)
	bool isThreadOpen(String projectId, String threadId) {
		return _currentlyOpenThreadKey == '${projectId}_$threadId';
	}

	Future<void> loadFromFirestore(String projectId) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final base = fs.collection('projects').doc(projectId).collection('chats');
			final snap = await base.get();
			if (snap.docs.isEmpty) return;
			final remoteThreads = <ChatThread>[];
			for (final d in snap.docs) {
				remoteThreads.add(ChatThreadFirestore.fromMap(d.id, d.data()));
				// Load messages subcollection best-effort
				try {
					final msgsSnap = await base.doc(d.id).collection('messages').orderBy('time').get();
					final msgList = <ChatMessage>[];
					final currentUid = _currentUserUid;
					for (final m in msgsSnap.docs) {
						msgList.add(ChatMessageFirestore.fromMap(m.data(), currentUserUid: currentUid, id: m.id));
					}
					final byThread = _messagesByProject.putIfAbsent(projectId, () => {});
					byThread.putIfAbsent(d.id, () => msgList);
				} catch (_) {}
			}
			final local = _threadsByProject.putIfAbsent(projectId, () => []);
			if (local.isEmpty) local.addAll(remoteThreads);
		} catch (_) {
			// silent
		}
	}

	Future<void> _writeThread(String projectId, ChatThread t) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final ref = fs.collection('projects').doc(projectId).collection('chats').doc(t.id);
			await ref.set(ChatThreadFirestore(t).toMap(), SetOptions(merge: true));
		} catch (_) {}
	}

	Future<void> _writeMessage(String projectId, String threadId, ChatMessage m) async {
		try {
			final fs = _fs;
			if (fs == null) return;
			final ref = fs.collection('projects').doc(projectId).collection('chats').doc(threadId).collection('messages').doc();
			await ref.set(ChatMessageFirestore(m).toMap(), SetOptions(merge: true));
		} catch (_) {}
	}

	void listenTo(String projectId) {
		if (_liveThreads.containsKey(projectId)) return;
		final fs = _fs;
		if (fs == null) return;
		final threadsSub = fs
				.collection('projects')
				.doc(projectId)
				.collection('chats')
				.orderBy('lastTime', descending: true)
				.snapshots()
				.listen((snap) async {
			final list = <ChatThread>[];
			for (final d in snap.docs) {
				ChatThread? t;
				try {
					t = ChatThreadFirestore.fromMap(d.id, d.data());
				} catch (_) {}
				if (t != null) {
					// Don't calculate unread count here - messages might not be loaded yet
					// Unread count will be calculated by _recalculateUnreadCount when messages arrive
					list.add(t);
				}
				// Ensure we have a message listener per thread.
				_listenToMessages(projectId, d.id);
			}
			_threadsByProject[projectId] = list;
		}, onError: (_) {
			// Silently handle permission-denied errors (e.g., during account deletion)
		});
		_liveThreads[projectId] = threadsSub;
	}

	void _listenToMessages(String projectId, String threadId) {
		final fs = _fs;
		if (fs == null) return;
		final byProj = _liveMessages.putIfAbsent(projectId, () => {});
		if (byProj.containsKey(threadId)) return;
		final sub = fs
				.collection('projects')
				.doc(projectId)
				.collection('chats')
				.doc(threadId)
				.collection('messages')
				.orderBy('time')
				.snapshots()
				.listen((snap) {
			final list = <ChatMessage>[];
			final currentUid = _currentUserUid;
			for (final d in snap.docs) {
				try {
					list.add(ChatMessageFirestore.fromMap(d.data(), currentUserUid: currentUid, id: d.id));
				} catch (_) {}
			}
			final byThread = _messagesByProject.putIfAbsent(projectId, () => {});
			byThread[threadId] = list;
			
			// Recalculate unread count based on per-user lastReadTime from readBy subcollection
			// This replaces the old increment logic - unread count is now calculated from messages after lastReadTime
			_recalculateUnreadCount(projectId, threadId, list);
		}, onError: (_) {
			// Silently handle permission-denied errors (e.g., during account deletion)
		});
		byProj[threadId] = sub;
	}

	/// Recalculates unread count for a thread based on per-user lastReadTime from readBy subcollection
	/// If thread is currently open, updates lastReadTime to latest message time to keep it current
	Future<void> _recalculateUnreadCount(String projectId, String threadId, List<ChatMessage> messages) async {
		final currentUid = _currentUserUid;
		if (currentUid == null) return;
		
		try {
			final fs = _fs;
			if (fs == null) return;
			
			// If thread is open, update lastReadTime to latest message time (or now if no messages)
			// This keeps lastReadTime current while viewing, preventing flash when closing
			final isOpen = isThreadOpen(projectId, threadId);
			if (isOpen && messages.isNotEmpty) {
				// Find the latest message time
				final latestMessageTime = messages
					.where((m) => m.time != null)
					.map((m) => m.time!)
					.reduce((a, b) => a.isAfter(b) ? a : b);
				
				// Update lastReadTime to latest message time
				final readByRef = fs
					.collection('projects')
					.doc(projectId)
					.collection('chats')
					.doc(threadId)
					.collection('readBy')
					.doc(currentUid);
				
				await readByRef.set({
					'lastReadTime': latestMessageTime.toIso8601String(),
					'updatedAt': DateTime.now().toIso8601String(),
				}, SetOptions(merge: true));
				
				// Unread count is 0 while thread is open
				final threads = threadsFor(projectId);
				final idx = threads.indexWhere((t) => t.id == threadId);
				if (idx != -1) {
					final current = threads[idx];
					if (current.unreadCount != 0) {
						threads[idx] = ChatThread(
							id: current.id,
							username: current.username,
							lastMessage: current.lastMessage,
							lastTime: current.lastTime,
							unreadCount: 0,
							avatarAsset: current.avatarAsset,
							isTeam: current.isTeam,
						);
					}
				}
				return; // Skip normal calculation - unread is 0 while open
			}
			
			final readByDoc = await fs
				.collection('projects')
				.doc(projectId)
				.collection('chats')
				.doc(threadId)
				.collection('readBy')
				.doc(currentUid)
				.get();
			
			DateTime? lastReadTime;
			if (readByDoc.exists) {
				final lastReadTimeStr = readByDoc.data()?['lastReadTime'] as String?;
				if (lastReadTimeStr != null) {
					lastReadTime = DateTime.parse(lastReadTimeStr);
				}
			}
			
			// Calculate unread count from messages after lastReadTime
			final unreadCount = messages.where((m) {
				if (m.time == null) return false;
				if (m.senderUid == currentUid) return false; // Don't count own messages
				if (m.senderUid == null) return false; // Don't count system messages
				if (lastReadTime == null) return true; // If no lastReadTime, all messages are unread
				return m.time!.isAfter(lastReadTime);
			}).length;
			
			// Update local thread with recalculated unread count
			final threads = threadsFor(projectId);
			final idx = threads.indexWhere((t) => t.id == threadId);
			if (idx != -1) {
				final current = threads[idx];
				if (current.unreadCount != unreadCount) {
					threads[idx] = ChatThread(
						id: current.id,
						username: current.username,
						lastMessage: current.lastMessage,
						lastTime: current.lastTime,
						unreadCount: unreadCount,
						avatarAsset: current.avatarAsset,
						isTeam: current.isTeam,
					);
				}
			}
		} catch (_) {
			// Silent failure
		}
	}

	void stopListening(String projectId) {
		_liveThreads.remove(projectId)?.cancel();
		final msgs = _liveMessages.remove(projectId);
		if (msgs != null) {
			for (final s in msgs.values) {
				s.cancel();
			}
		}
	}

	/// Cancel all active listeners across projects (used on sign-out).
	void stopAll() {
		for (final sub in _liveThreads.values) {
			try { sub.cancel(); } catch (_) {}
		}
		_liveThreads.clear();
		for (final proj in _liveMessages.values) {
			for (final sub in proj.values) {
				try { sub.cancel(); } catch (_) {}
			}
		}
		_liveMessages.clear();
	}
}
