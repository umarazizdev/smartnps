import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../app/app_navigator.dart';
import '../utilities/app_config.dart';
import '../widgets/dialogs/mock_location_dialog.dart';
import '../utilities/overlay_prompt_guard.dart';
import 'mock_location_detection.dart';

enum MockLocationClockInCheck {

  clear,

  mockDetected,

  gpsUnavailable,
}

class MockLocationGuard {
  MockLocationGuard._();

  static const Duration _clockInGpsTimeout = Duration(seconds: 15);
  static const Duration _cooldown = Duration(minutes: 2);

  static DateTime? _lastDialogAt;
  static bool _dialogVisible = false;
  static StreamSubscription<Map<String, dynamic>?>? _backgroundSub;
  static int _pendingShowAttempts = 0;

  static void ensureBackgroundListenerInstalled() {
    if (!AppConfig.enableMockLocationDetection) return;
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
    final flags = MockLocationDetection.flagsFor(position);
    maybeShowDialog(
      isMocked: flags.isMocked,
      isSimulatedBySoftware: flags.isSimulatedBySoftware,
    );
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

    final position = await _readPositionOrNull();
    if (position == null) {
      debugPrint(
        '[MockLocationGuard] ensureClearForClockIn: GPS unavailable/timeout',
      );
      return MockLocationClockInCheck.gpsUnavailable;
    }

    final flags = MockLocationDetection.flagsFor(position);
    if (!flags.isDetected) return MockLocationClockInCheck.clear;

    debugPrint(
      '[MockLocationGuard] ensureClearForClockIn: mock detected '
      'isMocked=${flags.isMocked} isSimulated=${flags.isSimulatedBySoftware}',
    );
    await _presentBlockingDialog();

    final recheck = await _readPositionOrNull();
    if (recheck == null) {
      debugPrint(
        '[MockLocationGuard] ensureClearForClockIn: GPS unavailable after dialog',
      );
      return MockLocationClockInCheck.gpsUnavailable;
    }
    final clear = !MockLocationDetection.isDetected(recheck);
    debugPrint(
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
      final navigator = AppNavigator.key.currentState;
      final context =
          navigator?.overlay?.context ?? AppNavigator.key.currentContext;
      if (context == null || !context.mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      _pendingShowAttempts = 0;
      _dialogVisible = true;
      OverlayPromptGuard.registerBlockingOverlay();

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.32),
        builder: (context) => const MockLocationDialog(),
      ).whenComplete(() {
        OverlayPromptGuard.unregisterBlockingOverlay();
        _dialogVisible = false;
      });

      return;
    }
  }

  static void maybeShowDialog({
    required bool isMocked,
    required bool isSimulatedBySoftware,
  }) {
    if (!AppConfig.enableMockLocationDetection) return;
    if (!isMocked && !isSimulatedBySoftware) return;
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

    final navigator = AppNavigator.key.currentState;
    final context =
        navigator?.overlay?.context ?? AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      if (_pendingShowAttempts >= 8) return;
      _pendingShowAttempts++;
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentDialog());
      return;
    }

    _pendingShowAttempts = 0;
    _lastDialogAt = DateTime.now();
    _dialogVisible = true;
    OverlayPromptGuard.registerBlockingOverlay();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => const MockLocationDialog(),
    ).whenComplete(() {
      OverlayPromptGuard.unregisterBlockingOverlay();
      _dialogVisible = false;
    });
  }
}
