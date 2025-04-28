// default route shows scanner during manual testing
import 'package:flutter/material.dart';
import 'screens/scanner_page.dart';

void main() {
  runApp(const MobileHealthApp());
}

class MobileHealthApp extends StatelessWidget {
  const MobileHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Health MVP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ScannerPage(participantId: 'demoUser'),
    );
  }
}
