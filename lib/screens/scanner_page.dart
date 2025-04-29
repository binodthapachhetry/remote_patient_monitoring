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
      // --- Add this line for debugging ---
      debugPrint('Scan Result Received: ID=${r.device.remoteId}, Name=${r.advertisementData.advName}, PlatformName=${r.device.platformName}, RSSI=${r.rssi}');
      if (mounted && !_results.any((e) => e.device.remoteId == r.device.remoteId)) {
        setState(() => _results.add(r));
      }
    });
  }

  // On tap, bind to the selected device and listen for weight samples
  Future<void> _onTap(ScanResult r) async {
    await _scanner.stop();
    _adapter = WeightAdapter(
      participantId: widget.participantId,
      deviceId: r.device.remoteId.str,
    );
    await _adapter!.bind(r.device);
    _adapter!.samples.listen((s) => debugPrint('Weight: ${s.value} kg'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${r.device.platformName}')),
      );
    }
  }

  @override
  void dispose() {
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
