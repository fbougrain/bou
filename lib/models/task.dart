enum TaskStatus { pending, completed }

enum TaskPriority { critical, high, medium, low }

class TaskModel {
  final String id;
  final String name;
  final TaskStatus status;
  final String assignee;
  final String company;
  final DateTime startDate;
  final DateTime dueDate;
  final TaskPriority priority;
  final int progress; // 0-100

  const TaskModel({
    required this.id,
    required this.name,
    required this.status,
    required this.assignee,
    this.company = 'MyCompany',
    required this.startDate,
    required this.dueDate,
    required this.priority,
    required this.progress,
  });
}
