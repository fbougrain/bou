class ChatMessage {
  final String? id; // Firestore document ID
  final String text;
  final bool isMe;
  final String? attachmentType; // e.g. 'document', 'audio', 'location'
  final String? attachmentLabel; // display label or filename
  final String? senderName; // display name when not me
  final String? senderUid; // sender's user ID for determining isMe dynamically
  final DateTime? time; // timestamp

  const ChatMessage({
    this.id,
    required this.text,
    required this.isMe,
    this.attachmentType,
    this.attachmentLabel,
    this.senderName,
    this.senderUid,
    this.time,
  });

  bool get hasAttachment => attachmentType != null;

  factory ChatMessage.fromMap(Map<String, dynamic> map, {String? id}) => ChatMessage(
    id: id,
    text: map['text'] as String,
    isMe: map['isMe'] as bool,
    attachmentType: map['attachmentType'] as String?,
    attachmentLabel: map['attachmentLabel'] as String?,
    senderName: map['senderName'] as String?,
    senderUid: map['senderUid'] as String?,
    time: map['time'] != null ? DateTime.tryParse(map['time'] as String) : null,
  );

  Map<String, dynamic> toMap() => {
    'text': text,
    'isMe': isMe,
    if (attachmentType != null) 'attachmentType': attachmentType,
    if (attachmentLabel != null) 'attachmentLabel': attachmentLabel,
    if (senderName != null) 'senderName': senderName,
    if (senderUid != null) 'senderUid': senderUid,
    if (time != null) 'time': time!.toIso8601String(),
  };

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isMe,
    String? attachmentType,
    String? attachmentLabel,
    String? senderName,
    String? senderUid,
    DateTime? time,
  }) => ChatMessage(
    id: id ?? this.id,
    text: text ?? this.text,
    isMe: isMe ?? this.isMe,
    attachmentType: attachmentType ?? this.attachmentType,
    attachmentLabel: attachmentLabel ?? this.attachmentLabel,
    senderName: senderName ?? this.senderName,
    senderUid: senderUid ?? this.senderUid,
    time: time ?? this.time,
  );
}
