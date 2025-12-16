import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'task_repository.dart';
import 'stock_repository.dart';
import 'billing_repository.dart';
import 'forms_repository.dart';
import 'team_repository.dart';
import 'chat_repository.dart';
import 'media_repository.dart';
import 'notifications_repository.dart';
import 'profile_repository.dart';

/// Auth repository backed by FirebaseAuth.
/// Keeps the API stable for the UI while enabling real authentication.
class AuthRepository extends ChangeNotifier {
  AuthRepository._() {
    // Keep local state in sync with FirebaseAuth user.
    _auth.userChanges().listen((_) => notifyListeners());
  }
  static final AuthRepository instance = AuthRepository._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Tracks whether the currently signed-in account should complete onboarding
  // (first-time Google sign-in in this app session).
  bool _needsProfileSetup = false;

  bool get signedIn => _auth.currentUser != null;

  /// Whether the current user appears to be signing in for the first time.
  /// Uses Firebase [UserMetadata] where first sign-in results in
  /// [creationTime] == [lastSignInTime]. Only reliable right after sign-in.
  bool get isFirstTimeUser {
    final u = _auth.currentUser;
    if (u == null) return false;
    final meta = u.metadata;
    final created = meta.creationTime;
    final last = meta.lastSignInTime;
    if (created == null || last == null) return false;
    return created.isAtSameMomentAs(last);
  }

  /// Exposes whether the app should route to profile setup instead of home.
  bool get needsProfileSetup => _needsProfileSetup;

  /// Sign in with Google and link to FirebaseAuth.
  Future<void> signInWithGoogle() async {
    final gsi = GoogleSignIn.instance;
    // Safe to call multiple times; initializes configuration if needed.
    await gsi.initialize();
    final account = await gsi.authenticate();
    final tokens = account.authentication; // Provides idToken on v7+
    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    // Prefer SDK flag when available, otherwise fall back to metadata check
    final newFromSdk = result.additionalUserInfo?.isNewUser == true;
    _needsProfileSetup = newFromSdk || isFirstTimeUser;
    notifyListeners();
  }

  /// Sign in with Apple and link to FirebaseAuth.
  Future<void> signInWithApple() async {
    // Request Apple ID credential
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    // Create OAuth credential for Firebase
    final oauthCredential = OAuthProvider("apple.com").credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    // Sign in to Firebase with Apple credential
    final result = await _auth.signInWithCredential(oauthCredential);

    // Update display name if provided by Apple (only on first sign-in)
    if (appleCredential.givenName != null || appleCredential.familyName != null) {
      final displayName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((n) => n != null && n.isNotEmpty).join(' ');
      
      if (displayName.isNotEmpty && result.user != null) {
        await result.user!.updateDisplayName(displayName);
      }
    }

    // Check if this is a new user
    final newFromSdk = result.additionalUserInfo?.isNewUser == true;
    _needsProfileSetup = newFromSdk || isFirstTimeUser;
    notifyListeners();
  }

  Future<void> signOut() async {
    // CRITICAL: Cancel all stream subscriptions BEFORE signing out to prevent
    // permission-denied errors from Firestore snapshots that are still active.
    // This must happen before auth becomes null.
    try { ProfileRepository.instance.clearOnSignOut(); } catch (_) {}
    _cancelAllProjectStreams();
    
    try {
      // Sign out from Firebase
      await _auth.signOut();
    } finally {
      try {
        // Sign out from Google if signed in with Google
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
      // Note: Sign in with Apple doesn't require explicit sign-out
    }
    // Reset onboarding state on sign-out
    _needsProfileSetup = false;
    notifyListeners();
  }

  /// Call after the profile has been completed to route to the main app.
  void markOnboardingComplete() {
    if (_needsProfileSetup) {
      _needsProfileSetup = false;
      notifyListeners();
    }
  }

  /// Re-authenticate the current user based on their sign-in provider.
  /// This is required before sensitive operations like account deletion.
  /// Handles linked accounts (both Google and Apple) by trying both if available.
  Future<void> _reauthenticateUser() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    // Get the user's provider data to determine how they signed in
    final providerData = user.providerData;
    if (providerData.isEmpty) {
      throw Exception('No provider data found');
    }

    // Check which providers are available (user might have both Google and Apple linked)
    final hasGoogle = providerData.any((p) => p.providerId == 'google.com');
    final hasApple = providerData.any((p) => p.providerId == 'apple.com');

    // Try Google first if available, then Apple if Google fails or isn't available
    if (hasGoogle) {
      try {
        // Re-authenticate with Google
        final gsi = GoogleSignIn.instance;
        await gsi.initialize();
        final account = await gsi.authenticate();
        final tokens = account.authentication; // Provides idToken on v7+
        final credential = GoogleAuthProvider.credential(
          idToken: tokens.idToken,
        );
        await user.reauthenticateWithCredential(credential);
        return; // Success, exit early
      } catch (e) {
        // Check if it's a cancellation error
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('cancelled') || errorStr.contains('canceled') || errorStr.contains('sign_in_canceled')) {
          // User cancelled Google sign-in - try Apple if available
          if (hasApple) {
            // Fall through to try Apple
          } else {
            throw Exception('Re-authentication cancelled');
          }
        } else {
          // If Google re-authentication fails and Apple is also available, try Apple
          if (hasApple) {
            // Fall through to try Apple (might be a different error, but try Apple anyway)
          } else {
            // No Apple fallback, rethrow the error
            throw Exception('Google re-authentication failed: $e');
          }
        }
      }
    }

    // Try Apple if Google wasn't available or failed
    if (hasApple) {
      try {
        // Re-authenticate with Apple
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final oauthCredential = OAuthProvider("apple.com").credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode,
        );
        await user.reauthenticateWithCredential(oauthCredential);
        return; // Success
      } catch (e) {
        // Check if it's a cancellation error
        if (e.toString().contains('cancelled') || e.toString().contains('canceled')) {
          throw Exception('Re-authentication cancelled');
        }
        throw Exception('Apple re-authentication failed: $e');
      }
    }

    // If we get here, no supported providers were found
    throw Exception('No supported authentication providers found. Available: ${providerData.map((p) => p.providerId).join(", ")}');
  }

  /// Delete the current user's account and all associated data.
  /// This includes:
  /// - User profile from Firestore (users/{uid})
  /// - User's team member documents from all projects
  /// - User's UID from all project members arrays
  /// - Projects where the user is the only member
  /// - Firebase Auth account
  /// 
  /// After deletion, the user will be signed out automatically.
  /// 
  /// Note: This method requires recent authentication. If the user hasn't
  /// authenticated recently, they will be prompted to re-authenticate.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    try {
      // 0. Re-authenticate user before deletion (required by Firebase for sensitive operations)
      try {
        await _reauthenticateUser();
      } catch (e) {
        // If re-authentication fails, wrap the error to provide context
        throw Exception('Re-authentication required: ${e.toString()}');
      }
      // 1. Wait for any pending profile persist operations to complete
      // This prevents conflicts between profile updates and account deletion
      try {
        await ProfileRepository.instance.waitForPendingOperations();
      } catch (_) {}
      
      // 2. Mark account deletion in progress to prevent any profile loading
      // This stops any pending ensureLoaded() calls and cancels subscriptions
      try { 
        ProfileRepository.instance.markDeleting();
      } catch (_) {}
      
      // 3. Cancel all project stream subscriptions BEFORE deletion
      _cancelAllProjectStreams();
      
      // 4. Reset auth state immediately to prevent routing issues
      _needsProfileSetup = false;
      notifyListeners();

      // 5. Find all projects where the user is a member
      final projectsSnapshot = await firestore
          .collection('projects')
          .where('members', arrayContains: uid)
          .get();

      // 6. Separate projects into two groups:
      //    - Projects where user is the only member (will be deleted)
      //    - Projects with other members (user will be removed)
      final projectsToDelete = <String>[];
      final batch = firestore.batch();
      
      for (final projectDoc in projectsSnapshot.docs) {
        final projectData = projectDoc.data();
        final members = (projectData['members'] as List?)?.cast<String>() ?? <String>[];
        
        // Check if user is the only member
        if (members.length == 1 && members.contains(uid)) {
          // Mark project for deletion
          projectsToDelete.add(projectDoc.id);
        } else {
          // Remove user from members array and delete team member document
          final projectRef = projectDoc.reference;
          batch.update(projectRef, {
            'members': FieldValue.arrayRemove([uid]),
            'teamTotal': FieldValue.increment(-1),
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Delete team member document
          final teamMemberRef = projectRef.collection('team').doc(uid);
          batch.delete(teamMemberRef);
        }
      }

      // 7. Delete user profile document
      final userProfileRef = firestore.collection('users').doc(uid);
      batch.delete(userProfileRef);

      // 8. Commit all Firestore updates (removing user from projects with other members)
      // Add timeout to prevent hanging if batch is too large or network is slow
      try {
        await batch.commit().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Batch commit timed out');
          },
        );
      } catch (e) {
        // If batch fails, try individual operations as fallback in parallel
        // This ensures deletion continues even if batch is too large
        final projectsToUpdate = <DocumentReference>[];
        final teamMembersToDelete = <DocumentReference>[];
        
        for (final projectDoc in projectsSnapshot.docs) {
          final projectData = projectDoc.data();
          final members = (projectData['members'] as List?)?.cast<String>() ?? <String>[];
          
          // Only process projects with other members (skip projects to delete)
          if (members.length > 1 && members.contains(uid)) {
            final projectRef = projectDoc.reference;
            projectsToUpdate.add(projectRef);
            teamMembersToDelete.add(projectRef.collection('team').doc(uid));
          }
        }
        
        // Run all updates and deletions in parallel for better performance
        await Future.wait([
          // Update all projects in parallel
          ...projectsToUpdate.map((projectRef) async {
            try {
              await projectRef.update({
                'members': FieldValue.arrayRemove([uid]),
                'teamTotal': FieldValue.increment(-1),
                'updatedAt': DateTime.now().toIso8601String(),
              });
            } catch (_) {
              // Continue even if one fails
            }
          }),
          // Delete all team member documents in parallel
          ...teamMembersToDelete.map((teamMemberRef) async {
            try {
              await teamMemberRef.delete();
            } catch (_) {
              // Continue even if one fails
            }
          }),
        ], eagerError: false);
        
        // Try to delete user profile (CRITICAL: must delete to prevent recreation)
        try {
          await userProfileRef.delete();
        } catch (_) {}
      }
      
      // 9. Delete projects where user is the only member
      // Run deletions in parallel for better performance
      if (projectsToDelete.isNotEmpty) {
        await Future.wait(
          projectsToDelete.map((projectId) => _deleteProjectWithSubcollections(firestore, projectId)),
          eagerError: false, // Continue even if one project deletion fails
        );
      }

      // 10. Final deletion of user document to ensure it's completely removed
      // This happens after all other operations to prevent any race conditions
      // where other operations might recreate the document
      try {
        // Delete the user document one more time to ensure it's gone
        // This handles cases where lastProjectId writes might have recreated it
        final userDoc = await userProfileRef.get();
        if (userDoc.exists) {
          await userProfileRef.delete();
        }
      } catch (_) {
        // Best-effort deletion
      }

      // 11. Delete Firebase Auth account
      // This will trigger userChanges() stream with null, which will automatically
      // call ProfileRepository.clearOnSignOut() and reset the deletion flag
      await user.delete();

      // 8. Sign out from Google if applicable
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}

      // 9. Reset state to ensure proper routing to login page
      // Note: user.delete() will trigger userChanges() which will cause
      // ProfileRepository to call clearOnSignOut() automatically.
      // We reset _needsProfileSetup here to ensure AuthGate routes to LoginPage.
      _needsProfileSetup = false;
      notifyListeners();
    } catch (e) {
      // If deletion fails, rethrow so UI can handle it
      rethrow;
    }
  }

  /// Delete a project and all its subcollections efficiently.
  /// This is optimized to run deletions in parallel where possible.
  Future<void> _deleteProjectWithSubcollections(FirebaseFirestore firestore, String projectId) async {
    try {
      final projectRef = firestore.collection('projects').doc(projectId);
      
      // Delete all subcollections in parallel for better performance
      final subcollections = ['team', 'tasks', 'stock', 'forms', 'expenses', 'media', 'notifications'];
      await Future.wait(
        subcollections.map((subcolName) => _deleteCollection(firestore, projectRef.collection(subcolName))),
        eagerError: false,
      );
      
      // Delete chats and their subcollections
      try {
        final chatsCol = projectRef.collection('chats');
        final chatSnap = await chatsCol.get();
        
        // Delete all chat subcollections in parallel
        await Future.wait(
          chatSnap.docs.map((chatDoc) async {
            try {
              // Delete messages and readBy subcollections in parallel
              await Future.wait([
                _deleteCollection(firestore, chatDoc.reference.collection('messages')),
                _deleteCollection(firestore, chatDoc.reference.collection('readBy')),
              ], eagerError: false);
              // Delete chat document
              await chatDoc.reference.delete();
            } catch (_) {}
          }),
          eagerError: false,
        );
      } catch (_) {}
      
      // Delete all reports for this project (with pagination for large numbers)
      try {
        const batchSize = 300;
        while (true) {
          final reportsSnap = await firestore
              .collection('reports')
              .where('projectId', isEqualTo: projectId)
              .limit(batchSize)
              .get();
          
          if (reportsSnap.docs.isEmpty) break;
          
          final batch = firestore.batch();
          for (final doc in reportsSnap.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      } catch (_) {
        // Best-effort deletion - continue even if deletion fails
      }
      
      // Finally, delete the project document itself
      await projectRef.delete();
    } catch (_) {
      // Best-effort deletion - continue even if deletion fails
    }
  }
  
  /// Delete all documents in a collection using batched deletes.
  Future<void> _deleteCollection(FirebaseFirestore firestore, CollectionReference colRef) async {
    try {
      const batchSize = 300;
      while (true) {
        final snap = await colRef.limit(batchSize).get();
        if (snap.docs.isEmpty) break;
        final deleteBatch = firestore.batch();
        for (final doc in snap.docs) {
          deleteBatch.delete(doc.reference);
        }
        await deleteBatch.commit();
      }
    } catch (_) {
      // Silently fail - best-effort deletion
    }
  }

  // Central teardown of all repository listeners. Silent best-effort.
  // Note: ProfileRepository is handled separately in signOut() to ensure it happens first.
  void _cancelAllProjectStreams() {
    // Each repository now exposes a stopAll() for bulk teardown.
    try { TaskRepository.instance.stopAll(); } catch (_) {}
    try { StockRepository.instance.stopAll(); } catch (_) {}
    try { BillingRepository.instance.stopAll(); } catch (_) {}
    try { FormsRepository.instance.stopAll(); } catch (_) {}
    try { TeamRepository.instance.stopAll(); } catch (_) {}
    try { ChatRepository.instance.stopAll(); } catch (_) {}
    try { MediaRepository.instance.stopAll(); } catch (_) {}
    try { NotificationsRepository.instance.stopAll(); } catch (_) {}
  }
}
