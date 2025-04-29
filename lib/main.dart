// default route shows scanner during manual testing
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Add this import
// TODO: This import path seems incorrect based on the file tree provided earlier.
// Assuming ble_permission_gate.dart is directly under lib/
import 'ble_permission_gate.dart';
// If it's under mobile_app/lib/, the import should be:
// import 'package:mobile_health_app/ble_permission_gate.dart'; // Adjust package name if needed
import 'screens/scanner_page.dart';

// Make main async to allow awaiting Firebase initialization
Future<void> main() async {
  // Ensure Flutter bindings are initialized before calling native code
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase using the google-services.json config
  await Firebase.initializeApp();
  runApp(const MobileHealthApp());
}

class MobileHealthApp extends StatelessWidget {
  const MobileHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Health MVP',
      // Use Material 3 theme for modern look
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      // Wrap the initial screen with the permission gate
      home: const BlePermissionGate(
        child: ScannerPage(participantId: 'demoUser'),
      ),
    );
  }
}
