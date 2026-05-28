import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

import '../webview/app_config.dart';

class BackgroundLocationUploader {
  BackgroundLocationUploader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<void> upload(Position position, {String? deviceId}) async {
    if (AppConfig.locationUploadUrl.isEmpty) return;

    final payload = {
      'app': AppConfig.appName,
      'platform': Platform.operatingSystem,
      'deviceId': deviceId,
      'location': {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestampMs': position.timestamp.millisecondsSinceEpoch,
        'timestamp': position.timestamp.toIso8601String(),
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'isMocked': position.isMocked,
      },
    };

    if (kDebugMode) {
      debugPrint(
        '[BackgroundLocationUploader] POST ${AppConfig.locationUploadUrl} '
        'lat=${position.latitude} lng=${position.longitude} '
        'acc=${position.accuracy}m mocked=${position.isMocked} '
        'ts=${position.timestamp.toIso8601String()}',
      );
    }

    await _dio.postUri(
      Uri.parse(AppConfig.locationUploadUrl),
      data: payload,
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    if (kDebugMode) {
      debugPrint('[BackgroundLocationUploader] upload ok');
    }
  }
}
