import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../data/database_helper.dart';
import '../models/health_measurement.dart';
import '../hl7/hl7_message_generator.dart';
import 'user_manager.dart';

/// Manages the synchronization of health data to the cloud
/// Implements the batching and reliability strategies from the architecture doc
class SyncService {
  // Singleton pattern
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
  
  // Dependencies
  final _db = DatabaseHelper();
  final _hl7Generator = HL7MessageGenerator();
  final _connectivity = Connectivity();
  final _userManager = UserManager();
  
  // State tracking
  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _circuitBreakerOpen = false;
  int _failureCount = 0;
  Timer? _syncTimer;
  Timer? _circuitBreakerTimer;
  StreamSubscription? _connectivitySubscription;
  
  // Circuit breaker reset delay, increases with consecutive failures
  Duration get _circuitBreakerDelay {
    // Exponential backoff with maximum delay of 30 minutes
    final minutes = math.min(math.pow(2, _failureCount - 1).toInt(), 30);
    return Duration(minutes: minutes);
  }
  
  // Sync status for UI feedback
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;
  
  // Settings
  bool _autoSyncEnabled = true;
  bool _syncOnlyOnWifi = false;
  int _batchSize = 50; // Default max measurements per batch
  int _syncIntervalMinutes = 15; // Default sync frequency
  
  /// Initialize the sync service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Load user preferences
    await _loadSettings();
    
    // Start monitoring connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    
    // Schedule periodic sync if auto-sync is enabled
    if (_autoSyncEnabled) {
      _scheduleSyncTimer();
    }
    
    _isInitialized = true;
    _updateSyncStatus();
    debugPrint('>>> SyncService initialized: autoSync=$_autoSyncEnabled, interval=$_syncIntervalMinutes min');
  }
  
  /// Handle connectivity changes
  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    // In connectivity_plus 6.x, the callback returns a list of results
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    debugPrint('>>> Connectivity changed: $result');
    
    // If we have connectivity and circuit breaker was open, close it
    if (result != ConnectivityResult.none && _circuitBreakerOpen) {
      _resetCircuitBreaker();
    }
    
    // If we get connectivity and have pending data, trigger a sync 
    // (respecting wifi-only setting)
    if (result != ConnectivityResult.none && 
        !_isSyncing && 
        _autoSyncEnabled &&
        (!_syncOnlyOnWifi || result == ConnectivityResult.wifi)) {
      final stats = await _db.getSyncStats();
      final pendingCount = stats['measurements_pending'] ?? 0;
      
      if (pendingCount > 0) {
        debugPrint('>>> Connectivity restored with $pendingCount pending measurements, triggering sync');
        syncNow();
      }
    }
    
    _updateSyncStatus();
  }
  
  /// Load user settings for sync behavior
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSyncEnabled = prefs.getBool('autoSyncEnabled') ?? true;
    _syncOnlyOnWifi = prefs.getBool('syncOnlyOnWifi') ?? false;
    _batchSize = prefs.getInt('syncBatchSize') ?? 50;
    _syncIntervalMinutes = prefs.getInt('syncIntervalMinutes') ?? 15;
  }
  
  /// Save settings and apply changes
  Future<void> updateSettings({
    bool? autoSyncEnabled,
    bool? syncOnlyOnWifi,
    int? batchSize,
    int? syncIntervalMinutes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Update changed settings
    if (autoSyncEnabled != null) {
      _autoSyncEnabled = autoSyncEnabled;
      await prefs.setBool('autoSyncEnabled', autoSyncEnabled);
    }
    
    if (syncOnlyOnWifi != null) {
      _syncOnlyOnWifi = syncOnlyOnWifi;
      await prefs.setBool('syncOnlyOnWifi', syncOnlyOnWifi);
    }
    
    if (batchSize != null) {
      _batchSize = batchSize;
      await prefs.setInt('syncBatchSize', batchSize);
    }
    
    if (syncIntervalMinutes != null) {
      _syncIntervalMinutes = syncIntervalMinutes;
      await prefs.setInt('syncIntervalMinutes', syncIntervalMinutes);
    }
    
    // Apply changes
    _syncTimer?.cancel();
    if (_autoSyncEnabled) {
      _scheduleSyncTimer();
    }
    
    _updateSyncStatus();
    debugPrint('>>> SyncService settings updated: autoSync=$_autoSyncEnabled, interval=$_syncIntervalMinutes min');
  }
  
  /// Schedule periodic sync
  void _scheduleSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      Duration(minutes: _syncIntervalMinutes),
      (_) => _checkAndSync(),
    );
    debugPrint('>>> Scheduled sync every $_syncIntervalMinutes minutes');
  }
  
  /// Check conditions and sync if appropriate
  Future<void> _checkAndSync() async {
    if (_isSyncing || _circuitBreakerOpen) return;
    
    // Check if we meet connectivity requirements
    final connectivityResult = await _connectivity.checkConnectivity();
    final hasConnection = connectivityResult != ConnectivityResult.none;
    final isWifi = connectivityResult == ConnectivityResult.wifi;
    
    if (!hasConnection || (_syncOnlyOnWifi && !isWifi)) {
      debugPrint('>>> Skipping scheduled sync: connectivity requirements not met');
      return;
    }
    
    // Check if we have pending data
    final stats = await _db.getSyncStats();
    final pendingCount = stats['measurements_pending'] ?? 0;
    
    if (pendingCount > 0) {
      syncNow();
    } else {
      debugPrint('>>> No pending measurements to sync');
    }
  }
  
  /// Manually trigger sync (user initiated)
  Future<bool> syncNow() async {
    if (_isSyncing) {
      debugPrint('>>> Sync already in progress');
      return false;
    }
    
    if (_circuitBreakerOpen) {
      debugPrint('>>> Circuit breaker open, sync blocked until ${_circuitBreakerTimer?.tick} seconds');
      return false;
    }
    
    _isSyncing = true;
    _updateSyncStatus();
    
    try {
      // Check for active connection
      final connectivityResult = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResult != ConnectivityResult.none;
      
      if (!hasConnection) {
        debugPrint('>>> No network connection, sync aborted');
        _isSyncing = false;
        _updateSyncStatus();
        return false;
      }
      
      // First check for any previously prepared batches that failed to send
      final pendingBatches = await _db.getPendingBatches();
      if (pendingBatches.isNotEmpty) {
        debugPrint('>>> Found ${pendingBatches.length} pending batches to retry');
        
        for (final batch in pendingBatches) {
          final batchId = batch['id'] as String;
          final retryCount = batch['retryCount'] as int;
          
          // Skip batches that have exceeded retry limit
          if (retryCount >= 5) {
            debugPrint('>>> Batch $batchId exceeded retry limit, marking as failed');
            await _db.updateBatchStatus(batchId, 'failed', 
                errorMessage: 'Exceeded retry limit');
            continue;
          }
          
          // Get measurements associated with this batch
          final measurements = await _db.getMeasurementsByBatch(batchId);
          if (measurements.isEmpty) {
            debugPrint('>>> Batch $batchId has no measurements, deleting');
            await _db.updateBatchStatus(batchId, 'failed', 
                errorMessage: 'No measurements found');
            continue;
          }
          
          // Retry sending this batch
          final success = await _sendBatch(measurements, batchId);
          if (!success) {
            // If unsuccessful, we'll stop syncing and try again later
            _isSyncing = false;
            _updateSyncStatus();
            return false;
          }
        }
      }
      
      // Prepare new batches of pending measurements
      bool continueProcessing = true;
      while (continueProcessing) {
        // Get pending measurements up to batch size
        final pendingMeasurements = await _db.getPendingMeasurements(limit: _batchSize);
        
        if (pendingMeasurements.isEmpty) {
          debugPrint('>>> No more pending measurements to sync');
          continueProcessing = false;
          break;
        }
        
        // Create a new batch
        final batchId = const Uuid().v4();
        debugPrint('>>> Creating new batch $batchId with ${pendingMeasurements.length} measurements');
        
        // Update measurements with batch ID in database
        final measurementIds = pendingMeasurements.map((m) => m.id).toList();
        await _db.updateMeasurementBatch(measurementIds, 'batched', batchId);
        await _db.createSyncBatch(batchId, pendingMeasurements.length);
        
        // Send the batch
        final success = await _sendBatch(pendingMeasurements, batchId);
        if (!success) {
          // If unsuccessful, we'll stop syncing and try again later
          continueProcessing = false;
        }
      }
      
      // If we got this far without triggering circuit breaker, reset failure count
      if (_failureCount > 0) {
        _failureCount = 0;
      }
      
      debugPrint('>>> Sync completed successfully');
      _isSyncing = false;
      _updateSyncStatus();
      return true;
      
    } catch (e) {
      debugPrint('!!! Sync error: $e');
      _isSyncing = false;
      
      // Record failure and potentially trigger circuit breaker
      _failureCount++;
      if (_failureCount >= 3) {
        _openCircuitBreaker();
      }
      
      _updateSyncStatus();
      return false;
    }
  }
  
  /// Send a batch of measurements to the cloud
  Future<bool> _sendBatch(List<HealthMeasurement> measurements, String batchId) async {
    try {
      // Generate HL7 message segments
      final hl7Segments = _hl7Generator.generateMessageSegments(measurements);
      
      if (hl7Segments.isEmpty) {
        debugPrint('!!! No valid HL7 segments generated for batch $batchId');
        await _db.updateBatchStatus(batchId, 'failed', 
            errorMessage: 'No valid HL7 segments generated');
        return false;
      }
      
      // Create the message payload
      final messageData = {
        'sendingApplication': 'MobileHealthMVP',
        'messageSegments': hl7Segments,
        'batchId': batchId,
        'participantId': _userManager.participantId,
        'deviceCount': _countUniqueDevices(measurements),
        'messageCount': measurements.length,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Encode for Pub/Sub
      final encodedData = base64.encode(utf8.encode(jsonEncode(messageData)));
      
      // Create Pub/Sub formatted payload
      final payload = {
        'messages': [
          {
            'data': encodedData,
            'attributes': {
              'batch_id': batchId,
              'participant_id': _userManager.participantId ?? 'unknown',
              'device_count': _countUniqueDevices(measurements).toString(),
              'message_count': measurements.length.toString(),
              'hl7_version': '2.5',
              'message_type': 'ORU_R01',
            }
          }
        ]
      };
      
      // Send to the cloud service
      final result = await _sendToCloud(payload, batchId);
      final success = result['success'] as bool;
      
      if (success) {
        // Mark batch as sent
        final messageIds = result['messageIds'] as List<dynamic>;
        final pubsubMessageId = messageIds.isNotEmpty ? messageIds[0] as String : null;
        
        await _db.updateBatchStatus(
          batchId, 
          'sent', 
          pubsubMessageId: pubsubMessageId
        );
        
        // Mark all measurements in batch as sent
        for (final measurement in measurements) {
          await _db.updateMeasurementSyncStatus(measurement.id, 'sent');
        }
        
        debugPrint('>>> Batch $batchId sent successfully with ${measurements.length} measurements');
        return true;
      } else {
        // Mark batch as failed but keep measurements for retry
        await _db.updateBatchStatus(batchId, 'failed', 
            errorMessage: 'Failed to send to cloud');
        debugPrint('!!! Failed to send batch $batchId');
        
        // Record failure and potentially trigger circuit breaker
        _failureCount++;
        if (_failureCount >= 3) {
          _openCircuitBreaker();
        }
        
        return false;
      }
    } catch (e) {
      debugPrint('!!! Error sending batch $batchId: $e');
      await _db.updateBatchStatus(batchId, 'failed', 
          errorMessage: e.toString());
      
      // Record failure and potentially trigger circuit breaker
      _failureCount++;
      if (_failureCount >= 3) {
        _openCircuitBreaker();
      }
      
      return false;
    }
  }
  
  /// Send to cloud service
  Future<Map<String, dynamic>> _sendToCloud(Map<String, dynamic> payload, String batchId) async {
    try {
      // Use the GCP Cloud Run endpoint that processes Pub/Sub messages
      const url = 'https://health-data-ingest-abcdef-uc.a.run.app';
      
      // Get Firebase auth token
      final token = await _getAuthToken();
      
      debugPrint('>>> Sending Pub/Sub payload to cloud for batch: $batchId');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
      );
      
      debugPrint('>>> Cloud response: ${response.statusCode}');
      final success = response.statusCode >= 200 && response.statusCode < 300;
      
      Map<String, dynamic> result = {
        'success': success,
        'messageIds': <String>[],
      };
      
      if (success) {
        final responseData = json.decode(response.body);
        final messageIds = responseData['messageIds'] ?? [];
        result['messageIds'] = messageIds;
        debugPrint('>>> Published ${messageIds.length} Pub/Sub messages');
      } else {
        debugPrint('!!! Error response: ${response.body}');
        result['error'] = response.body;
      }
      
      return result;
    } catch (e) {
      debugPrint('!!! Error sending to cloud: $e');
      return {
        'success': false,
        'messageIds': <String>[],
        'error': e.toString()
      };
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
      debugPrint('>>> Successfully retrieved Firebase auth token');
      return token;
    } catch (e) {
      debugPrint('!!! Error getting auth token: $e');
      return '';
    }
  }
  
  /// Count unique devices in a batch
  int _countUniqueDevices(List<HealthMeasurement> measurements) {
    final deviceIds = <String>{};
    for (final measurement in measurements) {
      deviceIds.add(measurement.deviceId);
    }
    return deviceIds.length;
  }
  
  /// Trigger the circuit breaker pattern
  void _openCircuitBreaker() {
    if (_circuitBreakerOpen) return;
    
    _circuitBreakerOpen = true;
    final delay = _circuitBreakerDelay;
    
    debugPrint('>>> Circuit breaker opened for ${delay.inMinutes} minutes after $_failureCount failures');
    
    // Schedule the circuit breaker to close after the delay
    _circuitBreakerTimer?.cancel();
    _circuitBreakerTimer = Timer(delay, _resetCircuitBreaker);
    
    _updateSyncStatus();
  }
  
  /// Reset the circuit breaker
  void _resetCircuitBreaker() {
    _circuitBreakerOpen = false;
    _circuitBreakerTimer?.cancel();
    _circuitBreakerTimer = null;
    debugPrint('>>> Circuit breaker reset');
    
    // Try to sync again if we have auto-sync enabled
    if (_autoSyncEnabled) {
      _checkAndSync();
    }
    
    _updateSyncStatus();
  }
  
  /// Update sync status for UI feedback
  Future<void> _updateSyncStatus() async {
    if (!_syncStatusController.isClosed) {
      final stats = await _db.getSyncStats();
      
      final status = SyncStatus(
        isSyncing: _isSyncing,
        circuitBreakerOpen: _circuitBreakerOpen,
        circuitBreakerReopensIn: 
            _circuitBreakerTimer?.tick != null ? 
            Duration(seconds: _circuitBreakerTimer!.tick) : null,
        pendingCount: stats['measurements_pending'] ?? 0,
        sentCount: stats['measurements_sent'] ?? 0,
        failedCount: stats['measurements_failed'] ?? 0,
        autoSyncEnabled: _autoSyncEnabled,
        syncOnlyOnWifi: _syncOnlyOnWifi,
        lastSyncAttempt: DateTime.now(),
      );
      
      _syncStatusController.add(status);
    }
  }
  
  /// Store a new measurement in the database
  /// Called when sensors collect new data
  Future<void> storeMeasurement(HealthMeasurement measurement) async {
    await _db.insertMeasurement(measurement);
    
    // If auto-sync is enabled and we're not currently syncing,
    // check if we should trigger a sync based on volume
    if (_autoSyncEnabled && !_isSyncing && !_circuitBreakerOpen) {
      final stats = await _db.getSyncStats();
      final pendingCount = stats['measurements_pending'] ?? 0;
      
      // If we've accumulated enough measurements or have high priority data,
      // trigger a sync immediately instead of waiting for the timer
      if (pendingCount >= _batchSize * 0.8 || _isHighPriority(measurement)) {
        debugPrint('>>> Triggering immediate sync after new measurement');
        _checkAndSync();
      }
    }
    
    _updateSyncStatus();
  }
  
  /// Determine if a measurement is high priority
  bool _isHighPriority(HealthMeasurement measurement) {
    // Implement logic to identify high priority measurements
    // For example, abnormal values that might indicate a health issue
    
    // This is a simplified example - would be more sophisticated in production
    if (measurement.type == 'heart_rate' && measurement.value > 120) {
      return true;
    }
    if (measurement.type == 'oxygen_saturation' && measurement.value < 92) {
      return true;
    }
    if (measurement.type == 'blood_pressure_systolic' && measurement.value > 160) {
      return true;
    }
    
    return false;
  }
  
  /// Force purge of old data
  Future<int> purgeOldData({int keepDays = 30}) async {
    return await _db.purgeSyncedData(keepDays: keepDays);
  }
  
  /// Get current sync status
  Future<SyncStatus> getCurrentStatus() async {
    await _updateSyncStatus();
    final stats = await _db.getSyncStats();
    
    return SyncStatus(
      isSyncing: _isSyncing,
      circuitBreakerOpen: _circuitBreakerOpen,
      circuitBreakerReopensIn: 
          _circuitBreakerTimer?.tick != null ? 
          Duration(seconds: _circuitBreakerTimer!.tick) : null,
      pendingCount: stats['measurements_pending'] ?? 0,
      sentCount: stats['measurements_sent'] ?? 0,
      failedCount: stats['measurements_failed'] ?? 0,
      autoSyncEnabled: _autoSyncEnabled,
      syncOnlyOnWifi: _syncOnlyOnWifi,
      lastSyncAttempt: DateTime.now(),
    );
  }
  
  /// Clean up resources
  void dispose() {
    _syncTimer?.cancel();
    _circuitBreakerTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
}

/// Status data for sync UI feedback
class SyncStatus {
  final bool isSyncing;
  final bool circuitBreakerOpen;
  final Duration? circuitBreakerReopensIn;
  final int pendingCount;
  final int sentCount;
  final int failedCount;
  final bool autoSyncEnabled;
  final bool syncOnlyOnWifi;
  final DateTime lastSyncAttempt;
  
  SyncStatus({
    required this.isSyncing,
    required this.circuitBreakerOpen,
    this.circuitBreakerReopensIn,
    required this.pendingCount,
    required this.sentCount,
    required this.failedCount,
    required this.autoSyncEnabled,
    required this.syncOnlyOnWifi,
    required this.lastSyncAttempt,
  });
  
  /// Whether there is any pending data to sync
  bool get hasPendingData => pendingCount > 0;
  
  /// Total measurements tracked
  int get totalCount => pendingCount + sentCount + failedCount;
  
  /// Text description of current status
  String get statusText {
    if (isSyncing) return 'Syncing...';
    if (circuitBreakerOpen) return 'Sync paused due to errors';
    if (pendingCount > 0) return '$pendingCount items waiting to sync';
    return 'All data synced';
  }
}
