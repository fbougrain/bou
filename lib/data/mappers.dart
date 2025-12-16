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

DateTime _parseDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

// -------------------- Task --------------------
extension TaskFirestore on TaskModel {
  Map<String, Object?> toMap() => {
        'name': name,
        'status': status.name,
        'assignee': assignee,
        'company': company,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'priority': priority.name,
        'progress': progress,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static TaskModel fromMap(String id, Map<String, dynamic> data) {
    TaskStatus parseStatus(String? s) =>
        s == 'completed' ? TaskStatus.completed : TaskStatus.pending;
    TaskPriority parsePriority(String? s) {
      switch (s) {
        case 'critical':
          return TaskPriority.critical;
        case 'high':
          return TaskPriority.high;
        case 'low':
          return TaskPriority.low;
        case 'medium':
        default:
          return TaskPriority.medium;
      }
    }

    return TaskModel(
      id: id,
      name: (data['name'] as String?) ?? 'Task',
      status: parseStatus(data['status'] as String?),
      assignee: (data['assignee'] as String?) ?? 'Unassigned',
      company: (data['company'] as String?) ?? 'MyCompany',
      startDate: _parseDate(data['startDate']),
      dueDate: _parseDate(data['dueDate']),
      priority: parsePriority(data['priority'] as String?),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
    );
  }
}

// -------------------- Stock --------------------
extension StockFirestore on StockItem {
  Map<String, Object?> toMap() => {
        'name': name,
        'category': category,
        'quantity': quantity,
        'unit': unit,
        'supplier': supplier,
        'status': status.name,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static StockItem fromMap(String id, Map<String, dynamic> data) {
    StockStatus parseStatus(String? s) {
      switch (s) {
        case 'ok':
          return StockStatus.ok;
        case 'low':
          return StockStatus.low;
        case 'depleted':
        default:
          return StockStatus.depleted;
      }
    }

    return StockItem(
      id: id,
      name: (data['name'] as String?) ?? 'Item',
      category: (data['category'] as String?) ?? 'Materials',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      unit: (data['unit'] as String?) ?? 'pcs',
      supplier: (data['supplier'] as String?) ?? 'Unknown',
      status: parseStatus(data['status'] as String?),
    );
  }
}

// -------------------- Expense --------------------
extension ExpenseFirestore on Expense {
  Map<String, Object?> toMap() => {
        'number': number,
        'vendor': vendor,
        'paidDate': paidDate.toIso8601String(),
        'items': [
          for (final it in items)
            {
              'name': it.name,
              'qty': it.qty,
              'unitPrice': it.unitPrice,
            }
        ],
        'taxRate': taxRate,
        'discount': discount,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static Expense fromMap(String id, Map<String, dynamic> data) {
    final rawItems = (data['items'] as List?) ?? const [];
    final items = rawItems
        .map((e) => ExpenseItem(
              name: (e['name'] as String?) ?? 'Item',
              qty: (e['qty'] as num?)?.toDouble() ?? 0,
              unitPrice: (e['unitPrice'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
    return Expense(
      id: id,
      number: (data['number'] as String?) ?? id,
      vendor: (data['vendor'] as String?) ?? 'Vendor',
      paidDate: _parseDate(data['paidDate']),
      items: items,
      taxRate: (data['taxRate'] as num?)?.toDouble() ?? 0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0,
    );
  }
}

// -------------------- FormSubmission --------------------
extension FormSubmissionFirestore on FormSubmission {
  Map<String, Object?> toMap() => {
        'title': title,
        'kind': kind.name,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static FormSubmission fromMap(String id, Map<String, dynamic> data) {
    FormKind parseKind(String? s) {
      switch (s) {
        case 'dailyReport':
          return FormKind.dailyReport;
        case 'incident':
          return FormKind.incident;
        case 'safetyInspection':
          return FormKind.safetyInspection;
        case 'materialRequest':
        default:
          return FormKind.materialRequest;
      }
    }

    return FormSubmission(
      id: id,
      title: (data['title'] as String?) ?? 'Submission',
      kind: parseKind(data['kind'] as String?),
      status: (data['status'] as String?) ?? 'Submitted',
      createdAt: _parseDate(data['createdAt']),
    );
  }
}

// -------------------- TeamMember --------------------
extension TeamMemberFirestore on TeamMember {
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'role': role,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (country != null) 'country': country,
        if (photoAsset != null) 'photoAsset': photoAsset,
        'isOnline': isOnline,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static TeamMember fromMap(Map<String, dynamic> data) => TeamMember(
        id: (data['id'] as num?)?.toInt() ?? 0,
        name: (data['name'] as String?) ?? 'Member',
        role: (data['role'] as String?) ?? 'Role',
        phone: data['phone'] as String?,
        email: data['email'] as String?,
        country: data['country'] as String?,
        photoAsset: data['photoAsset'] as String?,
        isOnline: (data['isOnline'] as bool?) ?? false,
      );
}

// -------------------- MediaItem --------------------
extension MediaItemFirestore on MediaItem {
  Map<String, Object?> toMap() => {
        'name': name,
        'type': type.name,
        'date': date.toIso8601String(),
        'uploader': uploader,
        if (taskId != null) 'taskId': taskId,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static MediaItem fromMap(String id, Map<String, dynamic> data) {
    MediaType parseType(String? s) {
      switch (s) {
        case 'photo':
          return MediaType.photo;
        case 'video':
          return MediaType.video;
        case 'document':
        default:
          return MediaType.document;
      }
    }

    return MediaItem(
      id: id,
      name: (data['name'] as String?) ?? id,
      type: parseType(data['type'] as String?),
      date: _parseDate(data['date']),
      uploader: (data['uploader'] as String?) ?? 'Unknown',
      taskId: data['taskId'] as String?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
    );
  }
}

// -------------------- AppNotification --------------------
extension AppNotificationFirestore on AppNotification {
  Map<String, Object?> toMap() => {
        'message': message,
        'type': type,
        'date': date.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static AppNotification fromMap(String id, Map<String, dynamic> data) =>
      AppNotification(
        id: int.tryParse(id) ?? (data['id'] as num?)?.toInt() ?? 0,
        message: (data['message'] as String?) ?? '',
        type: (data['type'] as String?) ?? 'info',
        date: _parseDate(data['date']),
      );
}

// -------------------- ChatThread --------------------
extension ChatThreadFirestore on ChatThread {
  Map<String, Object?> toMap() => {
        'username': username,
        'lastMessage': lastMessage,
        'lastTime': lastTime.toIso8601String(),
        'unreadCount': unreadCount,
        'avatarAsset': avatarAsset,
        'isTeam': isTeam,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static ChatThread fromMap(String id, Map<String, dynamic> data) =>
      ChatThread(
        id: id,
        username: (data['username'] as String?) ?? 'Chat',
        lastMessage: (data['lastMessage'] as String?) ?? '',
        lastTime: _parseDate(data['lastTime']),
        unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
        avatarAsset: data['avatarAsset'] as String?,
        isTeam: (data['isTeam'] as bool?) ?? false,
      );
}

// -------------------- ChatMessage --------------------
extension ChatMessageFirestore on ChatMessage {
  Map<String, Object?> toMap() => {
        'text': text,
        'isMe': isMe,
        if (attachmentType != null) 'attachmentType': attachmentType,
        if (attachmentLabel != null) 'attachmentLabel': attachmentLabel,
        if (senderName != null) 'senderName': senderName,
        if (senderUid != null) 'senderUid': senderUid,
        if (time != null) 'time': time!.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static ChatMessage fromMap(Map<String, dynamic> data, {String? currentUserUid, String? id}) {
    final senderUid = data['senderUid'] as String?;
    // Compute isMe dynamically based on senderUid if available, otherwise fall back to stored value
    final isMe = currentUserUid != null && senderUid != null
        ? senderUid == currentUserUid
        : (data['isMe'] as bool?) ?? false;
    
    return ChatMessage(
      id: id,
      text: (data['text'] as String?) ?? '',
      isMe: isMe,
      attachmentType: data['attachmentType'] as String?,
      attachmentLabel: data['attachmentLabel'] as String?,
      senderName: data['senderName'] as String?,
      senderUid: senderUid,
      time: data['time'] != null ? _parseDate(data['time']) : null,
    );
  }
}
