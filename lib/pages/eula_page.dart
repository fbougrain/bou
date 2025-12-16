import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../state/profile_scope.dart';
import '../state/auth_scope.dart';

/// EULA (End User License Agreement) page shown before profile setup.
/// Users must accept the terms to proceed.
class EulaPage extends StatefulWidget {
  const EulaPage({super.key});

  @override
  State<EulaPage> createState() => _EulaPageState();
}

class _EulaPageState extends State<EulaPage> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _acceptEula() async {
    if (!_accepted) return;

    setState(() => _saving = true);
    final profileRepo = ProfileScope.of(context, listen: false);
    
    try {
      // Update profile with EULA acceptance
      final now = DateTime.now();
      await profileRepo.acceptEula(now);
      await profileRepo.persist();
    } catch (_) {
      // Ignore errors to keep UX flowing
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    
    if (!mounted) return;
    // Mark onboarding complete so AuthGate shows profile setup or main app
    AuthScope.of(context, listen: false).markOnboardingComplete();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: backgroundDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Match login gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surfaceDarker,
                  surfaceDark,
                  backgroundDark,
                ],
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.black.withValues(alpha: 0.08)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Terms of Service',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Please read and accept our terms to continue.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: neutralText.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surfaceDarker,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User-Generated Content Policy',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'By using this app, you agree to the following terms:',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: neutralText,
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _BulletPoint(
                          text:
                              'You will not post, share, or transmit any objectionable content, including but not limited to: harassment, hate speech, threats, spam, or illegal content.',
                        ),
                        const SizedBox(height: 8),
                        _BulletPoint(
                          text:
                              'You will not engage in abusive behavior towards other users.',
                        ),
                        const SizedBox(height: 8),
                        _BulletPoint(
                          text:
                              'We have a zero-tolerance policy for objectionable content and abusive users. Violations may result in immediate account suspension or termination.',
                        ),
                        const SizedBox(height: 8),
                        _BulletPoint(
                          text:
                              'You can report objectionable content or abusive users through the in-app reporting feature. Reports are sent to the project owner for review.',
                        ),
                        const SizedBox(height: 8),
                        _BulletPoint(
                          text:
                              'Project owners have the authority to remove (kick) users from their projects for violating these terms or engaging in abusive behavior.',
                        ),
                        const SizedBox(height: 8),
                        _BulletPoint(
                          text:
                              'As a project management application, moderation is handled by project owners and administrators. Users who are removed from a project will no longer have access to that project\'s content or be able to contact project members.',
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Project owners and administrators reserve the right to review and remove any content or users that violate these terms. Reports will be reviewed within 24 hours, and appropriate action will be taken, including removing objectionable content and ejecting users who provided the offending content.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: neutralText.withValues(alpha: 0.8),
                                height: 1.5,
                                // fontStyle: FontStyle.italic,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Checkbox(
                        value: _accepted,
                        onChanged: (value) {
                          setState(() => _accepted = value ?? false);
                        },
                        activeColor: newaccent,
                        checkColor: Colors.white,
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _accepted = !_accepted);
                          },
                          child: Text(
                            'I have read and agree to the Terms of Service',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: size.height * 0.04),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _accepted ? Colors.black : surfaceDarker,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                      onPressed: (_accepted && !_saving) ? _acceptEula : null,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(
                              'Accept and Continue',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: newaccent,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
        ),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: neutralText,
                  height: 1.5,
                ),
          ),
        ),
      ],
    );
  }
}
