import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../app/app_navigator.dart';
import '../utilities/app_config.dart';
import '../widgets/dialogs/glass_action_dialog.dart';
import 'mock_location_detection.dart';
import '../utilities/app_debug_log.dart';

enum MockLocationClockInCheck { clear, mockDetected, gpsUnavailable }

class MockLocationGuard {
  MockLocationGuard._();

  static const Duration _clockInGpsTimeout = Duration(seconds: 15);
  static const Duration _cooldown = Duration(minutes: 2);

  static const String _title = 'Mock location detected';
  static const String _message =
      'Your device appears to be using a fake/mock GPS location. '
      'Please disable mock location and try again.';

  static DateTime? _lastDialogAt;
  static bool _dialogVisible = false;
  static StreamSubscription<Map<String, dynamic>?>? _backgroundSub;
  static int _pendingShowAttempts = 0;

  static void ensureBackgroundListenerInstalled() {
    if (!AppConfig.enableMockLocationDetection) return;
    unawaited(MockLocationDetection.warmDeviceClass());
    _backgroundSub ??= FlutterBackgroundService().on('mock_location').listen((
      event,
    ) {
      if (event == null) return;
      maybeShowDialog(
        isMocked: event['isMocked'] == true,
        isSimulatedBySoftware: event['isSimulatedBySoftware'] == true,
      );
    });
  }

  static void maybeShowDialogForPosition(Position position) {
    if (!AppConfig.enableMockLocationDetection) return;
    unawaited(() async {
      await MockLocationDetection.warmDeviceClass();
      final flags = MockLocationDetection.flagsFor(position);
      maybeShowDialog(
        isMocked: flags.isMocked,
        isSimulatedBySoftware: flags.isSimulatedBySoftware,
      );
    }());
  }

  static void maybeShowDialogFromBridgeResult(Map<String, dynamic> result) {
    if (!AppConfig.enableMockLocationDetection) return;
    if (result['ok'] != true) return;

    final location = result['location'];
    if (location is! Map) return;

    maybeShowDialog(
      isMocked: location['isMocked'] == true,
      isSimulatedBySoftware: location['isSimulatedBySoftware'] == true,
    );
  }

  static Future<MockLocationClockInCheck> ensureClearForClockIn() async {
    if (!AppConfig.enableMockLocationDetection) {
      return MockLocationClockInCheck.clear;
    }

    await MockLocationDetection.warmDeviceClass();

    final position = await _readPositionOrNull();
    if (position == null) {
      locationDebugLog(
        '[MockLocationGuard] ensureClearForClockIn: GPS unavailable/timeout',
      );
      return MockLocationClockInCheck.gpsUnavailable;
    }

    final flags = MockLocationDetection.flagsFor(position);
    if (!flags.isDetected) return MockLocationClockInCheck.clear;

    locationDebugLog(
      '[MockLocationGuard] ensureClearForClockIn: mock detected '
      'isMocked=${flags.isMocked} isSimulated=${flags.isSimulatedBySoftware}',
    );
    await _presentBlockingDialog();

    final recheck = await _readPositionOrNull();
    if (recheck == null) {
      locationDebugLog(
        '[MockLocationGuard] ensureClearForClockIn: GPS unavailable after dialog',
      );
      return MockLocationClockInCheck.gpsUnavailable;
    }
    final clear = !MockLocationDetection.isDetected(recheck);
    locationDebugLog(
      '[MockLocationGuard] ensureClearForClockIn: after dialog clear=$clear',
    );
    return clear
        ? MockLocationClockInCheck.clear
        : MockLocationClockInCheck.mockDetected;
  }

  static Future<Position?> _readPositionOrNull() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _clockInGpsTimeout,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _presentBlockingDialog() async {
    if (_dialogVisible) return;

    for (var attempt = 0; attempt < 8; attempt++) {
      final context = AppNavigator.key.currentContext;
      if (context == null || !context.mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      _pendingShowAttempts = 0;
      _dialogVisible = true;
      try {
        await GlassActionDialog.show(
          context: context,
          icon: Icons.location_off_rounded,
          title: _title,
          message: _message,
          primaryLabel: 'OK',
          variant: GlassActionDialogVariant.error,
          useRootNavigator: true,
        );
      } finally {
        _dialogVisible = false;
      }
      return;
    }
  }

  static void maybeShowDialog({
    required bool isMocked,
    required bool isSimulatedBySoftware,
  }) {
    if (!AppConfig.enableMockLocationDetection) return;
    final simulated =
        isSimulatedBySoftware &&
        !MockLocationDetection.ignoreSimulatedSoftwareFlag;
    if (!isMocked && !simulated) return;
    if (_dialogVisible) return;

    final now = DateTime.now();
    final last = _lastDialogAt;
    if (last != null && now.difference(last) < _cooldown) return;

    _scheduleDialogPresentation();
  }

  static void _scheduleDialogPresentation() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentDialog());
  }

  static void _presentDialog() {
    if (_dialogVisible) return;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      if (_pendingShowAttempts >= 8) return;
      _pendingShowAttempts++;
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentDialog());
      return;
    }

    _pendingShowAttempts = 0;
    _lastDialogAt = DateTime.now();
    _dialogVisible = true;

    unawaited(() async {
      try {
        await GlassActionDialog.show(
          context: context,
          icon: Icons.location_off_rounded,
          title: _title,
          message: _message,
          primaryLabel: 'OK',
          variant: GlassActionDialogVariant.error,
          useRootNavigator: true,
        );
      } catch (e, st) {
        locationDebugLog('[MockLocationGuard] present dialog failed: $e\n$st');
      } finally {
        _dialogVisible = false;
      }
    }());
  }
}
