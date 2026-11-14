import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartnps360/src/screens/models/application_models.dart';

/// Storage service for persisting user accounts and application data locally
/// Mirrors the JavaScript localStorage functionality from the HTML app
class StorageService {
  static const String _storageKey = 'nps_registration_portal_v3';
  static const String _lastUserKey = 'nps_registration_last_user';

  /// Load all users from local storage
  Future<Map<String, UserAccount>> loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);

    if (jsonString == null || jsonString.isEmpty) {
      return {};
    }

    try {
      final Map<String, dynamic> data = json.decode(jsonString);
      final Map<String, dynamic> usersMap = data['users'] ?? {};

      return usersMap.map(
        (key, value) => MapEntry(key, UserAccount.fromJson(value)),
      );
    } catch (e) {
      debugPrint('Error loading users: $e');
      return {};
    }
  }

  /// Save all users to local storage
  Future<void> saveUsers(Map<String, UserAccount> users) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'users': users.map((key, value) => MapEntry(key, value.toJson())),
    };
    await prefs.setString(_storageKey, json.encode(data));
  }

  /// Get the last logged in user ID
  Future<String?> getLastUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUserKey);
  }

  /// Set the last logged in user ID
  Future<void> setLastUserId(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) {
      await prefs.remove(_lastUserKey);
    } else {
      await prefs.setString(_lastUserKey, userId);
    }
  }

  /// Clear all data (for testing/reset purposes)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_lastUserKey);
  }

  /// Generate a unique user ID
  String generateUserId() {
    return 'u_${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      length,
      (index) =>
          chars[(DateTime.now().microsecondsSinceEpoch + index) % chars.length],
    ).join();
  }
}
