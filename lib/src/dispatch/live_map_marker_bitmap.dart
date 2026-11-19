import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'live_map_marker_style.dart';

class LiveMapMarkerBitmap {
  LiveMapMarkerBitmap._();

  static const double tapPadding = 18;

  static final Map<String, BitmapDescriptor> _cache = {};
  static final Map<String, Uint8List> _pngCache = {};

  static Future<BitmapDescriptor> forStyle(
    LiveMapMarkerStyle style, {
    required double logicalSize,
    required double devicePixelRatio,
  }) async {
    final sizeDp = math.max(1.0, logicalSize);
    final dpr = devicePixelRatio.clamp(1.0, 4.0);
    final key =
        '${style.id}-${sizeDp.toStringAsFixed(1)}-${dpr.toStringAsFixed(2)}-pad$tapPadding';
    final cached = _cache[key];
    if (cached != null) return cached;
    final bytes = await pngBytesForStyle(
      style,
      logicalSize: sizeDp,
      devicePixelRatio: dpr,
    );
    final icon = BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: dpr,
    );
    _cache[key] = icon;
    return icon;
  }

  static Future<Uint8List> pngBytesForStyle(
    LiveMapMarkerStyle style, {
    required double logicalSize,
    required double devicePixelRatio,
  }) async {
    final sizeDp = math.max(1.0, logicalSize);
    final dpr = devicePixelRatio.clamp(1.0, 4.0);
    final key =
        '${style.id}-${sizeDp.toStringAsFixed(1)}-${dpr.toStringAsFixed(2)}-pad$tapPadding';
    final cached = _pngCache[key];
    if (cached != null) return cached;
    final bytes = await _svgAssetToPng(
      style.assetPath,
      logicalSize: sizeDp,
      devicePixelRatio: dpr,
      tapPadding: tapPadding,
    );
    _pngCache[key] = bytes;
    return bytes;
  }

  static Future<void> prefetchAll({
    required double logicalSize,
    required double devicePixelRatio,
  }) async {
    await Future.wait([
      for (final style in LiveMapMarkerStyle.values)
        forStyle(
          style,
          logicalSize: logicalSize,
          devicePixelRatio: devicePixelRatio,
        ),
    ]);
  }

  static Future<Uint8List> _svgAssetToPng(
    String asset, {
    required double logicalSize,
    required double devicePixelRatio,
    required double tapPadding,
  }) async {
    final pictureInfo = await vg.loadPicture(SvgAssetLoader(asset), null);
    try {
      final rawSize = pictureInfo.size;
      final maxRaw = math.max(rawSize.width, math.max(rawSize.height, 1));
      final visualPhysical = logicalSize * devicePixelRatio;
      final scale = visualPhysical / maxRaw;
      final contentWidth = math.max(1, (rawSize.width * scale).round());
      final contentHeight = math.max(1, (rawSize.height * scale).round());
      final pad = (tapPadding * devicePixelRatio).round();
      final width = contentWidth + (pad * 2);
      final height = contentHeight + (pad * 2);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(pad.toDouble(), pad.toDouble());
      canvas.scale(scale);
      canvas.drawPicture(pictureInfo.picture);
      final image = await recorder.endRecording().toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    } finally {
      pictureInfo.picture.dispose();
    }
  }
}
