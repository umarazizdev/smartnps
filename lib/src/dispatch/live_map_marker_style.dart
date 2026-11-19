enum LiveMapMarkerStyle {
  gpsDot,
  navigationArrow,
  patrolCar,
  blueSedan,
  securitySuv,
  pickupTruck,
  redSportsCar;

  static const double baseLogicalSize = 56;

  String get id => name;

  String get label => switch (this) {
    LiveMapMarkerStyle.gpsDot => 'GPS dot',
    LiveMapMarkerStyle.navigationArrow => 'Arrow',
    LiveMapMarkerStyle.patrolCar => 'Patrol car',
    LiveMapMarkerStyle.blueSedan => 'Sedan',
    LiveMapMarkerStyle.securitySuv => 'Security SUV',
    LiveMapMarkerStyle.pickupTruck => 'Pickup',
    LiveMapMarkerStyle.redSportsCar => 'Sports car',
  };

  String get assetPath => switch (this) {
    LiveMapMarkerStyle.gpsDot => 'assets/markers/gps_dot.svg',
    LiveMapMarkerStyle.navigationArrow => 'assets/markers/navigation_arrow.svg',
    LiveMapMarkerStyle.patrolCar => 'assets/markers/patrol_car.svg',
    LiveMapMarkerStyle.blueSedan => 'assets/markers/blue_sedan.svg',
    LiveMapMarkerStyle.securitySuv => 'assets/markers/security_suv.svg',
    LiveMapMarkerStyle.pickupTruck => 'assets/markers/pickup_truck.svg',
    LiveMapMarkerStyle.redSportsCar => 'assets/markers/red_sports_car.svg',
  };

  bool get rotatesWithBearing => this != LiveMapMarkerStyle.gpsDot;

  bool get usesPulse => this == LiveMapMarkerStyle.gpsDot;
}
