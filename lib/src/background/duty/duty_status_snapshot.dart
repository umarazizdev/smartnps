import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/auth_repository.dart';
import 'android_duty_kill_watch.dart';

class DutyStatusSnapshot {
  DutyStatusSnapshot._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _key = 'duty.status.snapshot.v1';

  static const Duration ttl = Duration(minutes: 30);

  static Map<String, dynamic>? _memoryCache;
  static bool _accessibilityMigrated = false;

  static Future<void> markOnDuty() async {
    final userId = await AuthRepository.instance.getOfficerAccountId();
    if (userId == null || userId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[DutyStatusSnapshot] skip markOnDuty; no officer account id',
        );
      }
      return;
    }

    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'userId': userId,
      'status': 'on_duty',
      'updatedAt': now.toIso8601String(),
      'expiresAt': now.add(ttl).toIso8601String(),
    };

    _memoryCache = payload;
    if (await _secureWrite(jsonEncode(payload))) {
      _accessibilityMigrated = true;
    }

    if (await AndroidDutyKillWatch.isKillWatchArmed()) {
      await AndroidDutyKillWatch.syncTokens();
    } else {
      await AndroidDutyKillWatch.arm();
    }
  }

  static Future<bool> renewIfStillOnDuty() async {
    try {
      final userId = await AuthRepository.instance.getOfficerAccountId();
      if (userId == null || userId.isEmpty) return false;

      final raw = await _secureRead();
      if (raw == null || raw.isEmpty) {
        return false;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final map = Map<String, dynamic>.from(decoded);
      if (map['status']?.toString() != 'on_duty') return false;
      if (map['userId']?.toString() != userId) return false;

      final expiresRaw = map['expiresAt']?.toString();
      final expiresAt = expiresRaw == null
          ? null
          : DateTime.tryParse(expiresRaw)?.toUtc();
      if (expiresAt == null) return false;

      final now = DateTime.now().toUtc();
      final grace = const Duration(minutes: 2);
      if (expiresAt.add(grace).isBefore(now)) {
        return false;
      }

      final stillThere = await _secureRead();
      if (stillThere == null || stillThere.isEmpty) return false;

      final payload = <String, dynamic>{
        'userId': userId,
        'status': 'on_duty',
        'updatedAt': now.toIso8601String(),
        'expiresAt': now.add(ttl).toIso8601String(),
      };
      _memoryCache = payload;
      if (await _secureWrite(jsonEncode(payload))) {
        _accessibilityMigrated = true;
      }
      await AndroidDutyKillWatch.syncTokens();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyStatusSnapshot] renew failed: $e');
      }
      return false;
    }
  }

  static Future<void> clear() async {
    _memoryCache = null;
    _accessibilityMigrated = false;
    await _secureDelete();
  }

  static Future<bool> isValidOnDutyForCurrentUser() async {
    try {
      final userId = await AuthRepository.instance.getOfficerAccountId();
      if (userId == null || userId.isEmpty) return false;

      final raw = await _secureRead();
      if (raw == null || raw.isEmpty) return false;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear();
        return false;
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['status']?.toString() != 'on_duty') {
        await clear();
        return false;
      }
      if (map['userId']?.toString() != userId) {
        if (kDebugMode) {
          debugPrint(
            '[DutyStatusSnapshot] rejected; user mismatch '
            'stored=${map['userId']} current=$userId',
          );
        }
        await clear();
        return false;
      }

      final expiresRaw = map['expiresAt']?.toString();
      final expiresAt = expiresRaw == null
          ? null
          : DateTime.tryParse(expiresRaw)?.toUtc();
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
        if (kDebugMode) {
          debugPrint('[DutyStatusSnapshot] rejected; expired');
        }
        await clear();
        return false;
      }

      _memoryCache = map;
      if (!_accessibilityMigrated && await _secureWrite(raw)) {
        _accessibilityMigrated = true;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyStatusSnapshot] isValid failed: $e');
      }
      return false;
    }
  }

  static Future<String?> _secureRead() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            _memoryCache = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
        return raw;
      }
      return null;
    } on PlatformException catch (e) {
      if (_isKeychainInteractionNotAllowed(e)) {
        final cached = _memoryCache;
        if (cached == null || cached.isEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[DutyStatusSnapshot] keychain locked; no memory cache',
            );
          }
          return null;
        }
        if (kDebugMode) {
          debugPrint(
            '[DutyStatusSnapshot] keychain locked; using memory cache',
          );
        }
        return jsonEncode(cached);
      }
      rethrow;
    }
  }

  static Future<bool> _secureWrite(String value) async {
    try {
      await _storage.write(key: _key, value: value);
      return true;
    } on PlatformException catch (e) {
      if (_isKeychainInteractionNotAllowed(e)) {
        if (kDebugMode) {
          debugPrint(
            '[DutyStatusSnapshot] write skipped; keychain interaction '
            'not allowed',
          );
        }
        return false;
      }
      rethrow;
    }
  }

  static Future<void> _secureDelete() async {
    try {
      await _storage.delete(key: _key);
    } on PlatformException catch (e) {
      if (_isKeychainInteractionNotAllowed(e)) {
        if (kDebugMode) {
          debugPrint(
            '[DutyStatusSnapshot] delete skipped; keychain interaction '
            'not allowed',
          );
        }
        return;
      }
      rethrow;
    }
  }

  static bool _isKeychainInteractionNotAllowed(PlatformException e) {
    final code = e.code.trim();
    if (code == '-25308') return true;

    final details = e.details?.toString() ?? '';
    return details.contains('-25308') ||
        (e.message?.contains('User interaction is not allowed') ?? false);
  }
}
