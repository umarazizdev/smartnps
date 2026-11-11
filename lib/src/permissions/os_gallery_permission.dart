import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class OsGalleryPermission {
  OsGalleryPermission._();

  static int? _androidSdkInt;

  static Future<int> _androidSdk() async {
    return _androidSdkInt ??=
        (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  }

  static Future<List<Permission>> permissions() async {
    if (Platform.isIOS) {
      return const [Permission.photos];
    }
    if (!Platform.isAndroid) {
      return const [];
    }
    if (await _androidSdk() >= 33) {
      return const [];
    }
    return const [Permission.storage];
  }

  static bool _isOk(PermissionStatus status) {
    return status.isGranted || status.isLimited;
  }

  static Future<bool> isGranted() async {
    final perms = await permissions();
    if (perms.isEmpty) return true;
    for (final permission in perms) {
      if (_isOk(await permission.status)) return true;
    }
    return false;
  }

  static Future<PermissionStatus> request() async {
    final perms = await permissions();
    if (perms.isEmpty) return PermissionStatus.granted;

    final pending = <Permission>[];
    PermissionStatus? firstDenied;
    for (final permission in perms) {
      final status = await permission.status;
      if (_isOk(status)) return status;
      firstDenied ??= status;
      pending.add(permission);
    }
    if (pending.isEmpty) {
      return firstDenied ?? PermissionStatus.denied;
    }

    Map<Permission, PermissionStatus> statuses;
    try {
      statuses = await pending.request();
    } on Exception catch (error) {
      if (!error.toString().contains('ALREADY_REQUESTING_PERMISSIONS')) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      statuses = {
        for (final permission in perms) permission: await permission.status,
      };
    }

    for (final status in statuses.values) {
      if (_isOk(status)) return status;
    }
    for (final status in statuses.values) {
      if (status.isPermanentlyDenied) return status;
    }
    return statuses.values.isNotEmpty
        ? statuses.values.first
        : PermissionStatus.denied;
  }
}
