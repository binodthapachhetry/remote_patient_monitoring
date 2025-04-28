/// Domain object representing a single physiological measurement that will
/// eventually be forwarded to Pub/Sub and mapped to HL7v2.
class PhysioSample {
  final String participantId;
  final String deviceId;
  final PhysioMetric metric;
  final num value;
  final DateTime timestamp;

  const PhysioSample({
    required this.participantId,
    required this.deviceId,
    required this.metric,
    required this.value,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'participantId': participantId,
        'deviceId': deviceId,
        'metric': metric.name,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Enumerates the physiological metrics our MVP supports.
enum PhysioMetric { heartRate, glucoseMgDl, weightKg }
