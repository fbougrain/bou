import 'package:intl/intl.dart';

/// Unified money formatting across the app: 100,000.00 (no currency symbol).
class Money {
  static final NumberFormat formatter = NumberFormat('#,##0.00', 'en_US');
  static String format(num? value) => formatter.format(value ?? 0);
}
