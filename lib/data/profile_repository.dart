import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import 'team_repository.dart';
import '../models/team_member.dart';

/// Repository handling Firestore persistence for the user's profile.
/// Keeps a local cache for fast rebuilds while listening to remote changes.
class ProfileRepository extends ChangeNotifier {
  ProfileRepository._internal() {
    // React to auth state changes so profile loads automatically on app start or sign-in.
    _auth.userChanges().listen((user) {
      if (user != null && !_isDeleting) {
        _loading = true;
        notifyListeners();
        // Defer to next microtask to avoid plugin channel races after hot restart
        Future.microtask(() {
          // Double-check we're not deleting before loading
          if (!_isDeleting && _auth.currentUser?.uid == user.uid) {
            ensureLoaded();
          }
        });
      } else {
        clearOnSignOut();
      }
    });
  }
  static final ProfileRepository instance = ProfileRepository._internal();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  UserProfile _profile = UserProfile.initial;
  UserProfile get profile => _profile;
  bool _loading = false;
  bool get loading => _loading;
  bool _isDeleting = false; // Flag to prevent loading during account deletion
  bool get isDeleting => _isDeleting; // Public getter to check if deletion is in progress
  Future<void>? _pendingPersist; // Track pending persist operations

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Ensure profile is loaded for current user, set up a snapshot listener.
  Future<void> ensureLoaded() async {
    // Don't load if we're in the process of deleting the account
    if (_isDeleting) {
      _loading = false;
      notifyListeners();
      return;
    }
    
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // User is not signed in, ensure loading is false
      _loading = false;
      notifyListeners();
      return;
    }
    _sub?.cancel();
    final docRef = _firestore.collection('users').doc(uid);
    try {
      _loading = true;
      notifyListeners();
      // Retry with simple exponential backoff to handle transient unavailability
      DocumentSnapshot<Map<String, dynamic>> doc;
      int attempts = 0;
      Duration delay = const Duration(milliseconds: 200);
      while (true) {
        // Check if user is still signed in before each retry
        if (_auth.currentUser?.uid != uid) {
          // User signed out or account deleted during loading
          _loading = false;
          notifyListeners();
          return;
        }
        try {
          doc = await docRef.get();
          break;
        } catch (e) {
          attempts++;
          if (attempts >= 4) {
            // Last resort: try cache read to avoid blocking UI offline
            try {
              final cached = await docRef.get(const GetOptions(source: Source.cache));
              doc = cached;
              break;
            } catch (_) {
              rethrow;
            }
          }
          await Future.delayed(delay);
          delay *= 2;
        }
      }
      
      // Final check: user might have been deleted/signed out during fetch
      if (_auth.currentUser?.uid != uid) {
        _loading = false;
        notifyListeners();
        return;
      }
      
      if (doc.exists) {
        _profile = UserProfile.fromMap(doc.data()!);
      } else {
        // Create initial doc if absent (first-time user after onboarding form fill).
        // But only if user is still signed in
        if (_auth.currentUser?.uid == uid) {
        await docRef.set(_profile.toMap());
        }
      }
      notifyListeners();
      
      // Only set up listener if user is still signed in
      if (_auth.currentUser?.uid == uid) {
      // Live updates
      _sub = docRef.snapshots().listen(
        (snap) {
            // Check if user is still signed in before processing
            if (_auth.currentUser?.uid != uid) {
              _sub?.cancel();
              _sub = null;
              return;
            }
          if (!snap.exists) return; // should not happen normally
          final data = snap.data();
          if (data == null) return;
          _profile = _profile.copyWith(
            name: data['name'] as String?,
            title: data['title'] as String?,
            country: data['country'] as String?,
            phone: data['phone'] as String?,
            email: data['email'] as String?,
            roles: (data['roles'] is List)
                ? (data['roles'] as List).whereType<String>().toList()
                : _profile.roles,
            version: (data['version'] as int?) ?? _profile.version,
              eulaAccepted: (data['eulaAccepted'] as bool?) ?? _profile.eulaAccepted,
              eulaAcceptedAt: _parseDate(data['eulaAcceptedAt']) ?? _profile.eulaAcceptedAt,
            updatedAt: DateTime.now(), // local hint; remote timestamp kept
          );
          notifyListeners();
        },
        onError: (error) {
            // Silently handle permission-denied errors (e.g., during account deletion)
            // This prevents unhandled exceptions from crashing the app
          // The subscription will be cancelled via clearOnSignOut() before auth changes
          _sub?.cancel();
          _sub = null;
        },
      );
      }
    } catch (e) {
      // Gracefully degrade to in-memory only; no crash
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return; // can't persist without user
    
    // Don't persist if we're deleting
    if (_isDeleting) return;
    
    final now = DateTime.now();
    _profile = _profile.copyWith(updatedAt: now, createdAt: _profile.createdAt ?? now);
    final data = _profile.toMap();
    // Add server timestamps via merge to avoid overwriting future fields
    try {
      // Track this persist operation so we can wait for it during account deletion
      _pendingPersist = _firestore.collection('users').doc(uid).set({
        ...data,
        'updatedAt': now.toIso8601String(),
        if (_profile.createdAt == now) 'createdAt': now.toIso8601String(),
      }, SetOptions(merge: true));
      await _pendingPersist;
      
      // Sync profile updates to team member documents in all projects
      // Check again if we're deleting before syncing (in case deletion started during the set operation)
      if (!_isDeleting) {
        _pendingPersist = _syncToTeamMembers(uid);
        await _pendingPersist;
      }
      _pendingPersist = null;
    } catch (e) {
      _pendingPersist = null;
      // Persist failure ignored to avoid crash; consider reporting to error tracking.
    }
  }
  
  /// Wait for any pending persist operations to complete.
  /// This should be called before account deletion to avoid conflicts.
  Future<void> waitForPendingOperations() async {
    if (_pendingPersist != null) {
      try {
        await _pendingPersist;
      } catch (_) {
        // Ignore errors - we're about to delete anyway
      }
      _pendingPersist = null;
    }
  }

  /// Sync current profile to team member documents in all projects the user is part of.
  /// This operation runs in parallel for better performance.
  Future<void> _syncToTeamMembers(String uid) async {
    try {
      // Check if we're deleting before starting sync
      if (_isDeleting) return;
      
      // Find all projects where the user is a member
      final projectsSnapshot = await _firestore
          .collection('projects')
          .where('members', arrayContains: uid)
          .get();
      
      // Build updated team member data once (shared across all projects)
      final updatedName = _profile.name.isNotEmpty ? _profile.name : uid.substring(0, 6);
      final updatedRole = _profile.title.isNotEmpty ? _profile.title : 'Member';
      final updatedEmail = _profile.email.isNotEmpty ? _profile.email : null;
      final updatedPhone = _profile.phone.isNotEmpty ? _profile.phone : null;
      final updatedCountry = _profile.country.isNotEmpty ? _profile.country : null;
      
      final updatedMemberData = {
        'name': updatedName,
        'role': updatedRole,
        'email': updatedEmail,
        'phone': updatedPhone,
        'country': updatedCountry,
        'uid': uid,
      };
      
      // Update all team member documents in parallel for instant sync
      await Future.wait(
        projectsSnapshot.docs.map((projectDoc) async {
          // Check again before each update in case deletion started during sync
          if (_isDeleting) return;
          
          final projectId = projectDoc.id;
          final teamMemberRef = _firestore
              .collection('projects')
              .doc(projectId)
              .collection('team')
              .doc(uid);
          
          // Update Firestore document (but only if we're not deleting)
          if (!_isDeleting) {
            await teamMemberRef.set(updatedMemberData, SetOptions(merge: true));
          }
          
          // Also update local cache immediately for better UX
          // Note: The Firestore listener will also update the cache, but this provides immediate feedback
          try {
            final teamMembers = TeamRepository.instance.membersFor(projectId);
            // Find member by matching email or name (since uid isn't stored in TeamMember model)
            final existingMemberIndex = teamMembers.indexWhere((m) => 
              (m.email != null && m.email != null && m.email == _profile.email) || 
              (m.email == null && m.name == _profile.name) ||
              (updatedEmail != null && m.email == updatedEmail)
            );
            
            if (existingMemberIndex != -1) {
              // Update existing member in local cache
              final existingMember = teamMembers[existingMemberIndex];
              final updatedMember = TeamMember(
                id: existingMember.id,
                name: updatedName,
                role: updatedRole,
                email: updatedEmail,
                phone: updatedPhone,
                country: updatedCountry,
                photoAsset: existingMember.photoAsset,
                isOnline: existingMember.isOnline,
              );
              teamMembers[existingMemberIndex] = updatedMember;
            }
          } catch (_) {
            // Local cache update failure is non-critical
            // Firestore listener will eventually sync the update
          }
        }),
        eagerError: false, // Continue even if one update fails
      );
    } catch (e) {
      // Silently fail - team member sync is best-effort
      // Profile update already succeeded, so don't block on team sync
    }
  }

  void updateNameTitle({required String name, required String title}) {
    _profile = _profile.copyWith(name: name, title: title);
    notifyListeners();
    _persist();
  }

  void updateDetails({
    String? name,
    String? title,
    String? country,
    String? phone,
    String? email,
  }) {
    _profile = _profile.copyWith(
      name: name,
      title: title,
      country: country,
      phone: phone,
      email: email,
    );
    notifyListeners();
    _persist();
  }

  /// Accept EULA and update profile.
  Future<void> acceptEula(DateTime acceptedAt) async {
    _profile = _profile.copyWith(
      eulaAccepted: true,
      eulaAcceptedAt: acceptedAt,
    );
    notifyListeners();
    await _persist();
  }


  /// Expose a way to ensure the current in-memory profile is saved immediately.
  Future<void> persist() => _persist();

  void setAvatarBytes(Uint8List bytes) {
    _profile = _profile.copyWith(avatarBytes: bytes);
    notifyListeners();
    // Avatar bytes not persisted yet (requires Storage integration).
  }

  void clearAvatar() {
    _profile = _profile.copyWith(clearAvatar: true);
    notifyListeners();
  }

  /// Call when user signs out to clear cache & listener.
  void clearOnSignOut() {
    _sub?.cancel();
    _sub = null;
    _profile = UserProfile.initial;
    _loading = false;
    // Reset deletion flag when user signs out (whether normal sign-out or account deletion)
    _isDeleting = false;
    notifyListeners();
  }
  
  /// Mark that account deletion is in progress to prevent any profile loading.
  /// Also cancels any pending persist operations.
  void markDeleting() {
    _isDeleting = true;
    _loading = false;
    _sub?.cancel();
    _sub = null;
    // Cancel pending persist - we're deleting anyway
    _pendingPersist = null;
    notifyListeners();
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.tryParse(v);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
