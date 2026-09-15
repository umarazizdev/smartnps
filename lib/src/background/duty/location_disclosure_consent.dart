import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utilities/secure_storage_access.dart';
import '../location/background_location_permissions.dart';

class LocationDisclosureConsent {
  LocationDisclosureConsent._();

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
    return (await SecureStorageAccess.read(_kDutyState)) == accepted;
  }

  static Future<bool> isClockInAccepted() async {
    await ensureMigrated();
    return (await SecureStorageAccess.read(_kClockInState)) == accepted;
  }

  static Future<void> markDutyAccepted() async {
    await ensureMigrated();
    if (await isDutyAccepted()) return;
    await SecureStorageAccess.write(_kDutyState, accepted);
    if (kDebugMode) {
      debugPrint('[LocationDisclosureConsent] stored duty=accepted (device-wide)');
    }
  }

  static Future<void> markClockInAccepted() async {
    await ensureMigrated();
    if (await isClockInAccepted()) return;
    await SecureStorageAccess.write(_kClockInState, accepted);
    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] stored clockin=accepted (device-wide)',
      );
    }
  }

  static Future<void> markAcceptedForAll() async {
    final dutyAccepted = await isDutyAccepted();
    final clockInAccepted = await isClockInAccepted();
    if (dutyAccepted && clockInAccepted) return;
    if (!dutyAccepted) {
      await markDutyAccepted();
    }
    if (!clockInAccepted) {
      await markClockInAccepted();
    }
  }

  static Future<void> reconcileFromOsIfBackgroundReady() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await ensureMigrated();
    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    if (!await BackgroundLocationPermissions.isClockInBackgroundReady()) {
      return;
    }
    if (await isDutyAccepted() || await isClockInAccepted()) return;

    await SecureStorageAccess.write(_kDutyState, accepted);
    await SecureStorageAccess.write(_kClockInState, accepted);
    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] reconciled disclosure from OS background grant',
      );
    }
  }

  static Future<void> ensureMigrated() async {
    if (_migrationComplete) return;

    try {
      await _migrateLegacyFlatKeysIfNeeded();
      await _migrateLegacyPerAccountRecordsIfNeeded();
      await SecureStorageAccess.delete(_kLegacyLastOfficerId);
      await SecureStorageAccess.delete(_kLegacyPendingAccept);
      await SecureStorageAccess.delete(_kLegacyRecords);
      _migrationComplete = true;
    } on PlatformException catch (e) {
      if (SecureStorageAccess.isInteractionNotAllowed(e)) {
        if (kDebugMode) {
          debugPrint(
            '[LocationDisclosureConsent] migration deferred; '
            'keychain interaction not allowed',
          );
        }
        return;
      }
      rethrow;
    }
  }

  static Future<void> _migrateLegacyFlatKeysIfNeeded() async {
    final legacyDuty = await SecureStorageAccess.read(_legacyDutyState);
    final legacyClockIn = await SecureStorageAccess.read(_legacyClockInState);
    final currentDuty = await SecureStorageAccess.read(_kDutyState);
    final currentClockIn = await SecureStorageAccess.read(_kClockInState);

    if (legacyDuty == accepted && currentDuty != accepted) {
      await SecureStorageAccess.write(_kDutyState, accepted);
    }
    if (legacyClockIn == accepted && currentClockIn != accepted) {
      await SecureStorageAccess.write(_kClockInState, accepted);
    }

    if (legacyDuty != null) {
      await SecureStorageAccess.delete(_legacyDutyState);
    }
    if (legacyClockIn != null) {
      await SecureStorageAccess.delete(_legacyClockInState);
    }
  }

  static Future<void> _migrateLegacyPerAccountRecordsIfNeeded() async {
    final currentDuty = await SecureStorageAccess.read(_kDutyState);
    final currentClockIn = await SecureStorageAccess.read(_kClockInState);
    if (currentDuty == accepted || currentClockIn == accepted) return;

    final raw = await SecureStorageAccess.read(_kLegacyRecords);
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
          await SecureStorageAccess.write(_kDutyState, accepted);
          await SecureStorageAccess.write(_kClockInState, accepted);
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
