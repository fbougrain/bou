import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';

// A plain dropdown that opens a custom overlay below the field, keeps width,
// removes selection highlight, and matches the 16px radius.
class PlainDropdown<T> extends StatefulWidget {
  const PlainDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 44,
    this.barrierLabel = 'Dismiss menu',
  });

  final T value; // T can itself be nullable (e.g., String?)
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double height;
  final String barrierLabel;

  @override
  State<PlainDropdown<T>> createState() => _PlainDropdownState<T>();
}

class _PlainDropdownState<T> extends State<PlainDropdown<T>> {
  final GlobalKey _outerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _outerKey,
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: widget.height,
      child: _DropdownButtonShell<T>(
        value: widget.value,
        items: widget.items,
        height: widget.height,
        onChanged: widget.onChanged,
        targetKey: _outerKey,
        barrierLabel: widget.barrierLabel,
      ),
    );
  }
}

class _DropdownButtonShell<T> extends StatelessWidget {
  const _DropdownButtonShell({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.height,
    required this.targetKey,
    required this.barrierLabel,
  });
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double height;
  final GlobalKey targetKey;
  final String barrierLabel;

  String _labelFor(T v) {
    final item = items.firstWhere(
      (e) => e.value == v,
      orElse: () => items.first,
    );
    final child = item.child;
    if (child is Padding && child.child is Text) {
      final t = child.child as Text;
      return t.data ?? '';
    }
    if (child is Text) return child.data ?? '';
    return v.toString();
  }

  Future<void> _openMenu(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final boxContext = targetKey.currentContext ?? context;
    final box = boxContext.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: barrierLabel,
      // Slightly shorter to reduce perceived lag
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, anim, secondary) {
        // Preserve original order; do not reorder selected item
        final displayItems = items;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(onTap: () => Navigator.of(context).pop()),
            ),
            Positioned(
              left: topLeft.dx,
              // Start menu at the initial top of the original box, then grow downward
              top: topLeft.dy,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: surfaceDark,
                    // Match the field radius exactly so it reads as one box
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderDark, width: 1.0),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 0),
                    shrinkWrap: true,
                    cacheExtent: 200,
                    itemCount: displayItems.length,
                    itemBuilder: (context, index) {
                      final item = displayItems[index];
                      final labelWidget = item.child;
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          onChanged(item.value);
                        },
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: WidgetStateProperty.all(
                          Colors.transparent,
                        ),
                        highlightColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                            ),
                            child: labelWidget,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, anim, secondary, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMenu(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _labelFor(value),
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(AppIcons.chevronDown, color: Colors.white70, size: 18),
        ],
      ),
    );
  }
}
