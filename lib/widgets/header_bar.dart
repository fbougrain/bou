import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/colors.dart';

/// Compact top header bar with project selector and quick action icons.
class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.projectName,
    required this.onOpenProjects,
    required this.onOpenTeam,
    required this.onOpenNotifications,
    required this.onOpenChat,
  });

  final String projectName;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.only(top: 12, left: 16, right: 10),
      color: backgroundDark,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpenProjects,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onOpenTeam,
                icon: const Icon(AppIcons.team, color: Colors.white),
              ),
              IconButton(
                onPressed: onOpenNotifications,
                icon: const Icon(AppIcons.notifications, color: Colors.white),
              ),
              IconButton(
                onPressed: onOpenChat,
                icon: const Icon(AppIcons.chats, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
