import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Platform-adaptive date picker:
/// - iOS: CupertinoDatePicker in a dark bottom sheet with Cancel/Done.
/// - Others: Material showDatePicker themed for dark.
Future<DateTime?> pickPlatformDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
}) async {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS) {
    // Use the same bottom-sheet chrome as Select assignees so the rounded
    // outer sheet covers the background and the title doesn't overlap.
    DateTime temp = initialDate;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null && title.trim().isNotEmpty)
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
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: surfaceDarker,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderDark, width: 1.1),
                  ),
                    child: Padding(
                      // reduce vertical padding so the picker fills the box more
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          // increased height so wheels occupy more of the surfacedarker box
                          height: 210,
                        child: CupertinoTheme(
                          data: const CupertinoThemeData(
                            brightness: Brightness.dark,
                            primaryColor: newaccent,
                          ),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
                            initialDateTime: initialDate,
                            minimumDate: firstDate,
                            maximumDate: lastDate,
                            onDateTimeChanged: (d) => temp = d,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                    onPressed: () => Navigator.pop(context, temp),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  // Material fallback: show a bottom sheet with CalendarDatePicker so we can match styling.
  DateTime temp = initialDate;
  final picked = await showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: surfaceDark,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null && title.trim().isNotEmpty)
                Center(
                  child: Text(
                      title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 390),
                child: CalendarDatePicker(
                  initialDate: initialDate,
                  firstDate: firstDate,
                  lastDate: lastDate,
                  onDateChanged: (d) => temp = d,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                child: SizedBox(
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, temp),
                    child: const Text('Save'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return picked;
}
