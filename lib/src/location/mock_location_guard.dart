import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../app/app_navigator.dart';
import '../widgets/mock_location_dialog.dart';
import 'mock_location_detection.dart';

class MockLocationGuard {
  MockLocationGuard._();

  static const Duration _cooldown = Duration(minutes: 2);

  static DateTime? _lastDialogAt;
  static bool _dialogVisible = false;
  static StreamSubscription<Map<String, dynamic>?>? _backgroundSub;
  static int _pendingShowAttempts = 0;

  static void ensureBackgroundListenerInstalled() {
    _backgroundSub ??= FlutterBackgroundService().on('mock_location').listen(
      (event) {
        if (event == null) return;
        maybeShowDialog(
          isMocked: event['isMocked'] == true,
          isSimulatedBySoftware: event['isSimulatedBySoftware'] == true,
        );
      },
    );
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
    final context = navigator?.overlay?.context ?? AppNavigator.key.currentContext;
    if (context == null || !context.mounted) {
      if (_pendingShowAttempts >= 8) return;
      _pendingShowAttempts++;
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentDialog());
      return;
    }

    _pendingShowAttempts = 0;
    _lastDialogAt = DateTime.now();
    _dialogVisible = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => const MockLocationDialog(),
    ).whenComplete(() {
      _dialogVisible = false;
    });
  }
}
