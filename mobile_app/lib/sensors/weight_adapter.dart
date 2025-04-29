import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Import for debugPrint

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/physio_sample.dart';
import 'sensor_adapter.dart';

/// Adapter for Bluetooth SIG Weight-Scale Service (0x181D).
/// Parses Weight-Measurement characteristic (0x2A9D) and emits kilograms.
class WeightAdapter extends SensorAdapter {
  WeightAdapter({
    required super.participantId,
    required this.deviceId,
  });

  final String deviceId;

  // ─── Public Stream ────────────────────────────────────────────────
  final _controller = StreamController<PhysioSample>.broadcast();
  @override
  Stream<PhysioSample> get samples => _controller.stream;

  // ─── BLE UUIDs ────────────────────────────────────────────────────
  static final Guid _serviceUuid =
      Guid('4143f6b0-5300-4900-4700-414943415245'); // Try the OTHER proprietary service UUID
  static final Guid _charUuid =
      Guid('4143f6b2-5300-4900-4700-414943415245'); // Try characteristic ...f6b3

  late BluetoothDevice _device;
  StreamSubscription<List<int>>? _sub;

  @override
  Future<void> bind(BluetoothDevice device) async {
    _device = device;
    await _device.connect(autoConnect: false);

    // --- Add Logging ---
    debugPrint('>>> WeightAdapter: Discovering services for ${device.remoteId}');
    final services = await _device.discoverServices();
    for (var service in services) {
      debugPrint('>>> Found service: ${service.serviceUuid}');
    }
    // --- End Logging ---

    // Discover Weight-Scale service & characteristic
    final service = services.firstWhere((s) => s.serviceUuid == _serviceUuid, orElse: () => throw Exception('Weight service not found'));

    // --- Add Logging ---
    debugPrint('>>> WeightAdapter: Looking for characteristic $_charUuid in service $_serviceUuid');
    for (var char in service.characteristics) {
      debugPrint('>>> Found characteristic: ${char.characteristicUuid} in service ${service.serviceUuid}');
    }
    // --- End Logging ---
    final char = service.characteristics.firstWhere((c) => c.characteristicUuid == _charUuid, orElse: () => throw Exception('Weight characteristic not found'));

    await char.setNotifyValue(true);
    _sub = char.onValueReceived.listen(_onData, onError: _controller.addError);
  }

  void _onData(List<int> payload) {
    // --- Add Logging ---
    final hexPayload = payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint('>>> Raw Payload Received: [$hexPayload] (${payload.length} bytes)');
    // --- End Logging ---
    final data = Uint8List.fromList(payload);
    // Ensure payload is long enough for our assumed format (at least 4 bytes for bytes 2 & 3)
    if (data.length < 4) {
      debugPrint('>>> Payload too short: ${data.length} bytes');
      return;
    }

    // --- New Parsing Logic Hypothesis ---
    // Assume bytes 2 & 3 (little-endian) represent weight in kg * 100
    // Example: [ac 02 fe 1c ff 00 cc e5] -> 0x1cfe = 7422 -> 74.22 kg
    final rawValue = (data[3] << 8) | data[2]; // Bytes 3 and 2 for uint16_le
    final weightKg = rawValue / 100.0;
    debugPrint('>>> Parsed Weight: $weightKg kg (Raw Value: $rawValue)'); // Add detailed log
    // --- End New Parsing Logic ---

    _controller.add(
      PhysioSample(
        participantId: participantId,
        deviceId: deviceId,
        metric: PhysioMetric.weightKg,
        value: weightKg,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    if (_device.isConnected) await _device.disconnect();
    await _controller.close();
  }
}
