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
  
  // Connection state tracking
  static bool _isConnecting = false;
  static int _retryCount = 0;
  Timer? _scanRestartTimer;
  Timer? _connectionStateTimer;
  BluetoothConnectionState _lastKnownState = BluetoothConnectionState.disconnected;
  BluetoothDevice? _currentDevice;
  
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
    
    // Reset retry counter when enabling auto-reconnect
    _resetRetryCounter();
    
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
    
    // Cancel any restart timers
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    
    // Cancel connection state monitoring
    _connectionStateTimer?.cancel();
    _connectionStateTimer = null;
    
    // Reset retry counter
    _resetRetryCounter();
    
    debugPrint('>>> Auto-reconnect disabled');
  }
  
  /// Reset the retry counter to start fresh
  void _resetRetryCounter() {
    _retryCount = 0;
    debugPrint('>>> Retry counter reset to 0');
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
    debugPrint('>>> DeviceDiscoveryService: start() called. _scanning=$_scanning, autoReconnect=$_autoReconnectEnabled, targetDevice=$_autoConnectDeviceId'); 
    if (_scanning) return;
    _scanning = true;
    
    // Reset retry counter on fresh start
    _resetRetryCounter();
    
    // Forward flutter_blue_plus scan results into our controller.
    _subscription = FlutterBluePlus.scanResults.listen(
      (batch) {
        debugPrint('>>> Scan batch received with ${batch.length} results');
        
        for (final result in batch) {
          _controller.add(result);
          
          // Add more detailed device logging
          debugPrint('>>> Found device: ${result.device.remoteId.str}, name: ${result.device.platformName}, adv name: ${result.advertisementData.advName}, RSSI: ${result.rssi}');
          
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
      timeout: const Duration(minutes: 1), // 1 minute timeout
    );
    
    // Set up a timer to restart scanning after the timeout 
    // This ensures we maintain continuous scanning capability
    _setupScanRestartTimer();
  }
  
  /// Set up a timer to restart scanning after timeout
  void _setupScanRestartTimer() {
    // Cancel any existing timer
    _scanRestartTimer?.cancel();
    
    // Create a new timer that fires faster (30 seconds instead of 65)
    _scanRestartTimer = Timer(const Duration(seconds: 30), () async {
      debugPrint('>>> Scan restart timer fired, restarting scan');
      if (_autoReconnectEnabled) {
        try {
          // Always stop the previous scan before starting a new one
          if (_scanning) await stop();
          // Start a new scan
          await start();
        } catch (e) {
          debugPrint('!!! Error restarting scan: $e');
          // Try again sooner if there was an error
          _scanRestartTimer = Timer(const Duration(seconds: 5), () async {
            if (_autoReconnectEnabled) {
              if (_scanning) await stop();
              await start();
            }
          });
        }
      }
    });
  }

  /// Stops scanning and closes internal subscription.
  Future<void> stop() async {
    debugPrint('>>> DeviceDiscoveryService: stop() called. _scanning=$_scanning'); 
    if (!_scanning) return;
    
    try {
      debugPrint('>>> DeviceDiscoveryService: Calling FlutterBluePlus.stopScan()');
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('!!! Error stopping scan: $e');
      // Continue with cleanup even if stopScan fails
    }
    
    try {
      await _subscription?.cancel();
    } catch (e) {
      debugPrint('!!! Error cancelling subscription: $e');
    }
    
    _subscription = null;
    _scanning = false;
    
    // Don't cancel the restart timer here to allow periodic scanning
    // The timer will restart scanning if auto-reconnect is still enabled
  }

  /// Attempt to connect to the auto-connect device
  Future<void> _attemptAutoConnect(BluetoothDevice device) async {
    if (!_autoReconnectEnabled) return;
    
    // Prevent multiple connection attempts at the same time
    if (_isConnecting) {
      debugPrint('>>> Auto-connect already in progress, skipping');
      return;
    }
    
    try {
      _isConnecting = true;
      _currentDevice = device;
      
      // Pause scanning during connection attempt
      await stop();
      
      debugPrint('>>> Attempting auto-connect to: ${device.remoteId.str}, name: ${device.platformName}');
      
      // First try to disconnect if there's an existing connection to clean state
      try {
        debugPrint('>>> Attempting to disconnect first to clean state');
        await device.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Ignore disconnect errors, device might already be disconnected
        debugPrint('>>> Disconnect before reconnect resulted in: $e');
      }
      
      // Use autoConnect: false to avoid MTU negotiation conflict
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      debugPrint('>>> Auto-connected successfully to: ${device.remoteId.str}');
      
      // Reset retry counter on successful connection
      _resetRetryCounter();
      
      // Set up connection state monitoring
      _monitorConnectionState(device);
      
      // Notify callback
      if (_onDeviceConnected != null) {
        debugPrint('>>> Calling onDeviceConnected callback');
        _onDeviceConnected!(device);
      }
    } catch (e) {
      debugPrint('!!! Auto-connect failed: $e');
      
      // Resume scanning after failure (with delay to avoid rapid retries)
      if (_autoReconnectEnabled) {
        // Use exponential backoff for reconnection attempts
        final delay = Duration(seconds: 5 * (1 << _retryCount));
        _retryCount = _retryCount < 5 ? _retryCount + 1 : 5; // Cap at ~160 seconds
        
        debugPrint('>>> Will retry auto-connect in ${delay.inSeconds} seconds');
        await Future.delayed(delay);
        await start();
      }
    } finally {
      _isConnecting = false;
    }
  }
  
  /// Monitor connection state of the device to detect disconnections
  void _monitorConnectionState(BluetoothDevice device) {
    // Cancel any existing monitoring
    _connectionStateTimer?.cancel();
    
    // Subscribe to connection state changes directly
    try {
      device.connectionState.listen((BluetoothConnectionState state) {
        debugPrint('>>> Connection state changed to: $state');
        
        // If state changed to disconnected and we were previously connected
        if (state == BluetoothConnectionState.disconnected && 
            _lastKnownState == BluetoothConnectionState.connected) {
          debugPrint('>>> Device disconnected, preparing for reconnection');
          
          // Update last known state
          _lastKnownState = BluetoothConnectionState.disconnected;
          
          // Restart scanning to find the device again
          if (!_scanning && _autoReconnectEnabled) {
            debugPrint('>>> Restarting scan after device disconnection detected by stream');
            start(); // Don't await as we're in a listener
          }
        }
        
        // Update last known state
        _lastKnownState = state;
      });
      
      debugPrint('>>> Started streaming connection state monitoring for ${device.remoteId.str}');
    } catch (e) {
      debugPrint('!!! Error setting up connection state listener: $e');
      // Set up a timer as backup monitoring method
      _setupBackupConnectionMonitoring(device);
    }
  }
  
  /// Set up a backup timer-based monitoring approach in case the stream-based approach fails
  void _setupBackupConnectionMonitoring(BluetoothDevice device) {
    // Set up a timer to periodically check connection state
    _connectionStateTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_autoReconnectEnabled) {
        timer.cancel();
        return;
      }
      
      try {
        // Get current connection state
        final state = await device.connectionState.first;
        debugPrint('>>> Backup monitor: connection state is $state');
        
        // If state changed to disconnected
        if (state == BluetoothConnectionState.disconnected && 
            _lastKnownState == BluetoothConnectionState.connected) {
          debugPrint('>>> Backup monitor: Device disconnected, preparing for reconnection');
          
          // Device disconnected, prepare for reconnection
          _lastKnownState = BluetoothConnectionState.disconnected;
          
          // Cancel this timer since we know device is disconnected
          timer.cancel();
          
          // Restart scanning to find the device again
          if (!_scanning && _autoReconnectEnabled) {
            debugPrint('>>> Backup monitor: Restarting scan after device disconnection');
            await start();
          }
        }
        
        // Update last known state
        _lastKnownState = state;
        
      } catch (e) {
        debugPrint('!!! Error checking connection state: $e');
        // Error likely means device is disconnected
        _lastKnownState = BluetoothConnectionState.disconnected;
        
        // Cancel timer and restart scan
        timer.cancel();
        if (!_scanning && _autoReconnectEnabled) {
          debugPrint('>>> Restarting scan after connection error');
          await start();
        }
      }
    });
  }

  // ─── Internals ──────────────────────────────────────────────────────
  final StreamController<ScanResult> _controller =
      StreamController.broadcast();
  StreamSubscription<List<ScanResult>>? _subscription;
  bool _scanning = false;
}
