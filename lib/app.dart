import 'package:flutter/material.dart';
import 'widgets/auth_gate.dart';
import 'state/auth_scope.dart';
import 'data/auth_repository.dart';
import 'theme/app_theme.dart';
import 'state/profile_scope.dart';
import 'data/profile_repository.dart';

class SuperAppConstruction extends StatelessWidget {
  const SuperAppConstruction({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileScope(
      notifier: ProfileRepository.instance,
      child: AuthScope(
        notifier: AuthRepository.instance,
        child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Construction Superapp',
      theme: AppTheme.dark,
      home: const AuthGate(),
      builder: (context, child) {
        // Global unfocus when tapping anywhere outside inputs/clickables
        return Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) {
            final currentFocus = FocusManager.instance.primaryFocus;
            if (currentFocus != null && currentFocus.hasFocus) {
              currentFocus.unfocus();
            }
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      ),
      ),
    );
  }
}
