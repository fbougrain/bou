class ChatThread {
  final String id;
  final String username;
  final String lastMessage;
  final DateTime lastTime;
  final int unreadCount;
  final String? avatarAsset;
  final bool isTeam;

  const ChatThread({
    required this.id,
    required this.username,
    required this.lastMessage,
    required this.lastTime,
    this.unreadCount = 0,
    this.avatarAsset,
    this.isTeam = false,
  });

  bool get isUnread => unreadCount > 0;
}
