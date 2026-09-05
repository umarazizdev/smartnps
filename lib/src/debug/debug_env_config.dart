import 'package:shared_preferences/shared_preferences.dart';

class DebugEnvConfig {
  DebugEnvConfig._();

  static final DebugEnvConfig instance = DebugEnvConfig._();

  static const String defaultApiOrigin = 'https://smartnps360.com';
  static const String defaultWebBaseUrl = 'https://smartnps360.com/';
  static const String apiPathSuffix = '/api';
  static const String accessPin = 'qwerty';

  static const String _prefsApiKey = 'debug_env_api_base_url';
  static const String _prefsWebKey = 'debug_env_web_base_url';

  String? _apiOriginOverride;
  String? _webOverride;
  bool _ready = false;

  bool get isReady => _ready;

  bool get hasOverride => _apiOriginOverride != null || _webOverride != null;

  String get apiOrigin => _apiOriginOverride ?? defaultApiOrigin;

  String get apiBaseUrl => '$apiOrigin$apiPathSuffix';

  String get webBaseUrl => _webOverride ?? defaultWebBaseUrl;

  String? get overrideHost {
    final webHost = Uri.tryParse(webBaseUrl)?.host;
    if (webHost != null && webHost.isNotEmpty) return webHost.toLowerCase();
    final apiHost = Uri.tryParse(apiOrigin)?.host;
    if (apiHost != null && apiHost.isNotEmpty) return apiHost.toLowerCase();
    return null;
  }

  Set<String> get overrideHosts {
    final hosts = <String>{};
    for (final raw in [apiOrigin, webBaseUrl]) {
      final host = Uri.tryParse(raw)?.host;
      if (host != null && host.isNotEmpty) hosts.add(host.toLowerCase());
    }
    return hosts;
  }

  Future<void> ensureReady() => init();

  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final api = prefs.getString(_prefsApiKey)?.trim();
    final web = prefs.getString(_prefsWebKey)?.trim();
    _apiOriginOverride =
        (api == null || api.isEmpty) ? null : _normalizeApiOrigin(api);
    _webOverride = (web == null || web.isEmpty) ? null : _normalizeWebBase(web);
    _ready = true;
  }

  Future<void> save({
    required String apiOrigin,
    required String webBaseUrl,
  }) async {
    final api = _normalizeApiOrigin(apiOrigin);
    final web = _normalizeWebBase(webBaseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsApiKey, api);
    await prefs.setString(_prefsWebKey, web);
    _apiOriginOverride = api;
    _webOverride = web;
  }

  Future<void> resetToProduction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsApiKey);
    await prefs.remove(_prefsWebKey);
    _apiOriginOverride = null;
    _webOverride = null;
  }

  static String? validateBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'URL is required';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL with host (e.g. http://192.168.1.10:8000)';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL must start with http:// or https://';
    }
    return null;
  }

  static String _normalizeApiOrigin(String raw) {
    var value = raw.trim();
    while (value.endsWith('/') && value.length > 1) {
      value = value.substring(0, value.length - 1);
    }
    if (value.toLowerCase().endsWith('/api')) {
      value = value.substring(0, value.length - 4);
      while (value.endsWith('/') && value.length > 1) {
        value = value.substring(0, value.length - 1);
      }
    }
    return value;
  }

  static String _normalizeWebBase(String raw) {
    var value = raw.trim();
    if (!value.endsWith('/')) value = '$value/';
    return value;
  }
}
