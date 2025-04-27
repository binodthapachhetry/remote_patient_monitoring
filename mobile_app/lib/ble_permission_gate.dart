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
    super.initState();
    _request();
  }

  Future<void> _request() async {
    final needed = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // Android <12 BLE requirement
    ];
    final statuses = await needed.request();
    final ok = statuses.values.every((s) => s.isGranted);
    if (!mounted) return;
    setState(() => _granted = ok);
  }

  @override
  Widget build(BuildContext context) {
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
}
