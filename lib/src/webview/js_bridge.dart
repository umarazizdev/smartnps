import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

class JsBridge {
  JsBridge({
    required this.getCurrentUrlHost,
    required this.onDownloadRequested,
  });

  final String? Function() getCurrentUrlHost;
  final Future<Map<String, dynamic>> Function(Uri url, {String? filename})
  onDownloadRequested;

  bool _isTrustedCaller() => AppConfig.isAllowedHost(getCurrentUrlHost());

  Map<String, dynamic> _deny([String message = 'Untrusted origin']) => {
    'ok': false,
    'error': {'code': 'untrusted_origin', 'message': message},
  };

  Map<String, dynamic> _ok([Map<String, dynamic>? data]) => {
    'ok': true,
    if (data != null) ...data,
  };

  Map<String, dynamic> _err(String code, String message) => {
    'ok': false,
    'error': {'code': code, 'message': message},
  };

  Future<Map<String, dynamic>> pickFile([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );
      final file = result?.files.singleOrNull;
      if (file == null || file.path == null) return _ok({'canceled': true});
      return _ok({
        'canceled': false,
        'file': {
          'path': file.path,
          'name': file.name,
          'size': file.size,
          'extension': file.extension,
        },
      });
    } catch (e) {
      return _err('pick_file_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> pickImage([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final status = await Permission.photos.request();
      if (!status.isGranted && Platform.isIOS) {
        return _err('permission_denied', 'Photos permission denied');
      }
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return _ok({'canceled': true});
      return _ok({
        'canceled': false,
        'image': {'path': image.path, 'name': image.name},
      });
    } catch (e) {
      return _err('pick_image_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> takePhoto([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        return _err('permission_denied', 'Camera permission denied');
      }
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo == null) return _ok({'canceled': true});
      return _ok({
        'canceled': false,
        'photo': {'path': photo.path, 'name': photo.name},
      });
    } catch (e) {
      return _err('take_photo_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> getCurrentLocation([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();

    StreamSubscription<Position>? subscription;

    double maxAllowedAccuracyMeters = 15.0;

    try {
      final Map? argsMap = args is Map ? args : null;
      final dynamic rawOptions = argsMap == null ? null : argsMap['options'];
      final Map? options = rawOptions is Map ? rawOptions : null;

      final int? timeoutMs =
          options != null && options['timeout_ms'] is num
              ? (options['timeout_ms'] as num).toInt()
              : null;
      final double? requiredAccuracyMeters =
          options != null && options['required_accuracy_meters'] is num
              ? (options['required_accuracy_meters'] as num).toDouble()
              : null;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return _err(
          'location_services_disabled',
          'Location services are disabled',
        );
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return _err('permission_denied', 'Location permission denied');
      }

      if (permission == LocationPermission.deniedForever) {
        return _err(
          'permission_denied_forever',
          'Location permission permanently denied. Enable it from settings.',
        );
      }

      maxAllowedAccuracyMeters = (requiredAccuracyMeters ?? 15.0)
          .clamp(5.0, 500.0)
          .toDouble();

      final Duration requestTimeout = Duration(
        milliseconds: (timeoutMs ?? 30000).clamp(5000, 45000),
      );

      final LocationSettings settings;

      if (Platform.isAndroid) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 250),
          timeLimit: requestTimeout,
          forceLocationManager: false,
        );
      } else if (Platform.isIOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          timeLimit: requestTimeout,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false,
        );
      } else {
        settings = LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          timeLimit: requestTimeout,
        );
      }

      final completer = Completer<Position>();
      final requestStopwatch = Stopwatch()..start();

      subscription = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
            (Position position) {
              if (completer.isCompleted) return;

              final hasRequiredAccuracy =
                  position.accuracy <= maxAllowedAccuracyMeters;

              if (!hasRequiredAccuracy) {
                debugPrint(
                  'Flutter GPS: inaccurate live value ignored. '
                  'Accuracy: ${position.accuracy}m',
                );
                return;
              }

              completer.complete(position);
            },
            onError: (Object error) {
              if (!completer.isCompleted) {
                completer.completeError(error);
              }
            },
          );

      final position = await completer.future.timeout(requestTimeout);

      requestStopwatch.stop();

      debugPrint(
        'Flutter GPS live position accepted. '
        'Accuracy: ${position.accuracy}m, '
        'receivedAfter: ${requestStopwatch.elapsedMilliseconds}ms',
      );

      return _ok({
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': position.timestamp.toIso8601String(),
          'timestampMs': position.timestamp.millisecondsSinceEpoch,
          'altitude': position.altitude,
          'speed': position.speed,
          'heading': position.heading,
          'isMocked': position.isMocked,
          'isSimulatedBySoftware': _isSimulatedBySoftware(position),
          'acceptedFromLiveStream': true,
          'maxAllowedAccuracyMeters': maxAllowedAccuracyMeters,
          'timeoutMs': requestTimeout.inMilliseconds,
        },
      });
    } on TimeoutException {
      return _err(
        'fresh_location_unavailable',
        'Unable to get a GPS location with accuracy <= ${maxAllowedAccuracyMeters.toStringAsFixed(0)} meters.',
      );
    } catch (e) {
      return _err('get_location_failed', e.toString());
    } finally {
      await subscription?.cancel();
    }
  }

  Future<Map<String, dynamic>> getDeviceInfo([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return _ok({
          'platform': 'android',
          'device': {
            'brand': a.brand,
            'manufacturer': a.manufacturer,
            'model': a.model,
            'sdkInt': a.version.sdkInt,
          },
        });
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return _ok({
          'platform': 'ios',
          'device': {
            'name': i.name,
            'model': i.model,
            'systemName': i.systemName,
            'systemVersion': i.systemVersion,
          },
        });
      }
      return _ok({'platform': Platform.operatingSystem});
    } catch (e) {
      return _err('device_info_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> openExternalUrl([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final urlString = (args is String)
          ? args
          : (args is Map ? (args['url'] as String?) : null);
      if (urlString == null || urlString.trim().isEmpty) {
        return _err('invalid_args', 'Missing url');
      }
      final url = Uri.parse(urlString);
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      return _ok({'launched': launched});
    } catch (e) {
      return _err('open_external_url_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> shareContent([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      String? text;
      String? subject;
      if (args is String) {
        text = args;
      } else if (args is Map) {
        text = args['text'] as String?;
        subject = args['subject'] as String?;
      }
      if (text == null || text.trim().isEmpty) {
        return _err('invalid_args', 'Missing text');
      }
      await Share.share(text, subject: subject);
      return _ok();
    } catch (e) {
      return _err('share_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> downloadFile([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final urlString = (args is String)
          ? args
          : (args is Map ? (args['url'] as String?) : null);
      final filename =
          (args is Map ? (args['filename'] as String?) : null) ?? '';
      if (urlString == null || urlString.trim().isEmpty) {
        return _err('invalid_args', 'Missing url');
      }
      final url = Uri.parse(urlString);
      final result = await onDownloadRequested(
        url,
        filename: filename.isEmpty ? null : filename,
      );
      return result;
    } catch (e) {
      return _err('download_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> getPushNotificationToken([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    return _ok({
      'token': null,
      'note':
          'Push notifications are not configured yet. Add a push provider (e.g. FCM) and expose token here.',
    });
  }

  String toJsonString(Map<String, dynamic> value) => jsonEncode(value);

  bool _isSimulatedBySoftware(Position position) {
    try {
      final dynamic p = position;
      final dynamic sourceInformation = p.sourceInformation;
      return sourceInformation?.isSimulatedBySoftware == true;
    } catch (_) {
      return false;
    }
  }
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : (isEmpty ? null : first);
}
