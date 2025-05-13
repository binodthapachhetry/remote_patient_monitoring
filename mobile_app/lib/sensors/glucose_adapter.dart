import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/physio_sample.dart';
import 'sensor_adapter.dart';

/// Adapter for BLE glucose monitors that support the Glucose Service (0x1808)
/// or compatible custom services.
class GlucoseAdapter extends SensorAdapter {
  // Standard Glucose Measurement characteristic
  static const String GLUCOSE_MEASUREMENT_CHARACTERISTIC = '2A18';
  
  // Control characteristic for triggering stored readings
  static const String RECORD_ACCESS_CONTROL_POINT = '2A52';
  
  // Streams
  final _measurementStreamController = StreamController<PhysioSample>.broadcast();
  Stream<PhysioSample> get measurements => _measurementStreamController.stream;
  
  BluetoothDevice? _device;
  
  GlucoseAdapter({
    required String participantId,
    required String deviceId,
  }) : super(participantId: participantId, deviceId: deviceId);
  
  @override
  Stream<PhysioSample> get samples => measurements;
  
  @override
  Future<void> bind(BluetoothDevice device) async {
    try {
      _device = device;
      debugPrint('>>> Binding glucose adapter to device ${device.remoteId.str}');
      
      // Discover services
      final services = await device.discoverServices();
      debugPrint('>>> Discovered ${services.length} services for glucose device');
      
      // Find the Glucose Service - both standard (0x1808) and custom implementations
      final glucoseServices = services.where((s) =>
        s.uuid.toString().toUpperCase().contains('1808') || // Standard Glucose service
        s.uuid.toString().toUpperCase().contains('F8083532')); // Custom glucose service
        
      if (glucoseServices.isEmpty) {
        debugPrint('!!! No glucose service found on the device');
        return;
      }
      
      // For each potential glucose service, set up notifications
      for (final service in glucoseServices) {
        debugPrint('>>> Processing glucose service: ${service.uuid.toString().toUpperCase()}');
        
        // Look for glucose measurement characteristic
        final glucoseCharacteristics = service.characteristics.where((c) =>
          c.uuid.toString().toUpperCase().contains(GLUCOSE_MEASUREMENT_CHARACTERISTIC));
          
        if (glucoseCharacteristics.isNotEmpty) {
          for (final characteristic in glucoseCharacteristics) {
            // Set up notifications for glucose readings
            debugPrint('>>> Setting up notifications for glucose measurements');
            
            // Enable notifications
            await characteristic.setNotifyValue(true);
            
            // Subscribe to notifications
            characteristic.onValueChanged.listen((value) {
              _handleGlucoseReading(value);
            });
            
            debugPrint('>>> Glucose notifications set up successfully');
          }
        } else {
          debugPrint('!!! No glucose measurement characteristic found in service');
        }
      }
      
      debugPrint('>>> Glucose adapter bound successfully');
    } catch (e) {
      debugPrint('!!! Error binding glucose adapter: $e');
    }
  }
  
  /// Request download of stored readings from the device
  @override
  Future<void> requestDataDownload() async {
    try {
      if (_device == null) {
        debugPrint('!!! Cannot request data download: device not bound');
        return;
      }
      
      final services = await _device!.discoverServices();
      
      // Find glucose services that might contain the record access control point
      for (final service in services) {
        if (service.uuid.toString().toUpperCase().contains('1808')) {
          // Look for Record Access Control Point characteristic
          final controlChars = service.characteristics.where((c) =>
            c.uuid.toString().toUpperCase().contains(RECORD_ACCESS_CONTROL_POINT));
            
          if (controlChars.isNotEmpty) {
            debugPrint('>>> Found Record Access Control Point characteristic');
            final controlChar = controlChars.first;
            
            // Send command to report all stored records (0x01 = Report Stored Records, 0x01 = All records)
            final command = [0x01, 0x01];
            await controlChar.write(command, withoutResponse: false);
            debugPrint('>>> Sent command to retrieve all stored glucose readings');
          }
        }
      }
    } catch (e) {
      debugPrint('!!! Error requesting glucose data download: $e');
    }
  }
  
  /// Handle glucose reading data from the device
  void _handleGlucoseReading(List<int> value) {
    try {
      // Basic glucose reading parser - this is a simplified implementation
      // Real glucose monitors may use different data formats
      
      // Skip the flags byte and sequence number
      if (value.length < 3) {
        debugPrint('!!! Glucose reading data too short');
        return;
      }
      
      // Simple parsing for demo purposes
      // Real implementations would need to parse according to the Bluetooth GATT specification
      // for the Glucose Measurement characteristic
      
      // For this example, assume a simplified format where:
      // - Byte 3-4: Glucose concentration in mg/dL as a uint16
      int glucoseValue;
      if (value.length >= 5) {
        glucoseValue = value[3] + (value[4] << 8);
      } else {
        // Fallback if data format is unexpected
        glucoseValue = value[2]; // Just use whatever byte we have as an example
      }
      
      debugPrint('>>> Parsed glucose value: $glucoseValue mg/dL');
      
      // Create and emit a new PhysioSample
      final sample = PhysioSample(
        participantId: participantId,
        deviceId: deviceId,
        metric: PhysioMetric.glucoseMgDl,
        value: glucoseValue,
        timestamp: DateTime.now(),
        metadata: {
          'rawData': value.toString(),
          'dataSource': 'ble_glucose_monitor'
        },
      );
      
      _measurementStreamController.add(sample);
      debugPrint('>>> Emitted glucose reading: $glucoseValue mg/dL');
    } catch (e) {
      debugPrint('!!! Error parsing glucose reading: $e');
    }
  }
  
  @override
  Future<void> dispose() async {
    await _measurementStreamController.close();
    _device = null;
    debugPrint('>>> Glucose adapter disposed');
  }
}
