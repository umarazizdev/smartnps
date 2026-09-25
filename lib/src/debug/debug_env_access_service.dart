import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production-style debug-tools access via Firebase Remote Config.
///
/// Firebase console → Remote Config parameters:
/// - [keyEnabled] (`bool`) — master switch; `false` revokes access without a release
/// - [keyPinSha256] (`String`) — lowercase SHA-256 hex of the PIN (never plaintext)
///
/// Last good values are cached locally for short offline use after a fetch.
class DebugEnvAccessService {
  DebugEnvAccessService._();

  static final DebugEnvAccessService instance = DebugEnvAccessService._();

  static const String keyEnabled = 'debug_tools_enabled';
  static const String keyPinSha256 = 'debug_tools_pin_sha256';

  static const String _prefsEnabled = 'debug_tools_rc_enabled_v1';
  static const String _prefsPinHash = 'debug_tools_rc_pin_sha256_v1';

  /// Bootstrap hash = SHA-256("qwerty") until Remote Config overrides it.
  /// Rotate the PIN in Firebase as soon as possible.
  static const String bootstrapPinSha256 =
      '65e84be33532fb784c48129675f9eff3a682b27168c0ea744b2cf58ee02337c5';

  bool _ready = false;
  bool _enabled = true;
  String _pinSha256 = bootstrapPinSha256;

  bool get isReady => _ready;
  bool get isEnabled => _enabled;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _loadCache();
    _ready = true;
    // Best-effort; do not block app start on network.
    // ignore: unawaited_futures
    refresh(force: false);
  }

  Future<void> refresh({bool force = true}) async {
    try {
      final remote = FirebaseRemoteConfig.instance;
      await remote.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: force
              ? Duration.zero
              : const Duration(minutes: 30),
        ),
      );
      await remote.setDefaults(<String, dynamic>{
        keyEnabled: true,
        keyPinSha256: bootstrapPinSha256,
      });
      await remote.fetchAndActivate();

      _enabled = remote.getBool(keyEnabled);
      final hash = remote.getString(keyPinSha256).trim().toLowerCase();
      if (_looksLikeSha256(hash)) {
        _pinSha256 = hash;
      } else if (kDebugMode) {
        debugPrint(
          '[DebugEnvAccess] invalid $keyPinSha256; keeping cached hash',
        );
      }
      await _persistCache();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DebugEnvAccess] Remote Config refresh failed: $e');
      }
    }
  }

  /// True when tools are enabled and [pin] matches the configured hash.
  Future<DebugEnvAccessResult> verifyPin(String pin) async {
    await ensureReady();
    await refresh(force: true);
    if (!_enabled) {
      return DebugEnvAccessResult.disabled;
    }
    if (hashPin(pin) == _pinSha256) {
      return DebugEnvAccessResult.granted;
    }
    return DebugEnvAccessResult.denied;
  }

  static String hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  static bool _looksLikeSha256(String value) {
    return value.length == 64 && RegExp(r'^[a-f0-9]+$').hasMatch(value);
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsEnabled) ?? true;
      final cached = prefs.getString(_prefsPinHash)?.trim().toLowerCase();
      _pinSha256 = (cached != null && _looksLikeSha256(cached))
          ? cached
          : bootstrapPinSha256;
    } catch (_) {
      _enabled = true;
      _pinSha256 = bootstrapPinSha256;
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsEnabled, _enabled);
      await prefs.setString(_prefsPinHash, _pinSha256);
    } catch (_) {}
  }
}

enum DebugEnvAccessResult { granted, denied, disabled }
