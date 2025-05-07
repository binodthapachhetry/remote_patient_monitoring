import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the lifecycle of the background BLE service on different platforms.
/// Provides a consistent API for starting/stopping the service and storing preferences.
class BackgroundServiceManager {
  // Singleton pattern
  static final BackgroundServiceManager _instance = BackgroundServiceManager._internal();
  factory BackgroundServiceManager() => _instance;
  BackgroundServiceManager._internal();
  
  // Platform channel for native communication
  static const MethodChannel _platform = MethodChannel('com.example.remote_patient_monitoring/background_service');
  
  // Service state
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  
  /// Start the background service based on the platform
  Future<void> startService() async {
    if (_isRunning) return;
    
    try {
      if (Platform.isAndroid) {
        final result = await _platform.invokeMethod<bool>('startService');
        _isRunning = result ?? false;
        debugPrint('>>> Background service started on Android: $_isRunning');
      } else if (Platform.isIOS) {
        // iOS uses the background modes configured in Info.plist
        // No explicit service to start, but we track state for API consistency
        _isRunning = true;
        debugPrint('>>> Background processing enabled on iOS');
      }
    } catch (e) {
      debugPrint('!!! Failed to start background service: $e');
    }
  }
  
  /// Stop the background service
  Future<void> stopService() async {
    if (!_isRunning) return;
    
    try {
      if (Platform.isAndroid) {
        final result = await _platform.invokeMethod<bool>('stopService');
        _isRunning = !(result ?? false);
      } else if (Platform.isIOS) {
        // iOS doesn't have explicit service stopping
      }
      
      _isRunning = false;
      debugPrint('>>> Background service stopped');
    } catch (e) {
      debugPrint('!!! Failed to stop background service: $e');
    }
  }
  
  /// Save the user's preference for background service and apply it
  Future<void> setServicePreference(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('backgroundServiceEnabled', enabled);
    
    if (enabled) {
      await startService();
    } else {
      await stopService();
    }
  }
  
  /// Initialize the background service based on saved preferences
  Future<void> initFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('backgroundServiceEnabled') ?? false;
    
    if (enabled) {
      await startService();
    }
  }
  
  /// Check if the service should be started on boot
  Future<bool> isStartedOnBoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('backgroundServiceEnabled') ?? false;
  }
}
