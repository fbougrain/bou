import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/task.dart';
import '../models/stock_item.dart';
import '../models/expense.dart';
import '../models/form_models.dart';
import '../models/team_member.dart';
import '../models/media_item.dart';
import '../models/app_notification.dart';
import '../models/chat_thread.dart';
import '../models/chat_message.dart';
import 'mappers.dart';

/// Centralized typed Firestore collection accessors used across the app.
///
/// Structure (scoped per project):
/// - projects/{projectId}/team
/// - projects/{projectId}/tasks
/// - projects/{projectId}/stock        (aka "Stocks")
/// - projects/{projectId}/forms
/// - projects/{projectId}/expenses     (aka "Billing")
/// - projects/{projectId}/media
/// - projects/{projectId}/notifications
/// - projects/{projectId}/chats
///     - chats/{chatId}/messages
///
/// Note: Firestore is schemaless; these helpers provide withConverter typings
/// and unify naming. Aliases in parentheses are conceptual labels used in the UI.
class FirestoreCollections {
  FirestoreCollections(this._fs);
  final FirebaseFirestore _fs;

  DocumentReference<Map<String, dynamic>> projectDoc(String projectId) =>
      _fs.collection('projects').doc(projectId);

  // Team
  CollectionReference<TeamMember> team(String projectId) =>
      projectDoc(projectId).collection('team').withConverter<TeamMember>(
            fromFirestore: (snap, _) => TeamMemberFirestore.fromMap(snap.data() ?? const {}),
            toFirestore: (value, _) => TeamMemberFirestore(value).toMap(),
          );

  // Tasks
  CollectionReference<TaskModel> tasks(String projectId) =>
      projectDoc(projectId).collection('tasks').withConverter<TaskModel>(
            fromFirestore: (snap, _) => TaskFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => TaskFirestore(value).toMap(),
          );

  // Stocks (stored under 'stock' collection key)
  CollectionReference<StockItem> stocks(String projectId) =>
      projectDoc(projectId).collection('stock').withConverter<StockItem>(
            fromFirestore: (snap, _) => StockFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => StockFirestore(value).toMap(),
          );

  // Forms (submissions)
  CollectionReference<FormSubmission> forms(String projectId) =>
      projectDoc(projectId).collection('forms').withConverter<FormSubmission>(
            fromFirestore: (snap, _) => FormSubmissionFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => FormSubmissionFirestore(value).toMap(),
          );

  // Billing (stored under 'expenses' collection key)
  CollectionReference<Expense> billing(String projectId) =>
      projectDoc(projectId).collection('expenses').withConverter<Expense>(
            fromFirestore: (snap, _) => ExpenseFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => ExpenseFirestore(value).toMap(),
          );

  // Media
  CollectionReference<MediaItem> media(String projectId) =>
      projectDoc(projectId).collection('media').withConverter<MediaItem>(
            fromFirestore: (snap, _) => MediaItemFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => MediaItemFirestore(value).toMap(),
          );

  // Notifications
  CollectionReference<AppNotification> notifications(String projectId) =>
      projectDoc(projectId)
          .collection('notifications')
          .withConverter<AppNotification>(
            fromFirestore: (snap, _) =>
                AppNotificationFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => AppNotificationFirestore(value).toMap(),
          );

  // Chats
  CollectionReference<ChatThread> chats(String projectId) =>
      projectDoc(projectId).collection('chats').withConverter<ChatThread>(
            fromFirestore: (snap, _) => ChatThreadFirestore.fromMap(snap.id, snap.data() ?? const {}),
            toFirestore: (value, _) => ChatThreadFirestore(value).toMap(),
          );

  // Chat messages subcollection
  CollectionReference<ChatMessage> chatMessages(
    String projectId,
    String chatId,
  ) => projectDoc(projectId)
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .withConverter<ChatMessage>(
            fromFirestore: (snap, _) => ChatMessageFirestore.fromMap(snap.data() ?? const {}),
            toFirestore: (value, _) => ChatMessageFirestore(value).toMap(),
          );
}
