import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/health_measurement.dart';

/// Generates HL7v2 message segments for health measurements
/// Implements a hybrid approach as recommended in the architecture doc
/// - Basic message structure created on device
/// - Final validation and assembly done in cloud
class HL7MessageGenerator {
  // Singleton pattern
  static final HL7MessageGenerator _instance = HL7MessageGenerator._internal();
  factory HL7MessageGenerator() => _instance;
  HL7MessageGenerator._internal();
  
  /// Date formatters for HL7 timestamps
  final _dateTimeFormatter = DateFormat('yyyyMMddHHmmss');
  
  /// Map of measurement types to HL7 observation identifiers
  final Map<String, Map<String, String>> _observationCodes = {
    'weight': {
      'code': '3141-9',
      'name': 'BODY WEIGHT',
      'system': 'LN',  // LOINC
    },
    'heart_rate': {
      'code': '8867-4',
      'name': 'HEART RATE',
      'system': 'LN',  // LOINC
    },
    'blood_pressure_systolic': {
      'code': '8480-6',
      'name': 'SYSTOLIC BLOOD PRESSURE',
      'system': 'LN',  // LOINC
    },
    'blood_pressure_diastolic': {
      'code': '8462-4',
      'name': 'DIASTOLIC BLOOD PRESSURE',
      'system': 'LN',  // LOINC
    },
    'oxygen_saturation': {
      'code': '2710-2',
      'name': 'OXYGEN SATURATION',
      'system': 'LN',  // LOINC
    },
    'temperature': {
      'code': '8310-5',
      'name': 'BODY TEMPERATURE',
      'system': 'LN',  // LOINC
    },
    'glucose': {
      'code': '2339-0',
      'name': 'GLUCOSE',
      'system': 'LN',  // LOINC
    },
  };
  
  /// Generate an HL7 MSH (Message Header) segment
  /// This forms the header for HL7v2 messages
  String generateMSH({
    required String sendingApp,
    required String sendingFacility,
    required String receivingApp,
    required String receivingFacility,
    String messageType = 'ORU^R01',
    String processingId = 'P',  // P=Production, D=Development
  }) {
    final timestamp = _dateTimeFormatter.format(DateTime.now());
    final messageId = 'MSG${DateTime.now().millisecondsSinceEpoch}';
    
    // MSH segment using pipe (|) as field separator
    return 'MSH|^~\\&|$sendingApp|$sendingFacility|$receivingApp|$receivingFacility|'
        '$timestamp||$messageType|$messageId|$processingId|2.5.1||';
  }
  
  /// Generate an HL7 PID (Patient Identification) segment
  String generatePID({
    required String patientId,
  }) {
    // Very basic PID segment with just the patient ID
    // In production, this would include more demographics
    return 'PID|||$patientId||^^^^||||||||||||||';
  }
  
  /// Generate an HL7 OBR (Observation Request) segment
  String generateOBR({
    required String observationId,
    required DateTime observationTime,
  }) {
    final formattedTime = _dateTimeFormatter.format(observationTime);
    
    return 'OBR|1|$observationId||||||$formattedTime|||||||||||||||||F|||||||';
  }
  
  /// Generate an HL7 OBX (Observation Result) segment for a measurement
  String generateOBX(HealthMeasurement measurement) {
    final DateTime observationTime = 
        DateTime.fromMillisecondsSinceEpoch(measurement.timestamp);
    final formattedTime = _dateTimeFormatter.format(observationTime);
    
    // Get observation code details from our mapping
    final obsDetails = _observationCodes[measurement.type] ?? {
      'code': 'UNK',
      'name': measurement.type.toUpperCase(),
      'system': 'L', // Local code
    };
    
    // OBX|set ID|value type|observation ID^name^coding system|sub-ID|value|units|reference range|abnormal flags|
    return 'OBX|1|NM|${obsDetails['code']}^${obsDetails['name']}^${obsDetails['system']}||'
        '${measurement.value}|${measurement.unit}|||N|||$formattedTime|${measurement.deviceId}||';
  }
  
  /// Generate segments for a batch of measurements
  /// Returns a list of segments that can be assembled into a complete message
  /// Following the hybrid approach, cloud will assemble final message
  List<String> generateMessageSegments(
    List<HealthMeasurement> measurements,
    {
      String sendingApp = 'MobileHealthMVP',
      String sendingFacility = 'MOBILE_CLIENT',
      String receivingApp = 'HL7_GATEWAY',
      String receivingFacility = 'CLOUD_HEALTHCARE_API',
    }
  ) {
    if (measurements.isEmpty) {
      return [];
    }
    
    final List<String> segments = [];
    
    // Add message header
    segments.add(generateMSH(
      sendingApp: sendingApp,
      sendingFacility: sendingFacility,
      receivingApp: receivingApp,
      receivingFacility: receivingFacility,
    ));
    
    // Group measurements by participant
    final Map<String, List<HealthMeasurement>> byParticipant = {};
    for (final measurement in measurements) {
      if (!byParticipant.containsKey(measurement.participantId)) {
        byParticipant[measurement.participantId] = [];
      }
      byParticipant[measurement.participantId]!.add(measurement);
    }
    
    // Generate segments for each participant
    byParticipant.forEach((participantId, participantMeasurements) {
      // Add patient identification segment
      segments.add(generatePID(patientId: participantId));
      
      // Group by observation time (rounded to minutes for practical grouping)
      final Map<int, List<HealthMeasurement>> byTime = {};
      for (final measurement in participantMeasurements) {
        final timeKey = measurement.timestamp ~/ 60000 * 60000; // Round to minutes
        if (!byTime.containsKey(timeKey)) {
          byTime[timeKey] = [];
        }
        byTime[timeKey]!.add(measurement);
      }
      
      // Generate OBR and OBX segments for each time group
      byTime.forEach((timeKey, timeMeasurements) {
        final obsTime = DateTime.fromMillisecondsSinceEpoch(timeKey);
        final obsId = 'OBS${timeKey}';
        
        // Add observation request segment
        segments.add(generateOBR(
          observationId: obsId,
          observationTime: obsTime,
        ));
        
        // Add observation result segments
        for (final measurement in timeMeasurements) {
          segments.add(generateOBX(measurement));
        }
      });
    });
    
    return segments;
  }
  
  /// Validates if the measurement type is supported for HL7 generation
  bool isSupported(String measurementType) {
    return _observationCodes.containsKey(measurementType);
  }
  
  /// For debug logging, returns a readable version of generated segments
  String debugSegments(List<String> segments) {
    return segments.join('\n');
  }
}
import 'dart:math' as math;
import '../models/health_measurement.dart';

/// Generates HL7 message segments from health measurements for transmission
class HL7MessageGenerator {
  /// Generate HL7 message segments from a list of health measurements
  List<Map<String, dynamic>> generateMessageSegments(List<HealthMeasurement> measurements) {
    if (measurements.isEmpty) return [];
    
    final messageSegments = <Map<String, dynamic>>[];
    
    // Group measurements by type
    final Map<String, List<HealthMeasurement>> measurementsByType = {};
    for (final measurement in measurements) {
      if (!measurementsByType.containsKey(measurement.type)) {
        measurementsByType[measurement.type] = [];
      }
      measurementsByType[measurement.type]!.add(measurement);
    }
    
    // Generate segments for each measurement type
    measurementsByType.forEach((type, typeMeasurements) {
      for (final measurement in typeMeasurements) {
        messageSegments.add(_createObservationSegment(measurement));
      }
    });
    
    return messageSegments;
  }
  
  /// Create an HL7 observation segment for a single measurement
  Map<String, dynamic> _createObservationSegment(HealthMeasurement measurement) {
    // Format timestamps
    final observationTime = _formatHL7DateTime(
      DateTime.fromMillisecondsSinceEpoch(measurement.timestamp)
    );
    final messageTime = _formatHL7DateTime(DateTime.now());
    
    // Generate a unique message ID
    final messageId = 'RPM${DateTime.now().millisecondsSinceEpoch}${math.Random().nextInt(1000)}';
    
    // Get descriptive name for the measurement type
    final typeName = _getDescriptiveTypeName(measurement.type);
    
    // Create HL7 fields
    return {
      'messageType': 'ORU^R01',
      'messageId': messageId,
      'messageTime': messageTime,
      'participantId': measurement.participantId,
      'deviceId': measurement.deviceId,
      'observationType': measurement.type,
      'observationTypeName': typeName,
      'observationValue': measurement.value,
      'observationUnit': measurement.unit,
      'observationTime': observationTime,
      'metadata': measurement.metadata,
    };
  }
  
  /// Format a DateTime into HL7 format
  String _formatHL7DateTime(DateTime date) {
    return date.year.toString() +
      date.month.toString().padLeft(2, '0') +
      date.day.toString().padLeft(2, '0') +
      date.hour.toString().padLeft(2, '0') +
      date.minute.toString().padLeft(2, '0') +
      date.second.toString().padLeft(2, '0');
  }
  
  /// Get a human-readable name for a measurement type
  String _getDescriptiveTypeName(String type) {
    switch (type) {
      case 'heart_rate':
        return 'Heart Rate';
      case 'blood_pressure_systolic':
        return 'Blood Pressure - Systolic';
      case 'blood_pressure_diastolic':
        return 'Blood Pressure - Diastolic';
      case 'weight':
        return 'Body Weight';
      case 'glucose':
        return 'Blood Glucose';
      case 'oxygen_saturation':
        return 'Oxygen Saturation';
      case 'temperature':
        return 'Body Temperature';
      case 'respiratory_rate':
        return 'Respiratory Rate';
      default:
        // Capitalize each word and replace underscores with spaces
        return type
            .split('_')
            .map((word) => word.isEmpty 
                ? '' 
                : word[0].toUpperCase() + word.substring(1))
            .join(' ');
    }
  }
}
