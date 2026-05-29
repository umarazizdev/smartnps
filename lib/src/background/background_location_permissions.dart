import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class BackgroundLocationPermissions {
  static Future<bool> ensureGranted() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    if (Platform.isAndroid) {
      // Android background needs an explicit "Allow all the time" grant.
      final status = await Permission.locationAlways.request();
      return status.isGranted;
    }

    if (Platform.isIOS) {
      // For background, iOS needs "Always". Geolocator can only request; user may
      // still need to upgrade it from Settings depending on prior choice.
      final after = await Geolocator.checkPermission();
      return after == LocationPermission.always;
    }

    return true;
  }
}

