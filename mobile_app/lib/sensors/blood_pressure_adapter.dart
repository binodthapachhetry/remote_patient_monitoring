import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/physio_sample.dart';

/// Adapter for Bluetooth Blood Pressure Monitors that implement the standard
/// Blood Pressure Service (0x1810)
class BloodPressureAdapter {
  // Standard BLE UUIDs for Blood Pressure service and characteristics
  static const String _bloodPressureServiceUuid = '1810'; // Correct UUID for Blood Pressure Service
  static const String _bloodPressureMeasurementCharUuid = '2A35';
  static const String _bloodPressureFeatureCharUuid = '2A49';
  
  // Optional Heart Rate service and characteristic
  static const String _heartRateServiceUuid = '180D';
  static const String _heartRateMeasurementCharUuid = '2A37';
  
  // Participant ID and device tracking
  final String participantId;
  final String deviceId;
  
  // BLE device and service references
  BluetoothDevice? _device;
  BluetoothService? _bloodPressureService;
  BluetoothService? _heartRateService;
  BluetoothCharacteristic? _bpMeasurementChar;
  BluetoothCharacteristic? _heartRateChar;
  
  // Stream controller for emitting samples
  final _samplesController = StreamController<PhysioSample>.broadcast();
  
  /// Stream of physiological samples from this device
  Stream<PhysioSample> get samples => _samplesController.stream;
  
  /// Whether the adapter is currently bound to a device
  bool get isBound => _device != null;
  
  /// Creates a new adapter for the specified participant and device
  BloodPressureAdapter({
    required this.participantId,
    required this.deviceId,
  });
  
  /// Bind to a BLE peripheral and discover its services
  Future<void> bind(BluetoothDevice device) async {
    if (_device != null) {
      throw Exception('Already bound to a device');
    }
    
    _device = device;
    debugPrint('Discovering services for blood pressure monitor: ${device.remoteId.str}');
    
    try {
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('Discovered ${services.length} services');
      
      // Find the Blood Pressure service
      _bloodPressureService = services.firstWhere(
        (s) => s.uuid.toString().toUpperCase().contains(_bloodPressureServiceUuid),
        orElse: () => throw Exception('Blood Pressure service not found'),
      );
      
      debugPrint('Found Blood Pressure service: ${_bloodPressureService!.uuid}');
      
      // Find the BP Measurement characteristic
      _bpMeasurementChar = _bloodPressureService!.characteristics.firstWhere(
        (c) => c.uuid.toString().toUpperCase().contains(_bloodPressureMeasurementCharUuid),
        orElse: () => throw Exception('Blood Pressure Measurement characteristic not found'),
      );
      
      debugPrint('Found Blood Pressure Measurement characteristic: ${_bpMeasurementChar!.uuid}');
      
      // Check for Heart Rate service as well (some BP monitors include it)
      try {
        _heartRateService = services.firstWhere(
          (s) => s.uuid.toString().toUpperCase().contains(_heartRateServiceUuid),
        );
        
        if (_heartRateService != null) {
          debugPrint('Found Heart Rate service: ${_heartRateService!.uuid}');
          
          // Find the Heart Rate Measurement characteristic
          // Use where() instead of firstWhere() to safely handle missing characteristic
          final matchingChars = _heartRateService!.characteristics
            .where((c) => c.uuid.toString().toUpperCase().contains(_heartRateMeasurementCharUuid))
            .toList();
          
          if (matchingChars.isNotEmpty) {
            _heartRateChar = matchingChars.first;
          }
          
          if (_heartRateChar != null) {
            debugPrint('Found Heart Rate Measurement characteristic: ${_heartRateChar!.uuid}');
          }
        }
      } catch (e) {
        debugPrint('Heart Rate service not found, this is normal for some BP devices');
        // Heart rate service is optional, so continue without it
      }
      
      // Subscribe to blood pressure notifications
      await _subscribeToBpMeasurements();
      
      // If heart rate characteristic exists, subscribe to it as well
      if (_heartRateChar != null) {
        await _subscribeToHeartRate();
      }
      
    } catch (e) {
      debugPrint('Error binding to blood pressure device: $e');
      await unbind();
      rethrow;
    }
  }
  
  /// Subscribe to blood pressure measurement notifications
  Future<void> _subscribeToBpMeasurements() async {
    if (_bpMeasurementChar == null) return;
    
    try {
      // Enable notifications for the BP Measurement characteristic
      await _bpMeasurementChar!.setNotifyValue(true);
      debugPrint('Subscribed to Blood Pressure notifications');
      
      // Listen for measurements
      _bpMeasurementChar!.onValueReceived.listen((data) {
        debugPrint('Received blood pressure data: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        _handleBpMeasurement(data);
      });
    } catch (e) {
      debugPrint('Error subscribing to blood pressure: $e');
      rethrow;
    }
  }
  
  /// Subscribe to heart rate measurement notifications
  Future<void> _subscribeToHeartRate() async {
    if (_heartRateChar == null) return;
    
    try {
      // Enable notifications for the Heart Rate Measurement characteristic
      await _heartRateChar!.setNotifyValue(true);
      debugPrint('Subscribed to Heart Rate notifications');
      
      // Listen for measurements
      _heartRateChar!.onValueReceived.listen((data) {
        debugPrint('Received heart rate data: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        _handleHeartRateMeasurement(data);
      });
    } catch (e) {
      debugPrint('Error subscribing to heart rate: $e');
      // Continue without heart rate - it's optional
    }
  }
  
  /// Parse blood pressure measurement data per BLE specification
  void _handleBpMeasurement(List<int> data) {
    try {
      if (data.isEmpty) return;
      
      // First byte contains flags
      final flags = data[0];
      final isMMHG = (flags & 0x01) == 0; // Units flag: 0 = mmHg, 1 = kPa
      final hasTimestamp = ((flags >> 1) & 0x01) == 1;
      final hasPulseRate = ((flags >> 2) & 0x01) == 1;
      
      // Blood pressure values are IEEE-11073 16-bit SFLOAT
      // Each value is 2 bytes in little endian format
      double systolic = _parseSfloat(data[1], data[2]);
      double diastolic = _parseSfloat(data[3], data[4]);
      double meanArterial = _parseSfloat(data[5], data[6]);
      
      // Convert to mmHg if needed
      String unit = isMMHG ? 'mmHg' : 'kPa';
      if (!isMMHG) {
        // Convert kPa to mmHg if needed
        systolic *= 7.5;
        diastolic *= 7.5;
        meanArterial *= 7.5;
        unit = 'mmHg'; // We normalize to mmHg for consistency
      }
      
      debugPrint('Blood Pressure: $systolic/$diastolic mmHg, MAP: $meanArterial mmHg');
      
      // Extract pulse rate if present
      double? pulseRate;
      int offset = 7;
      
      // Skip timestamp if present (7 bytes: year, month, day, hour, min, sec, offset)
      if (hasTimestamp) {
        offset += 7;
      }
      
      if (hasPulseRate && data.length >= offset + 2) {
        pulseRate = _parseSfloat(data[offset], data[offset + 1]);
        debugPrint('Pulse Rate: $pulseRate bpm');
      }
      
      // Create samples for systolic and diastolic
      final timestamp = DateTime.now();
      
      // Emit systolic reading
      final systolicSample = PhysioSample(
        participantId: participantId,
        deviceId: deviceId,
        metric: PhysioMetric.bloodPressureSystolicMmHg,
        value: systolic,
        timestamp: timestamp,
        metadata: {
          'diastolic': diastolic,
          'meanArterial': meanArterial,
          'unit': unit,
          if (pulseRate != null) 'pulseRate': pulseRate,
        },
      );
      _samplesController.add(systolicSample);
      
      // Also emit diastolic as separate sample
      final diastolicSample = PhysioSample(
        participantId: participantId,
        deviceId: deviceId,
        metric: PhysioMetric.bloodPressureDiastolicMmHg,
        value: diastolic,
        timestamp: timestamp,
        metadata: {
          'systolic': systolic,
          'meanArterial': meanArterial,
          'unit': unit,
          if (pulseRate != null) 'pulseRate': pulseRate,
        },
      );
      _samplesController.add(diastolicSample);
      
      // Emit pulse rate if available
      if (pulseRate != null) {
        final pulseSample = PhysioSample(
          participantId: participantId,
          deviceId: deviceId,
          metric: PhysioMetric.heartRate,
          value: pulseRate,
          timestamp: timestamp,
        );
        _samplesController.add(pulseSample);
      }
    } catch (e) {
      debugPrint('Error parsing blood pressure data: $e');
    }
  }
  
  /// Parse heart rate measurement data per BLE specification
  void _handleHeartRateMeasurement(List<int> data) {
    try {
      if (data.isEmpty) return;
      
      // First byte contains flags
      final flags = data[0];
      final isUint16 = ((flags >> 0) & 0x01) == 1; // Heart Rate Value Format bit
      
      // Extract the heart rate value
      int heartRate;
      if (isUint16 && data.length >= 3) {
        // Heart rate is 16-bit uint
        heartRate = data[1] + (data[2] << 8);
      } else if (data.length >= 2) {
        // Heart rate is 8-bit uint
        heartRate = data[1];
      } else {
        return; // Not enough data
      }
      
      debugPrint('Heart Rate from HR service: $heartRate bpm');
      
      // Create heart rate sample
      final hrSample = PhysioSample(
        participantId: participantId,
        deviceId: deviceId,
        metric: PhysioMetric.heartRate,
        value: heartRate.toDouble(),
        timestamp: DateTime.now(),
      );
      
      _samplesController.add(hrSample);
    } catch (e) {
      debugPrint('Error parsing heart rate data: $e');
    }
  }
  
  /// Parse IEEE-11073 16-bit SFLOAT value
  double _parseSfloat(int byte1, int byte2) {
    // SFLOAT is 16-bit - first 12 bits (mantissa) and last 4 bits (exponent)
    // In little endian: byte1 = LSB, byte2 = MSB
    
    int mantissa = ((byte2 & 0x0F) << 8) | byte1;
    // Sign extend if necessary (mantissa is a 12-bit signed value)
    if ((mantissa & 0x0800) != 0) {
      mantissa = mantissa | ~0x0FFF; // Extend sign to 32 bits
    }
    
    int exponent = byte2 >> 4;
    // Sign extend if necessary (exponent is a 4-bit signed value)
    if ((exponent & 0x08) != 0) {
      exponent = exponent | ~0x0F; // Extend sign to 32 bits
    }
    
    // Special values
    if (mantissa == 0x07FF && exponent == 0x0F) {
      return double.nan; // NaN
    } else if (mantissa == 0x0800 && exponent == 0x0F) {
      return double.negativeInfinity; // -Infinity
    } else if (mantissa == 0x07FF && exponent == 0x0F) {
      return double.infinity; // +Infinity
    } else if (exponent == 0x0F) {
      return double.nan; // Reserved for future use
    }
    
    // Regular values
    return mantissa * pow(10, exponent);
  }
  
  /// Calculate 10 raised to the power of n
  double pow(int base, int exponent) {
    if (exponent == 0) return 1;
    
    double result = 1.0;
    int absExponent = exponent.abs();
    
    for (int i = 0; i < absExponent; i++) {
      result *= base;
    }
    
    return exponent >= 0 ? result : 1.0 / result;
  }
  
  /// Disconnect from device and clean up resources
  Future<void> unbind() async {
    try {
      if (_device != null) {
        // Disable notifications
        if (_bpMeasurementChar != null) {
          await _bpMeasurementChar!.setNotifyValue(false);
        }
        if (_heartRateChar != null) {
          await _heartRateChar!.setNotifyValue(false);
        }
      }
    } catch (e) {
      debugPrint('Error during unbind: $e');
    } finally {
      _device = null;
      _bloodPressureService = null;
      _heartRateService = null;
      _bpMeasurementChar = null;
      _heartRateChar = null;
    }
  }
  
  /// Clean up resources
  void dispose() {
    _samplesController.close();
  }
}
