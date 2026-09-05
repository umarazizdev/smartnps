import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/auth_repository.dart';
import 'android_duty_kill_watch.dart';

class DutyStatusSnapshot {
  DutyStatusSnapshot._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'duty.status.snapshot.v1';

  static const Duration ttl = Duration(minutes: 30);

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

    await _storage.write(key: _key, value: jsonEncode(payload));
    // Arm once per session; repeated markOnDuty only refreshes tokens quietly.
    if (await AndroidDutyKillWatch.isKillWatchArmed()) {
      await AndroidDutyKillWatch.syncTokens();
    } else {
      await AndroidDutyKillWatch.arm();
    }
  }

  static Future<bool> renewIfStillOnDuty() async {
    final userId = await AuthRepository.instance.getOfficerAccountId();
    if (userId == null || userId.isEmpty) return false;

    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return false;
    }

    try {
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

      final stillThere = await _storage.read(key: _key);
      if (stillThere == null || stillThere.isEmpty) return false;

      final payload = <String, dynamic>{
        'userId': userId,
        'status': 'on_duty',
        'updatedAt': now.toIso8601String(),
        'expiresAt': now.add(ttl).toIso8601String(),
      };
      await _storage.write(key: _key, value: jsonEncode(payload));
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
    await _storage.delete(key: _key);
  }

  static Future<bool> isValidOnDutyForCurrentUser() async {
    final userId = await AuthRepository.instance.getOfficerAccountId();
    if (userId == null || userId.isEmpty) return false;

    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return false;

    try {
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

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyStatusSnapshot] parse failed: $e');
      }
      await clear();
      return false;
    }
  }
}
