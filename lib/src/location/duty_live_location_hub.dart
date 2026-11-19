import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../background/ios/ios_duty_location_pinger.dart';

@immutable
class DutyLiveLocationFix {
  const DutyLiveLocationFix({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.source = 'duty',
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracy;
  final String source;

  bool isFresh([Duration maxAge = DutyLiveLocationHub.freshMaxAge]) {
    return DateTime.now().difference(timestamp) <= maxAge;
  }
}

class DutyLiveLocationHub {
  DutyLiveLocationHub._();

  static const Duration freshMaxAge = Duration(seconds: 90);
  static const String androidEvent = 'duty_live_location';

  static final ValueNotifier<DutyLiveLocationFix?> latest =
      ValueNotifier<DutyLiveLocationFix?>(null);

  static StreamSubscription<Map<String, dynamic>?>? _androidSub;
  static bool _androidBridgeInstalled = false;

  static DutyLiveLocationFix? get current => latest.value;

  static void publish({
    required double latitude,
    required double longitude,
    DateTime? timestamp,
    double? accuracy,
    String source = 'duty',
  }) {
    latest.value = DutyLiveLocationFix(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp ?? DateTime.now(),
      accuracy: accuracy,
      source: source,
    );
  }

  static void publishPosition(Position position, {String source = 'duty'}) {
    publish(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      accuracy: position.accuracy,
      source: source,
    );
  }

  static void ensureAndroidBridge() {
    if (!Platform.isAndroid || _androidBridgeInstalled) return;
    _androidBridgeInstalled = true;
    _androidSub ??= FlutterBackgroundService().on(androidEvent).listen((event) {
      if (event == null) return;
      final lat = (event['lat'] as num?)?.toDouble();
      final lng = (event['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final accuracy = (event['accuracy'] as num?)?.toDouble();
      final at = DateTime.tryParse(event['at']?.toString() ?? '');
      publish(
        latitude: lat,
        longitude: lng,
        timestamp: at,
        accuracy: accuracy,
        source: 'duty_android',
      );
    });
  }

  static void seedFromDutyIfAvailable() {
    if (Platform.isIOS) {
      final pos = IosDutyLocationPinger.latestAcceptedPosition;
      if (pos != null) {
        publishPosition(pos, source: 'duty_ios');
      }
    }
    ensureAndroidBridge();
  }

  static DutyLiveLocationFix? freshFix([
    Duration maxAge = freshMaxAge,
  ]) {
    seedFromDutyIfAvailable();
    final fix = current;
    if (fix == null || !fix.isFresh(maxAge)) return null;
    return fix;
  }
}
