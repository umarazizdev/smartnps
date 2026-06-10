import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceIdentity {
  DeviceIdentity._();

  static String? _cachedDeviceId;

  static Future<String> getDeviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null && cached.isNotEmpty) return cached;

    final info = DeviceInfoPlugin();
    final String id;
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      id = '${_slug(android.brand)}-${_slug(android.model)}-${android.id}';
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      id = 'ios-${ios.identifierForVendor ?? _slug(ios.utsname.machine)}';
    } else {
      id = Platform.operatingSystem;
    }

    _cachedDeviceId = id;
    return id;
  }

  static String platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  static String _slug(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
