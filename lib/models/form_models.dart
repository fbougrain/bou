enum FormKind { dailyReport, incident, safetyInspection, materialRequest }

class FormTemplate {
  final String id;
  final String name;
  final String? category;
  final FormKind kind;
  final String? description;
  const FormTemplate({
    required this.id,
    required this.name,
    required this.kind,
    this.category,
    this.description,
  });
}

class FormSubmission {
  final String id;
  final String title;
  final FormKind kind;
  final String status; // Draft/Submitted
  final DateTime createdAt;
  const FormSubmission({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.createdAt,
  });
}
