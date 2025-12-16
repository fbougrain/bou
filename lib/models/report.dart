class Report {
  final String id;
  final String projectId;
  final String reporterUid; // UID of user who reported
  final String reporterName; // Name of user who reported
  final String? reportedUserUid; // UID of reported user (null if reporting content only)
  final String? reportedUserName; // Name of reported user
  final String? messageId; // ID of reported message (if reporting a message)
  final String? messageText; // Text of reported message
  final String reason; // Comment/reason from reporter
  final DateTime createdAt;
  final String? threadId; // Thread ID where the message was reported

  Report({
    required this.id,
    required this.projectId,
    required this.reporterUid,
    required this.reporterName,
    this.reportedUserUid,
    this.reportedUserName,
    this.messageId,
    this.messageText,
    required this.reason,
    required this.createdAt,
    this.threadId,
  });

  factory Report.fromMap(String id, Map<String, dynamic> map) => Report(
        id: id,
        projectId: map['projectId'] as String,
        reporterUid: map['reporterUid'] as String,
        reporterName: map['reporterName'] as String,
        reportedUserUid: map['reportedUserUid'] as String?,
        reportedUserName: map['reportedUserName'] as String?,
        messageId: map['messageId'] as String?,
        messageText: map['messageText'] as String?,
        reason: map['reason'] as String,
        threadId: map['threadId'] as String?,
        createdAt: map['createdAt'] is DateTime
            ? map['createdAt'] as DateTime
            : DateTime.parse(map['createdAt'] as String),
      );

  Map<String, dynamic> toMap() => {
        'projectId': projectId,
        'reporterUid': reporterUid,
        'reporterName': reporterName,
        if (reportedUserUid != null) 'reportedUserUid': reportedUserUid,
        if (reportedUserName != null) 'reportedUserName': reportedUserName,
        if (messageId != null) 'messageId': messageId,
        if (messageText != null) 'messageText': messageText,
        'reason': reason,
        if (threadId != null) 'threadId': threadId,
        'createdAt': createdAt.toIso8601String(),
      };
}
