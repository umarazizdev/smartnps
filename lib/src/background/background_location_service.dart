import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../location/mock_location_detection.dart';
import '../auth/auth_repository.dart';
import 'background_location_uploader.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  static const String _channelId = 'smartnps360_location';
  static const int _notificationId = 9911;

  @pragma('vm:entry-point')
  static Future<void> configureAndStart() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        foregroundServiceNotificationId: _notificationId,
        notificationChannelId: _channelId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
        initialNotificationTitle: 'SmartNPS360',
        initialNotificationContent: 'Sharing live location',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        // iOS background execution is limited; this is best-effort.
        onBackground: _onIosBackground,
      ),
    );

    await service.startService();
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    // Keep this isolate minimal: permissions must already be granted by UI.
    final uploader = BackgroundLocationUploader();
    await uploader.init();
    uploader.start();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[BackgroundLocationService] started');
    }

    StreamSubscription<Position>? sub;
    var stopping = false;

    Future<void> stop() async {
      if (stopping) return;
      stopping = true;
      await sub?.cancel();
      sub = null;
      await uploader.stop();
      service.stopSelf();
    }

    service.on('stop').listen((event) {
      unawaited(stop());
    });

    // Fresh-only: we only upload from the live stream.
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            timeLimit: null,
            forceLocationManager: false,
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            timeLimit: null,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );

    DateTime? lastUploadAt;
    sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        if (stopping) return;

        final token = await AuthRepository.instance.getAccessToken();
        if (token == null || token.isEmpty) {
          await stop();
          return;
        }

        final now = DateTime.now();
        final last = lastUploadAt;
        if (last != null && now.difference(last) < const Duration(seconds: 1)) {
          return;
        }
        lastUploadAt = now;

        final mockFlags = MockLocationDetection.flagsFor(pos);
        if (mockFlags.isDetected) {
          service.invoke('mock_location', {
            'isMocked': mockFlags.isMocked,
            'isSimulatedBySoftware': mockFlags.isSimulatedBySoftware,
            'timestamp': pos.timestamp.toIso8601String(),
          });
        }

        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[BackgroundLocationService] location '
            'lat=${pos.latitude} lng=${pos.longitude} acc=${pos.accuracy} '
            'mocked=${mockFlags.isMocked} simulated=${mockFlags.isSimulatedBySoftware} '
            'ts=${pos.timestamp.toIso8601String()}',
          );
        }
        try {
          await uploader.pingNow(pos);
          await uploader.add(pos);
        } catch (e) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[BackgroundLocationService] upload failed: $e');
          }
        }
      },
      onError: (Object error) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[BackgroundLocationService] stream error: $error');
        }
      },
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    // Returning true tells iOS the callback completed successfully.
    return true;
  }
}
