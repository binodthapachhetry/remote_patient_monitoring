import 'package:remote_patient_monitoring/models/health_measurement.dart';

/// Domain object representing a single physiological measurement that will
/// eventually be forwarded to Pub/Sub and mapped to HL7v2.
class PhysioSample {
  final String participantId;
  final String deviceId;
  final PhysioMetric metric;
  final num value;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const PhysioSample({
    required this.participantId,
    required this.deviceId,
    required this.metric,
    required this.value,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'participantId': participantId,
        'deviceId': deviceId,
        'metric': metric.name,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
        if (metadata != null) 'metadata': metadata,
      };
      
  /// Convert to a HealthMeasurement for HL7 processing
  HealthMeasurement toHealthMeasurement() {
    return HealthMeasurement(
      participantId: participantId,
      deviceId: deviceId,
      type: _getHealthMeasurementType(),
      value: value.toDouble(),
      unit: _getUnitForMetric(),
      timestamp: timestamp.millisecondsSinceEpoch,
      metadata: metadata,
    );
  }
  
  /// Map PhysioMetric to HealthMeasurement type string
  String _getHealthMeasurementType() {
    switch (metric) {
      case PhysioMetric.weightKg:
        return 'weight';
      case PhysioMetric.heartRate:
        return 'heart_rate';
      case PhysioMetric.glucoseMgDl:
        return 'glucose';
      case PhysioMetric.bloodPressureSystolicMmHg:
        return 'blood_pressure_systolic';
      case PhysioMetric.bloodPressureDiastolicMmHg:
        return 'blood_pressure_diastolic';
      default:
        return metric.name;
    }
  }
  
  /// Get unit for the metric type
  String _getUnitForMetric() {
    switch (metric) {
      case PhysioMetric.weightKg:
        return 'kg';
      case PhysioMetric.heartRate:
        return 'bpm';
      case PhysioMetric.glucoseMgDl:
        return 'mg/dL';
      case PhysioMetric.bloodPressureSystolicMmHg:
      case PhysioMetric.bloodPressureDiastolicMmHg:
        return 'mmHg';
      default:
        return '';
    }
  }
}

/// Enumerates the physiological metrics our MVP supports.
enum PhysioMetric { 
  heartRate, 
  glucoseMgDl, 
  weightKg,
  bloodPressureSystolicMmHg,
  bloodPressureDiastolicMmHg 
}
