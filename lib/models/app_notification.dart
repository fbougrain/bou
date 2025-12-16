class AppNotification {
  final int id;
  final String message;
  final String type;
  final DateTime date;

  AppNotification({
    required this.id,
    required this.message,
    required this.type,
    required this.date,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
    id: map['id'] as int,
    message: map['message'] as String,
    type: map['type'] as String,
    date: map['date'] is DateTime
        ? map['date'] as DateTime
        : DateTime.parse(map['date'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'message': message,
    'type': type,
    'date': date.toIso8601String(),
  };
}
