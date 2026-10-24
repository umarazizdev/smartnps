import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_routes.dart';

class SiteReachability {
  SiteReachability._();

  static const _timeout = Duration(seconds: 5);
  static const _maxAttempts = 3;
  static const _retryDelay = Duration(milliseconds: 700);

  static Future<bool>? _inFlight;

  static Future<bool> canReachSite() {
    return _inFlight ??= _probeWithRetries().whenComplete(() {
      _inFlight = null;
    });
  }

  static Future<bool> _probeWithRetries() async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (await _probeOnce(attempt: attempt)) return true;
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(_retryDelay);
      }
    }
    return false;
  }

  static Future<bool> _probeOnce({required int attempt}) async {
    final uri = Uri.parse(AppRoutes.webBaseUrl);
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..idleTimeout = _timeout
      ..autoUncompress = false
      ..userAgent =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
    try {
      final headStatus = await _statusFor(client, 'HEAD', uri);
      if (headStatus == HttpStatus.methodNotAllowed || headStatus == null) {
        final getStatus = await _statusFor(client, 'GET', uri);
        _log(
          getStatus != null,
          method: 'GET',
          status: getStatus,
          attempt: attempt,
        );
        return getStatus != null;
      }
      _log(true, method: 'HEAD', status: headStatus, attempt: attempt);
      return true;
    } catch (e) {
      _log(false, error: e, attempt: attempt);
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
      try {
        await response.drain<void>().timeout(_timeout);
      } catch (_) {}
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
    int? attempt,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[SmartNPS360][Reachability] reachable=$reachable'
      '${attempt != null ? ' attempt=$attempt/$_maxAttempts' : ''}'
      '${method != null ? ' $method' : ''}'
      '${status != null ? ' status=$status' : ''}'
      '${error != null ? ' error=$error' : ''}',
    );
  }
}
