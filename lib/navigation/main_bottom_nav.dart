import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import 'main_sections.dart';

class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
  });
  final MainSection current;
  final ValueChanged<MainSection> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    height: 80,
    padding: const EdgeInsets.only(bottom: 14),
    decoration: const BoxDecoration(
      color: backgroundDark,
      border: Border(top: BorderSide(color: borderDark)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _icon(MainSection.home, AppIcons.home.regular, AppIcons.home.filled),
        _icon(
          MainSection.project,
          AppIcons.project.regular,
          AppIcons.project.filled,
        ),
        _icon(MainSection.media, AppIcons.media.regular, AppIcons.media.filled),
        _icon(
          MainSection.profile,
          AppIcons.profile.regular,
          AppIcons.profile.filled,
        ),
      ],
    ),
  );

  Widget _icon(MainSection section, IconData regular, IconData filled) {
    final active = current == section;
    return GestureDetector(
      onTap: () => onSelect(section),
      child: Icon(active ? filled : regular, color: navActive, size: 28),
    );
  }
}
