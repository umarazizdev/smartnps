import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'background_location_permissions.dart';

class LocationDisclosureConsent {
  LocationDisclosureConsent._();

  static const _storage = FlutterSecureStorage();

  static const _kDutyState = 'location.disclosure.duty.v2';
  static const _kClockInState = 'location.disclosure.clockin.v2';

  static const _kLegacyRecords = 'location.disclosure.records.v1';
  static const _kLegacyLastOfficerId = 'location.disclosure.last_officer_id';
  static const _kLegacyPendingAccept = 'location.disclosure.pending_accept';
  static const _legacyDutyState = 'duty.disclosure_state';
  static const _legacyClockInState = 'clockin.disclosure_state';

  static const String accepted = 'accepted';
  static const String dismissed = 'dismissed';

  static bool _migrationComplete = false;

  static Future<bool> hasAccepted() async {
    await ensureMigrated();
    return await isDutyAccepted() || await isClockInAccepted();
  }

  static Future<bool> shouldShowLocationDisclosure() async {
    return !await hasAccepted();
  }

  static Future<bool> isDutyAccepted() async {
    await ensureMigrated();
    return (await _storage.read(key: _kDutyState)) == accepted;
  }

  static Future<bool> isClockInAccepted() async {
    await ensureMigrated();
    return (await _storage.read(key: _kClockInState)) == accepted;
  }

  static Future<void> markDutyAccepted() async {
    await ensureMigrated();
    await _storage.write(key: _kDutyState, value: accepted);
    if (kDebugMode) {
      debugPrint('[LocationDisclosureConsent] stored duty=accepted (device-wide)');
    }
  }

  static Future<void> markClockInAccepted() async {
    await ensureMigrated();
    await _storage.write(key: _kClockInState, value: accepted);
    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] stored clockin=accepted (device-wide)',
      );
    }
  }

  static Future<void> markAcceptedForAll() async {
    await markDutyAccepted();
    await markClockInAccepted();
  }

  static Future<void> reconcileFromOsIfBackgroundReady() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await ensureMigrated();
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
      return;
    }
    if (await isDutyAccepted() || await isClockInAccepted()) return;

    await _storage.write(key: _kDutyState, value: accepted);
    await _storage.write(key: _kClockInState, value: accepted);
    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] reconciled disclosure from OS background grant',
      );
    }
  }

  static Future<void> ensureMigrated() async {
    if (_migrationComplete) return;

    await _migrateLegacyFlatKeysIfNeeded();
    await _migrateLegacyPerAccountRecordsIfNeeded();
    await _storage.delete(key: _kLegacyLastOfficerId);
    await _storage.delete(key: _kLegacyPendingAccept);
    await _storage.delete(key: _kLegacyRecords);

    _migrationComplete = true;
  }

  static Future<void> _migrateLegacyFlatKeysIfNeeded() async {
    final legacyDuty = await _storage.read(key: _legacyDutyState);
    final legacyClockIn = await _storage.read(key: _legacyClockInState);
    final currentDuty = await _storage.read(key: _kDutyState);
    final currentClockIn = await _storage.read(key: _kClockInState);

    if (legacyDuty == accepted && currentDuty != accepted) {
      await _storage.write(key: _kDutyState, value: accepted);
    }
    if (legacyClockIn == accepted && currentClockIn != accepted) {
      await _storage.write(key: _kClockInState, value: accepted);
    }

    if (legacyDuty != null) {
      await _storage.delete(key: _legacyDutyState);
    }
    if (legacyClockIn != null) {
      await _storage.delete(key: _legacyClockInState);
    }
  }

  static Future<void> _migrateLegacyPerAccountRecordsIfNeeded() async {
    final currentDuty = await _storage.read(key: _kDutyState);
    final currentClockIn = await _storage.read(key: _kClockInState);
    if (currentDuty == accepted || currentClockIn == accepted) return;

    final raw = await _storage.read(key: _kLegacyRecords);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final record = Map<String, dynamic>.from(entry.value as Map);
        final duty = record['duty']?.toString();
        final clockIn = record['clockin']?.toString();
        if (duty == accepted || clockIn == accepted) {
          await _storage.write(key: _kDutyState, value: accepted);
          await _storage.write(key: _kClockInState, value: accepted);
          if (kDebugMode) {
            debugPrint(
              '[LocationDisclosureConsent] migrated per-account acceptance '
              'to device-wide (officerId=${entry.key})',
            );
          }
          return;
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[LocationDisclosureConsent] legacy per-account migration failed: $error',
        );
      }
    }
  }
}
