import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

@immutable
class DispatchRequestData {
  const DispatchRequestData({
    required this.address,
    required this.city,
    required this.summary,
    required this.score,
    required this.arrivalMinutes,
    required this.distanceMiles,
    required this.siteLatitude,
    required this.siteLongitude,
    this.responseSeconds = 30,
  });

  final String address;
  final String city;
  final String summary;
  final int score;
  final int arrivalMinutes;
  final double distanceMiles;
  final double siteLatitude;
  final double siteLongitude;
  final int responseSeconds;

  LatLng get site => LatLng(siteLatitude, siteLongitude);
}

class DispatchRequestConfig {
  static const bool openExpiredOnTimerEnd = true;
}
