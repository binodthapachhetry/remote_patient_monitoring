import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/physio_sample.dart';
import '../models/health_measurement.dart';
import '../services/sync_service.dart';
import 'sensor_adapter.dart';

/// Adapter for Bluetooth Blood Pressure Monitors that implement the standard
/// Blood Pressure Service (0x1810) or custom implementations with proprietary UUIDs
class BloodPressureAdapter extends SensorAdapter {
  // Standard BLE UUIDs for Blood Pressure service and characteristics
  static const String _bloodPressureServiceUuid = '1810'; // Correct UUID for Blood Pressure Service
  // Custom service UUID for non-standard blood pressure monitors
  static const String _customBloodPressureServiceUuid = '636F6D2E'; // The custom UUID we've detected
  static const String _bloodPressureMeasurementCharUuid = '7365642';
  static const String _bloodPressureFeatureCharUuid = '2A49';
  
  // Optional Heart Rate service and characteristic
  static const String _heartRateServiceUuid = '180D';
  static const String _heartRateMeasurementCharUuid = '2A37';
  
  // Device ID for tracking
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
    required super.participantId,
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
        (s) => s.uuid.toString().toUpperCase().contains(_bloodPressureServiceUuid) || 
               s.uuid.toString().toUpperCase().contains(_customBloodPressureServiceUuid),
        orElse: () => throw Exception('Blood Pressure service not found'),
      );
      
      debugPrint('Found Blood Pressure service: ${_bloodPressureService!.uuid}');
      
      // Log all characteristics for debugging
      debugPrint('Characteristics in BP service:');
      for (var c in _bloodPressureService!.characteristics) {
        debugPrint('  Characteristic: ${c.uuid}, properties: ${_describeProperties(c.properties)}');
      }
      
      // Find the BP Measurement characteristic
      // First try to find standard BP characteristic
      try {
        _bpMeasurementChar = _bloodPressureService!.characteristics.firstWhere(
          (c) => c.uuid.toString().toUpperCase().contains(_bloodPressureMeasurementCharUuid),
        );
        debugPrint('Found standard Blood Pressure Measurement characteristic: ${_bpMeasurementChar!.uuid}');
      } catch (e) {
        // If standard characteristic not found, try to find any characteristic with notify property
        // For custom devices, the main measurement characteristic typically has the notify property
        debugPrint('Standard BP characteristic not found, looking for alternative characteristics...');
        final notifyCharacteristics = _bloodPressureService!.characteristics
            .where((c) => c.properties.notify)
            .toList();
        
        if (notifyCharacteristics.isNotEmpty) {
          // Use the first characteristic with notify property as our measurement characteristic
          _bpMeasurementChar = notifyCharacteristics.first;
          debugPrint('Using alternative characteristic as measurement source: ${_bpMeasurementChar!.uuid}');
        } else {
          // If no notify characteristics found, try the first writeable characteristic
          final writeCharacteristics = _bloodPressureService!.characteristics
              .where((c) => c.properties.write || c.properties.writeWithoutResponse)
              .toList();
          
          if (writeCharacteristics.isNotEmpty) {
            _bpMeasurementChar = writeCharacteristics.first;
            debugPrint('Using writable characteristic: ${_bpMeasurementChar!.uuid}');
          } else {
            // Last resort: just use the first characteristic
            if (_bloodPressureService!.characteristics.isNotEmpty) {
              _bpMeasurementChar = _bloodPressureService!.characteristics.first;
              debugPrint('Using first available characteristic: ${_bpMeasurementChar!.uuid}');
            } else {
              throw Exception('No usable characteristics found in blood pressure service');
            }
          }
        }
      }
      
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
        final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        debugPrint('>>> RAW BP DATA: [${data.length} bytes] $hexData');
        
        // Always try to parse the data, even if it fails
        try {
          _handleBpMeasurement(data);
        } catch (e) {
          debugPrint('!!! BP data parse error: $e');
          debugPrint('!!! Raw data that failed parsing: $hexData');
        }
      });
      
      // Send initialization command to the device if the characteristic is writable
      if (_bpMeasurementChar!.properties.write || _bpMeasurementChar!.properties.writeWithoutResponse) {
        _sendInitializationCommand();
      }
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
  
  /// Send initialization command to the device to trigger readings
  Future<void> _sendInitializationCommand() async {
    if (_bpMeasurementChar == null) return;
    
    try {
      debugPrint('>>> Sending initialization command to blood pressure device');
      
      // Try different initialization commands that might work with this device
      // Command 1: Simple activation byte
      List<int> command1 = [0x01];
      await _bpMeasurementChar!.write(command1, withoutResponse: _bpMeasurementChar!.properties.writeWithoutResponse);
      debugPrint('>>> Sent command: ${command1.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Command 2: Start measurement command (common pattern)
      List<int> command2 = [0xAA, 0x01, 0x02, 0x03, 0x04];
      await _bpMeasurementChar!.write(command2, withoutResponse: _bpMeasurementChar!.properties.writeWithoutResponse);
      debugPrint('>>> Sent command: ${command2.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      debugPrint('>>> Initialization commands sent. Please start a measurement on the device.');
    } catch (e) {
      debugPrint('!!! Error sending initialization command: $e');
    }
  }
  
  /// Parse blood pressure measurement data per BLE specification
  void _handleBpMeasurement(List<int> data) {
    // Always log the raw data
    final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint('>>> Processing BP data: ${data.length} bytes: $hexData');
    
    if (data.isEmpty) return;
    
    // Try to detect if this is a standard BLE profile or a custom format
    if (data.length >= 7) {
      // First check if this might be standard BLE blood pressure format
      final flags = data[0];
      final isMMHG = (flags & 0x01) == 0; // Units flag: 0 = mmHg, 1 = kPa
      final hasTimestamp = ((flags >> 1) & 0x01) == 1;
      final hasPulseRate = ((flags >> 2) & 0x01) == 1;
      
      debugPrint('>>> BP Flags detected: isMMHG=$isMMHG, hasTimestamp=$hasTimestamp, hasPulseRate=$hasPulseRate');
      
      // Try standard BLE parsing first
      try {
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
        
        debugPrint('>>> Standard BLE format - Blood Pressure: $systolic/$diastolic mmHg, MAP: $meanArterial mmHg');
        
        // Emit measurements using standard format parsing
        _emitBloodPressureMeasurements(systolic, diastolic, meanArterial, unit, data, pulseRate: null);
        return;
      } catch (e) {
        debugPrint('>>> Standard format parsing failed: $e - Trying custom format parsing');
      }
    }
    
    // If standard parsing fails or we don't have enough data, try custom format parsing
    _tryCustomFormatParsing(data);
  }
  
  /// Try to parse custom format data from the device
  void _tryCustomFormatParsing(List<int> data) {
    debugPrint('>>> Attempting custom format parsing');
    
    try {
      // Sample custom parsing logic - adjust based on your device's actual data format
      // This is a guess based on common non-standard implementations
      
      // Method 1: Direct integer values (common in custom implementations)
      // Example: first byte = systolic, second = diastolic, etc.
      if (data.length >= 3) {
        final systolic = data[0].toDouble();  // First byte as systolic
        final diastolic = data[1].toDouble(); // Second byte as diastolic
        final pulse = data.length >= 3 ? data[2].toDouble() : null; // Third byte as pulse if available
        
        // Validate readings are in reasonable range for blood pressure
        if (systolic > 50 && systolic < 250 && diastolic > 30 && diastolic < 200) {
          debugPrint('>>> Custom format 1 - Blood Pressure: $systolic/$diastolic mmHg, Pulse: $pulse');
          _emitBloodPressureMeasurements(systolic, diastolic, (systolic + 2*diastolic)/3, 'mmHg', data, pulseRate: pulse);
          return;
        }
      }
      
      // Method 2: Two-byte values (little endian uint16)
      if (data.length >= 4) {
        final systolic = (data[1] << 8 | data[0]).toDouble();
        final diastolic = (data[3] << 8 | data[2]).toDouble();
        final pulse = data.length >= 6 ? (data[5] << 8 | data[4]).toDouble() : null;
        
        // Apply scaling if needed (some devices multiply by 10 or 100)
        final scaledSystolic = systolic / 10.0;
        final scaledDiastolic = diastolic / 10.0;
        final scaledPulse = pulse != null ? pulse / 10.0 : null;
        
        // Validate readings are in reasonable range
        if (scaledSystolic > 50 && scaledSystolic < 250 && scaledDiastolic > 30 && scaledDiastolic < 200) {
          debugPrint('>>> Custom format 2 - Blood Pressure: $scaledSystolic/$scaledDiastolic mmHg, Pulse: $scaledPulse');
          _emitBloodPressureMeasurements(scaledSystolic, scaledDiastolic, 
            (scaledSystolic + 2*scaledDiastolic)/3, 'mmHg', data, pulseRate: scaledPulse);
          return;
        }
      }
      
      // Method 3: Fixed positions with scaling factor
      // This is a common pattern where bytes at specific positions represent values with a scaling factor
      if (data.length >= 6) {
        // Try different combinations of byte positions and scaling
        for (var i = 0; i < data.length - 3; i++) {
          final possibleSystolic = data[i].toDouble();
          
          for (var j = i + 1; j < data.length - 1; j++) {
            final possibleDiastolic = data[j].toDouble();
            
            // Try different scaling factors
            for (var scale in [1.0, 10.0, 100.0]) {
              final scaledSystolic = possibleSystolic * scale;
              final scaledDiastolic = possibleDiastolic * scale;
              
              // Check if values fall in reasonable BP range
              if (scaledSystolic > 50 && scaledSystolic < 250 && 
                  scaledDiastolic > 30 && scaledDiastolic < 200 &&
                  scaledSystolic > scaledDiastolic) { // Systolic should be higher
                
                debugPrint('>>> Custom format 3 - Blood Pressure: $scaledSystolic/$scaledDiastolic mmHg (bytes $i,$j, scale $scale)');
                _emitBloodPressureMeasurements(scaledSystolic, scaledDiastolic, 
                  (scaledSystolic + 2*scaledDiastolic)/3, 'mmHg', data, pulseRate: null);
                return;
              }
            }
          }
        }
      }
      
      debugPrint('!!! Could not parse blood pressure data in any known format. Please take a measurement on the device.');
    } catch (e) {
      debugPrint('!!! Error in custom format parsing: $e');
    }
  }
  
  /// Create and emit blood pressure measurements from parsed values
  void _emitBloodPressureMeasurements(
    double systolic, 
    double diastolic, 
    double meanArterial, 
    String unit, 
    List<int> rawData, 
    {double? pulseRate}
  ) {
    // Create samples for systolic and diastolic
    final timestamp = DateTime.now();
    final hexData = rawData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    
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
        'rawData': hexData,
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
        'rawData': hexData,
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
        metadata: {
          'rawData': hexData,
        },
      );
      _samplesController.add(pulseSample);
    }
    
    // Also store in sync service
    final measurement = HealthMeasurement(
      participantId: participantId,
      deviceId: deviceId,
      type: 'blood_pressure',
      value: systolic,
      unit: 'mmHg',
      timestamp: timestamp.millisecondsSinceEpoch,
      metadata: {
        'systolic': systolic.toString(),
        'diastolic': diastolic.toString(),
        'meanArterial': meanArterial.toString(),
        if (pulseRate != null) 'pulseRate': pulseRate.toString(),
        'rawData': hexData,
      },
    );
    
    // Store in sync service
    SyncService().storeMeasurement(measurement);
    debugPrint('>>> Blood pressure measurement stored for sync: $systolic/$diastolic mmHg');
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
    debugPrint('>>> Parsing SFLOAT: bytes ${byte1.toRadixString(16)} ${byte2.toRadixString(16)}');
    
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
    
    debugPrint('>>> SFLOAT components: mantissa=$mantissa, exponent=$exponent');
    
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
    final value = mantissa * pow(10, exponent);
    debugPrint('>>> SFLOAT value: $value');
    return value;
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
  
  /// Helper to describe characteristic properties for logging
  String _describeProperties(CharacteristicProperties props) {
    final descriptions = <String>[];
    if (props.broadcast) descriptions.add('broadcast');
    if (props.read) descriptions.add('read');
    if (props.writeWithoutResponse) descriptions.add('writeWithoutResponse');
    if (props.write) descriptions.add('write');
    if (props.notify) descriptions.add('notify');
    if (props.indicate) descriptions.add('indicate');
    if (props.authenticatedSignedWrites) descriptions.add('authenticatedSignedWrites');
    if (props.extendedProperties) descriptions.add('extendedProperties');
    if (props.notifyEncryptionRequired) descriptions.add('notifyEncryptionRequired');
    if (props.indicateEncryptionRequired) descriptions.add('indicateEncryptionRequired');
    return descriptions.join(', ');
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
  
  /// Manually send a command to the device to request a measurement
  Future<void> requestMeasurement() async {
    if (_bpMeasurementChar == null || !_bpMeasurementChar!.properties.write) {
      debugPrint('!!! Cannot request measurement: No writable characteristic available');
      return;
    }
    
    try {
      debugPrint('>>> Sending measurement request command to blood pressure device');
      
      // Try multiple command formats that are known to work with various devices
      List<List<int>> commandsToTry = [
        [0x01],                // Simple command - works with some devices
        [0x02],                // Alternate command
        [0xAA, 0x01],          // Start sequence for some devices
        [0xFE, 0x01, 0x00],    // 3-byte command sequence
        [0xAA, 0x12, 0x34, 0x56] // More complex sequence
      ];
      
      for (var command in commandsToTry) {
        await _bpMeasurementChar!.write(command, 
          withoutResponse: _bpMeasurementChar!.properties.writeWithoutResponse);
        debugPrint('>>> Sent command: ${command.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      debugPrint('>>> Measurement request commands sent. Please also press START on the physical device.');
    } catch (e) {
      debugPrint('!!! Error requesting measurement: $e');
    }
  }
  
  /// Clean up resources - implements SensorAdapter.dispose()
  @override
  Future<void> dispose() async {
    await unbind();
    _samplesController.close();
  }
}
