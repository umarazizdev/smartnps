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

import '../background/location/background_location_permissions.dart';
import '../background/duty/clock_in_gate_service.dart';
import '../background/duty/location_disclosure_consent.dart';
import '../background/duty/duty_heartbeat_service.dart';
import '../utilities/app_config.dart';
import '../location/mock_location_detection.dart';
import '../location/mock_location_guard.dart';
import '../push/notifications/push_notification_service.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';

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

  Map<String, dynamic> _locationPayload(
    Position position, {
    required bool acceptedFromLiveStream,
    required bool isFreshLiveLocation,
    required bool isCachedLocation,
    required int timeoutMs,
  }) {
    final now = DateTime.now();
    var ageMsWhenAccepted = 0;
    try {
      ageMsWhenAccepted = now.difference(position.timestamp).inMilliseconds;
      if (ageMsWhenAccepted < 0) ageMsWhenAccepted = 0;
    } catch (_) {
      ageMsWhenAccepted = 0;
    }

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitudeAccuracy': _numOrNull(() => position.altitudeAccuracy),
      'timestampMs': position.timestamp.millisecondsSinceEpoch,
      'timestamp': position.timestamp.toIso8601String(),
      'altitude': position.altitude,
      'speed': position.speed,
      'speedAccuracy': _numOrNull(() => position.speedAccuracy),
      'heading': position.heading,
      'headingAccuracy': _numOrNull(() => position.headingAccuracy),
      'isMocked': position.isMocked,
      'isSimulatedBySoftware': _isSimulatedBySoftware(position),
      'floor': _numOrNull(() => (position as dynamic).floor as num),
      'acceptedFromLiveStream': acceptedFromLiveStream,
      'isFreshLiveLocation': isFreshLiveLocation,
      'isCachedLocation': isCachedLocation,
      'ageMsWhenAccepted': ageMsWhenAccepted,
      'maxAllowedAccuracyMeters': 0,
      'timeoutMs': timeoutMs,
    };
  }

  num? _numOrNull(num Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> pickFile([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    try {
      final result = await FilePicker.pickFiles(
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
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
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
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
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

    final requestStopwatch = Stopwatch()..start();
    Duration requestTimeout = const Duration(milliseconds: 12000);
    var forClockIn = false;
    var requiresBackgroundForClockIn = false;

    try {
      final Map? argsMap = args is Map ? args : null;
      final dynamic rawOptions = argsMap == null ? null : argsMap['options'];
      final Map? options = rawOptions is Map ? rawOptions : null;

      final int? timeoutMs = options != null && options['timeout_ms'] is num
          ? (options['timeout_ms'] as num).toInt()
          : null;
      forClockIn =
          options != null &&
          (options['for_clock_in'] == true ||
              options['purpose'] == 'clockIn' ||
              options['purpose'] == 'clock_in');
      final bool allowForegroundOnly =
          options?['allow_foreground_only'] == true;

      if ((Platform.isAndroid || Platform.isIOS) &&
          ClockInGateService.instance.isPrepareInFlight &&
          (!await BackgroundLocationPermissions.isClockInBackgroundReady() ||
              !await BackgroundLocationPermissions.hasPreciseLocationAccess())) {
        ClockInGateService.instance.clearGeoUnlock();
        return _err(
          'clock_in_gate_in_progress',
          'Location permission check is still in progress. '
              'Enable background location (${BackgroundLocationPermissions.alwaysAccessLabel()}) for shift attendance.',
        );
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return _err(
          'location_services_disabled',
          'Location services are disabled',
        );
      }

      if ((Platform.isAndroid || Platform.isIOS) && !allowForegroundOnly) {
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        final clockInLocationReady =
            await BackgroundLocationPermissions.isClockInBackgroundReady() &&
            await BackgroundLocationPermissions.hasPreciseLocationAccess();
        if (!clockInLocationReady) {
          if (!ClockInGateService.instance.isGeoUnlockedForClockIn) {
            final gate = await ClockInGateService.instance.prepareClockIn();
            if (gate['canClockIn'] != true) {
              ClockInGateService.instance.clearGeoUnlock();
              return _err(
                gate['reason']?.toString() ?? 'background_location_required',
                gate['message']?.toString() ??
                    BackgroundLocationPermissions.clockInMessageFor(
                      await BackgroundLocationPermissions.settingsDeniedReasonIfAny(),
                    ),
              );
            }
          }

          await BackgroundLocationPermissions.refreshPermissionStateFromOs();
          if (!await BackgroundLocationPermissions.isClockInBackgroundReady() ||
              !await BackgroundLocationPermissions.hasPreciseLocationAccess()) {
            ClockInGateService.instance.clearGeoUnlock();
            final deniedReason =
                await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
            return _err(
              deniedReason ?? 'background_location_required',
              BackgroundLocationPermissions.clockInMessageFor(deniedReason),
            );
          }
        }
      }

      requiresBackgroundForClockIn =
          forClockIn || ClockInGateService.instance.isGeoUnlockedForClockIn;

      if (allowForegroundOnly) {
        final disclosureReady = await DutyHeartbeatService.instance
            .ensureDisclosureBeforeWebLocationAccess();
        if (!disclosureReady) {
          return _err(
            'disclosure_required',
            'Location disclosure must be accepted to use GPS',
          );
        }
      } else if (requiresBackgroundForClockIn) {
        await BackgroundLocationPermissions.refreshPermissionStateFromOs();
        if (await BackgroundLocationPermissions.isClockInBackgroundReady()) {
          await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
        } else if (!await LocationDisclosureConsent.hasAccepted()) {
          return _err(
            'disclosure_required',
            'Shift attendance location disclosure must be accepted',
          );
        }
      } else {
        final disclosureReady = await DutyHeartbeatService.instance
            .ensureDisclosureBeforeWebLocationAccess();
        if (!disclosureReady) {
          return _err(
            'disclosure_required',
            'Location disclosure must be accepted to use GPS',
          );
        }
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied &&
          !await BackgroundLocationPermissions.hasForegroundLocationAccess()) {
        permission = await OverlayPromptGuard.runDuringOsPermissionPrompt(
          Geolocator.requestPermission,
        );
      }

      if (permission == LocationPermission.denied) {
        if (!DutyHeartbeatService.instance.shouldShowBackgroundLocationBanner) {
          unawaited(
            PermissionSettingsHelper.promptOpenSettings(
              title: 'Location permission denied',
              message:
                  'Location access was denied. To use GPS features, open '
                  'Settings, tap SmartNPS360, then enable Location.',
              dialogKey: 'webview_location',
            ),
          );
        }
        return _err('permission_denied', 'Location permission denied');
      }

      if (permission == LocationPermission.deniedForever) {
        if (!DutyHeartbeatService.instance.shouldShowBackgroundLocationBanner) {
          unawaited(
            PermissionSettingsHelper.promptOpenSettings(
              title: 'Location permission denied',
              message:
                  'Location access was permanently denied. Open Settings, tap '
                  'SmartNPS360, then enable Location.',
              dialogKey: 'webview_location',
            ),
          );
        }
        return _err(
          'permission_denied_forever',
          'Location permission permanently denied. Enable it from settings.',
        );
      }

      final defaultTimeoutMs = Platform.isIOS ? 20000 : 12000;
      requestTimeout = Duration(
        milliseconds: (timeoutMs ?? defaultTimeoutMs).clamp(5000, 45000),
      );

      final LocationSettings settings;
      if (Platform.isAndroid) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          timeLimit: requestTimeout,
          forceLocationManager: false,
        );
      } else if (Platform.isIOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          timeLimit: requestTimeout,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false,
        );
      } else {
        settings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          timeLimit: requestTimeout,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );

      if (!position.latitude.isFinite || !position.longitude.isFinite) {
        throw TimeoutException('Invalid GPS coordinates');
      }

      requestStopwatch.stop();

      debugPrint(
        'Flutter GPS current position accepted. '
        'Accuracy: ${position.accuracy}m, '
        'receivedAfter: ${requestStopwatch.elapsedMilliseconds}ms',
      );

      if (AppConfig.enableMockLocationDetection &&
          (forClockIn || requiresBackgroundForClockIn)) {
        if (MockLocationDetection.isDetected(position)) {
          ClockInGateService.instance.clearGeoUnlock();
          MockLocationGuard.maybeShowDialogForPosition(position);
          return _err(
            'mock_location',
            'Disable mock or fake GPS location before verifying shift attendance.',
          );
        }
        ClockInGateService.instance.clearGeoUnlock();
      } else if (forClockIn || requiresBackgroundForClockIn) {
        ClockInGateService.instance.clearGeoUnlock();
      }

      return _ok({
        'location': {
          ..._locationPayload(
            position,
            acceptedFromLiveStream: false,
            isFreshLiveLocation: true,
            isCachedLocation: false,
            timeoutMs: requestTimeout.inMilliseconds,
          ),
          'effectiveMaxAllowedAccuracyMeters': 0,
          'degradedAccuracyAccepted': false,
        },
      });
    } on TimeoutException {
      requestStopwatch.stop();
      if ((Platform.isAndroid || Platform.isIOS) &&
          (forClockIn || requiresBackgroundForClockIn)) {
        ClockInGateService.instance.clearGeoUnlock();
      }
      return _err(
        'fresh_location_unavailable',
        'Unable to get a GPS location.',
      );
    } catch (e) {
      requestStopwatch.stop();
      if ((Platform.isAndroid || Platform.isIOS) &&
          (forClockIn || requiresBackgroundForClockIn)) {
        ClockInGateService.instance.clearGeoUnlock();
      }
      final message = e.toString();
      if (message.contains('TimeoutException') ||
          message.contains('time limit') ||
          message.contains('TIME_OUT')) {
        return _err(
          'fresh_location_unavailable',
          'Unable to get a GPS location.',
        );
      }
      return _err('get_location_failed', message);
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
    final token = PushNotificationService.instance.lastFcmToken;
    return _ok({'token': token});
  }

  Future<Map<String, dynamic>> getPushNotificationStatus([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    return PushNotificationService.instance.getNotificationStatus();
  }

  Future<Map<String, dynamic>> setPushNotificationsEnabled([
    dynamic args,
  ]) async {
    if (!_isTrustedCaller()) return _deny();

    bool? enabled;
    if (args is bool) {
      enabled = args;
    } else if (args is Map) {
      final raw = args['enabled'];
      if (raw is bool) {
        enabled = raw;
      } else if (raw != null) {
        final text = raw.toString().toLowerCase();
        enabled = text == 'true' || text == '1';
      }
    }

    if (enabled == null) {
      return _err('invalid_args', 'Missing enabled boolean');
    }

    try {
      return await PushNotificationService.instance.setNotificationsEnabled(
        enabled,
      );
    } catch (e) {
      return _err('push_toggle_failed', e.toString());
    }
  }

  Future<Map<String, dynamic>> getBackgroundLocationStatus([
    dynamic args,
  ]) async {
    if (!_isTrustedCaller()) return _deny();

    if (!Platform.isAndroid && !Platform.isIOS) {
      return _ok({
        'backgroundReady': true,
        'phase': 'backgroundReady',
        'deniedReason': null,
        'disclosureAccepted': true,
        'serviceEnabled': true,
        'canClockIn': true,
        'platform': Platform.operatingSystem,
      });
    }

    await BackgroundLocationPermissions.refreshPermissionStateFromOs();
    final phase = await BackgroundLocationPermissions.currentPermissionPhase();
    final backgroundReady =
        await BackgroundLocationPermissions.isClockInBackgroundReady();
    final preciseReady =
        await BackgroundLocationPermissions.hasPreciseLocationAccess();
    if (backgroundReady) {
      await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
    }
    final deniedReason =
        await BackgroundLocationPermissions.settingsDeniedReasonIfAny();
    final disclosureAccepted = await LocationDisclosureConsent.hasAccepted();
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final prepareInFlight = ClockInGateService.instance.isPrepareInFlight;
    final canClockIn =
        backgroundReady && preciseReady && serviceEnabled && !prepareInFlight;

    final phaseName = switch (phase) {
      LocationPermissionPhase.none => 'none',
      LocationPermissionPhase.foregroundOnly => 'foregroundOnly',
      LocationPermissionPhase.backgroundReady => 'backgroundReady',
    };

    return _ok({
      'backgroundReady': backgroundReady,
      'phase': phaseName,
      'deniedReason': deniedReason,
      'disclosureAccepted': disclosureAccepted,
      'serviceEnabled': serviceEnabled,
      'canClockIn': canClockIn,
      'prepareInFlight': prepareInFlight,
      'title': canClockIn
          ? null
          : BackgroundLocationPermissions.clockInTitleFor(deniedReason),
      'message': canClockIn
          ? null
          : BackgroundLocationPermissions.clockInMessageFor(deniedReason),
      'platform': Platform.isIOS ? 'ios' : 'android',
    });
  }

  Future<Map<String, dynamic>> prepareClockIn([dynamic args]) async {
    if (!_isTrustedCaller()) return _deny();
    return ClockInGateService.instance.prepareClockIn();
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
