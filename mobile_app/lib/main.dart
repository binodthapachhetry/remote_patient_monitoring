import 'package:flutter/material.dart';
import 'ble_permission_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'screens/scanner_page.dart';               // enables in-app BLE scan UI

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // --- Load Auto-Connect Device ID ---
  final prefs = await SharedPreferences.getInstance();
  final String? autoConnectDeviceId = prefs.getString('autoConnectDeviceId');
  debugPrint('>>> Auto-Connect Device ID loaded: $autoConnectDeviceId');
  runApp(const MobileHealthApp());
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
      home: const BlePermissionGate(
        child: ScannerPage(participantId: 'demoUser'),
      ),
    );
  }
}
