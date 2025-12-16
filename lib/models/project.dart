enum ProjectStatus { active, completed }

class Project {
  final String id;
  final String name;
  final String? location; // e.g. city / site reference
  final DateTime startDate;
  final DateTime endDate; // planned end / target date
  final int progressPercent; // 0-100 physical progress
  final int lateTasks; // count of late/overdue tasks
  final int incidentCount; // safety / quality incidents recorded
  final int teamOnline; // currently online / present
  final int teamTotal; // total team members
  final ProjectStatus status;
  final double? budgetTotal; // planned total budget (nullable if unknown)
  final double? budgetSpent; // spent to date (nullable if unknown)
  final String? description;
  final DateTime? createdAt; // Firestore document creation timestamp (for ordering)

  const Project({
    required this.id,
    required this.name,
    this.location,
    required this.startDate,
    required this.endDate,
    required this.progressPercent,
    required this.lateTasks,
    required this.incidentCount,
    required this.teamOnline,
    required this.teamTotal,
    required this.status,
    this.budgetTotal,
    this.budgetSpent,
    this.description,
    this.createdAt,
  });

  double? get budgetConsumedRatio {
    if (budgetTotal == null || budgetSpent == null || budgetTotal == 0) {
      return null;
    }
    return (budgetSpent! / budgetTotal!).clamp(0, 1);
  }
}
