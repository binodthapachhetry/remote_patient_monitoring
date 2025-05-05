import 'package:flutter/material.dart';
import 'ble_permission_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'screens/scanner_page.dart';               // enables in-app BLE scan UI
import 'services/device_discovery_service.dart';   // for auto-reconnect
import 'services/background_service_manager.dart'; // for background service
import 'services/user_manager.dart';               // for participant ID management
import 'screens/login_screen.dart';                // login UI
import 'sensors/weight_adapter.dart';              // for weight scale communication

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize user manager
  await UserManager().initialize();
  
  // Initialize background service and auto-reconnect
  await _initializeBackgroundServices();
  
  runApp(const MobileHealthApp());
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
  
  // Initialize auto-reconnect if enabled
  if (autoConnectDeviceId != null) {
    final discovery = DeviceDiscoveryService();
    final userManager = UserManager();
    await discovery.initAutoReconnect((device) {
      // Handle successful connection
      debugPrint('>>> Auto-reconnect successful to ${device.remoteId.str}');
      
      // Create weight adapter and start data collection
      final adapter = WeightAdapter(
        participantId: userManager.participantId ?? 'guest', // Use authenticated user ID or fallback
        deviceId: device.remoteId.str,
      );
      
      adapter.bind(device).then((_) {
        debugPrint('>>> Weight adapter bound after app startup auto-reconnect');
        
        // Listen for weight samples
        adapter.samples.listen((s) => 
          debugPrint('Weight measurement received: ${s.value} kg'));
      }).catchError((e) {
        debugPrint('!!! Error binding to auto-reconnected device: $e');
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
