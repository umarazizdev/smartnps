import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Apple DeviceCheck token generation (iOS only).
class DeviceCheckService {
  DeviceCheckService._();

  static const MethodChannel _channel = MethodChannel(
    'com.smartnps360.app/device_check',
  );

  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DeviceCheck] isSupported failed: $e');
      }
      return false;
    }
  }

  static Future<String?> generateToken() async {
    if (!Platform.isIOS) return null;
    if (!await isSupported()) return null;

    try {
      final token = await _channel.invokeMethod<String>('generateToken');
      if (token == null || token.trim().isEmpty) return null;
      return token.trim();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DeviceCheck] generateToken failed: $e');
      }
      return null;
    }
  }

  /// Fields merged into auth requests that support DeviceCheck validation.
  static Future<Map<String, dynamic>> authPayloadExtras() async {
    final token = await generateToken();
    if (token == null) return const {};
    return {'device_check_token': token};
  }

  /// Back-compat alias for login payloads.
  static Future<Map<String, dynamic>> loginPayloadExtras() =>
      authPayloadExtras();
}
