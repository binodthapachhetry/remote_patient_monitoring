import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../sensors/weight_adapter.dart';
import '../sensors/blood_pressure_adapter.dart';
import '../sensors/sensor_adapter.dart';
import '../models/physio_sample.dart';

/// Utility for detecting device types and creating the right adapter
class DeviceDetector {
  /// Detect device type and create appropriate adapter
  static Future<SensorAdapter?> createAdapterForDevice({
    required BluetoothDevice device,
    required String participantId,
  }) async {
    try {
      debugPrint('>>> Detecting device type for ${device.remoteId.str}');
      
      // First check if the device is connected
      final connectionState = await device.connectionState.first;
      if (connectionState != BluetoothConnectionState.connected) {
        debugPrint('>>> Device not connected, connecting first...');
        await device.connect(autoConnect: false);
        // Allow a short delay for connection to stabilize
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('>>> Connected to device, now discovering services');
      }
      
      final services = await device.discoverServices();
      
      debugPrint('>>> Device services discovered: ${services.length} services');
      for (var service in services) {
        debugPrint('>>> Service UUID: ${service.uuid.toString().toUpperCase()}');
      }
      
      // Check for standard Weight Scale service (0x181D) or custom services used by eufy scale
      final hasWeightService = services.any((s) => 
        s.uuid.toString().toUpperCase().contains('181D') || // Standard Weight Scale service
        s.uuid.toString().toUpperCase().contains('D618D000') || // Custom eufy scale service
        s.uuid.toString().toUpperCase().contains('4143F6B0')); // Another custom eufy scale service
      
      // Check for Blood Pressure service - both standard and custom implementations
      final hasBloodPressureService = services.any((s) => 
        s.uuid.toString().toUpperCase().contains('636F6D2E') || // Custom BP service
        s.uuid.toString().toUpperCase().contains('1800')); // Standard BP service 0x1810
      
      debugPrint('>>> Has weight service: $hasWeightService');
      debugPrint('>>> Has blood pressure service: $hasBloodPressureService');
      
      if (hasWeightService) {
        // Create weight adapter for weight scale
        final adapter = WeightAdapter(
          participantId: participantId,
          deviceId: device.remoteId.str,
        );
        
        await adapter.bind(device);
        debugPrint('>>> Weight adapter bound successfully');
        return adapter;
        
      } else if (hasBloodPressureService) {
        // Create blood pressure adapter for BP monitor
        debugPrint('>>> Creating blood pressure adapter for device: ${device.remoteId.str}');
        final adapter = BloodPressureAdapter(
          participantId: participantId,
          deviceId: device.remoteId.str,
        );
      
        debugPrint('>>> Binding blood pressure adapter to device...');
        await adapter.bind(device);
        debugPrint('>>> Blood pressure adapter bound successfully');
      
        // Additional debug info for BP monitor
        debugPrint('>>> Blood pressure monitor ready - adapter created and bound');
        
        // Automatically trigger data download to retrieve stored measurements
        debugPrint('>>> Automatically requesting stored readings from blood pressure device');
        await Future.delayed(const Duration(milliseconds: 500)); // Short delay for stability
        await adapter.requestDataDownload();
        
        return adapter;
        
      } else {
        debugPrint('!!! Unknown device type, no suitable adapter available');
        return null;
      }
    } catch (e) {
      debugPrint('!!! Error setting up device adapter: $e');
      return null;
    }
  }
}
