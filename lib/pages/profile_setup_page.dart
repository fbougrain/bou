import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../state/profile_scope.dart';
import '../state/auth_scope.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  late final TextEditingController _name;
  late final TextEditingController _title;
  late final TextEditingController _country;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  bool _nameError = false;
  bool _titleError = false;
  bool _countryError = false;
  bool _phoneError = false;
  bool _emailError = false;
  bool _phoneFormatError = false;
  bool _emailFormatError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    _name = TextEditingController(text: u?.displayName ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _title = TextEditingController();
    _country = TextEditingController();
    _phone = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _country.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final title = _title.text.trim();
    final country = _country.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();

    final missingName = name.isEmpty;
    final missingTitle = title.isEmpty;
    final missingEmail = email.isEmpty;

    // Country and Phone are now optional - only validate format if provided
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final phoneFormatBad = phone.isNotEmpty && phoneDigits.length < 8; // minimal digits only if phone is provided
    final emailFormatBad = !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

    setState(() {
      _nameError = missingName;
      _titleError = missingTitle;
      _countryError = false; // Country is optional
      _phoneError = false; // Phone is optional
      _emailError = missingEmail;
      _phoneFormatError = phoneFormatBad;
      _emailFormatError = !missingEmail && emailFormatBad;
    });
    if (missingName || missingTitle || missingEmail || phoneFormatBad || emailFormatBad) return;

    final profileRepo = ProfileScope.of(context, listen: false);
    profileRepo.updateDetails(
      name: name,
      title: title,
      country: country,
      phone: phone,
      email: email,
    );
    setState(() => _saving = true);
    try {
      // Persist to Firestore under users/{uid}; don't crash on connectivity/plugin issues
      await profileRepo.persist();
    } catch (_) {
      // Ignore to keep UX flowing; in-memory profile still updated
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return; // safe context usage after async
    // ensureLoaded creates doc if missing and sets up listener; updateDetails already persisted
    // Mark onboarding complete so AuthGate shows the main app.
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
                      'Set up your profile',
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
                      'We just need a few details to personalize your experience.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: neutralText.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _Field(
                    label: 'Name',
                    controller: _name,
                    error: _nameError,
                    onTap: () => setState(() => _nameError = false),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Title',
                    controller: _title,
                    error: _titleError,
                    onTap: () => setState(() => _titleError = false),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Country (Optional)',
                    controller: _country,
                    error: _countryError,
                    onTap: () => setState(() => _countryError = false),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Phone (Optional)',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    error: _phoneError || _phoneFormatError,
                    onTap: () => setState(() { _phoneError = false; _phoneFormatError = false; }),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'E-Mail',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    error: _emailError || _emailFormatError,
                    onTap: () => setState(() { _emailError = false; _emailFormatError = false; }),
                  ),
                  SizedBox(height: size.height * 0.04),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                      ),
                      onPressed: _saving ? null : _save,
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
                              'Save and continue',
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.error = false,
    this.onTap,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final bool error;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
      keyboardType: keyboardType,
      inputFormatters: label == 'Phone'
          ? [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
              TextInputFormatter.withFunction((oldValue, newValue) {
                final text = newValue.text;
                if (text.isEmpty) return newValue;
                final first = text[0] == '+' ? '+' : '';
                final digits = text.substring(first.isEmpty ? 0 : 1).replaceAll('+', '');
                final sanitized = first + digits;
                if (sanitized == text) return newValue;
                return TextEditingValue(
                  text: sanitized,
                  selection: TextSelection.collapsed(offset: sanitized.length),
                );
              }),
            ]
          : null,
      maxLines: 1,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelBehavior:
            error ? FloatingLabelBehavior.always : FloatingLabelBehavior.auto,
        hintText: error ? 'Required' : null,
        hintStyle: const TextStyle(color: Colors.redAccent),
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: surfaceDarker,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : borderDark,
            width: error ? 1.2 : 1.1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : borderDark,
            width: error ? 1.2 : 1.1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : newaccent.withValues(alpha: 0.95),
            width: error ? 1.3 : 1.6,
          ),
        ),
      ),
    );
  }
}
