import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/media_item.dart';
import '../models/stock_item.dart';
import '../models/chat_thread.dart';
import '../models/team_member.dart';
import '../models/chat_message.dart';
import '../models/app_notification.dart';

final sampleProject = Project(
  id: 'Demo',
  name: 'Demo Site',
  location: 'Casablanca, MA',
  startDate: DateTime(2025, 9, 1),
  endDate: DateTime(2025, 12, 31),
  progressPercent: 0,
  lateTasks: 0,
  incidentCount: 0,
  teamOnline: 0,
  teamTotal: 0,
  status: ProjectStatus.active,
  budgetTotal: 1_250_000, // USD planned
  budgetSpent: 0, // USD spent so far
  description:
      'Personal demo sandbox project for experimentation.',
);

final List<TaskModel> sampleTasks = [
  TaskModel(
    id: '1',
    name: 'Prepare foundations',
    status: TaskStatus.completed,
    assignee: 'Omar Haddad',
    company: 'MyCompany',
    startDate: DateTime(2025, 9, 1),
    dueDate: DateTime(2025, 9, 8),
    priority: TaskPriority.critical,
    progress: 100,
  ),
  TaskModel(
    id: '2',
    name: 'Ground floor concrete pour',
    status: TaskStatus.completed,
    assignee: 'Omar Haddad',
    company: 'MyCompany',
    startDate: DateTime(2025, 9, 9),
    dueDate: DateTime(2025, 9, 11),
    priority: TaskPriority.high,
    progress: 100,
  ),
  TaskModel(
    id: '3',
    name: 'Load-bearing walls',
    status: TaskStatus.pending,
    assignee: 'Sara Kouiri',
    company: 'MyCompany',
    startDate: DateTime(2025, 9, 12),
    dueDate: DateTime(2025, 9, 25),
    priority: TaskPriority.high,
    progress: 80,
  ),
];

final List<MediaItem> sampleMedia = [
  MediaItem(
    id: 'm1',
    name: 'foundation_plan.pdf',
    type: MediaType.document,
    date: DateTime(2025, 9, 1),
    uploader: 'Marie Leclere',
    taskId: '1',
  ),
  MediaItem(
    id: 'm2',
    name: 'progress_photo.jpg',
    type: MediaType.photo,
    date: DateTime(2025, 9, 10),
    uploader: 'Jean Dupont',
    taskId: '2',
    thumbnailUrl: 'https://placehold.co/200x200/3B82F6/FFFFFF?text=PHOTO',
  ),
  MediaItem(
    id: 'm3',
    name: 'drone_overview.mp4',
    type: MediaType.video,
    date: DateTime(2025, 9, 12),
    uploader: 'Jean Dupont',
  ),
];

final List<StockItem> sampleStock = [
  StockItem(
    id: 's1',
    name: 'Portland Cement',
    category: 'Materials',
    quantity: 25,
    unit: 'bags',
    supplier: 'Cemex',
    status: StockStatus.low,
  ),
  StockItem(
    id: 's2',
    name: 'Concrete Mixer',
    category: 'Tools',
    quantity: 2,
    unit: 'units',
    supplier: 'ToolRentCo',
    status: StockStatus.ok,
  ),
  StockItem(
    id: 's3',
    name: 'Wood Screws 5x70',
    category: 'Consumables',
    quantity: 0,
    unit: 'boxes',
    supplier: 'FastenAll',
    status: StockStatus.depleted,
  ),
  StockItem(
    id: 's4',
    name: 'Hard Hat',
    category: 'PPE',
    quantity: 12,
    unit: 'units',
    supplier: 'SafeGear',
    status: StockStatus.ok,
  ),
  StockItem(
    id: 's5',
    name: 'Plasterboard Sheet',
    category: 'Materials',
    quantity: 50,
    unit: 'sheets',
    supplier: 'BuildSupplies',
    status: StockStatus.ok,
  ),
  StockItem(
    id: 's6',
    name: 'Electrical Cable 3G2.5',
    category: 'Materials',
    quantity: 100,
    unit: 'meters',
    supplier: 'ElectroMart',
    status: StockStatus.ok,
  ),
];

// Shared in‑memory (session) team members list so other panels (e.g. chats) can reference it.
final List<TeamMember> sampleTeamMembers = [
  TeamMember(
    id: 1,
    name: 'Amina El Idrissi',
    role: 'Project Manager',
    phone: '+212 600-123456',
    email: 'amina.elidrissi@example.com',
    country: 'Morocco',
    photoAsset: 'assets/projectpicplaceholder.jpg',
    isOnline: true,
  ),
  TeamMember(
    id: 2,
    name: 'Youssef Benali',
    role: 'Site Engineer',
    phone: '+212 611-987654',
    email: 'youssef.benali@example.com',
    country: 'Morocco',
    photoAsset: 'assets/profile_placeholder.jpg',
    isOnline: true,
  ),
  TeamMember(
    id: 3,
    name: 'Sara Kouiri',
    role: 'Safety Officer',
    phone: '+212 622-555555',
    email: 'sara.kouiri@example.com',
    country: 'Morocco',
    photoAsset: 'assets/profile_placeholder.jpg',
    isOnline: false,
  ),
  TeamMember(
    id: 4,
    name: 'Omar Haddad',
    role: 'Foreman',
    phone: '+212 633-777777',
    email: 'omar.haddad@example.com',
    country: 'Morocco',
    photoAsset: 'assets/profile_placeholder.jpg',
    isOnline: false,
  ),
];

// Sample chat threads to populate Chats panel
final List<ChatThread> sampleChats = [
  // Team chat (pinned to top in UI)
  ChatThread(
    id: 'team',
    username: 'Team – ${sampleProject.name}',
    lastMessage: 'Welcome! Share updates and files here.',
    lastTime: DateTime(2025, 9, 12, 11, 10),
    unreadCount: 3,
    avatarAsset: 'assets/projectpicplaceholder.jpg',
    isTeam: true,
  ),
  // Individual members
  ChatThread(
    id: 'c1',
    username: 'Amina El Idrissi',
    lastMessage: 'Is there any new bills today?',
    lastTime: DateTime(2025, 9, 12, 10, 24),
    unreadCount: 1,
    avatarAsset: 'assets/profile_placeholder.jpg',
  ),
  ChatThread(
    id: 'c2',
    username: 'Youssef Benali',
    lastMessage: 'Team did a great work today. 👍',
    lastTime: DateTime(2025, 9, 12, 9, 5),
    unreadCount: 0,
    avatarAsset: 'assets/profile_placeholder.jpg',
  ),
];

// In-memory sample messages per thread (session only)
final Map<String, List<ChatMessage>> sampleChatMessages = {
  'team': [
    // Removed duplicated 'Welcome' system message since thread.lastMessage already conveys it
    ChatMessage(
      text: 'Morning team, today we pour the slab at 14:00.',
      isMe: true,
      senderName: 'Me',
      time: DateTime(2025, 9, 12, 8, 32),
    ),
    ChatMessage(
      text: 'Copy that. Safety checks at 13:30.',
      isMe: false,
      senderName: 'Amina El Idrissi',
      time: DateTime(2025, 9, 12, 8, 34),
    ),
  ],
  'c1': [
    ChatMessage(
      text: 'Is there any new bills today?',
      isMe: false,
      senderName: 'Amina El Idrissi',
      time: DateTime(2025, 9, 12, 10, 24),
    ),
    ChatMessage(
      text: 'I will check with accounting and get back to you.',
      isMe: true,
      senderName: 'Me',
      time: DateTime(2025, 9, 12, 10, 25),
    ),
  ],
  'c2': [
    ChatMessage(
      text: 'Team did a great work today. 👍',
      isMe: false,
      senderName: 'Youssef Benali',
      time: DateTime(2025, 9, 12, 9, 5),
    ),
    ChatMessage(
      text: 'Great! I will let Omar know.',
      isMe: true,
      senderName: 'Me',
      time: DateTime(2025, 9, 12, 9, 6),
    ),
  ],
};

// In-memory participants per thread (used for mentions/autocomplete)
final Map<String, List<TeamMember>> sampleChatParticipants = {
  'team': sampleTeamMembers,
  // For the seeded 1:1 chats, link to the corresponding member by name.
  'c1': [...sampleTeamMembers.where((m) => m.name == 'Amina El Idrissi')],
  'c2': [...sampleTeamMembers.where((m) => m.name == 'Youssef Benali')],
};

// Simple notifier to trigger UI rebuilds wherever chat data changes.
final ValueNotifier<int> chatRevision = ValueNotifier<int>(0);

// Sample notifications for demo projects.
final List<AppNotification> sampleNotifications = [
  AppNotification(
    id: 1,
    message: 'Foundation inspection scheduled tomorrow at 09:00',
    type: 'schedule',
    date: DateTime(2025, 9, 12, 8, 0),
  ),
  AppNotification(
    id: 2,
    message: 'New expense added: Site inspection (300 USD)',
    type: 'billing',
    date: DateTime(2025, 9, 12, 8, 45),
  ),
  AppNotification(
    id: 3,
    message: 'Stock low: Portland Cement (25 bags remaining)',
    type: 'stock',
    date: DateTime(2025, 9, 12, 9, 10),
  ),
];

/// Adds a new team member and automatically updates the built-in team chat.
/// - The member is appended to the shared [sampleTeamMembers].
/// - The team chat participants are synced to include the new member.
/// - A system message like "NAME joined the team" is posted to the 'team' chat.
/// - The 'team' thread's preview/time are updated and listeners are notified.
void addTeamMember(TeamMember member) {
  sampleTeamMembers.add(member);
  // Keep participants map in sync for any code still reading from it.
  sampleChatParticipants['team'] = sampleTeamMembers;
  // Post a system message to the team chat.
  final now = DateTime.now();
  final msgs = sampleChatMessages['team'] ??= [];
  msgs.add(
    ChatMessage(
      text: '${member.name} joined the team',
      isMe: false,
      senderName: 'System',
      time: now,
    ),
  );
  // Update preview/time for the team thread entry.
  final i = sampleChats.indexWhere((t) => t.id == 'team');
  if (i != -1) {
    final current = sampleChats[i];
    sampleChats[i] = ChatThread(
      id: current.id,
      username: current.username,
      lastMessage: '${member.name} joined the team',
      lastTime: now,
      unreadCount: current.unreadCount,
      avatarAsset: current.avatarAsset,
      isTeam: current.isTeam,
    );
  }
  chatRevision.value++;
}
