import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../data/database_helper.dart';
import '../models/health_measurement.dart';
import 'key_manager.dart';

/// Handles processing of messages that failed to be delivered to Pub/Sub
/// and were sent to the Dead Letter Queue (DLQ)
class DlqHandler {
  // Singleton pattern
  static final DlqHandler _instance = DlqHandler._internal();
  factory DlqHandler() => _instance;
  DlqHandler._internal();
  
  // Dependencies
  final _db = DatabaseHelper();
  final _keyManager = KeyManager();
  
  // Constants
  static const int _maxRetryAttempts = 5;
  static const Duration _initialBackoff = Duration(minutes: 5);
  
  // State tracking
  bool _isProcessing = false;
  Timer? _retryTimer;
  Timer? _retryQueueTimer;
  
  /// Initialize the DLQ handler
  Future<void> initialize() async {
    // Start the retry queue processor
    _retryQueueTimer = Timer.periodic(
      Duration(minutes: 15),
      (_) => checkRetryQueue(),
    );
    
    debugPrint('>>> DLQ handler initialized');
  }
  
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
      
      if (attributes == null || messageId == null) {
        debugPrint('!!! Invalid DLQ message format');
        _isProcessing = false;
        return false;
      }
      
      // Extract batch information
      final batchId = attributes['batch_id'] as String?;
      if (batchId == null) {
        debugPrint('!!! Missing batch_id in DLQ message');
        _isProcessing = false;
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
          
        case 'key_version_mismatch':
          // Handle key version mismatch
          await _handleKeyVersionMismatch(batchId, message);
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
    
    // Update batch status to retry_scheduled with increased retry count
    await _db.updateBatchStatus(
      batchId, 
      'retry_scheduled',
      errorMessage: 'Rate limit exceeded, retry scheduled'
    );
    
    // Schedule retry after delay
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () async {
      // Get measurements for this batch
      final measurements = await _db.getMeasurementsByBatch(batchId);
      if (measurements.isEmpty) {
        debugPrint('!!! No measurements found for batch: $batchId');
        return;
      }
      
      // Attempt to resend with the SyncService
      // This is intentionally not awaited to avoid blocking the DLQ handler
      await _retrySendBatch(measurements, batchId);
    });
    
    // Log retry scheduling for audit trail
    await _logRetryEvent(batchId, retryCount, DateTime.now().add(delay), 'rate_limit_exceeded');
  }
  
  /// Handle format/validation failures
  Future<void> _handleFormatFailure(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling format failure for batch: $batchId');
    
    // These are permanent failures, so mark as failed
    await _db.updateBatchStatus(
      batchId, 
      'permanently_failed',
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
    
    // Mark all measurements in this batch as failed
    await _markMeasurementsFailed(batchId);
  }
  
  /// Handle authentication failures
  Future<void> _handleAuthFailure(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling auth failure for batch: $batchId');
    
    // Update batch status
    await _db.updateBatchStatus(
      batchId, 
      'retry_scheduled',
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
    
    // Get measurements for this batch
    final measurements = await _db.getMeasurementsByBatch(batchId);
    if (measurements.isEmpty) {
      debugPrint('!!! No measurements found for batch: $batchId');
      return;
    }
    
    // Schedule immediate retry
    await _retrySendBatch(measurements, batchId);
  }
  
  /// Handle key version mismatch
  Future<void> _handleKeyVersionMismatch(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling key version mismatch for batch: $batchId');
    
    try {
      // Get the batch information
      final batch = await _getBatchInfo(batchId);
      if (batch == null) {
        debugPrint('!!! Batch not found: $batchId');
        return;
      }
      
      // Get the key version used for this batch
      final keyVersion = batch['key_version'] as String? ?? 'v1';
      
      // Get the current key version
      final currentKeyVersion = _keyManager.getCurrentKeyVersion();
      
      debugPrint('>>> Batch key version: $keyVersion, current key version: $currentKeyVersion');
      
      // If the batch was encrypted with an old key, we need to re-encrypt
      if (keyVersion != currentKeyVersion) {
        // Get measurements for this batch
        final measurements = await _db.getMeasurementsByBatch(batchId);
        if (measurements.isEmpty) {
          debugPrint('!!! No measurements found for batch: $batchId');
          return;
        }
        
        // Update batch with current key version
        final db = await _db.database;
        await db.update(
          DatabaseHelper.tableSyncBatches,
          {'key_version': currentKeyVersion},
          where: 'id = ?',
          whereArgs: [batchId],
        );
        
        // Update measurements with current key version
        for (final measurement in measurements) {
          await db.update(
            DatabaseHelper.tableHealthMeasurements,
            {'key_version': currentKeyVersion},
            where: 'id = ?',
            whereArgs: [measurement.id],
          );
        }
        
        // Log key version update
        await _logDlqEvent('key_version_updated', {
          'batch_id': batchId,
          'old_version': keyVersion,
          'new_version': currentKeyVersion,
          'measurement_count': measurements.length,
        });
        
        // Retry sending with updated key version
        await _retrySendBatch(measurements, batchId);
      } else {
        // If the key version is current but still failing, treat as server error
        await _scheduleRetry(batchId, message);
      }
    } catch (e) {
      debugPrint('!!! Error handling key version mismatch: $e');
      await _scheduleRetry(batchId, message);
    }
  }
  
  /// Schedule a retry for server errors
  Future<void> _scheduleRetry(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Scheduling retry for server error on batch: $batchId');
    
    // Get retry count
    final batch = await _getBatchInfo(batchId);
    final retryCount = batch?['retryCount'] as int? ?? 0;
    
    // If we've exceeded max retries, mark as failed
    if (retryCount >= _maxRetryAttempts) {
      await _handlePermanentFailure(batchId, message);
      return;
    }
    
    // Otherwise, schedule a retry with backoff
    // Exponential backoff: 5min, 10min, 20min, 40min, 80min
    final backoffMinutes = _initialBackoff.inMinutes * (1 << retryCount);
    final nextRetryTime = DateTime.now().add(Duration(minutes: backoffMinutes));
    
    await _db.updateBatchStatus(
      batchId, 
      'retry_scheduled',
      errorMessage: 'Server error, retry scheduled for ${nextRetryTime.toIso8601String()}'
    );
    
    // Store retry information for the retry queue processor
    await _storeRetryInfo(batchId, nextRetryTime);
    
    // Schedule retry
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(minutes: backoffMinutes), () async {
      // Get measurements for this batch
      final measurements = await _db.getMeasurementsByBatch(batchId);
      if (measurements.isEmpty) {
        debugPrint('!!! No measurements found for batch: $batchId');
        return;
      }
      
      // Attempt to resend
      await _retrySendBatch(measurements, batchId);
    });
    
    // Log retry scheduling for audit trail
    await _logRetryEvent(batchId, retryCount, nextRetryTime, 'server_error');
  }
  
  /// Store retry information for the retry queue processor
  Future<void> _storeRetryInfo(String batchId, DateTime retryTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final retryQueue = prefs.getStringList('retry_queue') ?? [];
      
      // Create retry info
      final retryInfo = {
        'batch_id': batchId,
        'retry_time': retryTime.millisecondsSinceEpoch,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Add to queue
      retryQueue.add(jsonEncode(retryInfo));
      
      // Keep queue size reasonable
      if (retryQueue.length > 100) {
        retryQueue.removeRange(0, retryQueue.length - 100);
      }
      
      await prefs.setStringList('retry_queue', retryQueue);
      debugPrint('>>> Stored retry info for batch: $batchId, retry at: ${retryTime.toIso8601String()}');
    } catch (e) {
      debugPrint('!!! Error storing retry info: $e');
    }
  }
  
  /// Handle a permanently failed batch
  Future<void> _handlePermanentFailure(String batchId, Map<String, dynamic> message) async {
    debugPrint('>>> Handling permanent failure for batch: $batchId');
    
    // Update batch status to indicate permanent failure
    await _db.updateBatchStatus(
      batchId, 
      'permanently_failed', 
      errorMessage: 'Exceeded maximum retry attempts'
    );
    
    // Archive the failed message
    await _archiveMessage(batchId, message, 'max_retries_exceeded');
    
    // Mark all measurements as failed
    await _markMeasurementsFailed(batchId);
    
    // Log permanent failure for audit trail
    await _logDlqEvent('max_retries_exceeded', {
      'batch_id': batchId,
      'retry_count': _maxRetryAttempts,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Mark all measurements in a batch as failed
  Future<void> _markMeasurementsFailed(String batchId) async {
    final measurements = await _db.getMeasurementsByBatch(batchId);
    
    for (final measurement in measurements) {
      await _db.updateMeasurementSyncStatus(
        measurement.id, 
        'failed',
      );
    }
    
    debugPrint('>>> Marked ${measurements.length} measurements as failed for batch: $batchId');
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
  
  /// Simplified version of SyncService._sendBatch to avoid circular dependencies
  Future<bool> _retrySendBatch(List<HealthMeasurement> measurements, String batchId) async {
    try {
      debugPrint('>>> Retrying send for batch: $batchId with ${measurements.length} measurements');
      
      // Update batch status to indicate retry in progress
      await _db.updateBatchStatus(batchId, 'retrying');
      
      // Get user's preferred region for data residency
      final region = await _getUserRegionPreference();
      final url = 'https://health-data-ingest-abcdef-$region.a.run.app/retry';
      
      // Get Firebase auth token
      final token = await _getAuthToken();
      
      // Create simplified payload for retry
      final payload = {
        'batch_id': batchId,
        'retry': true,
        'measurements': measurements.map((m) => m.toMap()).toList(),
        'metadata': {
          'retry_count': await _getBatchRetryCount(batchId),
          'original_timestamp': measurements.first.timestamp,
          'retry_timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      };
      
      // Add data integrity checksum
      final checksum = _calculatePayloadChecksum(payload);
      
      // Get current key version
      final keyVersion = _keyManager.getCurrentKeyVersion();
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Retry-Attempt': 'true',
          'X-Data-Checksum': checksum,
          'X-Data-Region': region,
          'X-Key-Version': keyVersion,
        },
        body: json.encode(payload),
      );
      
      debugPrint('>>> Retry response: ${response.statusCode}');
      final success = response.statusCode >= 200 && response.statusCode < 300;
      
      if (success) {
        // Mark batch as sent
        final messageIds = json.decode(response.body)['messageIds'] as List<dynamic>?;
        final pubsubMessageId = messageIds != null && messageIds.isNotEmpty ? messageIds[0] as String : null;
        
        await _db.updateBatchStatus(
          batchId, 
          'sent', 
          pubsubMessageId: pubsubMessageId
        );
        
        // Mark all measurements in batch as sent
        for (final measurement in measurements) {
          await _db.updateMeasurementSyncStatus(measurement.id, 'sent');
        }
        
        // Log successful retry for audit trail
        await _logDlqEvent('retry_success', {
          'batch_id': batchId,
          'measurement_count': measurements.length,
          'retry_count': await _getBatchRetryCount(batchId),
          'pubsub_message_id': pubsubMessageId,
        });
      } else {
        // Increment retry count
        final db = await _db.database;
        await db.rawUpdate(
          'UPDATE ${DatabaseHelper.tableSyncBatches} SET retryCount = retryCount + 1 WHERE id = ?',
          [batchId]
        );
        
        // Update batch status to indicate retry failed
        await _db.updateBatchStatus(batchId, 'retry_failed', 
            errorMessage: 'Retry attempt failed: ${response.statusCode}');
        
        // Log failed retry for audit trail
        await _logDlqEvent('retry_failed', {
          'batch_id': batchId,
          'status_code': response.statusCode,
          'retry_count': await _getBatchRetryCount(batchId),
          'response': response.body.length > 1000 ? response.body.substring(0, 1000) : response.body,
        });
      }
      
      return success;
    } catch (e) {
      debugPrint('!!! Error retrying batch $batchId: $e');
      
      // Update batch status to indicate retry failed
      await _db.updateBatchStatus(batchId, 'retry_failed', 
          errorMessage: 'Exception during retry: $e');
      
      return false;
    }
  }
  
  /// Get batch retry count
  Future<int> _getBatchRetryCount(String batchId) async {
    try {
      final db = await _db.database;
      final results = await db.query(
        DatabaseHelper.tableSyncBatches,
        columns: ['retryCount'],
        where: 'id = ?',
        whereArgs: [batchId],
      );
      
      if (results.isNotEmpty) {
        return results.first['retryCount'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('!!! Error getting batch retry count: $e');
      return 0;
    }
  }
  
  /// Log retry event for audit trail
  Future<void> _logRetryEvent(String batchId, int retryCount, DateTime nextRetryTime, String errorType) async {
    try {
      final auditEvent = {
        'event_type': 'dlq_retry_scheduled',
        'timestamp': DateTime.now().toIso8601String(),
        'batch_id': batchId,
        'retry_count': retryCount,
        'next_retry_time': nextRetryTime.toIso8601String(),
        'error_type': errorType,
      };
      
      await _logDlqEvent('retry_scheduled', auditEvent);
    } catch (e) {
      debugPrint('!!! Error logging retry event: $e');
    }
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
      await _sendToAuditService(auditEvent);
      
      debugPrint('>>> DLQ audit log: $eventType');
    } catch (e) {
      debugPrint('!!! Error logging DLQ audit event: $e');
    }
  }
  
  /// Send to audit service
  Future<void> _sendToAuditService(Map<String, dynamic> auditEvent) async {
    try {
      // Get user's preferred region for data residency
      final region = await _getUserRegionPreference();
      
      // Cloud Logging integration for HIPAA-compliant audit trails
      final url = 'https://logging.googleapis.com/v2/entries:write';
      
      // Get auth token
      final token = await _getAuthToken();
      if (token.isEmpty) {
        debugPrint('!!! No auth token available for audit service');
        return;
      }
      
      // Format for Cloud Logging
      final payload = {
        'entries': [
          {
            'logName': 'projects/health-data-project/logs/health-app-dlq-audit',
            'resource': {
              'type': 'mobile_device',
              'labels': {
                'device_id': await _getDeviceIdentifier(),
              }
            },
            'severity': 'WARNING',
            'jsonPayload': auditEvent,
            'labels': {
              'event_type': auditEvent['event_type'],
              'region': region,
            }
          }
        ],
        'partialSuccess': true,
      };
      
      // Send asynchronously - don't wait for response
      http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
      ).then((response) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          debugPrint('>>> DLQ audit log sent to Cloud Logging');
        } else {
          debugPrint('!!! Failed to send DLQ audit log: ${response.statusCode}');
        }
      }).catchError((e) {
        debugPrint('!!! Error sending DLQ audit log: $e');
      });
    } catch (e) {
      debugPrint('!!! Error preparing DLQ audit log: $e');
    }
  }
  
  /// Get auth token for API requests
  Future<String> _getAuthToken() async {
    try {
      // Get the current Firebase user and their ID token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('!!! No authenticated user found');
        return '';
      }
      
      final token = await user.getIdToken();
      return token;
    } catch (e) {
      debugPrint('!!! Error getting auth token: $e');
      return '';
    }
  }
  
  /// Get user's preferred region for data residency
  Future<String> _getUserRegionPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('preferred_region') ?? 'us-central1';
    } catch (e) {
      return 'us-central1'; // Default region
    }
  }
  
  /// Get device identifier for audit logs
  Future<String> _getDeviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_identifier');
    
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('device_identifier', deviceId);
    }
    
    return deviceId;
  }
  
  /// Calculate checksum for data integrity verification
  String _calculatePayloadChecksum(Map<String, dynamic> payload) {
    try {
      // Create a stable JSON representation
      final jsonData = json.encode(payload);
      
      // Calculate SHA-256 hash
      final bytes = utf8.encode(jsonData);
      final digest = crypto.sha256.convert(bytes);
      
      return digest.toString();
    } catch (e) {
      debugPrint('!!! Error calculating checksum: $e');
      return '';
    }
  }
  
  /// Get all archived failed messages
  Future<List<Map<String, dynamic>>> getArchivedFailedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final categories = ['format_failure', 'unknown_failure', 'max_retries_exceeded'];
      final allMessages = <Map<String, dynamic>>[];
      
      for (final category in categories) {
        final key = 'archived_messages_$category';
        final messages = prefs.getStringList(key) ?? [];
        
        for (final msg in messages) {
          allMessages.add(jsonDecode(msg) as Map<String, dynamic>);
        }
      }
      
      // Sort by timestamp (newest first)
      allMessages.sort((a, b) {
        final aTime = a['timestamp'] as String;
        final bTime = b['timestamp'] as String;
        return bTime.compareTo(aTime);
      });
      
      return allMessages;
    } catch (e) {
      debugPrint('!!! Error getting archived failed messages: $e');
      return [];
    }
  }
  
  /// Check for and process any due retries
  Future<void> checkRetryQueue() async {
    try {
      debugPrint('>>> Checking retry queue');
      
      final prefs = await SharedPreferences.getInstance();
      final retryQueue = prefs.getStringList('retry_queue') ?? [];
      
      if (retryQueue.isEmpty) {
        debugPrint('>>> Retry queue is empty');
        return;
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final dueRetries = <String>[];
      final pendingRetries = <String>[];
      
      // Find retries that are due
      for (final retryJson in retryQueue) {
        try {
          final retry = jsonDecode(retryJson) as Map<String, dynamic>;
          final retryTime = retry['retry_time'] as int;
          
          if (retryTime <= now) {
            dueRetries.add(retryJson);
          } else {
            pendingRetries.add(retryJson);
          }
        } catch (e) {
          debugPrint('!!! Error parsing retry info: $e');
          // Skip invalid entries
        }
      }
      
      // Update the queue to remove due retries
      await prefs.setStringList('retry_queue', pendingRetries);
      
      if (dueRetries.isEmpty) {
        debugPrint('>>> No due retries found');
        return;
      }
      
      debugPrint('>>> Found ${dueRetries.length} due retries');
      
      // Process each due retry
      for (final retryJson in dueRetries) {
        try {
          final retry = jsonDecode(retryJson) as Map<String, dynamic>;
          final batchId = retry['batch_id'] as String;
          
          // Get batch info
          final batch = await _getBatchInfo(batchId);
          if (batch == null) {
            debugPrint('!!! Batch not found: $batchId');
            continue;
          }
          
          // Check if batch is still in a retryable state
          final status = batch['status'] as String;
          if (status != 'retry_scheduled' && status != 'retry_failed') {
            debugPrint('>>> Batch $batchId is no longer in retryable state: $status');
            continue;
          }
          
          // Get measurements for this batch
          final measurements = await _db.getMeasurementsByBatch(batchId);
          if (measurements.isEmpty) {
            debugPrint('!!! No measurements found for batch: $batchId');
            continue;
          }
          
          // Update batch status
          await _db.updateBatchStatus(batchId, 'retrying');
          
          // Attempt to resend
          final success = await _retrySendBatch(measurements, batchId);
          
          if (success) {
            debugPrint('>>> Successfully retried batch: $batchId');
          } else {
            debugPrint('!!! Failed to retry batch: $batchId');
            
            // Check if we've exceeded retry attempts
            final retryCount = batch['retryCount'] as int? ?? 0;
            if (retryCount >= _maxRetryAttempts) {
              await _handlePermanentFailure(batchId, {
                'messageId': 'retry-${const Uuid().v4()}',
                'attributes': {
                  'batch_id': batchId,
                  'error_type': 'retry_limit_exceeded',
                },
              });
            }
          }
        } catch (e) {
          debugPrint('!!! Error processing due retry: $e');
        }
      }
    } catch (e) {
      debugPrint('!!! Error checking retry queue: $e');
    }
  }
  
  /// Clean up resources
  void dispose() {
    _retryTimer?.cancel();
    _retryQueueTimer?.cancel();
  }
}
