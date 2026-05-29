import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'js_bridge.dart';
import 'offline_screen.dart';
import '../widgets/platform_bottom_bar.dart';
import '../widgets/mock_location_dialog.dart';
import '../auth/auth_state.dart';
import '../auth/auth_repository.dart';
import '../api/api_client.dart';

class WebViewShell extends StatefulWidget {
  const WebViewShell({super.key});

  @override
  State<WebViewShell> createState() => _WebViewShellState();
}

class _WebViewShellState extends State<WebViewShell> {
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefreshController;

  bool _firstPageLoaded = false;
  bool _showOffline = false;
  Uri? _currentUri;
  bool _webPrefersDark = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _mockLocationDialogVisible = false;
  final Map<int, StreamSubscription<Position>> _nativeGeoWatches = {};

  Map<String, dynamic> _safeBridgePayloadForLog(Map payload) {
    final copy = <String, dynamic>{};
    payload.forEach((key, value) {
      final k = key.toString().toLowerCase();
      if (k.contains('password')) return;
      copy[key.toString()] = value;
    });
    return copy;
  }

  String _safeTextForLog(Object? value, {int max = 800}) {
    final text = value?.toString() ?? '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  bool _isSimulatedBySoftware(Position position) {
    try {
      final dynamic p = position;
      final dynamic sourceInformation = p.sourceInformation;
      return sourceInformation?.isSimulatedBySoftware == true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _toWebGeolocationPayloadFromBridgeLocation(
    Map<String, dynamic> location,
  ) {
    return {
      'coords': {
        'latitude': location['latitude'],
        'longitude': location['longitude'],
        'accuracy': location['accuracy'],
        'altitude': location['altitude'] ?? 0,
        'altitudeAccuracy': null,
        'heading': location['heading'] ?? 0,
        'speed': location['speed'] ?? 0,
      },
      'timestamp':
          location['timestampMs'] ?? DateTime.now().millisecondsSinceEpoch,
      'nativeSource': true,
      // Pass through native verification fields (when present).
      'provider': 'flutter_geolocator',
      'is_mocked': location['isMocked'] == true,
      'is_simulated_by_software': location['isSimulatedBySoftware'] == true,
      'accepted_from_live_stream': location['acceptedFromLiveStream'] == true,
      'max_allowed_accuracy_meters': location['maxAllowedAccuracyMeters'] ?? 0,
      'timeout_ms': location['timeoutMs'] ?? 0,
    };
  }

  Map<String, dynamic> _toWebGeolocationPayloadFromPosition(
    Position position, {
    required double requiredAccuracyMeters,
  }) {
    return {
      'coords': {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'altitudeAccuracy': null,
        'heading': position.heading,
        'speed': position.speed,
      },
      'timestamp': position.timestamp.millisecondsSinceEpoch,
      'nativeSource': true,
      'provider': 'flutter_geolocator',
      'is_mocked': position.isMocked,
      'is_simulated_by_software': _isSimulatedBySoftware(position),
      'accepted_from_live_stream': true,
      'max_allowed_accuracy_meters': requiredAccuracyMeters,
      'timeout_ms': 0,
    };
  }

  static final UserScript _smartNpsBridgeScript = UserScript(
    source: r'''
    (function () {
      'use strict';

      try {
        if (window.__smartnps_native_bridge_installed) return;
        window.__smartnps_native_bridge_installed = true;

        function safeJsonParse(value) {
          if (typeof value !== 'string') return value;
          try { return JSON.parse(value); } catch (_) { return null; }
        }

        function callbackOk(payload) {
          try {
            if (window.SmartNPSWeb && typeof window.SmartNPSWeb.receiveLocation === 'function') {
              window.SmartNPSWeb.receiveLocation(payload);
            }
          } catch (_) {}
        }

        function callbackErr(payload) {
          try {
            if (window.SmartNPSWeb && typeof window.SmartNPSWeb.receiveLocationError === 'function') {
              window.SmartNPSWeb.receiveLocationError(payload);
            }
          } catch (_) {}
        }

        function ensureFlutterBridge() {
          if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
            return Promise.resolve(true);
          }
          return new Promise(function (resolve, reject) {
            var done = false;
            function finish() {
              if (done) return;
              done = true;
              window.removeEventListener('flutterInAppWebViewPlatformReady', onReady);
              if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
                resolve(true);
              } else {
                reject(new Error('Flutter bridge is not available.'));
              }
            }
            function onReady() { finish(); }
            window.addEventListener('flutterInAppWebViewPlatformReady', onReady);
            setTimeout(finish, 4000);
          });
        }

        function postAuthEvent(payload) {
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler('authEvent', payload);
            });
        }

        if (!window.SmartNPSNativeAuth) window.SmartNPSNativeAuth = {};
        if (typeof window.SmartNPSNativeAuth.login !== 'function') {
          window.SmartNPSNativeAuth.login = function (user, session) {
            return postAuthEvent({
              action: 'login',
              user: user || null,
              session: session || null
            });
          };
        }
        if (typeof window.SmartNPSNativeAuth.setSession !== 'function') {
          window.SmartNPSNativeAuth.setSession = function (session) {
            return postAuthEvent({ action: 'session', session: session || null });
          };
        }
        if (typeof window.SmartNPSNativeAuth.logout !== 'function') {
          window.SmartNPSNativeAuth.logout = function () {
            return postAuthEvent({ action: 'logout' });
          };
        }

        function handleMessage(payload) {
          var data = safeJsonParse(payload);
          if (!data || typeof data !== 'object') {
            callbackErr({ code: 'INVALID_PAYLOAD', message: 'Invalid bridge payload.' });
            return;
          }

          var action = String(data.action || data.type || '');
          if (action !== 'request_current_location') {
            callbackErr({ code: 'UNSUPPORTED_ACTION', message: 'Unsupported action: ' + action });
            return;
          }

          ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler('getCurrentLocation', data);
            })
            .then(function (result) {
              if (!result || result.ok !== true || !result.location) {
                var message = (result && result.error && result.error.message) ? result.error.message : 'Native GPS failed.';
                callbackErr({ code: 'NATIVE_GPS_FAILED', message: message });
                return;
              }

              var loc = result.location || {};
              callbackOk({
                latitude: Number(loc.latitude),
                longitude: Number(loc.longitude),
                accuracy: Number(loc.accuracy),
                provider: 'flutter_geolocator',
                timestamp: (typeof loc.timestampMs === 'number' && isFinite(loc.timestampMs)) ? Number(loc.timestampMs) : Date.now(),
                timestamp_iso: (typeof loc.timestamp === 'string') ? String(loc.timestamp) : null,
                altitude: Number(loc.altitude || 0),
                speed: Number(loc.speed || 0),
                heading: Number(loc.heading || 0),
                is_mocked: loc.isMocked === true,
                is_simulated_by_software: loc.isSimulatedBySoftware === true,
                accepted_from_live_stream: loc.acceptedFromLiveStream === true,
                max_allowed_accuracy_meters: Number(loc.maxAllowedAccuracyMeters || 0),
                timeout_ms: Number(loc.timeoutMs || 0)
              });
            })
            .catch(function (e) {
              callbackErr({ code: 'NATIVE_BRIDGE_ERROR', message: (e && e.message) ? e.message : String(e) });
            });
        }

        if (!window.SmartNPSBridge) window.SmartNPSBridge = {};
        if (typeof window.SmartNPSBridge.postMessage !== 'function') {
          window.SmartNPSBridge.postMessage = handleMessage;
        }

        if (!window.SmartNPSAndroid) window.SmartNPSAndroid = {};
        if (typeof window.SmartNPSAndroid.postMessage !== 'function') {
          window.SmartNPSAndroid.postMessage = handleMessage;
        }
      } catch (_) {}
    })();
  ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  static final UserScript _geolocationScript = UserScript(
    source: r'''
    (function () {
      try {
        if (!navigator.geolocation) return;
        if (window.__smartnps_native_geo_installed) return;

        window.__smartnps_native_geo_installed = true;

        var nativeWatchCounter = 900000;
        var nativeWatches = {};
        var nativeWatchCallbacks = {};

        function log(message, data) {
          try {
            console.log('[SmartNPS360 Native GPS] ' + message, data || '');
          } catch (_) {}
        }

        function gpsError(message) {
          return {
            code: 2,
            message: message || 'Native GPS location unavailable.'
          };
        }

        function waitForFlutterBridge() {
          if (
            window.flutter_inappwebview &&
            typeof window.flutter_inappwebview.callHandler === 'function'
          ) {
            return Promise.resolve(true);
          }

          return new Promise(function (resolve, reject) {
            var completed = false;

            function done() {
              if (completed) return;
              completed = true;
              window.removeEventListener(
                'flutterInAppWebViewPlatformReady',
                onReady
              );

              if (
                window.flutter_inappwebview &&
                typeof window.flutter_inappwebview.callHandler === 'function'
              ) {
                resolve(true);
              } else {
                reject(new Error('Flutter bridge is not available.'));
              }
            }

            function onReady() {
              done();
            }

            window.addEventListener(
              'flutterInAppWebViewPlatformReady',
              onReady
            );

            setTimeout(done, 4000);
          });
        }

        function convertNativeResult(result) {
          if (!result || result.ok !== true || !result.location) {
            var message =
              result &&
              result.error &&
              result.error.message
                ? result.error.message
                : 'Native GPS failed.';

            throw new Error(message);
          }

          var location = result.location;
          var timestamp = Date.parse(location.timestamp);

          if (!Number.isFinite(timestamp)) {
            timestamp = Date.now();
          }

          return {
            coords: {
              latitude: Number(location.latitude),
              longitude: Number(location.longitude),
              accuracy: Number(location.accuracy),
              altitude: Number(location.altitude || 0),
              altitudeAccuracy: null,
              heading: Number(location.heading || 0),
              speed: Number(location.speed || 0)
            },
            timestamp: timestamp,

            // Extra native verification values available to your page.
            nativeSource: true,
            ageMsWhenAccepted: Number(location.ageMsWhenAccepted || 0),
            isFreshLiveLocation: location.isFreshLiveLocation === true,
            isCachedLocation: location.isCachedLocation === true
          };
        }

        function requestNativePosition(success, error) {
          log('Native location requested from webpage');

          waitForFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'getCurrentLocation',
                {
                  source: 'flutter_geolocation_override',
                  requestedAt: Date.now()
                }
              );
            })
            .then(function (result) {
              log('Native location response received', result);

              var position = convertNativeResult(result);

              if (typeof success === 'function') {
                success(position);
              }
            })
            .catch(function (exception) {
              log('Native location failed', exception.message);

              if (typeof error === 'function') {
                error(gpsError(exception.message));
              }
            });
        }

        function ensureWatchRegistry(watchId, success, error) {
          nativeWatches[watchId] = true;
          nativeWatchCallbacks[watchId] = {
            success: (typeof success === 'function') ? success : null,
            error: (typeof error === 'function') ? error : null
          };
        }

        // Called by Flutter to emit watch updates.
        window.__smartnps_native_geo_emit = function (watchId, payload) {
          try {
            var cb = nativeWatchCallbacks[watchId];
            if (!cb || !nativeWatches[watchId]) return;
            if (cb.success) cb.success(payload);
          } catch (_) {}
        };

        // Called by Flutter to emit watch errors.
        window.__smartnps_native_geo_error = function (watchId, payload) {
          try {
            var cb = nativeWatchCallbacks[watchId];
            if (!cb || !nativeWatches[watchId]) return;
            if (cb.error) cb.error(payload);
          } catch (_) {}
        };

        navigator.geolocation.getCurrentPosition = function (
          success,
          error,
          options
        ) {
          log('getCurrentPosition intercepted');
          requestNativePosition(success, error);
        };

        navigator.geolocation.watchPosition = function (
          success,
          error,
          options
        ) {
          log('watchPosition intercepted');

          var watchId = ++nativeWatchCounter;
          ensureWatchRegistry(watchId, success, error);

          waitForFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'startLocationWatch',
                {
                  watchId: watchId,
                  options: options || null,
                  source: 'flutter_geolocation_watch_override',
                  requestedAt: Date.now()
                }
              );
            })
            .catch(function (exception) {
              log('startLocationWatch failed', exception.message);
              if (typeof error === 'function') {
                error(gpsError(exception.message));
              }
            });

          return watchId;
        };

        navigator.geolocation.clearWatch = function (watchId) {
          log('clearWatch intercepted', watchId);
          delete nativeWatches[watchId];
          delete nativeWatchCallbacks[watchId];
          try {
            if (
              window.flutter_inappwebview &&
              typeof window.flutter_inappwebview.callHandler === 'function'
            ) {
              window.flutter_inappwebview.callHandler('clearLocationWatch', {
                watchId: watchId,
                source: 'flutter_geolocation_watch_override',
                requestedAt: Date.now()
              });
            }
          } catch (_) {}
        };

        log('Flutter native GPS override installed successfully');
      } catch (exception) {
        try {
          console.log(
            '[SmartNPS360 Native GPS] Installation failed',
            exception.message
          );
        } catch (_) {}
      }
    })();
  ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );
  late final JsBridge _bridge = JsBridge(
    getCurrentUrlHost: () => _currentUri?.host,
    onDownloadRequested: _downloadAndReturn,
  );

  void _applySystemUi() {
    SystemChrome.setSystemUIOverlayStyle(
      _webPrefersDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
  }

  @override
  void initState() {
    super.initState();
    _webPrefersDark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    _applySystemUi();

    if (Platform.isAndroid || Platform.isIOS) {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(color: const Color(AppConfig.cPrimary)),
        onRefresh: () async {
          final controller = _controller;
          if (controller == null) return;
          if (Platform.isAndroid) {
            await controller.reload();
          } else if (Platform.isIOS) {
            final url = await controller.getUrl();
            if (url != null) {
              await controller.loadUrl(urlRequest: URLRequest(url: url));
            } else {
              await controller.reload();
            }
          }
        },
      );
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasInternet = results.any((r) => r != ConnectivityResult.none);
      if (hasInternet && _showOffline) {
        setState(() => _showOffline = false);
        unawaited(_controller?.reload());
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    for (final sub in _nativeGeoWatches.values) {
      sub.cancel();
    }
    _nativeGeoWatches.clear();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _showOffline = false);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConfig.initialUrl)),
    );
  }

  bool _isInternalUrl(Uri uri) => AppConfig.isAllowedHost(uri.host);

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final uri = action.request.url?.uriValue;
    if (uri == null) return NavigationActionPolicy.ALLOW;

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      if (_isInternalUrl(uri)) return NavigationActionPolicy.ALLOW;
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return opened
          ? NavigationActionPolicy.CANCEL
          : NavigationActionPolicy.ALLOW;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.CANCEL;
  }

  Future<bool> _onWillPop() async {
    final controller = _controller;
    if (controller == null) return true;
    final canGoBack = await controller.canGoBack();
    if (canGoBack) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  void _installJsHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'pickFile',
      callback: (args) => _bridge.pickFile(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'pickImage',
      callback: (args) => _bridge.pickImage(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'takePhoto',
      callback: (args) => _bridge.takePhoto(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'getCurrentLocation',
      callback: (args) async {
        debugPrint(
          '[SmartNPS360] JS callHandler: getCurrentLocation args=$args',
        );
        final result = await _bridge.getCurrentLocation(
          args.isEmpty ? null : args.first,
        );
        debugPrint('[SmartNPS360] getCurrentLocation result=$result');
        _maybeShowMockLocationDialog(result);
        return result;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'startLocationWatch',
      callback: (args) async {
        final Map? payload = args.isNotEmpty && args.first is Map
            ? args.first as Map
            : null;
        if (payload == null) {
          return {
            'ok': false,
            'error': {'code': 'invalid_args', 'message': 'Missing payload'},
          };
        }
        final int? watchId =
            payload['watchId'] is num
                ? (payload['watchId'] as num).toInt()
                : null;
        if (watchId == null) {
          return {'ok': false, 'error': {'code': 'invalid_args', 'message': 'Missing watchId'}};
        }

        await _nativeGeoWatches.remove(watchId)?.cancel();

        // Use the same trust + permission checks as getCurrentLocation.
        final Map<String, dynamic> initial =
            await _bridge.getCurrentLocation(payload);
        if (initial['ok'] != true) return initial;
        final Map<String, dynamic>? initialLocation =
            (initial['location'] is Map<String, dynamic>)
                ? initial['location'] as Map<String, dynamic>
                : null;
        if (initialLocation != null) {
          final initialPayload =
              _toWebGeolocationPayloadFromBridgeLocation(initialLocation);
          final js =
              'window.__smartnps_native_geo_emit($watchId, ${jsonEncode(initialPayload)});';
          await controller.evaluateJavascript(source: js);
        }

        final Map? options =
            payload['options'] is Map ? payload['options'] as Map : null;
        final int intervalMs =
            options != null && options['interval_ms'] is num
                ? (options['interval_ms'] as num).toInt().clamp(500, 5000)
                : 1000;
        final double requiredAccuracyMeters =
            options != null && options['required_accuracy_meters'] is num
                ? (options['required_accuracy_meters'] as num).toDouble().clamp(5.0, 500.0)
                : 15.0;

        final LocationSettings settings;
        if (Platform.isAndroid) {
          settings = AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: Duration(milliseconds: intervalMs),
            timeLimit: null,
            forceLocationManager: false,
          );
        } else if (Platform.isIOS) {
          settings = AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            timeLimit: null,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: false,
          );
        } else {
          settings = LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            timeLimit: null,
          );
        }

        final sub = Geolocator.getPositionStream(locationSettings: settings)
            .listen(
          (position) async {
            if (position.accuracy > requiredAccuracyMeters) return;
            final payload = _toWebGeolocationPayloadFromPosition(
              position,
              requiredAccuracyMeters: requiredAccuracyMeters,
            );
            final js = 'window.__smartnps_native_geo_emit($watchId, ${jsonEncode(payload)});';
            await controller.evaluateJavascript(source: js);
          },
          onError: (Object error) async {
            final err = {
              'code': 2,
              'message': error.toString(),
            };
            final js =
                'window.__smartnps_native_geo_error($watchId, ${jsonEncode(err)});';
            await controller.evaluateJavascript(source: js);
          },
        );
        _nativeGeoWatches[watchId] = sub;

        return {'ok': true, 'watchId': watchId, 'intervalMs': intervalMs};
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'clearLocationWatch',
      callback: (args) async {
        final Map? payload = args.isNotEmpty && args.first is Map
            ? args.first as Map
            : null;
        final int? watchId =
            payload != null && payload['watchId'] is num
                ? (payload['watchId'] as num).toInt()
                : null;
        if (watchId == null) return {'ok': false};
        await _nativeGeoWatches.remove(watchId)?.cancel();
        return {'ok': true, 'watchId': watchId};
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'getDeviceInfo',
      callback: (args) =>
          _bridge.getDeviceInfo(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'openExternalUrl',
      callback: (args) =>
          _bridge.openExternalUrl(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'shareContent',
      callback: (args) =>
          _bridge.shareContent(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'downloadFile',
      callback: (args) =>
          _bridge.downloadFile(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'getPushNotificationToken',
      callback: (args) =>
          _bridge.getPushNotificationToken(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'themeChanged',
      callback: (args) {
        final value = args.isNotEmpty ? args.first : null;
        final next = value is bool ? value : null;
        if (next != null && mounted) {
          setState(() => _webPrefersDark = next);
          _applySystemUi();
        }
        return {'ok': true};
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'loginWithSanctum',
      callback: (args) async {
        final currentHost = _currentUri?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          debugPrint(
            '[SmartNPS360][Auth] denied loginWithSanctum from host=$currentHost args=$args',
          );
          return {
            'ok': false,
            'error': {'code': 'untrusted_origin', 'message': 'Untrusted origin'},
          };
        }

        final dynamic first = args.isNotEmpty ? args.first : null;
        final Map? payload = first is Map ? first : null;
        if (payload == null) {
          return {
            'ok': false,
            'error': {'code': 'invalid_args', 'message': 'Missing payload'},
          };
        }

        final username = payload['username']?.toString();
        final password = payload['password']?.toString();
        if (username == null ||
            username.isEmpty ||
            password == null ||
            password.isEmpty) {
          return {
            'ok': false,
            'error': {
              'code': 'invalid_args',
              'message': 'Missing username/password'
            },
          };
        }

        debugPrint(
          '[SmartNPS360][Auth] loginWithSanctum payload=${_safeBridgePayloadForLog(payload)}',
        );

        ApiClient.instance.ensureAuthInterceptorInstalled();
        final dio = ApiClient.instance.dio;
        try {
          final response = await dio.postUri(
            Uri.parse(AppConfig.sanctumLoginUrl),
            data: {
              'employee_no': username,
              'password': password,
              'device_name': 'mobile-app',
            },
            options: Options(
              headers: const {'Accept': 'application/json'},
              contentType: Headers.jsonContentType,
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

          debugPrint(
            '[SmartNPS360][Auth] sanctum login status=${response.statusCode} body=${_safeTextForLog(response.data)}',
          );

          final dynamic body = response.data;
          final Map<String, dynamic>? map =
              body is Map ? Map<String, dynamic>.from(body) : null;
          final token =
              (map?['token'] ?? map?['access_token'] ?? map?['accessToken'])
                  ?.toString();
          if (token == null || token.isEmpty) {
            return {
              'ok': false,
              'error': {
                'code': 'missing_token',
                'message': 'Login succeeded but token missing in response'
              },
            };
          }

          await AuthRepository.instance.saveAccessToken(token);
          AuthState.instance.setSession({'accessToken': token});

          return {'ok': true, 'hasToken': true};
        } catch (e) {
          debugPrint('[SmartNPS360][Auth] sanctum login failed: $e');
          return {
            'ok': false,
            'error': {'code': 'request_failed', 'message': e.toString()},
          };
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'authEvent',
      callback: (args) async {
        final currentHost = _currentUri?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          debugPrint(
            '[SmartNPS360][Auth] denied authEvent from host=$currentHost args=$args',
          );
          return {
            'ok': false,
            'error': {'code': 'untrusted_origin', 'message': 'Untrusted origin'},
          };
        }

        final dynamic first = args.isNotEmpty ? args.first : null;
        final Map? payload = first is Map ? first : null;
        if (payload == null) {
          return {
            'ok': false,
            'error': {'code': 'invalid_args', 'message': 'Missing payload'},
          };
        }

        final action = (payload['action'] ?? payload['type'] ?? '').toString();
        if (action == 'logout') {
          AuthState.instance.clear();
          await AuthRepository.instance.clear();
          return {'ok': true, 'action': 'logout'};
        }

        if (action == 'login') {
          final dynamic rawUser = payload['user'] ?? payload['profile'];
          final Map<String, dynamic>? user =
              rawUser is Map ? Map<String, dynamic>.from(rawUser) : null;
          if (user == null) {
            return {
              'ok': false,
              'error': {'code': 'invalid_args', 'message': 'Missing user'},
            };
          }
          AuthState.instance.setLoggedInUser(user);
          final dynamic rawSession =
              payload['session'] ?? payload['auth'] ?? payload['tokens'];
          final Map<String, dynamic>? session =
              rawSession is Map ? Map<String, dynamic>.from(rawSession) : null;
          if (session != null) {
            AuthState.instance.setSession(session);
          }
          final accessToken =
              (payload['accessToken'] ??
                      payload['access_token'] ??
                      payload['token'] ??
                      payload['jwt'] ??
                      session?['accessToken'] ??
                      session?['access_token'] ??
                      session?['token'] ??
                      session?['jwt'])
                  ?.toString();
          final refreshToken =
              (payload['refreshToken'] ??
                      payload['refresh_token'] ??
                      session?['refreshToken'] ??
                      session?['refresh_token'])
                  ?.toString();
          await AuthRepository.instance.saveLogin(
            user: user,
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
          return {'ok': true, 'action': 'login'};
        }

        if (action == 'session') {
          final dynamic rawSession =
              payload['session'] ?? payload['auth'] ?? payload['tokens'];
          final Map<String, dynamic>? session =
              rawSession is Map ? Map<String, dynamic>.from(rawSession) : null;
          if (session == null) {
            return {
              'ok': false,
              'error': {'code': 'invalid_args', 'message': 'Missing session'},
            };
          }
          AuthState.instance.setSession(session);
          final accessToken =
              (payload['accessToken'] ??
                      payload['access_token'] ??
                      payload['token'] ??
                      payload['jwt'] ??
                      session['accessToken'] ??
                      session['access_token'] ??
                      session['token'] ??
                      session['jwt'])
                  ?.toString();
          final refreshToken =
              (payload['refreshToken'] ??
                      payload['refresh_token'] ??
                      session['refreshToken'] ??
                      session['refresh_token'])
                  ?.toString();
          await AuthRepository.instance.saveLogin(
            user: AuthState.instance.user.value ?? <String, dynamic>{},
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
          return {'ok': true, 'action': 'session'};
        }

        return {
          'ok': false,
          'error': {
            'code': 'unsupported_action',
            'message': 'Unsupported auth action: $action',
          },
        };
      },
    );
  }

  void _maybeShowMockLocationDialog(Map<String, dynamic> result) {
    if (!mounted) return;
    if (_mockLocationDialogVisible) return;

    final ok = result['ok'] == true;
    if (!ok) return;

    final location = result['location'];
    if (location is! Map) return;

    final isMocked = location['isMocked'] == true;
    final isSimulatedBySoftware = location['isSimulatedBySoftware'] == true;
    if (!isMocked && !isSimulatedBySoftware) return;

    _mockLocationDialogVisible = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => const MockLocationDialog(),
    ).whenComplete(() {
      if (mounted) _mockLocationDialogVisible = false;
    });
  }

  Future<void> _installThemeListener(InAppWebViewController controller) async {
    await controller.evaluateJavascript(
      source: '''
	      (function () {
	        try {
		          if (window.__smartnps_theme_listener_installed) return;
		          window.__smartnps_theme_listener_installed = true;
		          window.__smartnps_theme_last = null;
		          function computeDark() {
		            try {
		              var mq = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
		              var sysDark = mq && typeof mq.matches === 'boolean' ? !!mq.matches : null;

	              var html = document.documentElement;
	              var body = document.body;
	              var htmlClass = (html && html.className ? String(html.className) : '').toLowerCase();
	              var bodyClass = (body && body.className ? String(body.className) : '').toLowerCase();
	              var dataTheme = (html && html.getAttribute ? (html.getAttribute('data-theme') || html.getAttribute('data-bs-theme')) : '') || '';
	              dataTheme = String(dataTheme).toLowerCase();

	              var classDark = htmlClass.indexOf('dark') !== -1 || bodyClass.indexOf('dark') !== -1;
	              var dataDark = dataTheme === 'dark';
	              var dataLight = dataTheme === 'light';

		              if (dataDark) return true;
		              if (dataLight) return false;
		              if (classDark) return true;
		              // Heuristic: infer from computed background color when the site toggles
		              // theme without changing attributes/classes (CSS variables, inline styles).
		              try {
		                var el = document.body || document.documentElement;
		                if (el && window.getComputedStyle) {
		                  var bg = getComputedStyle(el).backgroundColor;
		                  if (bg && typeof bg === 'string' && bg.indexOf('rgb') === 0) {
		                    var nums = bg.replace(/rgba?\\(|\\)|\\s/g,'').split(',');
		                    if (nums.length >= 3) {
		                      var r = parseFloat(nums[0]) || 0;
		                      var g = parseFloat(nums[1]) || 0;
		                      var b = parseFloat(nums[2]) || 0;
		                      var lum = 0.2126*r + 0.7152*g + 0.0722*b;
		                      if (lum <= 128) return true;
		                      if (lum >= 180) return false;
		                    }
		                  }
		                }
		              } catch (e) {}
		              if (sysDark !== null) return sysDark;
		              return null;
		            } catch (e) {}
		            return null;
		          }

		          function notify() {
		            try {
		              var next = computeDark();
		              if (next === null || next === window.__smartnps_theme_last) return;
		              window.__smartnps_theme_last = next;
		              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
		                window.flutter_inappwebview.callHandler('themeChanged', !!next);
		              }
		            } catch (e) {}
		          }

	          notify();

	          // System theme changes
	          try {
	            var mq = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
	            if (mq) {
	              if (typeof mq.addEventListener === 'function') mq.addEventListener('change', notify);
	              else if (typeof mq.addListener === 'function') mq.addListener(notify);
	            }
	          } catch (e) {}

		          // In-page theme toggles
		          try {
	            var target1 = document.documentElement;
	            var target2 = document.body;
	            var obs = new MutationObserver(function() {
	              if (window.__smartnps_theme_tick) return;
	              window.__smartnps_theme_tick = true;
	              setTimeout(function() {
	                window.__smartnps_theme_tick = false;
	                notify();
	              }, 50);
	            });
		            if (target1) obs.observe(target1, { attributes: true, attributeFilter: ['class','data-theme','data-bs-theme'] });
		            if (target2) obs.observe(target2, { attributes: true, attributeFilter: ['class'] });
		          } catch (e) {}

		          // Fallback: periodic check for sites toggling via CSS variables/styles.
		          try { setInterval(notify, 400); } catch (e) {}
		        } catch (e) {}
		      })();
		    ''',
    );
  }

  Future<Map<String, dynamic>> _downloadAndReturn(
    Uri url, {
    String? filename,
  }) async {
    try {
      final dir = await _defaultDownloadDir();
      await dir.create(recursive: true);
      final safeName = _sanitizeFilename(
        filename ??
            url.pathSegments.lastWhere(
              (s) => s.trim().isNotEmpty,
              orElse: () => 'download',
            ),
      );
      final path = '${dir.path}/$safeName';
      final dio = Dio();
      await dio.download(url.toString(), path);
      return {
        'ok': true,
        'file': {'path': path, 'name': safeName},
      };
    } catch (e) {
      return {
        'ok': false,
        'error': {'code': 'download_failed', 'message': e.toString()},
      };
    }
  }

  Future<Directory> _defaultDownloadDir() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      return Directory(
        '${dir?.path ?? (await getTemporaryDirectory()).path}/downloads',
      );
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/downloads');
  }

  String _sanitizeFilename(String name) {
    final trimmed = name.trim().isEmpty ? 'download' : name.trim();
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          top: true,
          bottom: false,
          child: Stack(
            children: [
              if (_showOffline)
                OfflineScreen(onRetry: _retry)
              else
                Padding(
                  padding: EdgeInsets.only(bottom: 0),
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(AppConfig.initialUrl),
                    ),
                    initialUserScripts: UnmodifiableListView([
                      _smartNpsBridgeScript,
                      _geolocationScript,
                    ]),
                    pullToRefreshController: _pullToRefreshController,
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      allowsInlineMediaPlayback: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useShouldOverrideUrlLoading: true,
                      supportZoom: false,
                      transparentBackground: false,
                      thirdPartyCookiesEnabled: true,
                      cacheEnabled: true,
                      clearCache: false,
                      sharedCookiesEnabled: true,
                      userAgent:
                          'SmartNPS360/1.0 (Flutter; InAppWebView) ${Platform.operatingSystem}',
                      geolocationEnabled: false,
                      allowsBackForwardNavigationGestures: true,
                      verticalScrollBarEnabled: true,
                      horizontalScrollBarEnabled: false,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      _installJsHandlers(controller);
                    },
                    onConsoleMessage: (controller, message) {
                      debugPrint(
                        '[WebView][${message.messageLevel}] ${message.message}',
                      );
                    },
                    shouldOverrideUrlLoading: (controller, action) async =>
                        _handleNavigation(action),
                    onLoadStart: (controller, url) {
                      setState(() {
                        _currentUri = url?.uriValue;
                      });
                    },
                    onProgressChanged: (controller, progress) {
                      if (progress == 100) {
                        _pullToRefreshController?.endRefreshing();
                      }
                    },
                    onLoadStop: (controller, url) async {
                      _pullToRefreshController?.endRefreshing();
                      final prefersDark = await _readWebPrefersDark(controller);
                      await _installThemeListener(controller);
                      setState(() {
                        _currentUri = url?.uriValue;
                        _firstPageLoaded = true;
                        _webPrefersDark = prefersDark ?? _webPrefersDark;
                      });
                      _applySystemUi();
                    },
                    onReceivedError: (controller, request, error) async {
                      _pullToRefreshController?.endRefreshing();
                      if (!_firstPageLoaded) {
                        final connectivity = await Connectivity()
                            .checkConnectivity();
                        if (!connectivity.any(
                          (r) => r != ConnectivityResult.none,
                        )) {
                          if (mounted) setState(() => _showOffline = true);
                        }
                      }
                    },
                    onGeolocationPermissionsShowPrompt:
                        (controller, origin) async {
                          final uri = Uri.tryParse(origin);
                          final allow = uri == null
                              ? false
                              : AppConfig.isAllowedHost(uri.host);
                          if (!allow) {
                            return GeolocationPermissionShowPromptResponse(
                              origin: origin,
                              allow: false,
                              retain: false,
                            );
                          }
                          final status = await Permission.locationWhenInUse
                              .request();
                          final granted = status.isGranted;
                          return GeolocationPermissionShowPromptResponse(
                            origin: origin,
                            allow: granted,
                            retain: granted,
                          );
                        },
                    onReceivedServerTrustAuthRequest:
                        (controller, challenge) async {
                          final host = challenge.protectionSpace.host;
                          final isAllowed = AppConfig.isAllowedHost(host);

                          // iOS often reports sslError code 4 even when evaluation succeeded
                          // ("implicitly trusted, but user intent was not explicitly specified").
                          // Proceed for allowed hosts to avoid resource loading issues.
                          if (isAllowed) {
                            return ServerTrustAuthResponse(
                              action:
                                  ServerTrustAuthResponseAction.PROCEED,
                            );
                          }

                          return ServerTrustAuthResponse(
                            action: ServerTrustAuthResponseAction.CANCEL,
                          );
                        },
                    onDownloadStartRequest: (controller, request) async {
                      final uri = request.url.uriValue;
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
              if (!_firstPageLoaded && !_showOffline)
                _SplashOverlay(isDark: _webPrefersDark),
              if (_shouldShowBottomBar())
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _BottomBar(
                    currentUri: _currentUri,
                    isDark: _webPrefersDark,
                    onTap: _onBottomTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _readWebPrefersDark(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            const mq = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
            if (mq && typeof mq.matches === 'boolean') return mq.matches;
            return null;
          } catch (e) { return null; }
        })();
      ''',
      );
      if (result is bool) return result;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onBottomTap(_BottomItem item) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(item.url)));
  }

  bool _isAuthRoute(Uri? uri) {
    if (uri == null) return false;
    final s = (uri.path).toLowerCase();
    // Your login screen uses the base URL path.
    if (s.isEmpty || s == '/' || uri.toString() == AppConfig.initialUrl) {
      return true;
    }
    return s.contains('officer/login') ||
        s.contains('officer/sign-in') ||
        s.contains('officer/signin') ||
        s.contains('officer/sign_up') ||
        s.contains('officer/sign-up') ||
        s.contains('officer/signup') ||
        s.contains('officer/register');
  }

  bool _shouldShowBottomBar() {
    if (_showOffline) return false;
    if (!_firstPageLoaded) return false; // never on splash
    if (_isAuthRoute(_currentUri)) return false;
    return true;
  }
}

class _SplashOverlay extends StatelessWidget {
  const _SplashOverlay({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: isDark
          ? const Color(AppConfig.cDarkCardColor)
          : const Color(AppConfig.cSurface),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/npslogo.png', width: 160, height: 160),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BottomItem {
  dashboard(
    'Dashboard',
    'assets/postFilFill.png',
    'assets/postFil.png',
    'https://smartnps360.com/officer/dashboard',
  ),
  timesheet(
    'TimeSheet',
    'assets/calendar_outline.png',
    'assets/schedule.png',
    'https://smartnps360.com/officer/timesheet/monthly',
  ),
  dar(
    'DAR',
    'assets/reports.png',
    'assets/reports_outline.png',
    'https://smartnps360.com/officer/dar',
  ),
  profile(
    'Profile',
    'assets/avatar.png',
    'assets/profile.png',
    'https://smartnps360.com/officer/profile',
  );

  const _BottomItem(
    this.label,
    this.iconAsset,
    this.iconAssetSelected,
    this.url,
  );
  final String label;
  final String iconAsset;
  final String iconAssetSelected;
  final String url;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentUri,
    required this.isDark,
    required this.onTap,
  });

  final Uri? currentUri;
  final bool isDark;
  final ValueChanged<_BottomItem> onTap;

  int _indexFromUrl(Uri? uri) {
    final s = uri?.toString() ?? '';
    if (s.contains('/officer/timesheet')) return 1;
    if (s.contains('/officer/dar')) return 2;
    if (s.contains('/officer/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _indexFromUrl(currentUri);
    final tabs = <PlatformBottomTab>[
      for (final item in _BottomItem.values)
        PlatformBottomTab(
          label: item.label,
          index: item.index,
          iosSymbolName: switch (item) {
            _BottomItem.dashboard => 'house.fill',
            _BottomItem.timesheet => 'calendar',
            _BottomItem.dar => 'doc.text.image.fill',
            _BottomItem.profile => 'person.crop.circle.fill',
          },
          activeAssetIcon: item.iconAssetSelected,
          inactiveAssetIcon: item.iconAsset,
        ),
    ];

    return PlatformBottomBar(
      tabs: tabs,
      currentIndex: selected,
      tint: const Color(AppConfig.cPrimary),
      surface: const Color(AppConfig.cSurface),
      darkSurface: const Color(AppConfig.cDarkCardColor),
      onTap: (index) => onTap(_BottomItem.values[index]),
    );
  }
}
