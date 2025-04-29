import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/device_discovery_service.dart';
import '../sensors/weight_adapter.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.participantId});
  final String participantId;
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _scanner = DeviceDiscoveryService();
  StreamSubscription? _sub;
  final List<ScanResult> _results = [];
  WeightAdapter? _adapter;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  // Start BLE scan and listen for results
  Future<void> _startScan() async {
    await _scanner.start();
    _sub = _scanner.results.listen((r) {
      if (mounted && !_results.any((e) => e.device.remoteId == r.device.remoteId)) {
        setState(() => _results.add(r));
      }
    });
  }

  // On tap, bind to the selected device and listen for weight samples
  Future<void> _onTap(ScanResult r) async {
    // Stop scanning before connecting
    await _scanner.stop(); // Consider moving stop() inside try if connection fails often

    try {
      _adapter = WeightAdapter(
        participantId: widget.participantId,
        deviceId: r.device.remoteId.str,
      );
      await _adapter!.bind(r.device); // Attempt to connect and bind

      // Listen for samples only after successful binding
      _adapter!.samples.listen((s) => debugPrint('Weight: ${s.value} kg'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          // Show device ID if name is empty for better identification
          SnackBar(content: Text('Connected to ${r.device.platformName.isNotEmpty ? r.device.platformName : r.device.remoteId.str}')),
        );
      }
    } catch (e) {
      // Log the error for debugging
      debugPrint('!!! Error connecting/binding to device: $e');
      if (mounted) {
        // Show user-friendly error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting: ${e.toString()}')),
        );
      }
      // Optionally, restart scanning if connection fails to allow retry
      // await _startScan();
    }
  }

  @override
  void dispose() {
    debugPrint('ScannerPage dispose called'); // Add logging here
    _sub?.cancel();
    _scanner.stop();
    _adapter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan for Weight-Scale')),
      body: ListView.separated(
        itemCount: _results.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final r = _results[i];
          return ListTile(
            title: Text(r.device.platformName.isEmpty
                ? r.advertisementData.advName
                : r.device.platformName),
            subtitle: Text(r.device.remoteId.str),
            trailing: Text('${r.rssi} dBm'),
            onTap: () => _onTap(r),
          );
        },
      ),
    );
  }
}
