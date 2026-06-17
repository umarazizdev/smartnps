import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_repository.dart';

/// Store-safe location disclosure consent scoped to each officer account.
///
/// Google Play and Apple require disclosure before the first background location
/// request for each user of the app. Persist acceptance per officer id so a
/// different login on the same device sees disclosure again.
class LocationDisclosureConsent {
  LocationDisclosureConsent._();

  static const _storage = FlutterSecureStorage();
  static const _kRecords = 'location.disclosure.records.v1';
  static const _kLastOfficerId = 'location.disclosure.last_officer_id';
  static const _kPendingAccept = 'location.disclosure.pending_accept';
  static const _legacyDutyState = 'duty.disclosure_state';
  static const _legacyClockInState = 'clockin.disclosure_state';

  static const String accepted = 'accepted';
  static const String dismissed = 'dismissed';

  static const _dutyScope = 'duty';
  static const _clockInScope = 'clockin';

  static String? _activeOfficerId;

  static String? get activeOfficerId => _activeOfficerId;

  static Future<bool> hasAccepted() async {
    return await isDutyAccepted() || await isClockInAccepted();
  }

  /// True when the in-app disclosure must still be shown for this officer.
  static Future<bool> shouldShowLocationDisclosure() async {
    return !await hasAccepted();
  }

  static Future<bool> isDutyAccepted() async {
    return (await _readScopeState(_dutyScope)) == accepted;
  }

  static Future<bool> isClockInAccepted() async {
    return (await _readScopeState(_clockInScope)) == accepted;
  }

  static Future<void> markDutyAccepted() async {
    await _writeScopeState(_dutyScope, accepted);
  }

  static Future<void> markClockInAccepted() async {
    await _writeScopeState(_clockInScope, accepted);
  }

  static Future<void> markAcceptedForAll() async {
    final officerId = await _resolveOfficerId();
    if (officerId == null) {
      await _storage.write(key: _kPendingAccept, value: '1');
      if (kDebugMode) {
        debugPrint(
          '[LocationDisclosureConsent] queued pending accept (no officer id yet)',
        );
      }
      return;
    }
    await _storage.delete(key: _kPendingAccept);
    await markDutyAccepted();
    await markClockInAccepted();
  }

  /// Returns true only when switching from one officer account to another.
  static Future<bool> resolveActiveOfficerAccount() async {
    await _applyPendingAcceptIfNeeded();
    await _migrateLegacyIfNeeded();

    final officerId = await AuthRepository.instance.getOfficerAccountId();
    if (officerId == null || officerId.isEmpty) return false;
    if (_activeOfficerId == officerId) return false;

    final storedLast = await _storage.read(key: _kLastOfficerId);
    final previous =
        (_activeOfficerId != null && _activeOfficerId!.isNotEmpty)
            ? _activeOfficerId
            : storedLast;

    _activeOfficerId = officerId;
    await _storage.write(key: _kLastOfficerId, value: officerId);

    if (previous == null || previous.isEmpty || previous == officerId) {
      return false;
    }

    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] officer account switched '
        'from=$previous to=$officerId',
      );
    }
    return true;
  }

  static void clearActiveOfficerAccount() {
    _activeOfficerId = null;
  }

  static Future<String?> _readScopeState(String scope) async {
    await _migrateLegacyIfNeeded();
    final officerId = await _resolveOfficerId();
    if (officerId == null) return null;

    final records = await _loadRecords();
    final officerRecord = records[officerId];
    if (officerRecord is! Map) return null;
    final state = officerRecord[scope]?.toString();
    if (state == accepted || state == dismissed) return state;
    return null;
  }

  static Future<void> _writeScopeState(String scope, String state) async {
    await _migrateLegacyIfNeeded();
    final officerId = await _resolveOfficerId();
    if (officerId == null) {
      if (kDebugMode) {
        debugPrint(
          '[LocationDisclosureConsent] skip persist scope=$scope (no officer id)',
        );
      }
      return;
    }

    final records = await _loadRecords();
    final officerRecord = Map<String, dynamic>.from(
      records[officerId] is Map
          ? Map<String, dynamic>.from(records[officerId] as Map)
          : {},
    );
    officerRecord[scope] = state;
    records[officerId] = officerRecord;
    await _saveRecords(records);
    _activeOfficerId = officerId;

    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] stored scope=$scope state=$state '
        'officerId=$officerId',
      );
    }
  }

  static Future<String?> _resolveOfficerId() async {
    if (_activeOfficerId != null && _activeOfficerId!.isNotEmpty) {
      return _activeOfficerId;
    }
    final officerId = await AuthRepository.instance.getOfficerAccountId();
    _activeOfficerId = officerId;
    return officerId;
  }

  static Future<Map<String, dynamic>> _loadRecords() async {
    final raw = await _storage.read(key: _kRecords);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[LocationDisclosureConsent] corrupt records: $error');
      }
    }
    return {};
  }

  static Future<void> _saveRecords(Map<String, dynamic> records) async {
    await _storage.write(key: _kRecords, value: jsonEncode(records));
  }

  static Future<void> _applyPendingAcceptIfNeeded() async {
    if ((await _storage.read(key: _kPendingAccept)) != '1') return;

    final officerId = await AuthRepository.instance.getOfficerAccountId();
    if (officerId == null || officerId.isEmpty) return;

    await _storage.delete(key: _kPendingAccept);
    await markDutyAccepted();
    await markClockInAccepted();

    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] applied pending accept for officerId=$officerId',
      );
    }
  }

  static Future<void> _migrateLegacyIfNeeded() async {
    final legacyDuty = await _storage.read(key: _legacyDutyState);
    final legacyClockIn = await _storage.read(key: _legacyClockInState);
    if (legacyDuty == null && legacyClockIn == null) return;

    final officerId = await AuthRepository.instance.getOfficerAccountId();
    if (officerId == null) return;

    final records = await _loadRecords();
    final officerRecord = Map<String, dynamic>.from(
      records[officerId] is Map
          ? Map<String, dynamic>.from(records[officerId] as Map)
          : {},
    );

    if (legacyDuty != null &&
        legacyDuty.isNotEmpty &&
        officerRecord[_dutyScope] == null) {
      officerRecord[_dutyScope] = legacyDuty;
    }
    if (legacyClockIn != null &&
        legacyClockIn.isNotEmpty &&
        officerRecord[_clockInScope] == null) {
      officerRecord[_clockInScope] = legacyClockIn;
    }

    records[officerId] = officerRecord;
    await _saveRecords(records);
    await _storage.delete(key: _legacyDutyState);
    await _storage.delete(key: _legacyClockInState);

    if (kDebugMode) {
      debugPrint(
        '[LocationDisclosureConsent] migrated legacy disclosure for officerId=$officerId',
      );
    }
  }
}
