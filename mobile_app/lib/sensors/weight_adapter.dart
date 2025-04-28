import 'dart:async';
import 'dart:typed_data';

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
      Guid('0000181d-0000-1000-8000-00805f9b34fb'); // Weight Scale
  static final Guid _charUuid =
      Guid('00002a9d-0000-1000-8000-00805f9b34fb'); // Weight Measurement

  late BluetoothDevice _device;
  StreamSubscription<List<int>>? _sub;

  @override
  Future<void> bind(BluetoothDevice device) async {
    _device = device;
    await _device.connect(autoConnect: false);

    // Discover Weight-Scale service & characteristic
    final service = (await _device.discoverServices())
        .firstWhere((s) => s.serviceUuid == _serviceUuid,
            orElse: () => throw Exception('Weight service not found'));

    final char = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == _charUuid,
        orElse: () => throw Exception('Weight characteristic not found'));

    await char.setNotifyValue(true);
    _sub = char.onValueReceived.listen(_onData, onError: _controller.addError);
  }

  void _onData(List<int> payload) {
    final data = Uint8List.fromList(payload);
    if (data.length < 3) return; // flags + 2-byte weight

    // Flags → bit-0 == unit (0 = kg, 1 = lb)
    final unitIsLb = (data[0] & 0x01) == 0x01;
    final rawWeight = (data[2] << 8) | data[1]; // uint16

    // Resolution: kg 0.005, lb 0.01
    final weightKg = unitIsLb
        ? rawWeight * 0.01 * 0.45359237
        : rawWeight * 0.005;

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
