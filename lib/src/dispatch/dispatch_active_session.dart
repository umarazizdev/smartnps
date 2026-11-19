import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dispatch_request_screen.dart';

@immutable
class DispatchActiveSession {
  const DispatchActiveSession({
    required this.request,
    this.origin,
    this.routePoints = const [],
    this.navigationStarted = false,
  });

  final DispatchRequestData request;
  final LatLng? origin;
  final List<LatLng> routePoints;
  final bool navigationStarted;

  DispatchActiveSession copyWith({
    DispatchRequestData? request,
    LatLng? origin,
    List<LatLng>? routePoints,
    bool? navigationStarted,
  }) {
    return DispatchActiveSession(
      request: request ?? this.request,
      origin: origin ?? this.origin,
      routePoints: routePoints ?? this.routePoints,
      navigationStarted: navigationStarted ?? this.navigationStarted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': request.address,
      'city': request.city,
      'summary': request.summary,
      'score': request.score,
      'arrivalMinutes': request.arrivalMinutes,
      'distanceMiles': request.distanceMiles,
      'siteLatitude': request.siteLatitude,
      'siteLongitude': request.siteLongitude,
      'responseSeconds': request.responseSeconds,
      'navigationStarted': navigationStarted,
      if (origin != null) 'originLatitude': origin!.latitude,
      if (origin != null) 'originLongitude': origin!.longitude,
      'routePoints': [
        for (final point in routePoints)
          {'lat': point.latitude, 'lng': point.longitude},
      ],
    };
  }

  static DispatchActiveSession? fromJson(Map<String, dynamic> json) {
    final siteLatitude = (json['siteLatitude'] as num?)?.toDouble();
    final siteLongitude = (json['siteLongitude'] as num?)?.toDouble();
    if (siteLatitude == null || siteLongitude == null) return null;

    final originLat = (json['originLatitude'] as num?)?.toDouble();
    final originLng = (json['originLongitude'] as num?)?.toDouble();
    final rawPoints = json['routePoints'];
    final routePoints = <LatLng>[];
    if (rawPoints is List) {
      for (final item in rawPoints) {
        if (item is! Map) continue;
        final lat = (item['lat'] as num?)?.toDouble();
        final lng = (item['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        routePoints.add(LatLng(lat, lng));
      }
    }

    return DispatchActiveSession(
      request: DispatchRequestData(
        address: (json['address'] as String?)?.trim().isNotEmpty == true
            ? (json['address'] as String).trim()
            : 'Dispatch site',
        city: (json['city'] as String?)?.trim() ?? '',
        summary: (json['summary'] as String?)?.trim() ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        arrivalMinutes: (json['arrivalMinutes'] as num?)?.toInt() ?? 1,
        distanceMiles: (json['distanceMiles'] as num?)?.toDouble() ?? 0,
        siteLatitude: siteLatitude,
        siteLongitude: siteLongitude,
        responseSeconds: (json['responseSeconds'] as num?)?.toInt() ?? 30,
      ),
      origin: originLat != null && originLng != null
          ? LatLng(originLat, originLng)
          : null,
      routePoints: routePoints,
      navigationStarted: json['navigationStarted'] == true,
    );
  }
}

class DispatchActiveSessionStore {
  DispatchActiveSessionStore._();

  static const String _storageKey = 'dispatch_active_session_v1';

  static final ValueNotifier<DispatchActiveSession?> active =
      ValueNotifier<DispatchActiveSession?>(null);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        active.value = null;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        active.value = null;
        return;
      }
      active.value = DispatchActiveSession.fromJson(decoded);
    } catch (_) {
      active.value = null;
    }
  }

  static Future<void> save({
    required DispatchRequestData request,
    LatLng? origin,
    List<LatLng> routePoints = const [],
    bool? navigationStarted,
  }) async {
    final existing = active.value;
    final session = DispatchActiveSession(
      request: request,
      origin: origin,
      routePoints: List<LatLng>.from(routePoints),
      navigationStarted:
          navigationStarted ?? existing?.navigationStarted ?? false,
    );
    active.value = session;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(session.toJson()));
    } catch (_) {}
  }

  static Future<void> markNavigationStarted() async {
    final current = active.value;
    if (current == null || current.navigationStarted) return;
    final session = current.copyWith(navigationStarted: true);
    active.value = session;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(session.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    active.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
