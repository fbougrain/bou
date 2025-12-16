import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';

enum PanelSide { left, right }

class PanelScaffold extends StatelessWidget {
  const PanelScaffold({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.side = PanelSide.right,
    this.fab,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final PanelSide side;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final backBtn = IconButton(
      icon: Icon(
        side == PanelSide.left ? AppIcons.backright : AppIcons.back,
        color: Colors.white,
        size: 20,
      ),
      onPressed: onClose,
    );
    return Scaffold(
      backgroundColor: backgroundDark,
      appBar: AppBar(
        backgroundColor: backgroundDark,
        elevation: 0,
        // Prevent Material 3 scroll-under behavior from tinting the bar when content scrolls.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        leading: side == PanelSide.right ? backBtn : null,
        actions: side == PanelSide.left ? [backBtn] : null,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: child,
      floatingActionButton: fab,
    );
  }
}
