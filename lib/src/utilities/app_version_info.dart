import 'package:package_info_plus/package_info_plus.dart';

import 'app_config.dart';

/// Runtime app version/build from pubspec (via iOS/Android bundle metadata).
class AppVersionInfo {
  AppVersionInfo._();

  static String _version = '1.0.0';
  static String _buildNumber = '1';

  static String get version => _version;
  static String get buildNumber => _buildNumber;

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    _version = info.version.isNotEmpty ? info.version : _version;
    _buildNumber = info.buildNumber.isNotEmpty ? info.buildNumber : _buildNumber;
  }

  /// Example: `SmartNPS360App/1.0.0 (Flutter; InAppWebView; iOS; Build 16)`
  static String webViewUserAgentToken({required String platform}) {
    return '${AppConfig.webViewAppSignature}/$_version '
        '(Flutter; InAppWebView; $platform; Build $_buildNumber)';
  }
}
