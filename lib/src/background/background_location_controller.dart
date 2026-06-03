import 'package:flutter_background_service/flutter_background_service.dart';

import 'background_location_permissions.dart';
import 'background_location_service.dart';

class BackgroundLocationController {
  BackgroundLocationController._();

  static Future<Map<String, dynamic>> ensureStarted() async {
    try {
      final service = FlutterBackgroundService();
      final bool alreadyRunning = await service.isRunning();
      if (alreadyRunning) {
        return {'ok': true, 'started': false, 'running': true};
      }

      final granted = await BackgroundLocationPermissions.ensureGranted();
      if (!granted) {
        return {
          'ok': false,
          'permissions': await BackgroundLocationPermissions.statusSnapshot(),
          'error': {
            'code': 'permission_denied',
            'message': 'Background location permission not granted',
          },
        };
      }

      await BackgroundLocationService.configureAndStart();
      return {
        'ok': true,
        'started': true,
        'running': true,
        'permissions': await BackgroundLocationPermissions.statusSnapshot(),
      };
    } catch (e) {
      return {
        'ok': false,
        'permissions': await BackgroundLocationPermissions.statusSnapshot(),
        'error': {'code': 'start_failed', 'message': e.toString()},
      };
    }
  }

  static Future<Map<String, dynamic>> stop() async {
    try {
      final service = FlutterBackgroundService();
      final bool running = await service.isRunning();
      if (!running) {
        return {'ok': true, 'stopped': false, 'running': false};
      }
      service.invoke('stop');
      return {'ok': true, 'stopped': true, 'running': false};
    } catch (e) {
      return {
        'ok': false,
        'error': {'code': 'stop_failed', 'message': e.toString()},
      };
    }
  }
}
