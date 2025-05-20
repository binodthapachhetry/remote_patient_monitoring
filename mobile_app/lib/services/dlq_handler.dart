import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';

/// Handles processing of messages that failed to be delivered to Pub/Sub
/// and were sent to the Dead Letter Queue (DLQ)
class DlqHandler {
  // Singleton pattern
  static final DlqHandler _instance = DlqHandler._internal();
  factory DlqHandler() => _instance;
  DlqHandler._internal();
  
  // Dependencies
  final _db = DatabaseHelper();
  
  // State tracking
  bool _isProcessing = false;
  
  /// Process a failed message from the DLQ
  Future<bool> processFailedMessage(Map<String, dynamic> message) async {
    if (_isProcessing) {
      debugPrint('>>> DLQ handler already processing a message');
      return false;
    }
    
    _isProcessing = true;
    
    try {
      // Extract message data
      final attributes = message['attributes'] as Map<String, dynamic>?;
      final data = message['data'] as String?;
      final messageId = message['messageId'] as String?;
      
      if (attributes == null || data == null || messageId == null) {
        debugPrint('!!! Invalid DLQ message format');
        return false;
      }
      
      // Extract batch information
      final batchId = attributes['batch_id'] as String?;
      if (batchId == null) {
        debugPrint('!!! Missing batch_id in DLQ message');
        return false;
      }
      
      debugPrint('>>> Processing DLQ message for batch: $batchId');
      
      // Log the failure for audit purposes
      await _logDlqEvent('dlq_message_received', {
        'batch_id': batchId,
        'message_id': messageId,
        'error_type': attributes['error_type'] ?? 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Determine failure type and appropriate action
      final errorType = attributes['error_type'] as String? ?? 'unknown';
      
      switch (errorType) {
        case 'rate_limit_exceeded':
          // Wait and retry with exponential backoff
          await _handleRateLimitFailure(batchId, message);
          break;
          
        case 'invalid_format':
          // Log and mark as permanently failed
          await _handleFormatFailure(batchId, message);
          break;
          
        case 'authentication_failure':
          // Refresh auth token and retry
          await _handleAuthFailure(batchId, message);
          break;
          
        case 'server_error':
          // Wait and retry later
          await _scheduleRetry(batchId, message);
          break;
          
        default:
          // Unknown error - archive for manual review
          await _archiveForReview(batchId, message);
          break;
      }
      
      _isProcessing = false;
      return true;
    } catch (e) {
      debugPrint('!!! Error processing DLQ message: $e');
      _isProcessing = false;
      return false;
    }
  }
  
  /// Handle rate limit exceeded errors
  Future<void> _handleRateLimitFailure(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling rate limit failure for batch: $batchId');
    
    // Get retry count from database
    final batch = await _getBatchInfo(batchId);
    final retryCount = batch?['retryCount'] as int? ?? 0;
    
    // Calculate backoff time (exponential with jitter)
    final baseDelay = Duration(seconds: (1 << retryCount) * 10);
    final jitter = Duration(seconds: (DateTime.now().millisecondsSinceEpoch % 10));
    final delay = baseDelay + jitter;
    
    debugPrint('>>> Scheduling retry in ${delay.inSeconds} seconds');
    
    // Update batch status to pending with increased retry count
    await _db.updateBatchStatus(
      batchId, 
      'pending',
      errorMessage: 'Rate limit exceeded, retry scheduled'
    );
    
    // Schedule retry after delay
    Timer(delay, () async {
      // Get measurements for this batch
      final measurements = await _db.getMeasurementsByBatch(batchId);
      if (measurements.isEmpty) {
        debugPrint('!!! No measurements found for batch: $batchId');
        return;
      }
      
      // Attempt to resend with the SyncService
      // This is intentionally not awaited to avoid blocking the DLQ handler
      _resendBatch(batchId);
    });
  }
  
  /// Handle format/validation failures
  Future<void> _handleFormatFailure(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling format failure for batch: $batchId');
    
    // These are permanent failures, so mark as failed
    await _db.updateBatchStatus(
      batchId, 
      'failed',
      errorMessage: 'Message format validation failed'
    );
    
    // Log detailed error for debugging
    final errorDetails = message['attributes']?['error_details'] as String? ?? 'Unknown format error';
    
    await _logDlqEvent('permanent_failure', {
      'batch_id': batchId,
      'error_type': 'format_validation',
      'details': errorDetails,
      'message_id': message['messageId'],
    });
    
    // Archive the failed message for analysis
    await _archiveMessage(batchId, message, 'format_failure');
  }
  
  /// Handle authentication failures
  Future<void> _handleAuthFailure(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling auth failure for batch: $batchId');
    
    // Update batch status
    await _db.updateBatchStatus(
      batchId, 
      'pending',
      errorMessage: 'Authentication failure, will retry with fresh token'
    );
    
    // Force token refresh
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.getIdToken(true); // Force refresh
        debugPrint('>>> Successfully refreshed auth token');
      }
    } catch (e) {
      debugPrint('!!! Failed to refresh auth token: $e');
    }
    
    // Schedule immediate retry
    _resendBatch(batchId);
  }
  
  /// Schedule a retry for server errors
  Future<void> _scheduleRetry(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Scheduling retry for server error on batch: $batchId');
    
    // Get retry count
    final batch = await _getBatchInfo(batchId);
    final retryCount = batch?['retryCount'] as int? ?? 0;
    
    // If we've exceeded max retries, mark as failed
    if (retryCount >= 5) {
      await _db.updateBatchStatus(
        batchId, 
        'failed',
        errorMessage: 'Exceeded maximum retry attempts'
      );
      
      await _logDlqEvent('max_retries_exceeded', {
        'batch_id': batchId,
        'retry_count': retryCount,
      });
      
      return;
    }
    
    // Otherwise, schedule a retry with backoff
    final delay = Duration(minutes: retryCount + 1);
    
    await _db.updateBatchStatus(
      batchId, 
      'pending',
      errorMessage: 'Server error, retry scheduled'
    );
    
    // Schedule retry
    Timer(delay, () {
      _resendBatch(batchId);
    });
  }
  
  /// Archive message for manual review
  Future<void> _archiveForReview(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Archiving message for review: $batchId');
    
    // Mark as failed in database
    await _db.updateBatchStatus(
      batchId, 
      'failed',
      errorMessage: 'Unknown error, archived for review'
    );
    
    // Archive the message
    await _archiveMessage(batchId, message, 'unknown_failure');
    
    // Log for audit
    await _logDlqEvent('archived_for_review', {
      'batch_id': batchId,
      'message_id': message['messageId'],
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Archive a message for later analysis
  Future<void> _archiveMessage(String batchId, Map<String, dynamic> message, String category) async {
    try {
      // In production, this would store to a secure cloud storage location
      // For now, we'll store locally with a limit
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing archives by category
      final key = 'archived_messages_$category';
      final archives = prefs.getStringList(key) ?? [];
      
      // Add this message
      archives.add(jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'batch_id': batchId,
        'message': message,
      }));
      
      // Keep only the most recent 50 archives per category
      if (archives.length > 50) {
        archives.removeRange(0, archives.length - 50);
      }
      
      await prefs.setStringList(key, archives);
      debugPrint('>>> Archived message for batch: $batchId (category: $category)');
    } catch (e) {
      debugPrint('!!! Failed to archive message: $e');
    }
  }
  
  /// Get batch information from database
  Future<Map<String, dynamic>?> _getBatchInfo(String batchId) async {
    final db = await _db.database;
    
    final results = await db.query(
      DatabaseHelper.tableSyncBatches,
      where: 'id = ?',
      whereArgs: [batchId],
    );
    
    if (results.isEmpty) {
      return null;
    }
    
    return results.first;
  }
  
  /// Trigger resend of a batch
  Future<void> _resendBatch(String batchId) async {
    // This would normally call SyncService.syncNow() with the specific batch
    // For now, we'll just update the status to trigger the next sync cycle
    debugPrint('>>> Triggering resend of batch: $batchId');
    
    // Get measurements for this batch
    final measurements = await _db.getMeasurementsByBatch(batchId);
    if (measurements.isEmpty) {
      debugPrint('!!! No measurements found for batch: $batchId');
      return;
    }
    
    // Update measurements to pending status
    for (final measurement in measurements) {
      await _db.updateMeasurementSyncStatus(
        measurement.id, 
        'pending',
      );
    }
    
    // The next sync cycle will pick these up
  }
  
  /// Log DLQ events for audit trail
  Future<void> _logDlqEvent(String eventType, Map<String, dynamic> details) async {
    try {
      final auditEvent = {
        'event_type': 'dlq_$eventType',
        'timestamp': DateTime.now().toIso8601String(),
        'details': details,
      };
      
      // Store audit log locally
      final prefs = await SharedPreferences.getInstance();
      final auditLogs = prefs.getStringList('dlq_audit_logs') ?? [];
      auditLogs.add(jsonEncode(auditEvent));
      
      // Keep only the most recent 500 logs locally
      if (auditLogs.length > 500) {
        auditLogs.removeRange(0, auditLogs.length - 500);
      }
      
      await prefs.setStringList('dlq_audit_logs', auditLogs);
      
      // In production, would also send to secure audit log service
      // await _sendToAuditService(auditEvent);
      
      debugPrint('>>> DLQ audit log: $eventType');
    } catch (e) {
      debugPrint('!!! Error logging DLQ audit event: $e');
    }
  }
  
  /// Send to audit service (to be implemented)
  Future<void> _sendToAuditService(Map<String, dynamic> auditEvent) async {
    // TODO: Implement integration with cloud audit logging service
    // This would send the audit event to a HIPAA-compliant logging service
  }
}
