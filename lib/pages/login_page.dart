import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/colors.dart';
import '../widgets/overlay_notice.dart';
import '../state/auth_scope.dart';

/// A themed login/landing page that mimics the provided mock.
/// - Dark, blurry gradient background
/// - App icon at top (assets/logo.png)
/// - "Welcome to" + brand headline
/// - Tagline
/// - Primary CTA: Continue with Google
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: backgroundDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 57,
                    width: 57,
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Icon(
                        Icons.construction_rounded,
                        size: 40,
                        color: neutralText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Welcome to',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: neutralText.withValues(alpha: 0.7),
                          letterSpacing: 0.2,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Binaytech',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A construction site,\n in the palm of your hand.',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: neutralText.withValues(alpha: 0.85),
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Spacer(),
                  _GoogleCta(
                    onPressed: () async {
                      final auth = AuthScope.of(context, listen: false);
                      final wasSignedIn = auth.signedIn;
                      try {
                        await auth.signInWithGoogle();
                        if (context.mounted && auth.signedIn && !wasSignedIn) {
                          showOverlayNotice(
                            context,
                            'Signed in with Google',
                            duration: const Duration(seconds: 2),
                            liftAboveNav: false,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showOverlayNotice(
                            context,
                            'Google sign-in failed. Try again later.',
                            duration: const Duration(seconds: 3),
                            liftAboveNav: false,
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _AppleCta(
                    onPressed: () async {
                      final auth = AuthScope.of(context, listen: false);
                      final wasSignedIn = auth.signedIn;
                      try {
                        await auth.signInWithApple();
                        if (context.mounted && auth.signedIn && !wasSignedIn) {
                          showOverlayNotice(
                            context,
                            'Signed in with Apple',
                            duration: const Duration(seconds: 2),
                            liftAboveNav: false,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showOverlayNotice(
                            context,
                            'Apple sign-in failed. Try again later.',
                            duration: const Duration(seconds: 3),
                            liftAboveNav: false,
                          );
                        }
                      }
                    },
                  ),
                  SizedBox(height: size.height * 0.04),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _GoogleCta extends StatelessWidget {
  const _GoogleCta({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _FullWidthButton(
      background: Colors.black,
      foreground: Colors.white,
      leading: SvgPicture.asset(
        'assets/google_g.svg',
        width: 20,
        height: 20,
        fit: BoxFit.contain,
      ),
      label: 'Continue with Google',
      onPressed: onPressed,
    );
  }
}

class _FullWidthButton extends StatelessWidget {
  const _FullWidthButton({
    required this.background,
    required this.foreground,
    required this.label,
    required this.onPressed,
    this.leading,
  });

  final Color background;
  final Color foreground;
  final String label;
  final VoidCallback onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleCta extends StatelessWidget {
  const _AppleCta({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _FullWidthButton(
      background: Colors.white,
      foreground: Colors.black,
      leading: SvgPicture.asset(
        'assets/apple_logo.svg',
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
      ),
      label: 'Continue with Apple',
      onPressed: onPressed,
    );
  }
}
