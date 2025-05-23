import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'ble_permission_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'screens/scanner_page.dart';               // enables in-app BLE scan UI
import 'services/device_discovery_service.dart';   // for auto-reconnect
import 'services/background_service_manager.dart'; // for background service
import 'services/user_manager.dart';               // for participant ID management
import 'screens/login_screen.dart';                // login UI
import 'sensors/weight_adapter.dart';              // for weight scale communication
import 'sensors/blood_pressure_adapter.dart';      // for blood pressure monitor communication
import 'models/physio_sample.dart';                // for PhysioMetric enum
import 'package:permission_handler/permission_handler.dart'; // For battery optimization
import 'utils/device_detector.dart';               // for device type detection

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize user manager
  await UserManager().initialize();
  
  // Initialize background service and auto-reconnect
  await _initializeBackgroundServices();
  
  // Request battery optimization exemption on Android
  _requestBatteryOptimization();
  
  runApp(const MobileHealthApp());
}

/// Request battery optimization exemption on Android
Future<void> _requestBatteryOptimization() async {
  if (Platform.isAndroid) {
    // Check if we should show the battery optimization dialog
    final prefs = await SharedPreferences.getInstance();
    final hasRequestedBatteryOpt = prefs.getBool('hasRequestedBatteryOpt') ?? false;
    
    if (!hasRequestedBatteryOpt) {
      // Mark as requested to avoid showing repeatedly
      await prefs.setBool('hasRequestedBatteryOpt', true);
      
      // Check current battery optimization status
      final isIgnoringBatteryOptimizations = 
          await Permission.ignoreBatteryOptimizations.status.isGranted;
      
      if (!isIgnoringBatteryOptimizations) {
        debugPrint('>>> Requesting battery optimization exemption for better BLE performance');
        // Request battery optimization exemption
        await Permission.ignoreBatteryOptimizations.request();
      }
    }
  }
}

/// Gate that shows either login screen or main app based on authentication state
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final userManager = UserManager();
    
    return StreamBuilder<bool>(
      stream: userManager.authStateChanges,
      initialData: userManager.isAuthenticated,
      builder: (context, snapshot) {
        final isAuthenticated = snapshot.data ?? false;
        
        if (isAuthenticated) {
          return BlePermissionGate(
            child: ScannerPage(participantId: userManager.participantId!),
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

/// Initialize background services and auto-reconnect functionality
Future<void> _initializeBackgroundServices() async {
  // Get saved preferences
  final prefs = await SharedPreferences.getInstance();
  final autoConnectDeviceId = prefs.getString('autoConnectDeviceId');
  debugPrint('>>> Auto-Connect Device ID loaded: $autoConnectDeviceId');
  
  // Initialize background service manager
  final serviceManager = BackgroundServiceManager();
  await serviceManager.initFromPreferences();
  
  // Ensure background service is active for BLE operations even when locked
  if (await serviceManager.isStartedOnBoot()) {
    debugPrint('>>> Auto-starting background service for BLE operations');
    await serviceManager.startService();
  }
  
  // Initialize auto-reconnect if enabled
  if (autoConnectDeviceId != null) {
    final discovery = DeviceDiscoveryService();
    final userManager = UserManager();
    await discovery.initAutoReconnect((device) {
      // Handle successful connection
      debugPrint('>>> Auto-reconnect successful to ${device.remoteId.str}');
      
      // Use the DeviceDetector utility to determine device type and create adapter
      DeviceDetector.createAdapterForDevice(
        device: device,
        participantId: userManager.participantId ?? 'guest',
      ).then((adapter) {
        if (adapter != null) {
          debugPrint('>>> Device adapter created for auto-reconnect: ${adapter.runtimeType}');
            
          // Listen for samples from the device based on type
          adapter.samples.listen((s) {
            if (s.metric == PhysioMetric.weightKg) {
              debugPrint('Weight measurement received: ${s.value} kg');
            } else if (s.metric == PhysioMetric.bloodPressureSystolicMmHg) {
              final diastolic = s.metadata?['diastolic'] ?? 0;
              debugPrint('Blood pressure measurement received: ${s.value}/${diastolic} mmHg');
            } else if (s.metric == PhysioMetric.heartRate) {
              debugPrint('Heart rate measurement received: ${s.value} bpm');
            }
          });
        } else {
          debugPrint('!!! No suitable adapter found for connected device');
        }
      }).catchError((e) {
        debugPrint('!!! Error setting up device adapter: $e');
      });
    });
  }
}

/// Root widget for the Mobile Health MVP.
class MobileHealthApp extends StatelessWidget {
  const MobileHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Health MVP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
