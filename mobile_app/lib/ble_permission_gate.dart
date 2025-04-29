import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Blocks UI until required BLE (and, on Android ≤11, location) permissions
/// are granted. Reusable for any screen needing Bluetooth access.
class BlePermissionGate extends StatefulWidget {
  final Widget child;
  const BlePermissionGate({required this.child, super.key});

  @override
  State<BlePermissionGate> createState() => _BlePermissionGateState();
}

class _BlePermissionGateState extends State<BlePermissionGate> {
  bool _granted = false;

  @override
  void initState() {
    debugPrint('BlePermissionGate initState'); // Add logging
    super.initState();
    _request();
  }

  Future<void> _request() async {
    debugPrint('BlePermissionGate requesting permissions...'); // Add logging
    final needed = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // Android <12 BLE requirement
    ];
    final statuses = await needed.request();
    final ok = statuses.values.every((s) => s.isGranted);
    debugPrint('BlePermissionGate permissions granted: $ok'); // Add logging
    if (!mounted) return;
    setState(() => _granted = ok);
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('BlePermissionGate build, granted: $_granted'); // Add logging
    if (_granted) return widget.child;
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: _request,
          child: const Text('Grant Bluetooth Permissions'),
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
