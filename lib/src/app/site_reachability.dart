import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_routes.dart';

class SiteReachability {
  SiteReachability._();

  static const _timeout = Duration(seconds: 5);

  static Future<bool>? _inFlight;

  /// True when smartnps360.com returns any HTTP status (200, 403, 502, etc.).
  /// Only waits for response headers — not the heavy WebView page.
  static Future<bool> canReachSite() {
    return _inFlight ??= _probe().whenComplete(() {
      _inFlight = null;
    });
  }

  static Future<bool> _probe() async {
    final uri = Uri.parse(AppRoutes.webBaseUrl);
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..idleTimeout = _timeout
      ..autoUncompress = false;
    try {
      final headStatus = await _statusFor(client, 'HEAD', uri);
      if (headStatus == HttpStatus.methodNotAllowed) {
        final getStatus = await _statusFor(client, 'GET', uri);
        _log(getStatus != null, method: 'GET', status: getStatus);
        return getStatus != null;
      }
      if (headStatus != null) {
        _log(true, method: 'HEAD', status: headStatus);
        return true;
      }
      _log(false, method: 'HEAD');
      return false;
    } catch (e) {
      _log(false, error: e);
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<int?> _statusFor(
    HttpClient client,
    String method,
    Uri uri,
  ) async {
    try {
      final request = await client.openUrl(method, uri).timeout(_timeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.persistentConnection = false;
      if (method == 'GET') {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      }
      final response = await request.close().timeout(_timeout);
      unawaited(response.drain<void>());
      return response.statusCode;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on TlsException {
      return null;
    } on HttpException {
      return null;
    } on OSError {
      return null;
    }
  }

  static void _log(
    bool reachable, {
    String? method,
    int? status,
    Object? error,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[SmartNPS360][Reachability] reachable=$reachable'
      '${method != null ? ' $method' : ''}'
      '${status != null ? ' status=$status' : ''}'
      '${error != null ? ' error=$error' : ''}',
    );
  }
}
