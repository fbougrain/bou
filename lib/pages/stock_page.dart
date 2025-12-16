import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/sample_data.dart';
import '../models/stock_item.dart';
import '../models/project.dart';
import '../data/stock_repository.dart';
import '../data/mappers.dart';
import '../theme/colors.dart';
import '../panels/panel_scaffold.dart';
import '../theme/app_icons.dart';
import '../widgets/plain_dropdown.dart';
import '../widgets/status_picker.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key, this.project});
  final Project? project;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fadeCtrl.forward());
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: _StockBody(project: widget.project),
    );
  }
}

class _StockBody extends StatefulWidget {
  const _StockBody({this.project});
  final Project? project;
  @override
  State<_StockBody> createState() => _StockBodyState();
}

class _StockBodyState extends State<_StockBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _category; // null=all
  StockStatus? _status; // null=all

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<StockItem> _applyFilters(List<StockItem> items) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return items.where((it) {
      if (_category != null && it.category != _category) return false;
      if (_status != null && it.status != _status) return false;
      if (q.isNotEmpty) {
        final h = '${it.name} ${it.supplier} ${it.category}'.toLowerCase();
        if (!h.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  void _openAdd() async {
    final created = await showModalBottomSheet<StockItem>(
      isScrollControlled: true,
      context: context,
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      builder: (_) => _AddStockSheet(),
    );
    if (created != null) {
      final project = widget.project ?? sampleProject;
      StockRepository.instance.addItem(project.id, created, insertOnTop: true);
      // Stream will update automatically
    }
  }

  Widget _buildStockScaffold(Project project, List<StockItem> items) {
    final filtered = _applyFilters(items);
    final distinctCategories = items.map((e) => e.category).toSet().toList()..sort();
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (context.findAncestorWidgetOfExactType<PanelScaffold>() == null) ...[
                  const Text(
                    'Inventory',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _SearchBar(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: PlainDropdown<String?>(
                          value: _category,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                child: Text(
                                  'All',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                            ...(distinctCategories.isNotEmpty
                                ? distinctCategories
                                : <String>['Materials', 'Tools', 'Consumables', 'PPE'])
                                .map(
                              (c) => DropdownMenuItem<String?>(
                                value: c,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 6,
                                  ),
                                  child: Text(
                                    c,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _category = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: PlainDropdown<StockStatus?>(
                          value: _status,
                          items: const [
                            DropdownMenuItem<StockStatus?>(
                              value: null,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                child: Text(
                                  'All',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                            DropdownMenuItem<StockStatus?>(
                              value: StockStatus.ok,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                child: Text(
                                  'OK',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                            DropdownMenuItem<StockStatus?>(
                              value: StockStatus.low,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                child: Text(
                                  'Low',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                            DropdownMenuItem<StockStatus?>(
                              value: StockStatus.depleted,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                child: Text(
                                  'Depleted',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _status = v),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: filtered.isEmpty
                      ? const _EmptyInventoryState()
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _StockCard(item: filtered[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (context.findAncestorWidgetOfExactType<PanelScaffold>() == null)
          Positioned(right: 20, bottom: 20, child: _AddButton(onTap: _openAdd)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project ?? sampleProject;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('projects')
          .doc(project.id)
          .collection('stock')
          .orderBy('updatedAt', descending: true)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final items = snapshot.data!.docs
              .map((d) => StockFirestore.fromMap(d.id, d.data()))
              .toList();
          return _buildStockScaffold(project, items);
        }
        // Fallback to repository for demo/offline
        final repoItems = StockRepository.instance.itemsFor(project.id);
        if (repoItems.isNotEmpty) {
          return _buildStockScaffold(project, repoItems);
        }
        // Show loading indicator if no data yet
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StockLoadingIndicator();
        }
        return _buildStockScaffold(project, []);
      },
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.item});
  final StockItem item;
  @override
  Widget build(BuildContext context) {
    final bg = surfaceDark;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Qty: ${item.quantity} ${item.unit} • ${item.supplier}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(status: item.status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final StockStatus status;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.chipColor(background: true).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: status.chipColor(background: false).withValues(alpha: 0.9),
          width: 1.1,
        ),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// Legacy _DropdownFilter removed in favor of PlainDropdown

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            FluentIcons.box_24_regular,
            color: Colors.white24,
            size: 64,
          ),
          const SizedBox(height: 20),
          const Text(
            'No Items',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your inventory list is empty.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

class _StockLoadingIndicator extends StatelessWidget {
  const _StockLoadingIndicator();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF191B1B),
        foregroundColor: Colors.white,
        side: BorderSide(color: newaccent.withValues(alpha: 0.95), width: 1.6),
        elevation: 6,
        shadowColor: newaccent.withValues(alpha: 0.10),
        padding: EdgeInsets.zero,
        minimumSize: const Size(56, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Icon(
        FluentIcons.add_24_filled,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

/// Public helper to show the "Add Inventory Item" sheet from other pages.
/// Returns the created [StockItem] or null when dismissed.
Future<StockItem?> showAddStockSheet(BuildContext context) {
  return showModalBottomSheet<StockItem>(
    isScrollControlled: true,
    context: context,
    backgroundColor: surfaceDark,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    builder: (_) => _AddStockSheet(),
  );
}

class _AddStockSheet extends StatefulWidget {
  @override
  State<_AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends State<_AddStockSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _supplier = TextEditingController();
  final _qty = TextEditingController();
  final _unit = TextEditingController();
  String? _category; // label-only until picked
  // Inline error flags
  bool _nameError = false;
  bool _supplierError = false;
  bool _unitError = false;
  bool _qtyError = false; // indicates invalid/empty number
  bool _categoryError = false; // picker error: show red + "Required"

  @override
  void dispose() {
    _name.dispose();
    _supplier.dispose();
    _qty.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _submit() {
    // Inline validation for text fields
    final nameEmpty = _name.text.trim().isEmpty;
    final supplierEmpty = _supplier.text.trim().isEmpty;
    final unitEmpty = _unit.text.trim().isEmpty;
    final qtyInt = int.tryParse(_qty.text.trim());
    final qtyInvalid = qtyInt == null;
    final categoryEmpty = _category == null || _category!.trim().isEmpty;

    if (nameEmpty ||
        supplierEmpty ||
        unitEmpty ||
        qtyInvalid ||
        categoryEmpty) {
      setState(() {
        _nameError = nameEmpty;
        _supplierError = supplierEmpty;
        _unitError = unitEmpty;
        _qtyError = qtyInvalid;
        _categoryError = categoryEmpty;
      });
      return;
    }
    final quantity = qtyInt;
    final status = StockItem.deriveStatus(quantity);
    final item = StockItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      category: _category!,
      quantity: quantity,
      unit: _unit.text.trim(),
      supplier: _supplier.text.trim(),
      status: status,
    );
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 50),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(
                child: Text(
                  'Add Inventory Item',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Name',
                controller: _name,
                error: _nameError,
                onTap: () => setState(() => _nameError = false),
              ),
              const SizedBox(height: 12),
              _CategoryField(
                label: 'Category',
                value: _category,
                error: _categoryError,
                onTap: () => setState(() => _categoryError = false),
                onPick: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _LabeledField(
                      label: 'Quantity',
                      controller: _qty,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      error: _qtyError,
                      onTap: () => setState(() => _qtyError = false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LabeledField(
                      label: 'Unit',
                      controller: _unit,
                      error: _unitError,
                      onTap: () => setState(() => _unitError = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Supplier',
                controller: _supplier,
                error: _supplierError,
                onTap: () => setState(() => _supplierError = false),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    // Match floating add button visuals for consistency
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
                  onPressed: _submit,
                  child: const Text(
                    'Add Item',
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
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.error = false,
    this.onTap,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool error;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
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
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : borderDark,
            width: error ? 1.2 : 1.1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : borderDark,
            width: error ? 1.2 : 1.1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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

// Removed old _LabeledDropdown; Add Item uses _CategoryField with a bottom sheet picker.

class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.only(left: 12, right: 8),
      height: 44,
      child: Row(
        children: [
          const Icon(AppIcons.search, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryField extends StatefulWidget {
  const _CategoryField({
    required this.label,
    required this.value,
    required this.onPick,
    this.error = false,
    this.onTap,
  });
  final String label;
  final String? value;
  final ValueChanged<String> onPick;
  final bool error;
  final VoidCallback? onTap;

  @override
  State<_CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends State<_CategoryField> {
  bool _tapped = false;

  Future<void> _handleTap() async {
    widget.onTap?.call();
    setState(() => _tapped = true);
    try {
      final picked = await showSingleChoicePicker<String>(
        context,
        items: const ['Materials', 'Tools', 'Consumables', 'PPE'],
        current: widget.value,
        title: 'Category',
        labelBuilder: (s) => s,
      );
      if (picked != null) widget.onPick(picked);
    } finally {
      if (mounted) setState(() => _tapped = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.value?.trim() ?? '';
    return GestureDetector(
      onTap: _handleTap,
      child: InputDecorator(
        isFocused: _tapped,
        isEmpty: text.isEmpty,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.white70),
          floatingLabelBehavior: widget.error
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          hintText: widget.error ? 'Required' : null,
          hintStyle: const TextStyle(color: Colors.redAccent),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          filled: true,
          fillColor: surfaceDarker,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: widget.error ? Colors.redAccent : borderDark,
              width: widget.error ? 1.2 : 1.1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: widget.error ? Colors.redAccent : borderDark,
              width: widget.error ? 1.2 : 1.1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: widget.error
                  ? Colors.redAccent
                  : newaccent.withValues(alpha: 0.95),
              width: widget.error ? 1.3 : 1.6,
            ),
          ),
          suffixIcon: const Icon(
            AppIcons.chevronDown,
            color: Colors.white70,
            size: 20,
          ),
        ),
        child: text.isEmpty
            ? const SizedBox.shrink()
            : Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

// Category picker replaced by generic showSingleChoicePicker<String>.
