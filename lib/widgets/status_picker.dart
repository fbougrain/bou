import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../theme/app_icons.dart';
import '../theme/colors.dart';

typedef LabelBuilder<T> = String Function(T item);

/// Generic surfacedarker single-choice picker.
/// Returns the chosen item or null when dismissed.
Future<T?> showSingleChoicePicker<T>(
  BuildContext context, {
  required List<T> items,
  required LabelBuilder<T> labelBuilder,
  T? current,
  String title = 'Select',
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: surfaceDark,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    isScrollControlled: true,
    builder: (_) => _SingleChoicePicker<T>(
      items: items,
      labelBuilder: labelBuilder,
      current: current,
      title: title,
    ),
  );
}

class _SingleChoicePicker<T> extends StatelessWidget {
  const _SingleChoicePicker({
    required this.items,
    required this.labelBuilder,
    this.current,
    this.title = 'Select',
  });

  final List<T> items;
  final LabelBuilder<T> labelBuilder;
  final T? current;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // surfacedarker container
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              decoration: BoxDecoration(
                color: surfaceDarker,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderDark, width: 1.1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        InkWell(
                          onTap: () => Navigator.pop(context, items[i]),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    labelBuilder(items[i]),
                                    style: const TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                ),
                                if (items[i] == current)
                                  const Icon(AppIcons.checkmark, color: Colors.white70)
                                else
                                  const SizedBox.shrink(),
                              ],
                            ),
                          ),
                        ),
                        if (i < items.length - 1) ...[
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 4),
                        ] else ...[
                          const SizedBox(height: 4),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
        ],
      ),
    );
  }
}

/// Show a surfacedarker-styled status picker and return the selected [TaskStatus]
/// or null if the user dismissed the sheet.
Future<TaskStatus?> showStatusPicker(BuildContext context,
    {TaskStatus? current, String title = 'Status'}) {
  return showSingleChoicePicker<TaskStatus>(
    context,
    items: const [TaskStatus.pending, TaskStatus.completed],
    current: current,
    title: title,
    labelBuilder: (t) => t == TaskStatus.pending ? 'Open' : 'Completed',
  );
}

/// ProjectStatus wrapper using the same surfacedarker chrome.
Future<ProjectStatus?> showProjectStatusPicker(BuildContext context,
    {ProjectStatus? current, String title = 'Status'}) {
  return showSingleChoicePicker<ProjectStatus>(
    context,
    items: const [ProjectStatus.active, ProjectStatus.completed],
    current: current,
    title: title,
    labelBuilder: (p) => p == ProjectStatus.active ? 'Active' : 'Completed',
  );
}
