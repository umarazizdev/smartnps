import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/api_client.dart';
import '../app/app_navigator.dart';
import '../auth/auth_repository.dart';
import '../utilities/app_config.dart';
import '../widgets/location_tracking_disclosure_dialog.dart';
import 'background_location_controller.dart';

class DutyHeartbeatService {
  DutyHeartbeatService._();

  static final DutyHeartbeatService instance = DutyHeartbeatService._();

  static const MethodChannel _settingsChannel = MethodChannel(
    'com.smartnps360.app/settings',
  );

  static const Duration _minPollInterval = Duration(seconds: 10);
  static const Duration _maxPollInterval = Duration(seconds: 15);

  static const String onDuty = 'on_duty';
  static const String offDuty = 'off_duty';

  final Dio _dio = ApiClient.instance.dio;
  final Random _random = Random();

  Timer? _pollTimer;
  bool _pollInFlight = false;
  String? _lastAppliedStatus;
  bool _disclosureAccepted = false;
  bool _disclosureDeclined = false;
  bool _backgroundLocationSettingsDialogVisible = false;

  void start() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_pollTimer != null) return;

    ApiClient.instance.ensureAuthInterceptorInstalled();
    debugPrint('[DutyHeartbeatService] starting heartbeat polling');

    unawaited(_pollOnce());
    _scheduleNextPoll();
  }

  void stop({bool stopBackgroundLocation = true}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _lastAppliedStatus = null;
    _resetDisclosureState();
    debugPrint('[DutyHeartbeatService] stopped heartbeat polling');

    if (stopBackgroundLocation) {
      unawaited(_applyOffDuty());
    }
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    final jitterMs =
        _minPollInterval.inMilliseconds +
        _random.nextInt(
          _maxPollInterval.inMilliseconds - _minPollInterval.inMilliseconds + 1,
        );
    _pollTimer = Timer(Duration(milliseconds: jitterMs), () async {
      await _pollOnce();
      if (_pollTimer != null) {
        _scheduleNextPoll();
      }
    });
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight) return;
    _pollInFlight = true;

    try {
      final token = await AuthRepository.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint('[DutyHeartbeatService] skip poll: no auth token');
        }
        return;
      }

      final status = await _fetchDutyStatus();
      if (status == null) return;

      if (status == _lastAppliedStatus) {
        if (status == onDuty) {
          final running = await FlutterBackgroundService().isRunning();
          if (!running) {
            debugPrint(
              '[DutyHeartbeatService] on_duty but service not running; restarting',
            );
            await _applyOnDuty();
          } else if (kDebugMode) {
            debugPrint('[DutyHeartbeatService] unchanged status=$status');
          }
        } else if (kDebugMode) {
          debugPrint('[DutyHeartbeatService] unchanged status=$status');
        }
        return;
      }

      debugPrint('[DutyHeartbeatService] duty status=$status');
      if (status == onDuty) {
        await _applyOnDuty();
      } else if (status == offDuty) {
        await _applyOffDuty();
      } else if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] ignored unknown status=$status');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DutyHeartbeatService] poll failed: $e');
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<String?> _fetchDutyStatus() async {
    final response = await _dio.getUri(
      Uri.parse(AppConfig.heartbeatUrl),
      options: Options(
        headers: const {'Accept': 'application/json'},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode == 401 || statusCode == 403) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] heartbeat unauthorized status=$statusCode',
        );
      }
      return null;
    }

    if (statusCode < 200 || statusCode >= 300) {
      if (kDebugMode) {
        debugPrint(
          '[DutyHeartbeatService] heartbeat failed status=$statusCode body=${_truncate(response.data)}',
        );
      }
      return null;
    }

    return _parseDutyStatus(response.data);
  }

  String? _parseDutyStatus(dynamic body) {
    if (body == null) return null;

    if (body is String) {
      final normalized = body.trim().toLowerCase();
      if (normalized == onDuty || normalized == offDuty) return normalized;
      return null;
    }

    if (body is! Map) return null;
    final map = Map<String, dynamic>.from(body);

    for (final key in const [
      'status',
      'duty_status',
      'dutyStatus',
      'duty',
      'state',
    ]) {
      final parsed = _normalizeDutyValue(map[key]);
      if (parsed != null) return parsed;
    }

    for (final nestedKey in const ['data', 'payload', 'result']) {
      final nested = map[nestedKey];
      if (nested is Map) {
        final parsed = _parseDutyStatus(nested);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  String? _normalizeDutyValue(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == onDuty || normalized == offDuty) return normalized;
    if (normalized == 'onduty' || normalized == 'on-duty') return onDuty;
    if (normalized == 'offduty' || normalized == 'off-duty') return offDuty;
    return null;
  }

  Future<void> _applyOnDuty() async {
    if (!await _confirmBackgroundLocationDisclosure()) {
      debugPrint('[DutyHeartbeatService] on_duty start canceled by user');
      return;
    }

    final result = await BackgroundLocationController.ensureStarted();
    debugPrint('[DutyHeartbeatService] ensureStarted result=$result');

    if (result['ok'] == true) {
      _lastAppliedStatus = onDuty;
      await _showAndroidBackgroundLocationSettingsDialogIfNeeded();
    }
  }

  Future<void> _applyOffDuty() async {
    final result = await BackgroundLocationController.stop();
    debugPrint('[DutyHeartbeatService] stop result=$result');
    if (result['ok'] == true) {
      _lastAppliedStatus = offDuty;
      _resetDisclosureState();
    }
  }

  void _resetDisclosureState() {
    _disclosureAccepted = false;
    _disclosureDeclined = false;
  }

  Future<bool> _confirmBackgroundLocationDisclosure() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (_disclosureAccepted) return true;
    if (_disclosureDeclined) return false;

    final context = AppNavigator.key.currentContext;
    if (context == null) {
      debugPrint(
        '[DutyHeartbeatService] disclosure skipped: navigator context unavailable',
      );
      return false;
    }

    if (!context.mounted) return false;

    final allowed = await LocationTrackingDisclosureDialog.show(context);
    if (allowed) {
      _disclosureAccepted = true;
      return true;
    }

    _disclosureDeclined = true;
    return false;
  }

  Future<void> _showAndroidBackgroundLocationSettingsDialogIfNeeded() async {
    if (!Platform.isAndroid) return;
    if (_backgroundLocationSettingsDialogVisible) return;

    final foreground = await Permission.location.status;
    if (!foreground.isGranted) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return;

    final dialogContext = AppNavigator.key.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;

    _backgroundLocationSettingsDialogVisible = true;
    try {
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enable background location'),
          content: const Text(
            'SmartNPS360 needs “Allow all the time” location access to keep '
            'tracking your live location during an active shift when the app is '
            'closed or not on screen. Tracking stops when you are off duty.\n\n'
            'Open App Settings, tap Location, then choose “Allow all the time”.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _openAndroidAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    } finally {
      _backgroundLocationSettingsDialogVisible = false;
    }
  }

  Future<void> _openAndroidAppSettings() async {
    try {
      await _settingsChannel.invokeMethod<bool>('openAppSettings');
    } catch (error) {
      debugPrint('[DutyHeartbeatService] native openAppSettings failed: $error');
      await openAppSettings();
    }
  }

  String _truncate(Object? value, {int max = 800}) {
    final text = value?.toString() ?? '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }
}
