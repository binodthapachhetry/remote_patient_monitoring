import 'package:flutter/material.dart';
import 'ble_permission_gate.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
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
        child: Scaffold(
          body: Center(child: Text('Mobile Health MVP')),
        ),
      ),
    );
  }
}
