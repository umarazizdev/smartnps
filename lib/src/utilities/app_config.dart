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
  static const String defaultPushUrl = '${initialUrl}officer/dashboard';

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

  /// Token the web app can detect in `navigator.userAgent` for native shell traffic.
  static const String webViewAppSignature = 'SmartNPS360App';

  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '14';

  /// Example Android UA:
  /// `SmartNPS360App/1.0.0 (Flutter; InAppWebView; Android; Build 14)`
  ///
  /// Example iOS UA suffix appended to Mobile Safari:
  /// `... SmartNPS360App/1.0.0 (Flutter; InAppWebView; iOS; Build 14)`
  static String webViewUserAgentToken({required String platform}) {
    return '$webViewAppSignature/$appVersion (Flutter; InAppWebView; $platform; Build $appBuildNumber)';
  }
}
