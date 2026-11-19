import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_map_marker_style.dart';

class DispatchLiveMarkerStyleStore {
  DispatchLiveMarkerStyleStore._();

  static const String _storageKey = 'dispatch_live_marker_style_v1';

  static LiveMapMarkerStyle current = LiveMapMarkerStyle.gpsDot;

  static final ValueNotifier<LiveMapMarkerStyle> listenable =
      ValueNotifier<LiveMapMarkerStyle>(current);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_storageKey);
      if (id == null || id.isEmpty) return;
      for (final style in LiveMapMarkerStyle.values) {
        if (style.id == id) {
          current = style;
          listenable.value = style;
          return;
        }
      }
    } catch (_) {}
  }

  static Future<void> set(LiveMapMarkerStyle style) async {
    current = style;
    if (listenable.value != style) {
      listenable.value = style;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, style.id);
    } catch (_) {}
  }
}
