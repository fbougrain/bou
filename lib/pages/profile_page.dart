import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../state/profile_scope.dart';
import '../state/auth_scope.dart';
import '../widgets/overlay_notice.dart';
import '../models/user_profile.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  // All profile state now lives in ProfileRepository (global, persists across pages).

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final repo = ProfileScope.of(context, listen: false);
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        repo.setAvatarBytes(bytes);
      }
    } on MissingPluginException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image picking isn\'t available (plugin not registered). Please stop the app and run it again so plugins are rebuilt.\nDetails: ${e.message}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  void _showAvatarOptions() {
    final repo = ProfileScope.of(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(AppIcons.camera, color: Colors.white),
                title: const Text('Take photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(AppIcons.folderOpen, color: Colors.white),
                title: const Text('Choose from library', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAvatar(ImageSource.gallery);
                },
              ),
              if (repo.profile.avatarBytes != null)
                ListTile(
                  leading: const Icon(AppIcons.delete, color: Colors.redAccent),
                  title: const Text('Remove photo', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    repo.clearAvatar();
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditSheet() {
    final repo = ProfileScope.of(context, listen: false);
    final nameController = TextEditingController(text: repo.profile.name);
    final titleController = TextEditingController(text: repo.profile.title);
    final countryController =
        TextEditingController(text: repo.profile.country);
    final phoneController = TextEditingController(text: repo.profile.phone);
    final emailController = TextEditingController(text: repo.profile.email);
    showModalBottomSheet<Map<String, String>?>(
      context: context,
      backgroundColor: surfaceDark,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (_) => _EditProfileSheet(
        nameController: nameController,
        titleController: titleController,
        countryController: countryController,
        phoneController: phoneController,
        emailController: emailController,
      ),
    ).then((res) {
      if (res == null) return;
      final newName = res['name'];
      final newTitle = res['title'];
      final newCountry = res['country'];
      final newPhone = res['phone'];
      final newEmail = res['email'];
      if (newName != null && newTitle != null) {
        repo.updateDetails(
          name: newName,
          title: newTitle,
          country: newCountry,
          phone: newPhone,
          email: newEmail,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for profile updates via ProfileScope
    final profile = ProfileScope.of(context).profile;
    return Scaffold(
      backgroundColor: backgroundDark,
      floatingActionButton: _FloatingEdit(onTap: _openEditSheet),
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fade,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 22),
                _HeroIdentityCard(
                  name: profile.name,
                  title: profile.title,
                  avatarBytes: profile.avatarBytes,
                  onChangeAvatar: _showAvatarOptions,
                ),
                const SizedBox(height: 28),
                _ProfileInfoCard(profile: profile),
                const SizedBox(height: 36),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LogoutButton(onTap: () async {
                    final auth = AuthScope.of(context, listen: false);
                    await auth.signOut();
                    if (!context.mounted) return;
                    showOverlayNotice(
                      context,
                      'Signed out',
                      duration: const Duration(seconds: 2),
                      liftAboveNav: false,
                    );
                  }),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _DeleteAccountButton(onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: surfaceDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Delete Account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Are you sure you want to delete your account? This action cannot be undone. All your data will be permanently deleted.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: newaccentbackground,
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.redAccent.withValues(alpha: 0.95),
                                    width: 0.8,
                                  ),
                                  elevation: 6,
                                  shadowColor: Colors.redAccent.withValues(alpha: 0.10),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                ),
              ],
            ),
          ),
                    );
                    
                    if (confirmed != true || !context.mounted) return;
                    
                    // Don't show loading dialog yet - re-authentication needs to happen first
                    // The re-authentication prompts must be able to appear
                    try {
                      final auth = AuthScope.of(context, listen: false);
                      
                      // Start deletion - re-authentication will happen first inside deleteAccount
                      // We'll show loading dialog after re-auth succeeds
                      final deletionFuture = auth.deleteAccount();
                      
                      // Wait a bit to see if re-auth succeeds, then show loading
                      // This allows re-auth prompts to appear first
                      await Future.delayed(const Duration(milliseconds: 500));
                      
                      // Now show loading dialog (re-auth should be done or in progress)
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        barrierColor: backgroundDark,
                        builder: (context) => Scaffold(
                          backgroundColor: backgroundDark,
                          body: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      );
                      
                      // Wait for deletion to complete
                      await deletionFuture;
                      
                      // After deletion, user.delete() signs out the user immediately
                      // AuthGate will automatically route to LoginPage via userChanges() stream
                      // We need to close the dialog, but the context might be invalid if navigation already changed
                      if (context.mounted) {
                        try {
                          Navigator.of(context).pop();
                        } catch (_) {
                          // Dialog might have already been closed or context invalid
                          // This is fine - user is being routed to login page
                        }
                      }
                      
                      // Don't show success message - user is already being routed to login page
                      // Showing a message here could cause issues if navigation has already changed
                    } catch (e) {
                      if (!context.mounted) return;
                      
                      // Close loading dialog if it was shown
                      try {
                        Navigator.of(context).pop();
                      } catch (_) {
                        // Dialog might not have been shown yet
                      }
                      
                      // Show error message - styled to match delete account pop-up
                      final errorMessage = e.toString().toLowerCase();
                      final isReauthError = errorMessage.contains('re-authentication') || 
                                           errorMessage.contains('reauthentication') ||
                                           errorMessage.contains('requires-recent-login');
                      
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: surfaceDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isReauthError ? 'Re-authentication required' : 'Error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isReauthError 
                                  ? 'Failed to delete account. Please re-authenticate and try again.'
                                  : 'Failed to delete account: ${e.toString().replaceAll('Exception: ', '').replaceAll('Re-authentication required: ', '')}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: newaccentbackground,
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: newaccent.withValues(alpha: 0.95),
                                      width: 0.8,
                                    ),
                                    elevation: 6,
                                    shadowColor: newaccent.withValues(alpha: 0.10),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text(
                                    'OK',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Removed header decoration per request.

class _Avatar extends StatelessWidget {
  const _Avatar({this.bytes, this.onTap});
  final Uint8List? bytes;
  final VoidCallback? onTap;
  static const double size = 86;
  static const double border = 2;
  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    final avatar = ClipOval(
      child: Builder(
        builder: (_) {
          if (bytes != null) {
            return Image.memory(
              bytes!,
              fit: BoxFit.cover,
            );
          }
          
          return Image.asset(
            'assets/profile_placeholder.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              color: surfaceDark,
              alignment: Alignment.center,
              child: Icon(
                AppIcons.profile.regular,
                color: Colors.white.withValues(alpha: 0.75),
                size: radius * 0.9,
              ),
            ),
          );
        },
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: size + border * 2,
            height: size + border * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: border,
              ),
            ),
            child: avatar,
          ),
          // Small camera badge
          Container(
            decoration: BoxDecoration(
              color: newaccentbackground.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              border: Border.all(color: newaccent, width: 1),
            ),
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(right: 3, bottom: 3),
            child: Icon(
              AppIcons.edit,
              size: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroIdentityCard extends StatelessWidget {
  const _HeroIdentityCard({
    required this.name,
    required this.title,
    this.avatarBytes,
    this.onChangeAvatar,
  });
  final String name;
  final String title;
  final Uint8List? avatarBytes;
  final VoidCallback? onChangeAvatar;
  @override
  Widget build(BuildContext context) {
    // Progress and project statistics removed per request.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderDark, width: 1.1),
        gradient: const LinearGradient(
          colors: [surfaceDarker, surfaceDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(bytes: avatarBytes, onTap: onChangeAvatar),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                    ),
                    _StatusDot(
                      label: 'Online',
                      color: Colors.greenAccent.shade400,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: neutralText.withValues(alpha: 0.85),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                // Removed mini stats row.
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusDot({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.profile});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: surfaceDark,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: borderDark, width: 1.1),
    ),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(AppIcons.profile.regular, 'Name', _fallback(profile.name)),
        _divider(),
        _infoRow(AppIcons.title, 'Title', _fallback(profile.title)),
        _divider(),
        _infoRow(AppIcons.location, 'Country', _fallback(profile.country)),
        _divider(),
        _infoRow(AppIcons.phone, 'Phone', _fallback(profile.phone)),
        _divider(),
        _infoRow(AppIcons.mail, 'E-Mail', _fallback(profile.email)),
      ],
    ),
  );

  String _fallback(String value) => value.isEmpty ? '—' : value;

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: neutralText.withValues(alpha: 0.85),
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: neutralText.withValues(alpha: 0.55),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );

  Widget _divider() => Divider(
    height: 1,
    thickness: 1,
    color: borderDark.withValues(alpha: 0.35),
  );
}

// Copy button removed as per request

// _TopIdentity removed; replaced by _IdentityCard

class _FloatingEdit extends StatelessWidget {
  const _FloatingEdit({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF191B1B),
      foregroundColor: Colors.white,
      side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
      elevation: 6,
      shadowColor: newaccent.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(18, 14, 22, 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(AppIcons.edit, color: Colors.white, size: 22),
        SizedBox(width: 10),
        Text(
          'Edit',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 24, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2530),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderDark, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.logout, size: 18, color: Colors.redAccent.shade200),
          const SizedBox(width: 10),
          const Text(
            'Sign-out',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 24, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2530),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderDark, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.deleteFilled, size: 18, color: Colors.redAccent.shade200),
          const SizedBox(width: 10),
          const Text(
            'Delete Account',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.error = false,
    this.onTap,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final bool error;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
      maxLines: 1,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelBehavior: error
            ? FloatingLabelBehavior.always
            : FloatingLabelBehavior.auto,
        hintText: error ? 'Required' : null,
        hintStyle: const TextStyle(color: Colors.redAccent),
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
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
            color: error
                ? Colors.redAccent
                : newaccent.withValues(alpha: 0.95),
            width: error ? 1.3 : 1.6,
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.nameController,
    required this.titleController,
    required this.countryController,
    required this.phoneController,
    required this.emailController,
  });
  final TextEditingController nameController;
  final TextEditingController titleController;
  final TextEditingController countryController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  bool _nameError = false;
  bool _titleError = false;
  bool _countryError = false;
  bool _phoneError = false;
  bool _emailError = false;
  bool _phoneFormatError = false;
  bool _emailFormatError = false;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _TextField(
                label: 'Name',
                controller: widget.nameController,
                error: _nameError,
                onTap: () => setState(() => _nameError = false),
              ),
              const SizedBox(height: 12),
              _TextField(
                label: 'Title',
                controller: widget.titleController,
                error: _titleError,
                onTap: () => setState(() => _titleError = false),
              ),
              const SizedBox(height: 12),
              _TextField(
                label: 'Country (Optional)',
                controller: widget.countryController,
                error: _countryError,
                onTap: () => setState(() => _countryError = false),
              ),
              const SizedBox(height: 12),
              _TextField(
                label: 'Phone (Optional)',
                controller: widget.phoneController,
                error: _phoneError || _phoneFormatError,
                onTap: () => setState(() {
                  _phoneError = false;
                  _phoneFormatError = false;
                }),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final text = newValue.text;
                    // Allow a single leading '+'; strip any subsequent '+' characters.
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
                ],
              ),
              const SizedBox(height: 12),
              _TextField(
                label: 'E-Mail',
                controller: widget.emailController,
                error: _emailError || _emailFormatError,
                onTap: () => setState(() {
                  _emailError = false;
                  _emailFormatError = false;
                }),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: newaccentbackground,
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: newaccent.withValues(alpha: 0.95),
                      width: 1.6,
                    ),
                    elevation: 6,
                    shadowColor: newaccent.withValues(alpha: 0.10),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    final newName = widget.nameController.text.trim();
                    final newTitle = widget.titleController.text.trim();
                    final newCountry = widget.countryController.text.trim();
                    final newPhone = widget.phoneController.text.trim();
                    final newEmail = widget.emailController.text.trim();
                    final missingName = newName.isEmpty;
                    final missingTitle = newTitle.isEmpty;
                    final missingEmail = newEmail.isEmpty;
                    // Basic format checks - Country and Phone are now optional
                    final phoneDigitsOnly = newPhone.replaceAll(RegExp(r'\D'), '');
                    final phoneFormatBad = newPhone.isNotEmpty && phoneDigitsOnly.length < 8; // minimal length only if phone is provided
                    final emailFormatBad = !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(newEmail);
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
                    Navigator.pop(context, {
                      'name': newName,
                      'title': newTitle,
                      'country': newCountry,
                      'phone': newPhone,
                      'email': newEmail,
                    });
                  },
                  child: const Text('Save changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
