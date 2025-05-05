import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to check if an email is approved for registration
class EmailApprovalService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Check if the given email is in the approved list
  Future<bool> isEmailApproved(String email) async {
    try {
      // Normalize email to lowercase for consistency
      final normalizedEmail = email.trim().toLowerCase();
      
      // Check if document exists with email as ID
      final docSnapshot = await _firestore
          .collection('approved_emails')
          .doc(normalizedEmail)
          .get();
      
      return docSnapshot.exists && (docSnapshot.data()?['approved'] == true);
    } catch (e) {
      print('Error checking email approval: $e');
      // In case of error, default to not approved for security
      return false;
    }
  }
}
