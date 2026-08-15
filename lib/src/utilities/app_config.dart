import '../app/app_routes.dart';

class AppConfig {
  AppConfig._();

  static const String appName = 'SmartNPS360';
  static const String webViewAppSignature = 'SmartNPS360App';

  static const String allowedHost = 'smartnps360.com';
  static const Set<String> allowedHosts = {
    'smartnps360.com',
    'www.smartnps360.com',
  };

  static const int cPrimary = 0xFF022A67;
  static const int cSurface = 0xFFFBFBFD;
  static const int cDarkCardColor = 0xFF1A2332;
  static const int cBottomBarActive = 0xFF0F93D2;

  static const bool enableMockLocationDetection = true;

  static const double keyboardOpenThreshold = 50.0;

  static bool isAllowedHost(String? host) {
    if (host == null) return false;
    final h = host.toLowerCase();
    if (allowedHosts.contains(h)) return true;
    return h.endsWith('.$allowedHost');
  }

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

  static bool isLoginRoute(Uri? uri) {
    if (uri == null) return false;
    if (!isAllowedHost(uri.host)) return false;

    final exact = _exactUrl(uri);
    return exact == AppRoutes.webLoginUrl ||
        exact == '${AppRoutes.webLoginUrl}/';
  }

  static bool isOfficerApplicationUrl(Uri? uri) {
    if (uri == null) return false;
    if (!isAllowedHost(uri.host)) return false;
    if (isLoginRoute(uri)) return false;

    final exact = _exactUrl(uri);
    return exact == AppRoutes.webDashboardUrl ||
        exact == AppRoutes.webTimesheetUrl ||
        exact == AppRoutes.webProfileUrl;
  }

  static String? normalizeWebPath(Uri? uri) {
    if (uri == null) return null;
    if (!isAllowedHost(uri.host)) return null;
    var path = uri.path.toLowerCase();
    if (path.isEmpty) return null;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static int? bottomTabIndexForUri(Uri? uri) {
    final path = normalizeWebPath(uri);
    if (path == null) return null;
    for (var i = 0; i < AppRoutes.bottomBarWebPaths.length; i++) {
      if (AppRoutes.bottomBarWebPaths[i] == path) return i;
    }
    return null;
  }

  static bool isBottomBarRoute(Uri? uri) => bottomTabIndexForUri(uri) != null;

  static String _exactUrl(Uri uri) {
    final text = uri.toString();
    if (text.endsWith('/') && uri.path != '/' && uri.path.isNotEmpty) {
      return text.substring(0, text.length - 1);
    }
    return text;
  }
}
