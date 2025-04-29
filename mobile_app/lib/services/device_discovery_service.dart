import 'dart:async';

import 'package:flutter/foundation.dart'; // Import for debugPrint
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Singleton that discovers nearby BLE peripherals and exposes their
/// [ScanResult]s as a broadcast stream.
class DeviceDiscoveryService {
  // ─── Singleton boilerplate ──────────────────────────────────────────
  DeviceDiscoveryService._internal();
  static final DeviceDiscoveryService _instance =
      DeviceDiscoveryService._internal();
  factory DeviceDiscoveryService() => _instance;

  // ─── Public API ─────────────────────────────────────────────────────

  /// Stream of scan events.  Each event is a [ScanResult] containing
  /// the advertisement data and RSSI of a single device.
  Stream<ScanResult> get results => _controller.stream;

  /// Begins continuous BLE scanning until [stop] is called.
  Future<void> start() async {
    debugPrint('>>> DeviceDiscoveryService: start() called. _scanning=$_scanning'); // Add log
    if (_scanning) return;
    _scanning = true;
    // Forward flutter_blue_plus scan results into our controller.
    _subscription = FlutterBluePlus.scanResults.listen(
      (batch) => batch.forEach(_controller.add), // flatten List<ScanResult>
      onError: (e) { // Add error logging
        debugPrint('!!! DeviceDiscoveryService: ScanResults stream error: $e');
        _controller.addError(e);
      },
    );
    debugPrint('>>> DeviceDiscoveryService: Calling FlutterBluePlus.startScan()'); // Add log
    await FlutterBluePlus.startScan(
      // Change scan mode here if power optimisation required.
      // Use a long timeout instead of zero to rule out immediate stop issues.
      timeout: const Duration(minutes: 1), // e.g., 1 minute timeout
    );
  }

  /// Stops scanning and closes internal subscription.
  Future<void> stop() async {
    debugPrint('>>> DeviceDiscoveryService: stop() called. _scanning=$_scanning'); // Add log
    if (!_scanning) return;
    debugPrint('>>> DeviceDiscoveryService: Calling FlutterBluePlus.stopScan()'); // Add log
    await FlutterBluePlus.stopScan();
    await _subscription?.cancel();
    _subscription = null;
    _scanning = false;
  }

  // ─── Internals ──────────────────────────────────────────────────────
  final StreamController<ScanResult> _controller =
      StreamController.broadcast();
  StreamSubscription<List<ScanResult>>? _subscription;
  bool _scanning = false;
}
