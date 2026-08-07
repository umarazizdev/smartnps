import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'visit_gps_session.dart';

class VisitMediaGeo {
  const VisitMediaGeo({
    required this.capturedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });

  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get stampLabel {
    final buffer = StringBuffer(_formatTimestamp(capturedAt));
    if (hasCoordinates) {
      buffer.write(' · ');
      buffer.write(latitude!.toStringAsFixed(6));
      buffer.write(', ');
      buffer.write(longitude!.toStringAsFixed(6));
      final accuracy = accuracyMeters;
      if (accuracy != null && accuracy.isFinite && accuracy >= 0) {
        buffer.write(' ±${accuracy.round()}m');
      }
    }
    return buffer.toString();
  }

  static Future<VisitMediaGeo> captureNow() => captureFast();

  static Future<String> describeFailure() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Location permission is required to stamp this capture. '
            'Enable location access, then tap Retry.';
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Location services are turned off. Enable GPS/location, '
            'then tap Retry.';
      }

      return 'Couldn\'t get a reliable GPS fix. This often happens with a weak '
          'signal indoors. Move to an open area with a clearer sky view, '
          'then tap Retry.';
    } catch (_) {
      return 'Failed to get GPS for this capture. Check location settings '
          'and try again.';
    }
  }

  static Future<VisitMediaGeo> captureFast() async {
    final capturedAt = DateTime.now();
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return VisitMediaGeo(capturedAt: capturedAt);
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return VisitMediaGeo(capturedAt: capturedAt);
      }

      final position = await VisitGpsSession.instance.acquireForCapture();
      if (position == null) {
        return VisitMediaGeo(capturedAt: capturedAt);
      }

      return VisitMediaGeo(
        capturedAt: capturedAt,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (_) {
      return VisitMediaGeo(capturedAt: capturedAt);
    }
  }

  static String _formatTimestamp(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = value.toLocal();
    final month = months[local.month - 1];
    final day = local.day.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour = hour12.toString().padLeft(2, '0');
    return '$month $day, $year $hour:$minute $period ${_formatGmt(local.timeZoneOffset)}';
  }

  static String _formatGmt(Duration offset) {
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes < 0 ? '-' : '+';
    final abs = totalMinutes.abs();
    final hours = abs ~/ 60;
    final minutes = abs % 60;
    if (minutes == 0) return 'GMT$sign$hours';
    return 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }
}

class VisitMediaStampBar extends StatelessWidget {
  const VisitMediaStampBar({
    super.key,
    required this.label,
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();

    final fontSize = compact ? 8.5 : 11.0;
    final vertical = compact ? 3.0 : 5.0;
    final horizontal = compact ? 4.0 : 8.0;

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              height: 1.15,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

enum VisitMediaPlayOverlaySize { compact, standard, large, control }

class VisitMediaPlayOverlay extends StatelessWidget {
  const VisitMediaPlayOverlay({
    super.key,
    this.size = VisitMediaPlayOverlaySize.standard,
  });

  final VisitMediaPlayOverlaySize size;

  @override
  Widget build(BuildContext context) {
    final iconSize = switch (size) {
      VisitMediaPlayOverlaySize.compact => 40.0,
      VisitMediaPlayOverlaySize.standard => 64.0,
      VisitMediaPlayOverlaySize.large => 60.0,
      VisitMediaPlayOverlaySize.control => 36.0,
    };

    return Icon(
      Icons.play_circle_fill_rounded,
      color: Colors.white.withValues(alpha: 0.95),
      size: iconSize,
      shadows: const [
        Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
      ],
    );
  }
}
