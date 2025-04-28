import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/physio_sample.dart';

/// Base class every BLE sensor profile must extend.
///
/// Responsibilities:
/// 1.   `bind`   – connect to a [BluetoothDevice] and subscribe to its
///                measurement characteristic(s).
/// 2.   `samples`– broadcast parsed [PhysioSample]s.
/// 3.   `dispose`– clean up subscriptions and connections.
abstract class SensorAdapter {
  /// [participantId] is required and passed as a **named** parameter by all
  /// concrete adapters (e.g., `WeightAdapter`).
  SensorAdapter({required this.participantId});

  /// The participant associated with the samples produced by this adapter.
  final String participantId;

  /// Parsed measurement stream (broadcast).
  Stream<PhysioSample> get samples;

  /// Initiates connection and notifications.
  Future<void> bind(BluetoothDevice device);

  /// Stops notifications, closes streams, disconnects if desired.
  Future<void> dispose();
}
