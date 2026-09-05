import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_repository.dart';
import '../../utilities/app_debug_log.dart';

/// Arms native Android keep-alive for when the UI is killed.
///
/// While the Flutter UI is open, [BackgroundLocationController.ensureStarted]
/// owns starting the location FGS. Native code only restarts/stops that same
/// FGS after the UI has been away long enough (real kill), not during brief
/// Settings jumps.
class AndroidDutyKillWatch {
  AndroidDutyKillWatch._();

  static const MethodChannel _channel = MethodChannel(
    'com.smartnps360.app/android_duty_kill',
  );

  static const forceOffKey = 'android_duty.kill.force_off';
  static const armedKey = 'android_duty.kill.armed';
  static const apiOnDutyUntilKey = 'android_duty.kill.api_on_duty_until';
  static const unpaidBreakKey = 'android_duty.kill.unpaid_break';

  static String? _lastArmedAccessToken;
  static Future<void>? _armInFlight;

  /// Full arm once per on-duty session; later calls only refresh tokens.
  static Future<void> arm() async {
    if (!Platform.isAndroid) return;
    final inFlight = _armInFlight;
    if (inFlight != null) return inFlight;

    final future = _armImpl();
    _armInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_armInFlight, future)) {
        _armInFlight = null;
      }
    }
  }

  static Future<void> _armImpl() async {
    await _writeForceOff(false);
    await _writeArmed(true);
    final access = await AuthRepository.instance.getAccessToken();
    final refresh = await AuthRepository.instance.getRefreshToken();
    if (access == null || access.isEmpty) return;

    final alreadyArmed = await isKillWatchArmed();
    if (alreadyArmed && _lastArmedAccessToken == access) {
      await syncTokens();
      return;
    }

    try {
      await _channel.invokeMethod<void>('arm', {
        'accessToken': access,
        'refreshToken': refresh,
      });
      _lastArmedAccessToken = access;
    } on MissingPluginException {
      locationDebugLog('[AndroidDutyKill] arm skipped; native plugin missing');
    } catch (e) {
      locationDebugLog('[AndroidDutyKill] arm failed: $e');
    }
  }

  static Future<void> setUnpaidBreak(bool unpaid) async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(unpaidBreakKey, unpaid);
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('setUnpaidBreak', {'unpaid': unpaid});
    } on MissingPluginException {
    } catch (e) {
      locationDebugLog('[AndroidDutyKill] setUnpaidBreak failed: $e');
    }
  }

  static Future<bool> isUnpaidBreak() async {
    if (!Platform.isAndroid) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(unpaidBreakKey) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> disarm({bool forceOff = false}) async {
    if (!Platform.isAndroid) return;
    _lastArmedAccessToken = null;
    await _writeArmed(false);
    await _writeUnpaidBreak(false);
    if (forceOff) {
      await _writeForceOff(true);
    }
    try {
      await _channel.invokeMethod<void>('disarm', {'forceOff': forceOff});
    } on MissingPluginException {
      // FGS isolate has no UI plugin; prefs + native alarm still see force_off.
    } catch (e) {
      locationDebugLog('[AndroidDutyKill] disarm failed: $e');
    }
  }

  static Future<void> syncTokens() async {
    if (!Platform.isAndroid) return;
    final access = await AuthRepository.instance.getAccessToken();
    final refresh = await AuthRepository.instance.getRefreshToken();
    if (access == null || access.isEmpty) {
      await disarm();
      return;
    }
    try {
      await _channel.invokeMethod<void>('syncSession', {
        'accessToken': access,
        'refreshToken': refresh,
      });
      _lastArmedAccessToken = access;
    } on MissingPluginException {
      // UI isolate owns token sync.
    } catch (e) {
      locationDebugLog('[AndroidDutyKill] syncSession failed: $e');
    }
  }

  static Future<bool> isForceOff() async {
    if (!Platform.isAndroid) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(forceOffKey) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isKillWatchArmed() async {
    if (!Platform.isAndroid) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(forceOffKey) == true) return false;
      return prefs.getBool(armedKey) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isNativeApiOnDutyFresh() async {
    if (!Platform.isAndroid) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(apiOnDutyUntilKey);
      final until = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
      if (until <= 0) return false;
      return DateTime.now().millisecondsSinceEpoch < until;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _writeArmed(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(armedKey, value);
    } catch (_) {}
  }

  static Future<void> _writeUnpaidBreak(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(unpaidBreakKey, value);
    } catch (_) {}
  }

  static Future<void> _writeForceOff(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(forceOffKey, value);
      if (!value) {
        await prefs.remove(apiOnDutyUntilKey);
      }
    } catch (_) {}
  }
}
