import 'package:flutter/material.dart';
import '../state/auth_scope.dart';
// Removed direct MainShell import; bootstrap now handles showing it.
import 'post_auth_bootstrap.dart';
import '../pages/login_page.dart';
import '../pages/profile_setup_page.dart';
import '../pages/eula_page.dart';
import '../state/profile_scope.dart';

/// Shows the main app when signed in; otherwise shows the LoginPage.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context); // listen for changes
    
    // CRITICAL: Always check auth state first - if not signed in, go to login immediately
    // This prevents any race conditions where profile might still be loading after account deletion
    if (!auth.signedIn) {
      return const LoginPage();
    }
    
    final profileRepo = ProfileScope.of(context);
    
    // If profile is loading, show loading indicator
    // But only if user is actually signed in (double-check to prevent race conditions)
    if (profileRepo.loading && auth.signedIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    // Final safety check: if user is no longer signed in, go to login
    if (!auth.signedIn) {
      return const LoginPage();
    }
    
    final profile = profileRepo.profile;
    
    // Check EULA acceptance first (before profile setup)
    if (!profile.eulaAccepted) {
      return const EulaPage();
    }
    
    // Only check profile setup if user is actually signed in
    if (auth.needsProfileSetup || profile.isIncomplete) {
      return const ProfileSetupPage();
    }
  // Perform post-auth bootstrap (demo project seeding) before showing main shell.
  return const PostAuthBootstrap();
  }
}
