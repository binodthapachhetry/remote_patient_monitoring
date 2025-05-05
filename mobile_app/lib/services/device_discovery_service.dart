import 'dart:async';

import 'package:flutter/foundation.dart'; // Import for debugPrint
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton that discovers nearby BLE peripherals and exposes their
/// [ScanResult]s as a broadcast stream.
class DeviceDiscoveryService {
  // ─── Singleton boilerplate ──────────────────────────────────────────
  DeviceDiscoveryService._internal();
  static final DeviceDiscoveryService _instance =
      DeviceDiscoveryService._internal();
  factory DeviceDiscoveryService() => _instance;

  // ─── Auto-reconnect properties ────────────────────────────────────────
  String? _autoConnectDeviceId;
  bool _autoReconnectEnabled = false;
  
  /// Whether auto-reconnect is currently enabled
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  
  /// The device ID that should be auto-connected when discovered
  String? get autoConnectDeviceId => _autoConnectDeviceId;
  
  /// Callback to invoke when auto-connect succeeds
  void Function(BluetoothDevice device)? _onDeviceConnected;

  // ─── Public API ─────────────────────────────────────────────────────

  /// Stream of scan events.  Each event is a [ScanResult] containing
  /// the advertisement data and RSSI of a single device.
  Stream<ScanResult> get results => _controller.stream;

  /// Configure auto-reconnect for a specific device
  Future<void> enableAutoReconnect(
    String deviceId, 
    void Function(BluetoothDevice device)? onConnected
  ) async {
    _autoConnectDeviceId = deviceId;
    _autoReconnectEnabled = true;
    _onDeviceConnected = onConnected;
    
    // Save preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('autoConnectDeviceId', deviceId);
    await prefs.setBool('autoReconnectEnabled', true);
    
    debugPrint('>>> Auto-reconnect enabled for device: $deviceId');
    
    // Ensure scanning is active
    if (!_scanning) {
      await start();
    }
  }
  
  /// Disable auto-reconnect functionality
  Future<void> disableAutoReconnect() async {
    _autoReconnectEnabled = false;
    
    // Update preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoReconnectEnabled', false);
    
    debugPrint('>>> Auto-reconnect disabled');
  }
  
  /// Initialize auto-reconnect from saved preferences
  Future<void> initAutoReconnect(
    void Function(BluetoothDevice device)? onConnected
  ) async {
    final prefs = await SharedPreferences.getInstance();
    _autoReconnectEnabled = prefs.getBool('autoReconnectEnabled') ?? false;
    _autoConnectDeviceId = prefs.getString('autoConnectDeviceId');
    _onDeviceConnected = onConnected;
    
    debugPrint('>>> Auto-reconnect initialized: enabled=$_autoReconnectEnabled, deviceId=$_autoConnectDeviceId');
    
    if (_autoReconnectEnabled && _autoConnectDeviceId != null) {
      // Start scanning to find the device
      await start();
    }
  }

  /// Begins continuous BLE scanning until [stop] is called.
  Future<void> start() async {
    debugPrint('>>> DeviceDiscoveryService: start() called. _scanning=$_scanning'); // Add log
    if (_scanning) return;
    _scanning = true;
    // Forward flutter_blue_plus scan results into our controller.
    _subscription = FlutterBluePlus.scanResults.listen(
      (batch) {
        for (final result in batch) {
          _controller.add(result);
          
          // Check for auto-connect device match
          if (_autoReconnectEnabled && 
              _autoConnectDeviceId != null && 
              result.device.remoteId.str == _autoConnectDeviceId) {
            debugPrint('>>> Found auto-connect device: ${result.device.remoteId.str}');
            _attemptAutoConnect(result.device);
          }
        }
      },
      onError: (e) { // Add error logging
        debugPrint('!!! DeviceDiscoveryService: ScanResults stream error: $e');
        _controller.addError(e);
      },
    );
    debugPrint('>>> DeviceDiscoveryService: Calling FlutterBluePlus.startScan()'); // Add log
    await FlutterBluePlus.startScan(
      // Change scan mode here if power optimisation required.
      // Use a long timeout instead of zero to rule out immediate stop issues.
      timeout: const Duration(minutes: 1), // e.g., 1 minute timeout
    );
  }

  /// Stops scanning and closes internal subscription.
  Future<void> stop() async {
    debugPrint('>>> DeviceDiscoveryService: stop() called. _scanning=$_scanning'); // Add log
    if (!_scanning) return;
    debugPrint('>>> DeviceDiscoveryService: Calling FlutterBluePlus.stopScan()'); // Add log
    await FlutterBluePlus.stopScan();
    await _subscription?.cancel();
    _subscription = null;
    _scanning = false;
  }

  /// Attempt to connect to the auto-connect device
  Future<void> _attemptAutoConnect(BluetoothDevice device) async {
    if (!_autoReconnectEnabled) return;
    
    try {
      // Pause scanning during connection attempt
      await stop();
      
      debugPrint('>>> Attempting auto-connect to: ${device.remoteId.str}');
      await device.connect(autoConnect: true);
      debugPrint('>>> Auto-connected successfully to: ${device.remoteId.str}');
      
      // Notify callback
      if (_onDeviceConnected != null) {
        _onDeviceConnected!(device);
      }
    } catch (e) {
      debugPrint('!!! Auto-connect failed: $e');
      
      // Resume scanning after failure (with delay to avoid rapid retries)
      if (_autoReconnectEnabled) {
        await Future.delayed(const Duration(seconds: 5));
        await start();
      }
    }
  }

  // ─── Internals ──────────────────────────────────────────────────────
  final StreamController<ScanResult> _controller =
      StreamController.broadcast();
  StreamSubscription<List<ScanResult>>? _subscription;
  bool _scanning = false;
}
