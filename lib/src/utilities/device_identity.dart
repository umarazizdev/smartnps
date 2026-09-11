import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceIdentity {
  DeviceIdentity._();

  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

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

  static Future<String?> getDeviceName() async {
    final cached = _cachedDeviceName;
    if (cached != null && cached.isNotEmpty) return cached;

    final info = DeviceInfoPlugin();
    final String? name;
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      final brand = android.brand.trim();
      final model = android.model.trim();
      name = [brand, model].where((part) => part.isNotEmpty).join(' ');
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      name = ios.name.trim();
    } else {
      name = null;
    }

    if (name != null && name.isNotEmpty) {
      _cachedDeviceName = name;
    }
    return name;
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
