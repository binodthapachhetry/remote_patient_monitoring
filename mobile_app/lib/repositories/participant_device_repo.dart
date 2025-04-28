import 'package:cloud_firestore/cloud_firestore.dart';

/// Persists which BLE device belongs to which participant.
/// Document path:
///   /participants/{pid}/devices/{did} → { bleProfile, nickname, pairedAt }
class ParticipantDeviceRepo {
  final _db = FirebaseFirestore.instance;

  Future<void> saveMapping({
    required String participantId,
    required String deviceId,
    required String bleProfile,      // e.g. "weight"
    String? nickname,
  }) {
    return _db
        .collection('participants')
        .doc(participantId)
        .collection('devices')
        .doc(deviceId)
        .set({
          'bleProfile': bleProfile,
          if (nickname != null) 'nickname': nickname,
          'pairedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}
