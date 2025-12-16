import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/money.dart';

import '../theme/colors.dart';
import '../widgets/platform_date_picker.dart';
import '../theme/app_icons.dart';
import '../data/mappers.dart';
import '../models/project.dart';
import '../models/expense.dart';
import '../data/billing_repository.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key, required this.project});
  final Project project;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  final _searchCtrl = TextEditingController();
  // Payments removed; single Expenses view only

  final _currency = Money.formatter;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fadeCtrl.forward());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .doc(widget.project.id)
            .collection('expenses')
            .orderBy('paidDate', descending: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final expenses = snapshot.data!.docs
                .map((d) => ExpenseFirestore.fromMap(d.id, d.data()))
                .toList();
            return _buildBillingScaffold(expenses);
          }
          // Fallback to repository for demo/offline
          final repoExpenses = BillingRepository.instance.expensesFor(widget.project.id);
          if (repoExpenses.isNotEmpty) {
            return _buildBillingScaffold(repoExpenses);
          }
          // Show loading indicator if no data yet
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _BillingLoadingIndicator();
          }
          return _buildBillingScaffold([]);
        },
      ),
    );
  }

  // ----- Data helpers -----
  
  List<Expense> _filteredExpenses(List<Expense> expenses) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return expenses;
    return expenses
        .where(
          (e) =>
              e.number.toLowerCase().contains(q) ||
              e.vendor.toLowerCase().contains(q),
        )
        .toList();
  }

  Widget _buildBillingScaffold(List<Expense> expenses) {
    final filteredExpenses = _filteredExpenses(expenses);
    final kpis = _computeKpis(expenses);
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
                const Text(
                  'Spending',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                _KpiRow(kpis: kpis, fmt: _currency),
                const SizedBox(height: 12),
                _SearchBar(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filteredExpenses.isEmpty
                      ? const _EmptyState(
                          title: 'No expenses',
                          message: 'Tap + to record your first expense.',
                        )
                      : ListView.separated(
                          itemCount: filteredExpenses.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) => _ExpenseCard(
                            expense: filteredExpenses[i],
                            fmt: _currency,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: ElevatedButton(
            onPressed: () async {
              final expenses = _getCurrentExpenses();
              final created = await showModalBottomSheet<Expense>(
                isScrollControlled: true,
                context: context,
                backgroundColor: surfaceDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                builder: (_) =>
                    _AddExpenseSheet(numberSeed: _nextNumber(expenses)),
              );
              if (created != null) {
                BillingRepository.instance.addExpense(
                  widget.project.id,
                  created,
                );
                // Stream will update automatically
              }
            },
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
            child: const Icon(AppIcons.add, color: Colors.white, size: 24),
          ),
        ),
      ],
    );
  }

  List<Expense> _getCurrentExpenses() {
    // This is a helper to get current expenses for number generation
    // In practice, we'll use the stream data, but for the add button we need a fallback
    return BillingRepository.instance.expensesFor(widget.project.id);
  }

  // Payments removed: filter not needed

  _Kpis _computeKpis(List<Expense> all) {
    // Use the active project's budget (works for any selected/created project)
    final budget = widget.project.budgetTotal ?? 0;
    // "Paid" per request = sum of all expenses' totals (spent/surplus across expenses)
    final totalPaid = all.fold<double>(0, (a, e) => a + e.total);
    // Remaining = Budget - Paid (not less than zero)
    final remaining = (budget - totalPaid).clamp(0, double.infinity).toDouble();

    return _Kpis(
      budgetTotal: budget,
      totalPaid: totalPaid,
      remaining: remaining,
    );
  }

  String _nextNumber(List<Expense> all) {
    final now = DateTime.now();
    final yyyymm = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final prefix = 'EXP-$yyyymm-';
    final existing = all.where((i) => i.number.startsWith(prefix)).length;
    return '$prefix${(existing + 1).toString().padLeft(3, '0')}';
  }
}

// ----- Models -----

// Payments removed: no tab enum needed

// Status removed: no status enum/labels/colors used anymore.

// Moved Expense/ExpenseItem to lib/models/expense.dart

// Payments removed

class _Kpis {
  final double budgetTotal;
  final double totalPaid;
  final double remaining;
  const _Kpis({
    required this.budgetTotal,
    required this.totalPaid,
    required this.remaining,
  });
}

// --------- UI pieces ---------
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.kpis, required this.fmt});
  final _Kpis kpis;
  final NumberFormat fmt;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            title: 'Budget Total',
            value: fmt.format(kpis.budgetTotal),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            title: 'Total Paid',
            value: fmt.format(kpis.totalPaid),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            title: 'Remaining',
            value: fmt.format(kpis.remaining),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      // Allow the card to adapt to tight vertical constraints while keeping a nice minimum height.
      constraints: const BoxConstraints(minHeight: 56),
      width: double.infinity,
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
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
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search expenses',
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

// Payments removed: segmented tabs and related widgets deleted

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense, required this.fmt});
  final Expense expense;
  final NumberFormat fmt;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // Status chip removed
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${expense.vendor} • Paid ${_date(expense.paidDate)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(expense.total),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
}

// Payments removed: payment card deleted

// Status chip removed

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          const Icon(AppIcons.receipt, size: 60, color: Colors.white30),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _BillingLoadingIndicator extends StatelessWidget {
  const _BillingLoadingIndicator();
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

// _AddButton removed: replaced inline with styled ElevatedButton to match Start/Add style

// --------- Sheets ---------
class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({required this.numberSeed});
  final String numberSeed;
  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _vendorCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  DateTime _paid = DateTime.now();
  bool _paidPicked = false;
  final List<ExpenseItem> _items = [
    // Start with a single blank row; fields show label only until focused/typed
    const ExpenseItem(name: '', qty: 0, unitPrice: 0),
  ];
  final ScrollController _itemsScrollCtrl = ScrollController();
  // Inline error flags for text fields
  bool _vendorError = false;
  bool _numberError = false;
  bool _paidError = false; // picker required error
  final List<GlobalKey<_ItemRowState>> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _numberCtrl.text = widget.numberSeed;
    _itemKeys.addAll(_items.map((_) => GlobalKey<_ItemRowState>()));
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _numberCtrl.dispose();
    _itemsScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: keep keys in sync with items to prevent index errors
    if (_itemKeys.length != _items.length) {
      if (_itemKeys.length < _items.length) {
        _itemKeys.addAll(
          List.generate(
            _items.length - _itemKeys.length,
            (_) => GlobalKey<_ItemRowState>(),
          ),
        );
      } else {
        _itemKeys.removeRange(_items.length, _itemKeys.length);
      }
    }
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final currency = Money.formatter;
    // Only count rows that have both a positive qty AND positive unit price.
    double subtotal = 0;
    for (final it in _items) {
      if (it.qty > 0 && it.unitPrice > 0) {
        subtotal += it.qty * it.unitPrice;
      }
    }
    final hasValid = subtotal > 0;
    double total = subtotal; // (Tax/discount not yet applied in this sheet.)
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    'New Expense',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _TextField(
                  label: 'Vendor',
                  controller: _vendorCtrl,
                  error: _vendorError,
                  onTap: () => setState(() => _vendorError = false),
                ),
                const SizedBox(height: 8),
                _TextField(
                  label: 'Expense ID',
                  controller: _numberCtrl,
                  error: _numberError,
                  onTap: () => setState(() => _numberError = false),
                ),
                const SizedBox(height: 8),
                _PickerField(
                  label: 'Paid date',
                  value: _paidPicked ? _dateStr(_paid) : '',
                  error: _paidError,
                  onTap: () async {
                    setState(() => _paidError = false);
                    final now = DateTime.now();
                    final picked = await pickPlatformDate(
                      context,
                      initialDate: _paid,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                      title: 'Paid date',
                    );
                    if (picked != null) {
                      setState(() {
                        _paid = picked;
                        _paidPicked = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 8), // Applies 16 pixels from left
                  child: const Text(
                    'Line items',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 215,
                  child: _items.isEmpty
                      ? const Center(
                          child: Text(
                            'No items',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.separated(
                          controller: _itemsScrollCtrl,
                          padding: EdgeInsets.zero,
                          itemCount: _items.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) => _ItemRow(
                            key: _itemKeys[i],
                            item: _items[i],
                            nameMaxChars: _items.length > 1 ? 20 : 23,
                            qtyMaxChars: 6,
                            priceMaxChars: 8,
                            onChanged: (it) => setState(() => _items[i] = it),
                            onRemove: _items.length == 1
                                ? null
                                : () => setState(() {
                                    _items.removeAt(i);
                                    _itemKeys.removeAt(i);
                                  }),
                          ),
                        ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _items.insert(
                          0,
                          const ExpenseItem(name: '', qty: 0, unitPrice: 0),
                        );
                        _itemKeys.insert(0, GlobalKey<_ItemRowState>());
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_itemsScrollCtrl.hasClients) {
                          _itemsScrollCtrl.animateTo(
                            0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    },
                    icon: const Icon(
                      AppIcons.add,
                      color: Colors.white70,
                      size: 18,
                    ),
                    label: const Text(
                      'Add item',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _TotalRow(
                            label: 'Subtotal',
                            value: hasValid
                                ? currency.format(subtotal)
                                : '0.00',
                          ),
                          _TotalRow(
                            label: 'Total',
                            value: hasValid ? currency.format(total) : '0.00',
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    onPressed: () {
                      final missingVendor = _vendorCtrl.text.trim().isEmpty;
                      final missingNumber = _numberCtrl.text.trim().isEmpty;
                      final missingPaid = !_paidPicked;
                      bool anyRowInvalid = false;
                      for (final k in _itemKeys) {
                        final ok = k.currentState?.validate() ?? false;
                        if (!ok) anyRowInvalid = true;
                      }
                      setState(() {
                        _vendorError = missingVendor;
                        _numberError = missingNumber;
                        _paidError = missingPaid;
                      });
                      if (missingVendor ||
                          missingNumber ||
                          missingPaid ||
                          anyRowInvalid) {
                        return;
                      }
                      final exp = Expense(
                        id: _numberCtrl.text.trim(),
                        number: _numberCtrl.text.trim(),
                        vendor: _vendorCtrl.text.trim(),
                        paidDate: _paid,
                        items: List.of(_items),
                        taxRate: 0,
                        discount: 0,
                      );
                      Navigator.pop(context, exp);
                    },
                    child: const Text(
                      'Create',
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
  }

  String _dateStr(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.item,
    required this.onChanged,
    this.onRemove,
    this.nameMaxChars = 23,
    this.qtyMaxChars = 6,
    this.priceMaxChars = 8,
    super.key,
  });
  final ExpenseItem item;
  final ValueChanged<ExpenseItem> onChanged;
  final VoidCallback? onRemove;
  final int nameMaxChars;
  final int qtyMaxChars;
  final int priceMaxChars;
  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _qtyFocus;
  late final FocusNode _priceFocus;
  bool _nameError = false;
  bool _qtyError = false;
  bool _priceError = false;
  // When true, temporarily suppress showing the focused/accent border for the whole row.
  bool _suppressFocusRing = false;
  String _fullNameValue = '';
  bool _isNameTruncated = false;
  String _fullQtyValue = '';
  bool _isQtyTruncated = false;
  String _fullPriceValue = '';
  bool _isPriceTruncated = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
    _fullNameValue = widget.item.name;
    // Show blank text if qty is 0; otherwise display normalized qty text
    _qtyCtrl = TextEditingController(
      text: widget.item.qty == 0 ? '' : _qtyToText(widget.item.qty),
    );
    _fullQtyValue = _qtyCtrl.text;
    // Show blank text if price is 0; otherwise show formatted money
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice == 0
          ? ''
          : Money.format(widget.item.unitPrice),
    );
    _fullPriceValue = _priceCtrl.text;
    _nameFocus = FocusNode();
    _qtyFocus = FocusNode();
    _priceFocus = FocusNode();
    _nameFocus.addListener(_handleNameFocusChange);
    _priceFocus.addListener(_handlePriceFocusChange);
    _qtyFocus.addListener(_handleQtyFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.name != widget.item.name &&
        _nameCtrl.text != widget.item.name) {
      _nameCtrl.text = widget.item.name;
    }
    final qText = widget.item.qty == 0 ? '' : _qtyToText(widget.item.qty);
    if (!_qtyFocus.hasFocus && oldWidget.item.qty != widget.item.qty) {
      // Update stored full value, then apply left-start truncation if needed
      _fullQtyValue = qText;
      if (qText.isEmpty) {
        _isQtyTruncated = false;
        _qtyCtrl.value = const TextEditingValue(text: '');
      } else if (qText.length > widget.qtyMaxChars) {
        final truncated = '${qText.substring(0, widget.qtyMaxChars)}...';
        _isQtyTruncated = true;
        _qtyCtrl.value = TextEditingValue(
          text: truncated,
          selection: TextSelection.collapsed(offset: truncated.length),
        );
      } else {
        _isQtyTruncated = false;
        _qtyCtrl.value = TextEditingValue(
          text: qText,
          selection: TextSelection.collapsed(offset: qText.length),
        );
      }
    }
    final pText = widget.item.unitPrice == 0
        ? ''
        : Money.format(widget.item.unitPrice);
    if (!_priceFocus.hasFocus &&
        oldWidget.item.unitPrice != widget.item.unitPrice) {
      // Update stored full value (formatted), then apply left-start truncation if needed
      _fullPriceValue = pText;
      if (pText.isEmpty) {
        _isPriceTruncated = false;
        _priceCtrl.value = const TextEditingValue(text: '');
      } else if (pText.length > widget.priceMaxChars) {
        final truncated = '${pText.substring(0, widget.priceMaxChars)}...';
        _isPriceTruncated = true;
        _priceCtrl.value = TextEditingValue(
          text: truncated,
          selection: TextSelection.collapsed(offset: truncated.length),
        );
      } else {
        _isPriceTruncated = false;
        _priceCtrl.value = TextEditingValue(
          text: pText,
          selection: TextSelection.collapsed(offset: pText.length),
        );
      }
    }

    // If truncation caps changed, re-apply truncation for unfocused fields based on stored full values
    final capsChanged =
        oldWidget.nameMaxChars != widget.nameMaxChars ||
        oldWidget.qtyMaxChars != widget.qtyMaxChars ||
        oldWidget.priceMaxChars != widget.priceMaxChars;
    if (capsChanged) {
      if (!_nameFocus.hasFocus) {
        final full = _fullNameValue.isEmpty ? _nameCtrl.text : _fullNameValue;
        _fullNameValue = full;
        if (full.isNotEmpty && full.length > widget.nameMaxChars) {
          final truncated = '${full.substring(0, widget.nameMaxChars)}...';
          _isNameTruncated = true;
          _nameCtrl.value = TextEditingValue(
            text: truncated,
            selection: TextSelection.collapsed(offset: truncated.length),
          );
        } else {
          _isNameTruncated = false;
          _nameCtrl.value = TextEditingValue(
            text: full,
            selection: TextSelection.collapsed(offset: full.length),
          );
        }
      }
      if (!_qtyFocus.hasFocus) {
        final full = _fullQtyValue.isEmpty
            ? _qtyCtrl.text.trim()
            : _fullQtyValue;
        if (full.isEmpty) {
          _isQtyTruncated = false;
          _fullQtyValue = '';
          _qtyCtrl.value = const TextEditingValue(text: '');
        } else {
          _fullQtyValue = full;
          if (full.length > widget.qtyMaxChars) {
            final truncated = '${full.substring(0, widget.qtyMaxChars)}...';
            _isQtyTruncated = true;
            _qtyCtrl.value = TextEditingValue(
              text: truncated,
              selection: TextSelection.collapsed(offset: truncated.length),
            );
          } else {
            _isQtyTruncated = false;
            // Normalize quantity display
            final parsed = double.tryParse(full);
            final norm = parsed == null ? full : _qtyToText(parsed);
            _fullQtyValue = norm;
            _qtyCtrl.value = TextEditingValue(
              text: norm,
              selection: TextSelection.collapsed(offset: norm.length),
            );
          }
        }
      }
      if (!_priceFocus.hasFocus) {
        final full = _fullPriceValue.isEmpty
            ? _priceCtrl.text.trim()
            : _fullPriceValue;
        if (full.isEmpty) {
          _isPriceTruncated = false;
          _fullPriceValue = '';
          _priceCtrl.value = const TextEditingValue(text: '');
        } else {
          _fullPriceValue = full;
          if (full.length > widget.priceMaxChars) {
            final truncated = '${full.substring(0, widget.priceMaxChars)}...';
            _isPriceTruncated = true;
            _priceCtrl.value = TextEditingValue(
              text: truncated,
              selection: TextSelection.collapsed(offset: truncated.length),
            );
          } else {
            _isPriceTruncated = false;
            _priceCtrl.value = TextEditingValue(
              text: full,
              selection: TextSelection.collapsed(offset: full.length),
            );
          }
        }
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _nameFocus.dispose();
    _qtyFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  String _qtyToText(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

  bool validate() {
    final nameEmpty = (_isNameTruncated ? _fullNameValue : _nameCtrl.text)
        .trim()
        .isEmpty;
    final qtyRaw = _isQtyTruncated ? _fullQtyValue : _qtyCtrl.text;
    final qtyTxt = qtyRaw.trim();
    final qtyInvalid = qtyTxt.isEmpty || double.tryParse(qtyTxt) == null;
    final priceRaw = _isPriceTruncated ? _fullPriceValue : _priceCtrl.text;
    final priceTxt = priceRaw.replaceAll(',', '').trim();
    final priceInvalid = priceTxt.isEmpty || double.tryParse(priceTxt) == null;
    setState(() {
      _nameError = nameEmpty;
      _qtyError = qtyInvalid;
      _priceError = priceInvalid;
    });
    return !(nameEmpty || qtyInvalid || priceInvalid);
  }

  void _handleNameFocusChange() {
    if (_nameFocus.hasFocus) {
      // Restore full text if it was truncated
      if (_isNameTruncated) {
        _isNameTruncated = false;
        _nameCtrl.value = TextEditingValue(
          text: _fullNameValue,
          selection: TextSelection.collapsed(offset: _fullNameValue.length),
        );
      }
    } else {
      // On blur: store full value and apply truncation if needed
      final full = _nameCtrl.text;
      _fullNameValue = full; // keep original
      final maxChars = widget.nameMaxChars; // adjustable cap (Item)
      if (full.length > maxChars) {
        final truncated = '${full.substring(0, maxChars)}...';
        _isNameTruncated = true;
        // Show truncated variant without altering stored full value
        _nameCtrl.value = TextEditingValue(
          text: truncated,
          selection: TextSelection.collapsed(offset: truncated.length),
        );
      } else {
        _isNameTruncated = false;
      }
    }
    // If the field lost focus while we were suppressing the focus ring, disable suppression
    if (!_nameFocus.hasFocus && _suppressFocusRing) {
      _suppressFocusRing = false;
    }
    setState(() {});
  }

  void _handleQtyFocusChange() {
    if (_qtyFocus.hasFocus) {
      if (_isQtyTruncated) {
        _isQtyTruncated = false;
        _qtyCtrl.value = TextEditingValue(
          text: _fullQtyValue,
          selection: TextSelection.collapsed(offset: _fullQtyValue.length),
        );
      }
    } else {
      final full = _qtyCtrl.text.trim();
      if (full.isEmpty) {
        // User cleared the field: keep it genuinely empty and clear stored full value
        _isQtyTruncated = false;
        _fullQtyValue = '';
      } else {
        _fullQtyValue = full;
        final maxChars = widget.qtyMaxChars; // shorter cap for numeric qty
        if (full.length > maxChars) {
          final truncated = '${full.substring(0, maxChars)}...';
          _isQtyTruncated = true;
          _qtyCtrl.value = TextEditingValue(
            text: truncated,
            selection: TextSelection.collapsed(offset: truncated.length),
          );
        } else {
          _isQtyTruncated = false;
        }
      }
      // Normalize qty formatting when not truncated
      if (!_isQtyTruncated && _fullQtyValue.isNotEmpty) {
        final parsed = double.tryParse(_fullQtyValue);
        if (parsed != null) {
          final norm = _qtyToText(parsed);
          _fullQtyValue = norm;
          if (_qtyCtrl.text != norm) {
            _qtyCtrl.value = TextEditingValue(
              text: norm,
              selection: TextSelection.collapsed(offset: norm.length),
            );
          }
        }
      }
    }
    if (!_qtyFocus.hasFocus && _suppressFocusRing) {
      _suppressFocusRing = false;
    }
    setState(() {});
  }

  void _handlePriceFocusChange() {
    if (_priceFocus.hasFocus) {
      // Always restore full formatted value first (if truncated) then switch to raw editable form
      String working = _fullPriceValue;
      if (_isPriceTruncated || _priceCtrl.text.endsWith('...')) {
        _isPriceTruncated = false;
      } else if (working.isEmpty) {
        working = _priceCtrl.text;
      }
      // Convert formatted (with commas) to raw editing form (strip commas, trim trailing .0s)
      String raw = working.replaceAll(',', '').trim();
      if (raw.contains('.')) {
        raw = raw.replaceFirst(RegExp(r'\.?0+$'), '');
      }
      _priceCtrl.value = TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      );
    } else {
      final full = _priceCtrl.text.replaceAll(',', '').trim();
      if (full.isEmpty) {
        // Keep field empty; clear stored full value so nothing auto-populates.
        _isPriceTruncated = false;
        _fullPriceValue = '';
      } else {
        final parsed = double.tryParse(full);
        if (parsed != null) {
          final formatted = Money.format(parsed);
          _fullPriceValue = formatted;
          // Decide if we truncate visually
          final maxChars =
              widget.priceMaxChars; // cap for price string (Unit $)
          if (formatted.length > maxChars) {
            final truncated = '${formatted.substring(0, maxChars)}...';
            _isPriceTruncated = true;
            _priceCtrl.value = TextEditingValue(
              text: truncated,
              selection: TextSelection.collapsed(offset: truncated.length),
            );
          } else {
            _isPriceTruncated = false;
            _priceCtrl.value = TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
          }
          if (parsed != widget.item.unitPrice) {
            widget.onChanged(
              ExpenseItem(
                name: widget.item.name,
                qty: widget.item.qty,
                unitPrice: parsed,
              ),
            );
          }
        }
      }
    }
    if (!_priceFocus.hasFocus && _suppressFocusRing) {
      _suppressFocusRing = false;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
  final hasError = _nameError || _qtyError || _priceError;
  final hasFocus = _nameFocus.hasFocus || _qtyFocus.hasFocus || _priceFocus.hasFocus;
  // If suppression is active, treat the row as not focused for border purposes
  final effectiveFocus = !_suppressFocusRing && hasFocus;
  final borderColor = hasError
    ? Colors.redAccent
    : (effectiveFocus ? newaccent.withValues(alpha: 0.95) : borderDark);
  final borderWidth = hasError ? 1.2 : (effectiveFocus ? 1.6 : 1.1);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: surfaceDarker,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              onTap: () => setState(() {
                    // Clear all errors for this row when any sub-field is tapped
                    _nameError = false;
                    _qtyError = false;
                    _priceError = false;
                    // Keep focus ring so the accent border remains when tapped
                    _suppressFocusRing = false;
                  }),
              onChanged: (v) {
                if (_suppressFocusRing) setState(() => _suppressFocusRing = false);
                widget.onChanged(
                  ExpenseItem(
                    name: _isNameTruncated ? _fullNameValue : v,
                    qty: widget.item.qty,
                    unitPrice: widget.item.unitPrice,
                  ),
                );
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Item',
                labelStyle: const TextStyle(color: Colors.white70),
                floatingLabelBehavior: _nameError
                    ? FloatingLabelBehavior.always
                    : FloatingLabelBehavior.auto,
                hintText: _nameError ? 'Required' : null,
                hintStyle: const TextStyle(color: Colors.redAccent),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
           // subtle vertical divider between Item and Qty columns
          Container(
            width: 2,
            height: 22,
            color: surfaceDark,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _qtyCtrl,
              focusNode: _qtyFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                _DecimalTextInputFormatter(maxDecimalDigits: 2),
              ],
              onTap: () => setState(() {
                    _nameError = false;
                    _qtyError = false;
                    _priceError = false;
                    _suppressFocusRing = false;
                  }),
              onChanged: (v) {
                if (_suppressFocusRing) setState(() => _suppressFocusRing = false);
                if (v.isEmpty) {
                  // propagate zero when cleared
                  widget.onChanged(
                    ExpenseItem(
                      name: widget.item.name,
                      qty: 0,
                      unitPrice: widget.item.unitPrice,
                    ),
                  );
                  _fullQtyValue = '';
                  _isQtyTruncated = false;
                  return;
                }
                if (v == '.' || v.endsWith('.')) return;
                final parsed = double.tryParse(v);
                if (parsed != null) {
                  widget.onChanged(
                    ExpenseItem(
                      name: widget.item.name,
                      qty: parsed,
                      unitPrice: widget.item.unitPrice,
                    ),
                  );
                  _fullQtyValue = _qtyToText(parsed);
                  _isQtyTruncated = false;
                }
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Qty',
                labelStyle: const TextStyle(color: Colors.white70),
                floatingLabelBehavior: _qtyError
                    ? FloatingLabelBehavior.always
                    : FloatingLabelBehavior.auto,
                hintText: _qtyError ? 'Required' : null,
                hintStyle: const TextStyle(color: Colors.redAccent),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // subtle vertical divider between Qty and Unit columns
          Container(
            width: 2,
            height: 22,
            color: surfaceDark,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _priceCtrl,
              focusNode: _priceFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                _PriceTextInputFormatter(
                  maxDecimalDigits: 2,
                  maxTotalDigits: 7,
                ),
              ],
              onTap: () => setState(() {
                    _nameError = false;
                    _qtyError = false;
                    _priceError = false;
                    _suppressFocusRing = false;
                  }),
              onChanged: (v) {
                if (_suppressFocusRing) setState(() => _suppressFocusRing = false);
                if (v.isEmpty) {
                  widget.onChanged(
                    ExpenseItem(
                      name: widget.item.name,
                      qty: widget.item.qty,
                      unitPrice: 0,
                    ),
                  );
                  _fullPriceValue = '';
                  _isPriceTruncated = false;
                  return;
                }
                if (v == '.' || v.endsWith('.')) return;
                final parsed = double.tryParse(v);
                if (parsed != null) {
                  widget.onChanged(
                    ExpenseItem(
                      name: widget.item.name,
                      qty: widget.item.qty,
                      unitPrice: parsed,
                    ),
                  );
                  _fullPriceValue = Money.format(parsed);
                  _isPriceTruncated = false;
                }
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Unit \$',
                labelStyle: const TextStyle(color: Colors.white70),
                floatingLabelBehavior: _priceError
                    ? FloatingLabelBehavior.always
                    : FloatingLabelBehavior.auto,
                hintText: _priceError ? 'Required' : null,
                hintStyle: const TextStyle(color: Colors.redAccent),
                border: InputBorder.none,
              ),
            ),
          ),
          if (widget.onRemove != null) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: widget.onRemove,
              icon: const Icon(AppIcons.delete, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerField extends StatefulWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.error = false,
  });
  final String label;
  final String value;
  final FutureOr<void> Function() onTap;
  final bool error;

  @override
  State<_PickerField> createState() => _PickerFieldState();
}

class _PickerFieldState extends State<_PickerField> {
  bool _tapped = false;

  Future<void> _handleTap() async {
    setState(() => _tapped = true);
    try {
      final res = widget.onTap();
      if (res is Future) await res;
    } finally {
      if (mounted) setState(() => _tapped = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.value.trim().isEmpty;
    return GestureDetector(
      onTap: _handleTap,
      child: InputDecorator(
        isFocused: _tapped,
        isEmpty: isEmpty,
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
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.error ? Colors.redAccent : borderDark,
              width: widget.error ? 1.2 : 1.1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.error ? Colors.redAccent : borderDark,
              width: widget.error ? 1.2 : 1.1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: widget.error
                  ? Colors.redAccent
                  : newaccent.withValues(alpha: 0.95),
              width: widget.error ? 1.3 : 1.6,
            ),
          ),
          suffixIcon: const Icon(
            AppIcons.calender,
            color: Colors.white70,
            size: 20,
          ),
        ),
        child: isEmpty
            ? const SizedBox.shrink()
            : Text(widget.value, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

// Payments removed: numeric field not needed

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.error = false,
    this.onTap,
  });
  final String label;
  final TextEditingController controller;
  final bool error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
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

// Payments removed: add-payment sheet and dropdown field deleted

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Restrict input to valid decimals with at most one dot and a max number of decimal digits.
class _DecimalTextInputFormatter extends TextInputFormatter {
  _DecimalTextInputFormatter({this.maxDecimalDigits = 2});
  final int maxDecimalDigits;
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Allow just a single dot while typing
    if (text == '.') return newValue;
    // Only digits and at most one dot
    if (!RegExp(r'^[0-9]*\.?[0-9]*$').hasMatch(text)) {
      return oldValue;
    }
    if ('.'.allMatches(text).length > 1) {
      return oldValue;
    }
    // Enforce decimal digits limit
    final dotIndex = text.indexOf('.');
    if (dotIndex != -1) {
      final decimals = text.substring(dotIndex + 1);
      if (decimals.length > maxDecimalDigits) {
        return oldValue;
      }
    }
    return newValue;
  }
}

// (Removed duplicate _PriceTextInputFormatter definition)

// Price input: allow only digits and one dot, at most 2 decimals, and at most N digits total (ignoring the dot)
class _PriceTextInputFormatter extends TextInputFormatter {
  _PriceTextInputFormatter({
    this.maxDecimalDigits = 2,
    this.maxTotalDigits = 7,
  });
  final int maxDecimalDigits;
  final int maxTotalDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Allow just a single dot while typing
    if (text == '.') return newValue;
    // Only digits and at most one dot
    if (!RegExp(r'^[0-9]*\.?[0-9]*$').hasMatch(text)) {
      return oldValue;
    }
    if ('.'.allMatches(text).length > 1) {
      return oldValue;
    }
    // Enforce decimal digits limit
    final dotIndex = text.indexOf('.');
    if (dotIndex != -1) {
      final decimals = text.substring(dotIndex + 1);
      if (decimals.length > maxDecimalDigits) {
        return oldValue;
      }
    }
    // Enforce total digits (ignoring dot)
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length > maxTotalDigits) {
      return oldValue;
    }
    return newValue;
  }
}
