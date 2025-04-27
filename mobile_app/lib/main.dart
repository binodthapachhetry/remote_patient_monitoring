import 'package:flutter/material.dart';
import 'ble_permission_gate.dart';

void main() {
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
      home: BlePermissionGate(
        child: const Scaffold(
          body: Center(child: Text('Mobile Health MVP')),
        ),
      ),
    );
  }
}
