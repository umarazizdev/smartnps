import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class BackgroundLocationPermissions {
  static Future<Map<String, dynamic>> statusSnapshot() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final geolocatorPermission = await Geolocator.checkPermission();

    return {
      'serviceEnabled': serviceEnabled,
      'geolocatorPermission': geolocatorPermission.name,
      if (Platform.isAndroid) ...{
        'foreground': (await Permission.location.status).toString(),
        'background': (await Permission.locationAlways.status).toString(),
        'notification': (await Permission.notification.status).toString(),
      },
      if (Platform.isIOS) ...{
        'whenInUse': (await Permission.locationWhenInUse.status).toString(),
        'always': (await Permission.locationAlways.status).toString(),
        'notification': (await Permission.notification.status).toString(),
      },
    };
  }

  static Future<bool> ensureGranted() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    if (Platform.isAndroid) {
      // Android background location requires foreground location first.
      final fgBefore = await Permission.location.status;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackgroundLocationPermissions] android fg(before)=$fgBefore');
      }
      final fg = fgBefore.isGranted
          ? fgBefore
          : await Permission.location.request();
      if (!fg.isGranted) return false;
      if (!fgBefore.isGranted) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      final notificationBefore = await Permission.notification.status;
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[BackgroundLocationPermissions] android notification(before)=$notificationBefore',
        );
      }
      if (!notificationBefore.isGranted) {
        final notification = await Permission.notification.request();
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[BackgroundLocationPermissions] android notification(after)=$notification',
          );
        }
      }

      // Android background needs an explicit "Allow all the time" grant.
      final bgBefore = await Permission.locationAlways.status;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackgroundLocationPermissions] android bg(before)=$bgBefore');
      }
      final bg = bgBefore.isGranted
          ? bgBefore
          : await Permission.locationAlways.request();
      if (kDebugMode) {
        // ignore: avoid_print
        print('[BackgroundLocationPermissions] android bg(after)=$bg');
      }
      if (bg.isGranted) return true;

      // Keep starting the foreground location service after foreground location
      // is granted. The persistent notification makes active tracking visible,
      // and the settings screen lets the user upgrade to "Allow all the time".
      return true;
    }

    if (Platform.isIOS) {
      var whenInUse = await Permission.locationWhenInUse.status;
      if (!whenInUse.isGranted) {
        whenInUse = await Permission.locationWhenInUse.request();
      }

      if (!whenInUse.isGranted) {
        return false;
      }

      final notification = await Permission.notification.status;
      if (!notification.isGranted) {
        await Permission.notification.request();
      }

      var always = await Permission.locationAlways.status;
      if (!always.isGranted) {
        always = await Permission.locationAlways.request();
      }

      return always.isGranted;
    }

    return true;
  }
}
