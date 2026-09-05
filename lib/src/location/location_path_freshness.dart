/// Live-first freshness limits for reused GPS samples (not the offline batch queue).
class LocationPathFreshness {
  LocationPathFreshness._();

  /// Median / average / speed / origin reuse must stay within this age.
  static const Duration reuseMaxAge = Duration(minutes: 1);
}
