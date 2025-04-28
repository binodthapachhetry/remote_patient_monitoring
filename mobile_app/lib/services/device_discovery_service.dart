import 'dart:async';

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
    if (_scanning) return;
    _scanning = true;
    // Forward flutter_blue_plus scan results into our controller.
    _subscription = FlutterBluePlus.scanResults.listen(
      (batch) => batch.forEach(_controller.add), // flatten List<ScanResult>
      onError: _controller.addError,
    );
    await FlutterBluePlus.startScan(
      // Duplicates can be useful for RSSI updates; reduce spam if needed.
      withDevices: const [],
      // Change scan mode here if power optimisation required.
      timeout: const Duration(seconds: 0), // 0 == no timeout
    );
  }

  /// Stops scanning and closes internal subscription.
  Future<void> stop() async {
    if (!_scanning) return;
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
