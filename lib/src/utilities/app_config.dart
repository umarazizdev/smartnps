class AppConfig {
  static const String appName = 'SmartNPS360';

  static const String initialUrl = 'https://smartnps360.com/';

  static const String gpsApiBaseUrl = '${initialUrl}api/gps/';
  static const String gpsPointPath = 'point';
  static const String gpsPingPath = 'ping';
  static const String gpsBatchPath = 'batch';

  static const String sanctumLoginUrl = '${initialUrl}api/auth/login';
  static const String refreshTokenUrl = '${initialUrl}api/auth/refresh';
  static const String heartbeatUrl = '${initialUrl}api/heartbeat';
  static const String pushTokenUrl = '${initialUrl}api/push-token';
  static const String permissionStatusUrl =
      '${initialUrl}api/native-app/permission-status';
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

  /// Google Maps / Fonts CDN hosts loaded as subresources from smartnps360 pages.
  /// iOS WKWebView TLS and iframe navigations must allow these for embedded maps.
  static bool isTrustedSubresourceHost(String? host) {
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase();
    const exact = {
      'google.com',
      'googleapis.com',
      'gstatic.com',
      'googleusercontent.com',
      'ggpht.com',
    };
    if (exact.contains(h)) return true;
    const suffixes = [
      '.google.com',
      '.googleapis.com',
      '.gstatic.com',
      '.googleusercontent.com',
      '.ggpht.com',
    ];
    for (final suffix in suffixes) {
      if (h.endsWith(suffix)) return true;
    }
    return false;
  }

  static const int cPrimary = 0xFF022A67;
  static const int cSurface = 0xFFFBFBFD;
  static const int cDarkCardColor = 0xFF1A2332;

  /// Active bottom-tab tint from the officer UI (cyan).
  static const int cBottomBarActive = 0xFF0F93D2;

  /// Token the web app can detect in `navigator.userAgent` for native shell traffic.
  static const String webViewAppSignature = 'SmartNPS360App';
}
