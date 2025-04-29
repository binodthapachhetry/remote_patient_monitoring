// default route shows scanner during manual testing
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Comment out
import 'package:remote_patient_monitoring/ble_permission_gate.dart'; // Adjust package name if needed
import 'screens/scanner_page.dart'; // Comment out

// Make main async to allow awaiting Firebase initialization
Future<void> main() async {
  // Ensure Flutter bindings are initialized before calling native code
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase using the google-services.json config
  // await Firebase.initializeApp(); // Comment out
  runApp(const MobileHealthApp());
}

class MobileHealthApp extends StatelessWidget {
  const MobileHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Health MVP Minimal',
      // Use Material 3 theme for modern look
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      // Replace home with a very simple widget
      home: const Scaffold(
        body: Center(
          child: Text('Minimal App Running!'),
        ),
      ),
      home: const BlePermissionGate( // Comment out
        child: ScannerPage(participantId: 'demoUser'),
      ),
    );
  }
}
