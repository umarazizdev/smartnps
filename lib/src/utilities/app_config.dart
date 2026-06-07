class AppConfig {
  static const String appName = 'SmartNPS360';

  static const String initialUrl = 'https://smartnps360.com/';

  static const String login = '${initialUrl}api/gauth/login';
  static const String gpsApiBaseUrl = '${initialUrl}api/gps/';
  static const String gpsPointPath = 'point';
  static const String gpsPingPath = 'ping';
  static const String gpsBatchPath = 'batch';

  static const String sanctumLoginUrl = '${initialUrl}api/auth/login';
  static const String heartbeatUrl = '${initialUrl}api/heartbeat';
  static const String pushTokenUrl = '${initialUrl}api/push-token';

  static const String allowedHost = 'smartnps360.com';
  static const Set<String> allowedHosts = {
    'smartnps360.com',
    'www.smartnps360.com',
  };

  static bool isAllowedHost(String? host) {
    if (host == null) return false;
    final h = host.toLowerCase();
    if (allowedHosts.contains(h)) return true;
    return h.endsWith('.$allowedHost');
  }

  static const int cPrimary = 0xFF022A67;
  static const int cSurface = 0xFFFBFBFD;
  static const int cDarkCardColor = 0xFF1A2332;
}
