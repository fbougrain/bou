import 'package:flutter/material.dart';
import '../models/team_member.dart';
import '../theme/colors.dart';

// Reusable team multi-picker. Returns a List<TeamMember> (selected members)
// Usage: showModalBottomSheet<List<TeamMember]>(..., builder: (_) => TeamMultiPicker(...));
class TeamMultiPicker extends StatefulWidget {
  const TeamMultiPicker({
    required this.title,
    required this.members,
    this.initiallySelectedNames = const [],
    super.key,
  });

  final String title;
  final List<TeamMember> members;
  final List<String> initiallySelectedNames;

  @override
  State<TeamMultiPicker> createState() => _TeamMultiPickerState();
}

class _TeamMultiPickerState extends State<TeamMultiPicker> {
  late final Set<int> _selectedIds = {
    for (final n in widget.initiallySelectedNames)
      if (widget.members.indexWhere((m) => m.name == n) != -1)
        widget.members[widget.members.indexWhere((m) => m.name == n)].id
  };

  late final List<TeamMember> _people = List<TeamMember>.from(widget.members)
    ..sort((a, b) => a.name.compareTo(b.name));

  void _toggle(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final isEmpty = _people.isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: surfaceDarker,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderDark, width: 1.1),
                ),
                // Keep the surfaced box visible even when there are no members
                // (real Firestore projects). This preserves the original look
                // without adding any placeholder content.
                constraints: const BoxConstraints(maxHeight: 360),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isEmpty
                      ? const SizedBox(
                          height: 56,
                          child: Center(
                            child: Text(
                              'No team members yet',
                              style: TextStyle(color: Colors.white60),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _people.length,
                          separatorBuilder: (_, idx) => const Divider(
                            height: 1,
                            color: borderDark,
                            indent: 56,
                          ),
                          itemBuilder: (_, i) {
                            final m = _people[i];
                            final selected = _selectedIds.contains(m.id);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _toggle(m.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? newaccent.withValues(alpha: 0.40)
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF374151),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: borderDark),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: m.photoAsset != null && m.photoAsset!.isNotEmpty
                                          ? ClipOval(
                                              child: Image.asset(
                                                m.photoAsset!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) => Center(
                                                  child: Text(
                                                    _initial(m.name),
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                _initial(m.name),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            m.role,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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
                    side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
                    elevation: 6,
                    shadowColor: newaccent.withValues(alpha: 0.10),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    final chosen = _people.where((m) => _selectedIds.contains(m.id)).toList(growable: false);
                    Navigator.pop(context, chosen);
                  },
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String name) {
    if (name.isEmpty) return '?';
    return name[0];
  }
}
