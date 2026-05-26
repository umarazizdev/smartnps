class AppConfig {
  static const String appName = 'SmartNPS360';

  static const String initialUrl = 'https://smartnps360.com/';

  static const String allowedHost = 'smartnps360.com';
  static const Set<String> allowedHosts = {
    'smartnps360.com',
    'www.smartnps360.com',
  };

  static bool isAllowedHost(String? host) =>
      host != null && allowedHosts.contains(host.toLowerCase());

  // UI colors aligned with your native app.
  static const int cPrimary = 0xFF022A67;
  static const int cSurface = 0xFFFBFBFD;
  static const int cDarkCardColor = 0xFF1A2332;
}
