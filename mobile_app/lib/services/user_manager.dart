import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages user authentication and participant ID storage.
/// Provides a simple, persistent user session.
class UserManager {
  // Singleton pattern
  static final UserManager _instance = UserManager._internal();
  factory UserManager() => _instance;
  UserManager._internal();
  
  // User state
  String? _participantId;
  bool _isAuthenticated = false;
  
  // Stream controller for auth state changes
  final _authStateController = StreamController<bool>.broadcast();
  
  /// Whether a user is currently authenticated
  bool get isAuthenticated => _isAuthenticated;
  
  /// The current participant ID (null if not authenticated)
  String? get participantId => _participantId;
  
  /// Stream of authentication state changes
  Stream<bool> get authStateChanges => _authStateController.stream;
  
  /// Initialize from stored preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _participantId = prefs.getString('participantId');
    _isAuthenticated = _participantId != null;
    
    // Notify listeners of initial state
    _authStateController.add(_isAuthenticated);
    
    debugPrint('>>> UserManager initialized: authenticated=$_isAuthenticated, id=$_participantId');
  }
  
  /// Log in with the specified participant ID
  Future<bool> login(String participantId) async {
    if (participantId.isEmpty) return false;
    
    try {
      // Save to persistent storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('participantId', participantId);
      
      // Update state
      _participantId = participantId;
      _isAuthenticated = true;
      _authStateController.add(true);
      
      debugPrint('>>> User logged in: $participantId');
      return true;
    } catch (e) {
      debugPrint('!!! Login error: $e');
      return false;
    }
  }
  
  /// Log out the current user
  Future<void> logout() async {
    try {
      // Clear from persistent storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('participantId');
      
      // Update state
      _participantId = null;
      _isAuthenticated = false;
      _authStateController.add(false);
      
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
