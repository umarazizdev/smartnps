import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/auth_repository.dart';

class DutyStatusSnapshot {
  DutyStatusSnapshot._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'duty.status.snapshot.v1';

  /// Heartbeat / FGS renew window. FGS renews this while still on_duty so the
  /// UI isolate being frozen in background cannot expire the gate.
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
    if (kDebugMode) {
      debugPrint(
        '[DutyStatusSnapshot] marked on_duty user=$userId '
        'ttl=${ttl.inMinutes}m',
      );
    }
  }

  /// Extends TTL only when an on_duty snapshot already exists for this user.
  ///
  /// Never recreates after [clear] (off_duty / logout). Safe to call from the
  /// Android FGS isolate while the UI heartbeat is frozen.
  static Future<bool> renewIfStillOnDuty() async {
    final userId = await AuthRepository.instance.getOfficerAccountId();
    if (userId == null || userId.isEmpty) return false;

    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      // Cleared ⇒ off_duty / logout. Do not recreate.
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

      // Only renew a still-valid (or barely-expired) live session. Fully
      // expired + cleared gates are handled by [isValidOnDutyForCurrentUser].
      final now = DateTime.now().toUtc();
      final grace = const Duration(minutes: 2);
      if (expiresAt.add(grace).isBefore(now)) {
        return false;
      }

      // Re-check key still present to reduce clear→recreate races.
      final stillThere = await _storage.read(key: _key);
      if (stillThere == null || stillThere.isEmpty) return false;

      final payload = <String, dynamic>{
        'userId': userId,
        'status': 'on_duty',
        'updatedAt': now.toIso8601String(),
        'expiresAt': now.add(ttl).toIso8601String(),
      };
      await _storage.write(key: _key, value: jsonEncode(payload));
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
    if (kDebugMode) {
      debugPrint('[DutyStatusSnapshot] cleared');
    }
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
