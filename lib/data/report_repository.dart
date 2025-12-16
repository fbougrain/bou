import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report.dart';

/// Repository for managing reports in Firestore.
class ReportRepository {
  ReportRepository._();
  static final ReportRepository instance = ReportRepository._();

  final _fs = FirebaseFirestore.instance;

  /// Submit a report to Firestore and create a notification for the project owner.
  Future<void> submitReport(Report report) async {
    try {
      // Write report to Firestore (top-level collection)
      final reportRef = _fs
          .collection('reports')
          .doc();
      
      await reportRef.set({
        ...report.toMap(),
        'id': reportRef.id,
      });

      // Create a notification for the project owner
      await _createReportNotification(report);
    } catch (e) {
      // Re-throw to let caller handle
      rethrow;
    }
  }

  /// Create a notification for the project owner about the report.
  Future<void> _createReportNotification(Report report) async {
    try {
      // Get project owner UID
      final projectDoc = await _fs
          .collection('projects')
          .doc(report.projectId)
          .get();
      
      if (!projectDoc.exists) return;
      
      final ownerUid = projectDoc.data()?['ownerUid'] as String?;
      if (ownerUid == null) return;

      // Create notification message
      final notificationId = DateTime.now().millisecondsSinceEpoch;
      final notificationRef = _fs
          .collection('projects')
          .doc(report.projectId)
          .collection('notifications')
          .doc(notificationId.toString());

      final notificationData = {
        'id': notificationId,
        'message': _buildNotificationMessage(report),
        'type': 'report',
        'date': DateTime.now().toIso8601String(),
        'reportId': report.id,
        'reporterUid': report.reporterUid,
        'reporterName': report.reporterName,
        'reportedUserUid': report.reportedUserUid,
        'reportedUserName': report.reportedUserName,
        'messageText': report.messageText,
        'reason': report.reason,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await notificationRef.set(notificationData);
    } catch (_) {
      // Silent fail - notification is not critical
    }
  }

  String _buildNotificationMessage(Report report) {
    if (report.reportedUserName != null) {
      return '${report.reporterName} reported ${report.reportedUserName}';
    }
    return '${report.reporterName} reported content';
  }

  /// Get all reports for a project (for developer/admin review).
  Future<List<Report>> getReportsForProject(String projectId) async {
    try {
      final snap = await _fs
          .collection('reports')
          .where('projectId', isEqualTo: projectId)
          .orderBy('createdAt', descending: true)
          .get();
      
      return snap.docs
          .map((doc) => Report.fromMap(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Delete all reports for a project (used when project is deleted).
  Future<void> deleteReportsForProject(String projectId) async {
    try {
      const batchSize = 300;
      while (true) {
        final snap = await _fs
            .collection('reports')
            .where('projectId', isEqualTo: projectId)
            .limit(batchSize)
            .get();
        
        if (snap.docs.isEmpty) break;
        
        final batch = _fs.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (_) {
      // Silent fail - best effort deletion
    }
  }
}
