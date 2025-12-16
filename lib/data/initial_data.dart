import '../models/project.dart';
import '../models/expense.dart';
import 'sample_data.dart';
import 'team_repository.dart';
import 'chat_repository.dart';
import 'media_repository.dart';
import 'notifications_repository.dart';
import 'task_repository.dart';
import 'stock_repository.dart';
import 'billing_repository.dart';

/// Known demo project ids. Static data (tasks, stock, billing) should only
/// be seeded for these projects. Real Firestore-created projects must start
/// empty so users aren't confused by built-in sample data.
/// Keep lowercase for case-insensitive matching.
const Set<String> _legacyDemoIds = {};

/// Return true if the project id should be treated as demo/sample.
/// New pattern: any id starting with 'demo-site-' (user-specific copy).
bool isDemoProjectId(String id) {
  final lower = id.toLowerCase();
  return lower.startsWith('demo-site-') || _legacyDemoIds.contains(lower);
}

/// Centralized app sample data seeding (demo-only).
/// Call this early (before pages build) to ensure repositories are populated
/// for demo projects. Non-demo projects are ignored.
void seedInitialDataForProjects(List<Project> projects) {
  for (final p in projects) {
  final id = p.id;
  if (!isDemoProjectId(id)) continue;
    TaskRepository.instance.seedIfEmpty(id, sampleTasks);
    StockRepository.instance.seedIfEmpty(id, sampleStock);
    BillingRepository.instance.seedIfEmpty(id, _defaultExpenses());
    TeamRepository.instance.seedIfEmpty(id, sampleTeamMembers);
    ChatRepository.instance.seedIfEmpty(id, sampleChats, sampleChatMessages);
    MediaRepository.instance.seedIfEmpty(id, sampleMedia);
    NotificationsRepository.instance.seedIfEmpty(id, sampleNotifications);
  }
}

List<Expense> _defaultExpenses() {
  final now = DateTime.now();
  return [
    Expense(
      id: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-001',
      number: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-001',
      vendor: 'Lumber Yard Co.',
      paidDate: DateTime(now.year, now.month, 2),
      items: const [
        ExpenseItem(name: 'Framing labor', qty: 12, unitPrice: 85),
        ExpenseItem(name: 'Lumber materials', qty: 1, unitPrice: 1250),
      ],
      taxRate: 0.1,
      discount: 0,
    ),
    Expense(
      id: 'EXP-${now.year}${(now.month - 1).toString().padLeft(2, '0')}-019',
      number:
          'EXP-${now.year}${(now.month - 1).toString().padLeft(2, '0')}-019',
      vendor: 'Electric Co',
      paidDate: DateTime(now.year, now.month - 1, 25),
      items: const [
        ExpenseItem(name: 'Electrical rough-in', qty: 20, unitPrice: 70),
      ],
      taxRate: 0.1,
      discount: 50,
    ),
    Expense(
      id: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-002',
      number: 'EXP-${now.year}${now.month.toString().padLeft(2, '0')}-002',
      vendor: 'Inspection Services',
      paidDate: DateTime(now.year, now.month, 20),
      items: const [
        ExpenseItem(name: 'Site inspection', qty: 1, unitPrice: 300),
      ],
      taxRate: 0,
      discount: 0,
    ),
  ];
}
