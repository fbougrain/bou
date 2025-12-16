import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Inventory status of a stock item.
enum StockStatus { ok, low, depleted }

extension StockStatusX on StockStatus {
  String get label => switch (this) {
    StockStatus.ok => 'OK',
    StockStatus.low => 'Low',
    StockStatus.depleted => 'Depleted',
  };

  Color chipColor({bool background = false}) {
    // Foreground vs background color choice for dark theme readability.
    switch (this) {
      case StockStatus.ok:
        return background ? newaccentbackground : const Color(0xFF34D399);
      case StockStatus.low:
        return background ? newaccentbackground : const Color(0xFFFBBF24);
      case StockStatus.depleted:
        return background ? newaccentbackground : const Color(0xFFF87171);
    }
  }
}

class StockItem {
  StockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.supplier,
    required this.status,
  });

  final String id;
  final String name;
  final String category; // Could later be enum.
  final int quantity;
  final String unit;
  final String supplier;
  final StockStatus status;

  StockItem copyWith({
    String? id,
    String? name,
    String? category,
    int? quantity,
    String? unit,
    String? supplier,
    StockStatus? status,
  }) => StockItem(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    supplier: supplier ?? this.supplier,
    status: status ?? this.status,
  );

  /// Simple helper to derive a StockStatus from a remaining quantity.
  static StockStatus deriveStatus(int quantity) {
    if (quantity <= 0) return StockStatus.depleted;
    if (quantity < 10) return StockStatus.low; // threshold adjustable.
    return StockStatus.ok;
  }
}
