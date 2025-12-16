class ExpenseItem {
  final String name;
  final double qty;
  final double unitPrice;
  const ExpenseItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
  });
  double get lineTotal => qty * unitPrice;
}

class Expense {
  final String id;
  final String number;
  final String vendor;
  final DateTime paidDate;
  final List<ExpenseItem> items;
  final double taxRate;
  final double discount;
  Expense({
    required this.id,
    required this.number,
    required this.vendor,
    required this.paidDate,
    required this.items,
    required this.taxRate,
    required this.discount,
  });
  double get subtotal => items.fold(0, (a, b) => a + b.lineTotal);
  double get tax => subtotal * taxRate;
  double get total => (subtotal + tax - discount).clamp(0, double.infinity);
}
