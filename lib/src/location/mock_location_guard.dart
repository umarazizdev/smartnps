import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../app/app_navigator.dart';
import '../widgets/mock_location_dialog.dart';
import '../utilities/overlay_prompt_guard.dart';
import 'mock_location_detection.dart';

class MockLocationGuard {
  MockLocationGuard._();

  static const Duration _cooldown = Duration(minutes: 2);

  static DateTime? _lastDialogAt;
  static bool _dialogVisible = false;
  static StreamSubscription<Map<String, dynamic>?>? _backgroundSub;
  static int _pendingShowAttempts = 0;

  static void ensureBackgroundListenerInstalled() {
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
    final flags = MockLocationDetection.flagsFor(position);
    maybeShowDialog(
      isMocked: flags.isMocked,
      isSimulatedBySoftware: flags.isSimulatedBySoftware,
    );
  }

  static void maybeShowDialogFromBridgeResult(Map<String, dynamic> result) {
    if (result['ok'] != true) return;

    final location = result['location'];
    if (location is! Map) return;

    maybeShowDialog(
      isMocked: location['isMocked'] == true,
      isSimulatedBySoftware: location['isSimulatedBySoftware'] == true,
    );
  }

  /// Blocking clock-in check: shows mock dialog when needed, then re-reads GPS.
  static Future<bool> ensureClearForClockIn() async {
    final position = await _readPositionOrNull();
    if (position == null) {
      return false;
    }

    final flags = MockLocationDetection.flagsFor(position);
    if (!flags.isDetected) return true;

    await _presentBlockingDialog();

    final recheck = await _readPositionOrNull();
    if (recheck == null) return false;
    return !MockLocationDetection.isDetected(recheck);
  }

  static Future<Position?> _readPositionOrNull() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 5),
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
