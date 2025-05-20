import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Manages encryption keys for secure data handling
/// Implements CMEK (Customer-Managed Encryption Keys) pattern
/// with secure key rotation and versioning
class KeyManager {
  // Singleton pattern
  static final KeyManager _instance = KeyManager._internal();
  factory KeyManager() => _instance;
  KeyManager._internal();
  
  // Key cache
  Map<String, _CachedKey> _keyCache = {};
  
  // Current key version
  String _currentKeyVersion = 'v1';
  
  // Key rotation schedule
  Timer? _keyRotationTimer;
  
  // Key rotation interval (90 days by default)
  Duration _rotationInterval = Duration(days: 90);
  
  // Flag to use local fallback keys in development
  bool _useLocalFallback = false;
  
  /// Initialize the key manager
  Future<void> initialize() async {
    debugPrint('>>> Initializing KeyManager');
    
    // Load cached key metadata
    await _loadKeyMetadata();
    
    // Check if we need to fetch the latest key
    await _refreshCurrentKey();
    
    // Schedule key rotation checks
    _scheduleKeyRotation();
    
    // Determine if we should use local fallback (for development)
    _useLocalFallback = await _shouldUseLocalFallback();
    
    debugPrint('>>> KeyManager initialized with key version: $_currentKeyVersion');
    debugPrint('>>> Using local fallback: $_useLocalFallback');
  }
  
  /// Get the current encryption key
  Future<encrypt.Key> getCurrentKey() async {
    try {
      // Check if we have the current key in cache
      if (_keyCache.containsKey(_currentKeyVersion) && 
          !_keyCache[_currentKeyVersion]!.isExpired) {
        return _keyCache[_currentKeyVersion]!.key;
      }
      
      // If not in cache or expired, fetch from key service
      final keyData = await _fetchKeyFromService(_currentKeyVersion);
      if (keyData != null) {
        // Cache the key with expiration
        _cacheKey(_currentKeyVersion, keyData);
        return encrypt.Key.fromBase64(keyData);
      }
      
      // If we couldn't fetch the key, use fallback
      debugPrint('!!! Failed to fetch key, using fallback');
      return _getFallbackKey();
    } catch (e) {
      debugPrint('!!! Error getting encryption key: $e');
      return _getFallbackKey();
    }
  }
  
  /// Get key by specific version (for decrypting old data)
  Future<encrypt.Key?> getKeyByVersion(String version) async {
    try {
      // Check cache first
      if (_keyCache.containsKey(version) && !_keyCache[version]!.isExpired) {
        return _keyCache[version]!.key;
      }
      
      // Fetch from service
      final keyData = await _fetchKeyFromService(version);
      if (keyData != null) {
        _cacheKey(version, keyData);
        return encrypt.Key.fromBase64(keyData);
      }
      
      // If we can't get the specific version, return null
      return null;
    } catch (e) {
      debugPrint('!!! Error getting key version $version: $e');
      return null;
    }
  }
  
  /// Get the current key version
  String getCurrentKeyVersion() {
    return _currentKeyVersion;
  }
  
  /// Fetch key from key management service
  Future<String?> _fetchKeyFromService(String version) async {
    if (_useLocalFallback) {
      debugPrint('>>> Using local fallback key (development mode)');
      return _getLocalKeyForVersion(version);
    }
    
    try {
      // Get auth token for API request
      final token = await _getAuthToken();
      if (token.isEmpty) {
        debugPrint('!!! No auth token available for key service');
        return null;
      }
      
      // In production, this would call a secure key management service
      // For example, Google Cloud KMS or a custom key service
      final response = await http.get(
        Uri.parse('https://key-service.example.com/keys/$version'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Client-Version': '1.0.0',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['key_material'] as String?;
      } else {
        debugPrint('!!! Failed to fetch key: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('!!! Error fetching key: $e');
      return null;
    }
  }
  
  /// Cache a key with expiration
  void _cacheKey(String version, String keyData) {
    // Cache keys expire after 24 hours to ensure we refresh regularly
    final expiration = DateTime.now().add(Duration(hours: 24));
    _keyCache[version] = _CachedKey(
      key: encrypt.Key.fromBase64(keyData),
      expiration: expiration,
    );
    
    debugPrint('>>> Cached key version $version until ${expiration.toIso8601String()}');
  }
  
  /// Get fallback key for development/emergency use
  encrypt.Key _getFallbackKey() {
    // In production, this would be a securely stored backup key
    // For this implementation, using a fixed key (NOT SECURE for production)
    const fallbackKeyString = 'CMEK_health_data_encryption_key_32byte';
    return encrypt.Key.fromUtf8(fallbackKeyString);
  }
  
  /// Get local key for development (by version)
  String _getLocalKeyForVersion(String version) {
    // For development only - simulate different key versions
    switch (version) {
      case 'v1':
        return base64.encode(utf8.encode('CMEK_health_data_encryption_key_v1_32b'));
      case 'v2':
        return base64.encode(utf8.encode('CMEK_health_data_encryption_key_v2_32b'));
      case 'v3':
        return base64.encode(utf8.encode('CMEK_health_data_encryption_key_v3_32b'));
      default:
        return base64.encode(utf8.encode('CMEK_health_data_encryption_key_32byte'));
    }
  }
  
  /// Load cached key metadata from storage
  Future<void> _loadKeyMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentKeyVersion = prefs.getString('current_key_version') ?? 'v1';
      
      // Load rotation interval (in days)
      final rotationDays = prefs.getInt('key_rotation_days') ?? 90;
      _rotationInterval = Duration(days: rotationDays);
    } catch (e) {
      debugPrint('!!! Error loading key metadata: $e');
      // Use defaults if we can't load
      _currentKeyVersion = 'v1';
      _rotationInterval = Duration(days: 90);
    }
  }
  
  /// Save key metadata to storage
  Future<void> _saveKeyMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_key_version', _currentKeyVersion);
      await prefs.setInt('key_rotation_days', _rotationInterval.inDays);
    } catch (e) {
      debugPrint('!!! Error saving key metadata: $e');
    }
  }
  
  /// Check if we should use local fallback keys
  Future<bool> _shouldUseLocalFallback() async {
    try {
      // In development, we might want to use local keys
      // This could be controlled by a feature flag or build config
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('use_local_keys') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Refresh the current key version
  Future<void> _refreshCurrentKey() async {
    try {
      // In production, this would check with the key service
      // for the latest key version
      if (_useLocalFallback) {
        // For development, simulate key versions
        final prefs = await SharedPreferences.getInstance();
        _currentKeyVersion = prefs.getString('current_key_version') ?? 'v1';
        return;
      }
      
      final token = await _getAuthToken();
      if (token.isEmpty) {
        debugPrint('!!! No auth token available for key service');
        return;
      }
      
      final response = await http.get(
        Uri.parse('https://key-service.example.com/keys/current'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Client-Version': '1.0.0',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['version'] as String?;
        
        if (latestVersion != null && latestVersion != _currentKeyVersion) {
          debugPrint('>>> Updating key version from $_currentKeyVersion to $latestVersion');
          _currentKeyVersion = latestVersion;
          await _saveKeyMetadata();
        }
      }
    } catch (e) {
      debugPrint('!!! Error refreshing current key: $e');
    }
  }
  
  /// Schedule key rotation checks
  void _scheduleKeyRotation() {
    _keyRotationTimer?.cancel();
    
    // Check for key rotation daily
    _keyRotationTimer = Timer.periodic(
      Duration(days: 1),
      (_) => _checkKeyRotation(),
    );
    
    debugPrint('>>> Scheduled key rotation checks');
  }
  
  /// Check if key rotation is needed
  Future<void> _checkKeyRotation() async {
    try {
      // In production, this would check with the key service
      // to see if rotation is needed based on policy
      await _refreshCurrentKey();
      
      // Log key status for audit
      await _logKeyEvent('key_rotation_check', {
        'current_version': _currentKeyVersion,
        'rotation_interval_days': _rotationInterval.inDays,
      });
    } catch (e) {
      debugPrint('!!! Error checking key rotation: $e');
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
  
  /// Log key events for audit trail
  Future<void> _logKeyEvent(String eventType, Map<String, dynamic> details) async {
    try {
      final auditEvent = {
        'event_type': 'key_$eventType',
        'timestamp': DateTime.now().toIso8601String(),
        'details': details,
      };
      
      // Store audit log locally
      final prefs = await SharedPreferences.getInstance();
      final auditLogs = prefs.getStringList('key_audit_logs') ?? [];
      auditLogs.add(jsonEncode(auditEvent));
      
      // Keep only the most recent 100 logs locally
      if (auditLogs.length > 100) {
        auditLogs.removeRange(0, auditLogs.length - 100);
      }
      
      await prefs.setStringList('key_audit_logs', auditLogs);
      
      // In production, would also send to secure audit log service
      debugPrint('>>> Key audit log: $eventType');
    } catch (e) {
      debugPrint('!!! Error logging key audit event: $e');
    }
  }
  
  /// Clean up resources
  void dispose() {
    _keyRotationTimer?.cancel();
  }
}

/// Cached key with expiration
class _CachedKey {
  final encrypt.Key key;
  final DateTime expiration;
  
  _CachedKey({
    required this.key,
    required this.expiration,
  });
  
  /// Check if the cached key is expired
  bool get isExpired => DateTime.now().isAfter(expiration);
}
