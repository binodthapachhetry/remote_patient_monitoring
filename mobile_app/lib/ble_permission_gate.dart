import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Blocks UI until required BLE (and other platform-specific) permissions
/// are granted. Reusable for any screen needing Bluetooth access.
/// 
/// Handles permission differences between Android <12 and ≥12, as well
/// as battery optimization requests for improved background operation.
class BlePermissionGate extends StatefulWidget {
  final Widget child;
  final bool checkBatteryOptimization;
  
  const BlePermissionGate({
    required this.child, 
    this.checkBatteryOptimization = true,
    super.key
  });

  @override
  State<BlePermissionGate> createState() => _BlePermissionGateState();
}

class _BlePermissionGateState extends State<BlePermissionGate> {
  bool _permissionsGranted = false;
  bool _requestingBatteryOptimization = false;
  bool _permanentlyDenied = false;
  String _pendingPermission = '';
  
  @override
  void initState() {
    debugPrint('BlePermissionGate initState'); // Add logging
    super.initState();
    _checkPermissions();
  }

  /// Check all required permissions first
  Future<void> _checkPermissions() async {
    debugPrint('BlePermissionGate checking existing permissions...'); // Add logging
    if (Platform.isAndroid) {
      await _checkAndroidPermissions();
    } else if (Platform.isIOS) {
      await _checkIosPermissions();
    } else {
      // Default to true on unsupported platforms
      setState(() => _permissionsGranted = true);
    }
  }
  
  /// Check permissions specific to Android
  Future<void> _checkAndroidPermissions() async {
    final bluetoothScan = await Permission.bluetoothScan.status;
    final bluetoothConnect = await Permission.bluetoothConnect.status;
    
    // Android <12 needs location for BLE scanning
    final sdkVersion = int.tryParse(Platform.version.split(' ').first) ?? 0;
    final needsLocation = sdkVersion < 31; // Android 12 is API 31
    
    final locationStatus = needsLocation 
        ? await Permission.locationWhenInUse.status 
        : PermissionStatus.granted;
    
    final allGranted = bluetoothScan.isGranted && 
                        bluetoothConnect.isGranted && 
                        locationStatus.isGranted;
                        
    debugPrint('BlePermissionGate permissions status: '
              'scan=${bluetoothScan.name}, '
              'connect=${bluetoothConnect.name}, '
              'location=${locationStatus.name}, '
              'needsLocation=$needsLocation');
    
    if (allGranted) {
      // All permissions granted, check battery optimization if enabled
      if (widget.checkBatteryOptimization) {
        await _checkBatteryOptimization();
      } else {
        if (mounted) setState(() => _permissionsGranted = true);
      }
    } else {
      // Not all permissions granted, request them
      await _requestPermissions();
    }
  }

  /// Check for iOS-specific permissions
  Future<void> _checkIosPermissions() async {
    // iOS 13+ uses the Bluetooth permission
    final bluetoothStatus = await Permission.bluetooth.status;
    
    if (bluetoothStatus.isGranted) {
      if (mounted) setState(() => _permissionsGranted = true);
    } else {
      await _requestPermissions();
    }
  }
  
  /// Request all required permissions for the current platform
  Future<void> _requestPermissions() async {
    debugPrint('BlePermissionGate requesting permissions...'); // Add logging
    
    // Check for any permanently denied permissions
    if (await _checkForPermanentlyDeniedPermissions()) {
      return;
    }
    
    final permissions = <Permission>[];
    
    // Always need these on Android
    if (Platform.isAndroid) {
      permissions.add(Permission.bluetoothScan);
      permissions.add(Permission.bluetoothConnect);
      
      // Android <12 needs location for BLE
      final sdkVersion = int.tryParse(Platform.version.split(' ').first) ?? 0;
      if (sdkVersion < 31) { // Android 12 is API 31
        permissions.add(Permission.locationWhenInUse);
      }
    } else if (Platform.isIOS) {
      permissions.add(Permission.bluetooth);
    }
    
    if (permissions.isEmpty) {
      // No permissions needed for this platform
      if (mounted) setState(() => _permissionsGranted = true);
      return;
    }
    
    // Request each permission individually for better user experience
    bool allGranted = true;
    for (final permission in permissions) {
      setState(() => _pendingPermission = _getPermissionName(permission));
      final status = await permission.request();
      if (!status.isGranted) {
        allGranted = false;
        if (status.isPermanentlyDenied) {
          setState(() {
            _permanentlyDenied = true;
            _pendingPermission = _getPermissionName(permission);
          });
          return;
        }
      }
    }
    
    if (allGranted) {
      // All permissions granted, check battery optimization if enabled
      if (widget.checkBatteryOptimization && Platform.isAndroid) {
        await _checkBatteryOptimization();
      } else {
        if (mounted) setState(() => _permissionsGranted = true);
      }
    } else {
      if (mounted) setState(() => _permissionsGranted = false);
    }
  }
  
  /// Check if any permissions are permanently denied
  Future<bool> _checkForPermanentlyDeniedPermissions() async {
    if (Platform.isAndroid) {
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      final locationStatus = await Permission.locationWhenInUse.status;
      
      if (scanStatus.isPermanentlyDenied) {
        setState(() {
          _permanentlyDenied = true;
          _pendingPermission = 'Bluetooth scanning';
        });
        return true;
      }
      
      if (connectStatus.isPermanentlyDenied) {
        setState(() {
          _permanentlyDenied = true;
          _pendingPermission = 'Bluetooth connection';
        });
        return true;
      }
      
      // Android <12 needs location for BLE
      final sdkVersion = int.tryParse(Platform.version.split(' ').first) ?? 0;
      if (sdkVersion < 31 && locationStatus.isPermanentlyDenied) {
        setState(() {
          _permanentlyDenied = true;
          _pendingPermission = 'Location';
        });
        return true;
      }
    } else if (Platform.isIOS) {
      final bluetoothStatus = await Permission.bluetooth.status;
      if (bluetoothStatus.isPermanentlyDenied) {
        setState(() {
          _permanentlyDenied = true;
          _pendingPermission = 'Bluetooth';
        });
        return true;
      }
    }
    
    return false;
  }
  
  /// Check and request battery optimization if needed
  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _permissionsGranted = true);
      return;
    }
    
    final isBatteryOptimizationDisabled = 
        await Permission.ignoreBatteryOptimizations.status.isGranted;
    
    if (isBatteryOptimizationDisabled) {
      // Battery optimization already disabled, we're good to go
      if (mounted) setState(() => _permissionsGranted = true);
    } else {
      // Show battery optimization prompt
      setState(() => _requestingBatteryOptimization = true);
    }
  }
  
  /// Request battery optimization exemption
  Future<void> _requestBatteryOptimization() async {
    debugPrint('Requesting battery optimization exemption...');
    setState(() => _requestingBatteryOptimization = false);
    
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (mounted) {
      setState(() => _permissionsGranted = true);
    }
    
    // Note: We proceed even if user denies battery optimization
    // This is an optional but recommended permission
    debugPrint('Battery optimization exemption status: ${status.name}');
  }
  
  /// Get a user-friendly name for a permission
  String _getPermissionName(Permission permission) {
    switch (permission) {
      case Permission.bluetoothScan:
        return 'Bluetooth scanning';
      case Permission.bluetoothConnect:
        return 'Bluetooth connection';
      case Permission.locationWhenInUse:
        return 'Location';
      case Permission.bluetooth:
        return 'Bluetooth';
      default:
        return permission.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('BlePermissionGate build, granted: $_permissionsGranted'); // Add logging
    
    if (_permissionsGranted) {
      return widget.child;
    }
    
    if (_requestingBatteryOptimization) {
      return _buildBatteryOptimizationRequest();
    }
    
    if (_permanentlyDenied) {
      return _buildOpenSettingsScreen();
    }
    
    return _buildPermissionRequest();
  }
  
  /// Build the basic permission request screen
  Widget _buildPermissionRequest() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions Required'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bluetooth_searching,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 24),
              Text(
                _pendingPermission.isNotEmpty
                    ? 'We need $_pendingPermission permission'
                    : 'We need permission to use Bluetooth',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'This app needs Bluetooth access to connect to your health devices. '
                'This allows the app to collect measurements automatically, even when the app is not open.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _requestPermissions,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('Grant Permissions'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build the battery optimization request screen
  Widget _buildBatteryOptimizationRequest() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimize Battery Use'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.battery_full,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 24),
              Text(
                'Disable Battery Optimization',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'For reliable background operation, this app needs to be excluded from '
                'battery optimization. This will allow it to monitor your health devices '
                'even when your phone is inactive.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      // Skip battery optimization and continue
                      setState(() {
                        _requestingBatteryOptimization = false;
                        _permissionsGranted = true;
                      });
                    },
                    child: const Text('Skip'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _requestBatteryOptimization,
                    child: const Text('Disable Optimization'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build screen when permissions are permanently denied
  Widget _buildOpenSettingsScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions Required'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.settings,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 24),
              Text(
                '$_pendingPermission Permission Denied',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'The $_pendingPermission permission is required for this app to function. '
                'Please open Settings and grant this permission manually.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('BlePermissionGate dispose'); // Add logging
    super.dispose();
  }
}
