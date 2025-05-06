import 'package:uuid/uuid.dart';

/// Data model for health measurements collected from devices
/// Used for SQLite storage and HL7v2 message generation
class HealthMeasurement {
  final String id;
  final String participantId;
  final String deviceId;
  final String type;
  final double value;
  final String unit;
  final int timestamp;
  final String syncStatus;
  final String? batchId;
  final int retryCount;
  final int? lastSyncAttempt;
  final Map<String, dynamic>? metadata;
  
  HealthMeasurement({
    String? id,
    required this.participantId,
    required this.deviceId,
    required this.type,
    required this.value,
    required this.unit,
    int? timestamp,
    String? syncStatus,
    this.batchId,
    this.retryCount = 0,
    this.lastSyncAttempt,
    this.metadata,
  }) : 
    id = id ?? const Uuid().v4(),
    timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch,
    syncStatus = syncStatus ?? 'pending';
  
  /// Create a measurement from a map (e.g., database row)
  factory HealthMeasurement.fromMap(Map<String, dynamic> map) {
    return HealthMeasurement(
      id: map['id'],
      participantId: map['participantId'],
      deviceId: map['deviceId'],
      type: map['type'],
      value: map['value'],
      unit: map['unit'],
      timestamp: map['timestamp'],
      syncStatus: map['syncStatus'],
      batchId: map['batchId'],
      retryCount: map['retryCount'] ?? 0,
      lastSyncAttempt: map['lastSyncAttempt'],
      metadata: map['metadata'] != null 
          ? Map<String, dynamic>.from(_parseMetadata(map['metadata']))
          : null,
    );
  }
  
  /// Parse metadata JSON string
  static dynamic _parseMetadata(String data) {
    try {
      if (data.isEmpty) return {};
      return Map<String, dynamic>.from(data as Map);
    } catch (e) {
      return {};
    }
  }
  
  /// Convert to map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participantId': participantId,
      'deviceId': deviceId,
      'type': type,
      'value': value,
      'unit': unit,
      'timestamp': timestamp,
      'syncStatus': syncStatus,
      'batchId': batchId,
      'retryCount': retryCount,
      'lastSyncAttempt': lastSyncAttempt,
      'metadata': metadata != null ? metadata.toString() : null,
    };
  }
  
  /// Create a copy with updated properties
  HealthMeasurement copyWith({
    String? id,
    String? participantId,
    String? deviceId,
    String? type,
    double? value,
    String? unit,
    int? timestamp,
    String? syncStatus,
    String? batchId,
    int? retryCount,
    int? lastSyncAttempt,
    Map<String, dynamic>? metadata,
  }) {
    return HealthMeasurement(
      id: id ?? this.id,
      participantId: participantId ?? this.participantId,
      deviceId: deviceId ?? this.deviceId,
      type: type ?? this.type,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      timestamp: timestamp ?? this.timestamp,
      syncStatus: syncStatus ?? this.syncStatus,
      batchId: batchId ?? this.batchId,
      retryCount: retryCount ?? this.retryCount,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
      metadata: metadata ?? this.metadata,
    );
  }
  
  @override
  String toString() {
    return 'HealthMeasurement{id: $id, type: $type, value: $value $unit, syncStatus: $syncStatus}';
  }
  
  /// Get formatted timestamp as DateTime
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}
