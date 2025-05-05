import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_approval_service.dart';

/// Manages user authentication using Firebase Auth.
/// Provides a persistent user session with email/password authentication.
class UserManager {
  // Singleton pattern
  static final UserManager _instance = UserManager._internal();
  factory UserManager() => _instance;
  UserManager._internal();
  
  // Firebase Auth instance
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Email approval service
  final EmailApprovalService _approvalService = EmailApprovalService();
  
  // Stream controller for compatibility with existing architecture
  final _authStateController = StreamController<bool>.broadcast();
  
  /// Whether a user is currently authenticated
  bool get isAuthenticated => _auth.currentUser != null;
  
  /// The current participant ID (null if not authenticated)
  /// Uses the Firebase UID as the participant ID
  String? get participantId => _auth.currentUser?.uid;
  
  /// The current user's email address (null if not authenticated)
  String? get userEmail => _auth.currentUser?.email;
  
  /// Stream of authentication state changes (as boolean)
  Stream<bool> get authStateChanges => _authStateController.stream;
  
  /// Initialize and set up auth state listener
  Future<void> initialize() async {
    // Listen to Firebase Auth state changes and forward to our controller
    _auth.authStateChanges().listen((User? user) {
      final isAuth = user != null;
      _authStateController.add(isAuth);
      debugPrint('>>> UserManager auth state changed: authenticated=$isAuth, id=${user?.uid}');
    });
    
    // Initial state
    final currentUser = _auth.currentUser;
    debugPrint('>>> UserManager initialized: authenticated=${currentUser != null}, id=${currentUser?.uid}');
  }
  
  /// Sign in with email and password
  Future<bool> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) return false;
    
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = userCredential.user;
      debugPrint('>>> User logged in: ${user?.uid}, email: ${user?.email}');
      return user != null;
    } on FirebaseAuthException catch (e) {
      String errorMsg;
      switch (e.code) {
        case 'user-not-found':
          errorMsg = 'No user found with this email';
          break;
        case 'wrong-password':
          errorMsg = 'Wrong password';
          break;
        case 'invalid-email':
          errorMsg = 'Invalid email format';
          break;
        case 'user-disabled':
          errorMsg = 'This account has been disabled';
          break;
        case 'too-many-requests':
          errorMsg = 'Too many attempts. Try again later';
          break;
        default:
          errorMsg = 'Authentication failed';
      }
      debugPrint('!!! Firebase login error: ${e.code} - $errorMsg');
      return false;
    } catch (e) {
      debugPrint('!!! Login error: $e');
      return false;
    }
  }
  
  /// Create a new account with email and password
  Future<bool> signUp(String email, String password) async {
    if (email.isEmpty || password.isEmpty) return false;
    
    try {
      // Check if email is in approved list before allowing registration
      final isApproved = await _approvalService.isEmailApproved(email);
      if (!isApproved) {
        debugPrint('!!! Email not approved for registration: $email');
        throw FirebaseAuthException(
          code: 'email-not-approved',
          message: 'This email is not approved for registration'
        );
      }
      
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final user = userCredential.user;
      debugPrint('>>> User signed up: ${user?.uid}, email: ${user?.email}');
      return user != null;
    } on FirebaseAuthException catch (e) {
      String errorMsg;
      switch (e.code) {
        case 'email-not-approved':
          errorMsg = 'This email is not approved for registration';
          break;
        case 'email-already-in-use':
          errorMsg = 'This email is already registered';
          break;
        case 'invalid-email':
          errorMsg = 'Invalid email format';
          break;
        case 'weak-password':
          errorMsg = 'Password is too weak';
          break;
        case 'operation-not-allowed':
          errorMsg = 'Email/password accounts are not enabled';
          break;
        default:
          errorMsg = 'Registration failed';
      }
      debugPrint('!!! Firebase signup error: ${e.code} - $errorMsg');
      return false;
    } catch (e) {
      debugPrint('!!! Signup error: $e');
      return false;
    }
  }
  
  /// Log out the current user
  Future<void> logout() async {
    try {
      await _auth.signOut();
      debugPrint('>>> User logged out');
    } catch (e) {
      debugPrint('!!! Logout error: $e');
    }
  }
  
  /// Clean up resources
  Future<void> dispose() async {
    await _authStateController.close();
  }
}
