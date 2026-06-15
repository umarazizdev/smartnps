import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utilities/app_config.dart';
import 'js_bridge.dart';
import '../app/offline_screen.dart';
import '../widgets/platform_bottom_bar.dart';
import '../widgets/background_location_required_banner.dart';
import '../location/mock_location_detection.dart';
import '../location/mock_location_guard.dart';
import '../auth/auth_session_manager.dart';
import '../auth/auth_state.dart';
import '../auth/auth_repository.dart';
import '../api/api_client.dart';
import '../background/duty_heartbeat_service.dart';
import '../background/background_location_permissions.dart';
import '../utilities/permission_settings_helper.dart';
import '../app/native_theme_controller.dart';
import '../push/push_notification_service.dart';
import '../utilities/overlay_prompt_guard.dart';

class WebViewShell extends StatefulWidget {
  const WebViewShell({super.key});

  @override
  State<WebViewShell> createState() => _WebViewShellState();
}

class _WebViewShellUiController extends GetxController {}

class _WebViewShellState extends State<WebViewShell>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefreshController;

  bool _firstPageLoaded = false;
  bool _showOffline = false;
  Uri? _currentUri;
  Uri? _uriAtLoadStart;
  bool _pullToRefreshActive = false;
  Uri? _pullToRefreshSourceUri;
  bool _webReloadInProgress = false;
  bool _webPrefersDark = false;
  bool _hasWebThemeSignal = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final Map<int, StreamSubscription<Position>> _nativeGeoWatches = {};
  final _WebViewShellUiController _uiController = _WebViewShellUiController();
  String? _pendingPushUrl;
  bool _hasNativeAuthSession = false;

  void _refreshUi() {
    if (mounted) _uiController.update();
  }

  void _setNativeAuthSession(bool value) {
    if (_hasNativeAuthSession == value) return;
    _hasNativeAuthSession = value;
    _refreshUi();
  }

  Future<void> _refreshNativeAuthSessionFromStorage() async {
    final token = await AuthRepository.instance.getAccessToken();
    _setNativeAuthSession(token != null && token.isNotEmpty);
  }

  bool _isSamePageReload(Uri? uriAtLoadStart, Uri? nextUri) {
    final start = _normalizePageUrl(uriAtLoadStart);
    final next = _normalizePageUrl(nextUri);
    if (start == null || next == null) return false;
    return start == next;
  }

  String? _normalizePageUrl(Uri? uri) {
    if (uri == null) return null;
    final withoutFragment = uri.replace(fragment: '');
    var normalized = withoutFragment.toString();
    if (normalized.endsWith('/') && withoutFragment.path.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void _clearPullToRefreshState() {
    _pullToRefreshActive = false;
    _pullToRefreshSourceUri = null;
  }

  bool _isTransientReloadUri(Uri? uri) {
    if (uri == null) return true;
    if (!_hasNativeAuthSession) return false;
    if (!_isAuthRoute(uri)) return false;
    final current = _currentUri;
    return current != null && !_isAuthRoute(current);
  }

  void _syncCurrentUriFromWebView(Uri? uri) {
    if (uri == null || _isTransientReloadUri(uri)) return;
    if (_currentUri?.toString() == uri.toString()) return;
    _currentUri = uri;
    _refreshUi();
  }

  void _restoreUriAfterReload(Uri? uri) {
    if (uri == null || _isAuthRoute(uri)) return;
    if (_currentUri?.toString() == uri.toString()) return;
    _currentUri = uri;
    _refreshUi();
  }

  bool _isPullToRefreshReload(Uri? nextUri) {
    if (!_pullToRefreshActive) return false;
    final source = _normalizePageUrl(_pullToRefreshSourceUri);
    final next = _normalizePageUrl(nextUri);
    if (source == null || next == null) return true;
    return source == next;
  }

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
      'is_simulated_by_software': MockLocationDetection.isSimulatedBySoftware(
        position,
      ),
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

        if (!window.SmartNPS360) window.SmartNPS360 = {};
        window.SmartNPS360.notifyTheme = function (mode) {
          var isDark = mode === 'dark' || mode === true;
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler('themeChanged', isDark);
            });
        };

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
            try { sessionStorage.removeItem('__smartnps_login'); } catch (_) {}
            return postAuthEvent({ action: 'logout' });
          };
        }

        function findLoginSubmitControl(form) {
          if (!form || !form.querySelector) return null;
          return (
            form.querySelector('button[type="submit"]') ||
            form.querySelector('input[type="submit"]') ||
            form.querySelector('button.btn-primary') ||
            form.querySelector('button')
          );
        }

        function setLoginLoading(form, loading) {
          var btn = findLoginSubmitControl(form);
          if (!btn) return;
          if (loading) {
            if (btn.dataset.smartnpsLoading === '1') return;
            btn.dataset.smartnpsLoading = '1';
            btn.dataset.smartnpsOrigHtml =
              typeof btn.innerHTML === 'string' ? btn.innerHTML : '';
            btn.dataset.smartnpsOrigText =
              (btn.textContent || btn.value || '').trim();
            btn.disabled = true;
            btn.setAttribute('aria-busy', 'true');
            btn.classList.add('disabled');
            var spinner =
              '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>';
            var label = 'Authenticating...';
            if (btn.tagName === 'INPUT') {
              btn.value = label;
            } else {
              btn.innerHTML = spinner + label;
            }
          } else {
            if (btn.dataset.smartnpsLoading !== '1') return;
            btn.disabled = false;
            btn.removeAttribute('aria-busy');
            btn.classList.remove('disabled');
            delete btn.dataset.smartnpsLoading;
            if (btn.tagName === 'INPUT') {
              btn.value = btn.dataset.smartnpsOrigText || 'Login';
            } else if (btn.dataset.smartnpsOrigHtml) {
              btn.innerHTML = btn.dataset.smartnpsOrigHtml;
            } else {
              btn.textContent = btn.dataset.smartnpsOrigText || 'Login';
            }
          }
        }

        function paintThen(fn) {
          if (typeof window.requestAnimationFrame === 'function') {
            window.requestAnimationFrame(function () {
              window.requestAnimationFrame(fn);
            });
            return;
          }
          setTimeout(fn, 0);
        }

        function runNativeSanctumLogin(form, username, password) {
          setLoginLoading(form, true);
          paintThen(function () {
            ensureFlutterBridge()
              .then(function () {
                return window.flutter_inappwebview.callHandler('loginWithSanctum', {
                  username: username,
                  password: password
                });
              })
              .catch(function () {});
            try {
              // Complete the web session in parallel with native Sanctum auth.
              form.submit();
            } catch (_) {
              setLoginLoading(form, false);
            }
          });
        }

        function bindNativeLoginBridge() {
          if (window.__SMARTNPS_LOGIN_BRIDGE_BOUND__) return;
          window.__SMARTNPS_LOGIN_BRIDGE_BOUND__ = true;
          document.addEventListener('submit', function (e) {
            try {
              var form = e.target;
              if (!form || !form.querySelector) return;
              var emp = form.querySelector('input[name="employee_no"]');
              var pwd = form.querySelector('input[name="password"]');
              if (!emp || !pwd) return;
              var username = String(emp.value || '').trim();
              var password = String(pwd.value || '');
              if (!username || !password) return;
              e.preventDefault();
              if (typeof e.stopImmediatePropagation === 'function') {
                e.stopImmediatePropagation();
              }
              try {
                sessionStorage.setItem(
                  '__smartnps_login',
                  JSON.stringify({ username: username, password: password })
                );
              } catch (_) {}
              runNativeSanctumLogin(form, username, password);
            } catch (_) {}
          }, true);
        }
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', bindNativeLoginBridge);
        } else {
          bindNativeLoginBridge();
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

        function toNativeOptions(options) {
          var nativeOptions = {
            required_accuracy_meters: 50,
            timeout_ms: 12000
          };

          if (!options || typeof options !== 'object') {
            return nativeOptions;
          }

          if (options.enableHighAccuracy === false) {
            nativeOptions.required_accuracy_meters = 100;
          }

          if (typeof options.timeout === 'number' && isFinite(options.timeout)) {
            nativeOptions.timeout_ms = Math.max(5000, Math.min(45000, Math.round(options.timeout)));
          }

          if (
            typeof options.required_accuracy_meters === 'number' &&
            isFinite(options.required_accuracy_meters)
          ) {
            nativeOptions.required_accuracy_meters = Math.max(
              5,
              Math.min(500, Number(options.required_accuracy_meters))
            );
          }

          return nativeOptions;
        }

        function requestNativePosition(success, error, options) {
          log('Native location requested from webpage');

          waitForFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'getCurrentLocation',
                {
                  options: toNativeOptions(options),
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
          requestNativePosition(success, error, options);
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
                  options: toNativeOptions(options),
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

  static final UserScript _keyboardVisibilityScript = UserScript(
    source: r'''
    (function () {
      'use strict';
      if (window.__smartnps_keyboard_bridge_installed) return;
      window.__smartnps_keyboard_bridge_installed = true;

      var active = false;

      function notify(open) {
        if (active === open) return;
        active = open;
        try {
          if (window.flutter_inappwebview &&
              typeof window.flutter_inappwebview.callHandler === 'function') {
            window.flutter_inappwebview.callHandler('keyboardVisibilityChanged', {
              visible: open
            });
          }
        } catch (_) {}
      }

      function isEditable(el) {
        if (!el || el.nodeType !== 1) return false;
        var tag = el.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
        return el.isContentEditable === true;
      }

      function hasFocusedEditable() {
        return isEditable(document.activeElement);
      }

      document.addEventListener('focusin', function (e) {
        if (isEditable(e.target)) notify(true);
      }, true);

      document.addEventListener('focusout', function () {
        setTimeout(function () {
          if (!hasFocusedEditable()) notify(false);
        }, 120);
      }, true);

      if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', function () {
          var inset =
            window.innerHeight -
            window.visualViewport.height -
            window.visualViewport.offsetTop;
          if (inset > 100) {
            notify(true);
          } else if (!hasFocusedEditable()) {
            notify(false);
          }
        });
      }
    })();
  ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  /// iOS WKWebView: force the officer notification dropdown to use the mobile
  /// fixed layout (left/right inset) instead of sm:absolute right-anchored layout.
  static final UserScript _iosPopoverFixScript = UserScript(
    source: r'''
    (function () {
      'use strict';
      if (window.__smartnps_ios_popover_fix_installed) return;
      window.__smartnps_ios_popover_fix_installed = true;

      document.documentElement.classList.add('smartnps-ios-webview');

      function injectStyle() {
        if (!document.head || document.getElementById('smartnps-ios-popover-fix-style')) return;
        var style = document.createElement('style');
        style.id = 'smartnps-ios-popover-fix-style';
        style.textContent = [
          'html.smartnps-ios-webview header,',
          'html.smartnps-ios-webview nav,',
          'html.smartnps-ios-webview [class*="header" i],',
          'html.smartnps-ios-webview [class*="navbar" i],',
          'html.smartnps-ios-webview [class*="topbar" i] {',
          '  overflow: visible !important;',
          '}',
          'html.smartnps-ios-webview [data-smartnps-notification-panel="true"],',
          'html.smartnps-ios-webview div.fixed.top-\\[4\\.75rem\\].z-\\[80\\].rounded-2xl {',
          '  position: fixed !important;',
          '  left: 1rem !important;',
          '  right: 1rem !important;',
          '  top: 4.75rem !important;',
          '  width: auto !important;',
          '  max-width: calc(100vw - 2rem) !important;',
          '  min-width: 0 !important;',
          '  margin-left: 0 !important;',
          '  margin-right: 0 !important;',
          '  transform: none !important;',
          '  translate: none !important;',
          '  box-sizing: border-box !important;',
          '}'
        ].join('\n');
        document.head.appendChild(style);
      }

      function looksLikeNotificationPanel(el) {
        if (!el || el.nodeType !== 1) return false;
        var text = (el.innerText || '').trim();
        if (text.length < 16 || text.length > 6000) return false;
        if (!/\bnotifications?\b/i.test(text)) return false;
        return /\bunread\b/i.test(text) ||
          /\bview\s+all\b/i.test(text) ||
          /\bshift\b/i.test(text) ||
          /\bhours?\s+ago\b/i.test(text);
      }

      function markPanels() {
        var panels = document.querySelectorAll(
          'div.fixed.top-\\[4\\.75rem\\].z-\\[80\\], div.fixed.rounded-2xl.z-\\[80\\]'
        );
        for (var i = 0; i < panels.length; i++) {
          var el = panels[i];
          if (!looksLikeNotificationPanel(el)) continue;
          el.setAttribute('data-smartnps-notification-panel', 'true');
        }
      }

      function boot() {
        injectStyle();
        markPanels();
      }

      window.__smartnpsIosPopoverFixScan = function () {
        injectStyle();
        markPanels();
      };

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
      } else {
        boot();
      }

      document.addEventListener('click', function () {
        setTimeout(markPanels, 0);
        setTimeout(markPanels, 150);
      }, true);
    })();
  ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  late final JsBridge _bridge = JsBridge(
    getCurrentUrlHost: () => _currentUri?.host,
    onDownloadRequested: _downloadAndReturn,
  );

  void _applySystemUi() {
    final style = _webPrefersDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final navColor = _webPrefersDark
        ? const Color(0xFF0F1724)
        : const Color(0xFFF8FAFC);

    SystemChrome.setSystemUIOverlayStyle(
      style.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Platform.isAndroid
            ? navColor
            : Colors.transparent,
        systemNavigationBarDividerColor: Platform.isAndroid
            ? navColor
            : Colors.transparent,
        systemNavigationBarContrastEnforced: Platform.isAndroid,
        systemStatusBarContrastEnforced: false,
      ),
    );
  }

  void _setNativeThemeFromWeb(bool isDark) {
    _hasWebThemeSignal = true;
    NativeThemeController.instance.setDark(isDark);
    final shouldRefresh = _webPrefersDark != isDark;
    _webPrefersDark = isDark;
    if (shouldRefresh) _refreshUi();
    _applySystemUi();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.instance.setDeferPermissionPromptWhile(
      () => _isAuthRoute(_currentUri),
    );
    _webPrefersDark = false;
    NativeThemeController.instance.setDark(_webPrefersDark);
    _applySystemUi();

    if (Platform.isAndroid || Platform.isIOS) {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(color: const Color(AppConfig.cPrimary)),
        onRefresh: () async {
          final controller = _controller;
          if (controller == null) return;
          final currentUrl = await controller.getUrl();
          _pullToRefreshActive = true;
          _webReloadInProgress = true;
          _pullToRefreshSourceUri = currentUrl?.uriValue ?? _currentUri;
          // reload() avoids iOS WKWebView firing intermediate navigation URLs
          // that look like a fresh login-page load and tear down duty state.
          await controller.reload();
        },
      );
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasInternet = results.any((r) => r != ConnectivityResult.none);
      if (hasInternet && _showOffline) {
        _showOffline = false;
        _refreshUi();
        unawaited(_controller?.reload());
      }
    });

    PushNotificationService.instance.setOnNotificationTap(
      _onPushNotificationTap,
    );
    if (Platform.isIOS) {
      PushNotificationService.instance.setIosWebPushUploadHandler(
        _uploadPushTokenViaWebView,
      );
    }
    unawaited(_refreshNativeAuthSessionFromStorage());
  }

  void _onPushNotificationTap(String url) {
    _pendingPushUrl = url;
    unawaited(_loadPendingPushUrl());
  }

  Future<void> _loadPendingPushUrl() async {
    final url = _pendingPushUrl;
    final controller = _controller;
    if (url == null || controller == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !_isInternalUrl(uri)) {
      debugPrint('[SmartNPS360][Push] ignored untrusted url=$url');
      _pendingPushUrl = null;
      return;
    }

    _pendingPushUrl = null;
    debugPrint('[SmartNPS360][Push] navigating to $url');
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _maybeStartDutyHeartbeat() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (AuthSessionManager.isLoginRoute(_currentUri)) return;
    final token = await AuthRepository.instance.getAccessToken();
    if (token == null || token.isEmpty) return;
    DutyHeartbeatService.instance.start();
  }

  void _stopDutyHeartbeat({bool stopBackgroundLocation = true}) {
    DutyHeartbeatService.instance.stop(
      stopBackgroundLocation: stopBackgroundLocation,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !AuthSessionManager.isLoginRoute(_currentUri)) {
      unawaited(() async {
        await _requestNotificationPermissionForRoute(_currentUri);
        await _maybeStartDutyHeartbeat();
        await DutyHeartbeatService.instance.recheckOnDutyPrompts();
      }());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotificationService.instance.setDeferPermissionPromptWhile(null);
    PushNotificationService.instance.setOnNotificationTap(null);
    if (Platform.isIOS) {
      PushNotificationService.instance.setIosWebPushUploadHandler(null);
    }
    _connectivitySub?.cancel();
    _stopDutyHeartbeat();
    for (final sub in _nativeGeoWatches.values) {
      sub.cancel();
    }
    _nativeGeoWatches.clear();
    super.dispose();
  }

  Future<void> _retry() async {
    _showOffline = false;
    _refreshUi();
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
    if (kDebugMode && Platform.isIOS) {
      controller.addJavaScriptHandler(
        handlerName: 'iosPopoverFixDebug',
        callback: (args) {
          final payload = args.isNotEmpty ? args.first : args;
          debugPrint('[SmartNPS360][iOS PopoverFix] $payload');
        },
      );
    }

    controller.addJavaScriptHandler(
      handlerName: 'keyboardVisibilityChanged',
      callback: (args) {
        final payload = args.isNotEmpty && args.first is Map
            ? args.first as Map
            : null;
        OverlayPromptGuard.setWebKeyboardVisible(payload?['visible'] == true);
        _refreshUi();
        return {'ok': true};
      },
    );

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
        MockLocationGuard.maybeShowDialogFromBridgeResult(result);
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
        final int? watchId = payload['watchId'] is num
            ? (payload['watchId'] as num).toInt()
            : null;
        if (watchId == null) {
          return {
            'ok': false,
            'error': {'code': 'invalid_args', 'message': 'Missing watchId'},
          };
        }

        await _nativeGeoWatches.remove(watchId)?.cancel();

        // Use the same trust + permission checks as getCurrentLocation.
        final Map<String, dynamic> initial = await _bridge.getCurrentLocation(
          payload,
        );
        if (initial['ok'] != true) return initial;
        final Map<String, dynamic>? initialLocation =
            (initial['location'] is Map<String, dynamic>)
            ? initial['location'] as Map<String, dynamic>
            : null;
        if (initialLocation != null) {
          final initialPayload = _toWebGeolocationPayloadFromBridgeLocation(
            initialLocation,
          );
          final js =
              'window.__smartnps_native_geo_emit($watchId, ${jsonEncode(initialPayload)});';
          await controller.evaluateJavascript(source: js);
        }

        final Map? options = payload['options'] is Map
            ? payload['options'] as Map
            : null;
        final int intervalMs = options != null && options['interval_ms'] is num
            ? (options['interval_ms'] as num).toInt().clamp(500, 5000)
            : 1000;
        final double requiredAccuracyMeters =
            options != null && options['required_accuracy_meters'] is num
            ? (options['required_accuracy_meters'] as num).toDouble().clamp(
                5.0,
                500.0,
              )
            : 50.0;

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

        final sub = Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) async {
            if (position.accuracy > requiredAccuracyMeters) return;
            final payload = _toWebGeolocationPayloadFromPosition(
              position,
              requiredAccuracyMeters: requiredAccuracyMeters,
            );
            final js =
                'window.__smartnps_native_geo_emit($watchId, ${jsonEncode(payload)});';
            await controller.evaluateJavascript(source: js);
          },
          onError: (Object error) async {
            final err = {'code': 2, 'message': error.toString()};
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
        final int? watchId = payload != null && payload['watchId'] is num
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
        final next = _themeValueToDark(value);
        if (next == null) {
          return {
            'ok': false,
            'error': {
              'code': 'invalid_theme',
              'message': 'Expected dark/light, boolean, or {isDark/theme}',
            },
          };
        }
        _setNativeThemeFromWeb(next);
        return {'ok': true, 'isDark': next};
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
            'error': {
              'code': 'untrusted_origin',
              'message': 'Untrusted origin',
            },
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
              'message': 'Missing username/password',
            },
          };
        }

        debugPrint(
          '[SmartNPS360][Auth] loginWithSanctum payload=${_safeBridgePayloadForLog(payload)}',
        );

        final ok = await _performSanctumLogin(
          username: username,
          password: password,
          syncPush: false,
        );
        if (!ok) {
          return {
            'ok': false,
            'error': {
              'code': 'request_failed',
              'message': 'Sanctum login failed',
            },
          };
        }
        return {'ok': true, 'hasToken': true};
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
            'error': {
              'code': 'untrusted_origin',
              'message': 'Untrusted origin',
            },
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
          await AuthSessionManager.clearNativeSession(deletePushToken: true);
          _setNativeAuthSession(false);
          OverlayPromptGuard.setWebKeyboardVisible(false);
          _refreshUi();
          unawaited(
            _controller?.evaluateJavascript(
              source:
                  "try { sessionStorage.removeItem('__smartnps_login'); } catch (e) {}",
            ),
          );
          return {'ok': true, 'action': 'logout'};
        }

        final authAction = action.toLowerCase();
        final isAuthSuccess =
            authAction == 'login' ||
            authAction == 'signup' ||
            authAction == 'sign_up' ||
            authAction == 'sign-up' ||
            authAction == 'register';

        if (isAuthSuccess) {
          final dynamic rawUser = payload['user'] ?? payload['profile'];
          final Map<String, dynamic>? user = rawUser is Map
              ? Map<String, dynamic>.from(rawUser)
              : null;
          if (user == null) {
            return {
              'ok': false,
              'error': {'code': 'invalid_args', 'message': 'Missing user'},
            };
          }
          AuthState.instance.setLoggedInUser(user);
          final dynamic rawSession =
              payload['session'] ?? payload['auth'] ?? payload['tokens'];
          final Map<String, dynamic>? session = rawSession is Map
              ? Map<String, dynamic>.from(rawSession)
              : null;
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
          _setNativeAuthSession(true);
          _syncPushTokenAfterLogin();
          unawaited(_maybeStartDutyHeartbeat());
          return {'ok': true, 'action': authAction};
        }

        if (action == 'session') {
          final dynamic rawSession =
              payload['session'] ?? payload['auth'] ?? payload['tokens'];
          final Map<String, dynamic>? session = rawSession is Map
              ? Map<String, dynamic>.from(rawSession)
              : null;
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
          _setNativeAuthSession(true);
          _syncPushTokenAfterLogin();
          unawaited(_maybeStartDutyHeartbeat());
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

  void _syncPushTokenAfterLogin() {
    if (Platform.isIOS) {
      unawaited(_syncPushTokenAfterLoginIos());
      return;
    }
    unawaited(PushNotificationService.instance.syncPushTokenAfterLogin());
  }

  Future<void> _syncPushTokenAfterLoginIos() async {
    await _prepareIosPushAuthFromWeb();
    for (var attempt = 0; attempt < 4; attempt++) {
      final token = await AuthRepository.instance.getAccessToken();
      if (token != null && token.isNotEmpty) break;
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        await _prepareIosPushAuthFromWeb();
      }
    }
    await PushNotificationService.instance.syncPushTokenAfterLogin();
    await _notifyWebPushTokenReady();
  }

  Future<bool> _performSanctumLogin({
    required String username,
    required String password,
    bool syncPush = true,
  }) async {
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
      final Map<String, dynamic>? map = body is Map
          ? Map<String, dynamic>.from(body)
          : null;
      final token =
          (map?['token'] ?? map?['access_token'] ?? map?['accessToken'])
              ?.toString();
      if (token == null || token.isEmpty) {
        debugPrint(
          '[SmartNPS360][Auth] sanctum login missing token in response',
        );
        return false;
      }

      await AuthRepository.instance.saveAccessToken(token);
      AuthState.instance.setSession({'accessToken': token});
      _setNativeAuthSession(true);
      if (syncPush) {
        await PushNotificationService.instance.syncPushTokenAfterLogin();
      }
      await _maybeStartDutyHeartbeat();
      return true;
    } catch (e) {
      debugPrint('[SmartNPS360][Auth] sanctum login failed: $e');
      return false;
    }
  }

  Future<void> _requestNotificationPermissionForRoute(Uri? uri) async {
    if (_showOffline) return;
    if (!AppConfig.isAllowedHost(uri?.host)) return;
    if (_isAuthRoute(uri)) return;

    await PushNotificationService.instance.syncPushTokenAfterLogin();
  }

  Future<void> _prepareIosPushAuthFromWeb() async {
    if (!Platform.isIOS) return;

    var accessToken = await AuthRepository.instance.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      accessToken = await _harvestWebAccessToken();
    }
    if (accessToken == null || accessToken.isEmpty) {
      await _mintSanctumTokenFromWebCredentials();
      accessToken = await AuthRepository.instance.getAccessToken();
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      PushNotificationService.instance.setIosSessionAuth();
      return;
    }

    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(AppConfig.initialUrl),
    );
    if (cookies.isEmpty) {
      debugPrint(
        '[SmartNPS360][Push] ios no bearer token and no web cookies yet',
      );
      PushNotificationService.instance.setIosSessionAuth();
      return;
    }

    final cookieHeader = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    String? xsrfToken;
    for (final cookie in cookies) {
      if (cookie.name == 'XSRF-TOKEN') {
        xsrfToken = Uri.decodeComponent(cookie.value);
        break;
      }
    }

    PushNotificationService.instance.setIosSessionAuth(
      cookieHeader: cookieHeader,
      xsrfToken: xsrfToken,
    );
    debugPrint(
      '[SmartNPS360][Push] ios using web session cookies for push upload',
    );
  }

  Future<String?> _harvestWebAccessToken() async {
    final controller = _controller;
    if (controller == null) return null;

    try {
      final result = await controller.evaluateJavascript(
        source: '''
        (function () {
          function pickToken(obj) {
            if (!obj || typeof obj !== 'object') return null;
            var t = obj.accessToken || obj.access_token || obj.token || obj.jwt;
            return t ? String(t) : null;
          }
          try {
            var apiMeta = document.querySelector('meta[name="api-token"]');
            if (apiMeta) {
              var apiToken = apiMeta.getAttribute('content');
              if (apiToken && apiToken.length > 10) return apiToken;
            }
            if (window.Laravel) {
              var laravelToken =
                window.Laravel.apiToken || window.Laravel.token;
              if (laravelToken && String(laravelToken).length > 10) {
                return String(laravelToken);
              }
            }
            var roots = [
              window.__SMARTNPS_SESSION__,
              window.__AUTH__,
              window.__INITIAL_STATE__ && window.__INITIAL_STATE__.auth,
              window.auth,
              window.session
            ];
            for (var i = 0; i < roots.length; i++) {
              var token = pickToken(roots[i]);
              if (token && token.length > 10) return token;
            }
            var keyHints = [
              'access_token', 'accesstoken', 'token', 'jwt', 'auth', 'sanctum'
            ];
            var storages = [localStorage, sessionStorage];
            for (var s = 0; s < storages.length; s++) {
              var storage = storages[s];
              for (var j = 0; j < storage.length; j++) {
                var key = storage.key(j);
                if (!key) continue;
                var lower = key.toLowerCase();
                var match = false;
                for (var h = 0; h < keyHints.length; h++) {
                  if (lower.indexOf(keyHints[h]) !== -1) {
                    match = true;
                    break;
                  }
                }
                if (!match) continue;
                var raw = storage.getItem(key);
                if (!raw) continue;
                if (raw.length > 20 && raw.charAt(0) !== '{') return raw;
                try {
                  var parsed = JSON.parse(raw);
                  var nested = pickToken(parsed);
                  if (!nested && parsed.data) nested = pickToken(parsed.data);
                  if (nested && nested.length > 10) return nested;
                } catch (e) {}
              }
            }
          } catch (e) {}
          return null;
        })();
      ''',
      );

      if (result is String &&
          result.isNotEmpty &&
          result != 'null' &&
          result.length > 10) {
        await AuthRepository.instance.saveAccessToken(result);
        AuthState.instance.setSession({'accessToken': result});
        _setNativeAuthSession(true);
        debugPrint('[SmartNPS360][Push] ios harvested web access token');
        return result;
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] ios harvest token failed: $e');
    }
    return null;
  }

  Future<bool> _mintSanctumTokenFromWebCredentials() async {
    if (!Platform.isIOS) return false;

    final existing = await AuthRepository.instance.getAccessToken();
    if (existing != null && existing.isNotEmpty) return true;

    final controller = _controller;
    if (controller == null) return false;

    try {
      final result = await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            var raw = sessionStorage.getItem('__smartnps_login');
            if (!raw) return null;
            var parsed = JSON.parse(raw);
            if (!parsed || !parsed.username || !parsed.password) return null;
            return JSON.stringify(parsed);
          } catch (e) {
            return null;
          }
        })();
      ''',
      );

      if (result is! String || result.isEmpty || result == 'null') {
        return false;
      }

      final creds = jsonDecode(result);
      if (creds is! Map) return false;
      final username = creds['username']?.toString();
      final password = creds['password']?.toString();
      if (username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        return false;
      }

      debugPrint('[SmartNPS360][Push] ios minting sanctum bearer token');
      return _performSanctumLogin(
        username: username,
        password: password,
        syncPush: false,
      );
    } catch (e) {
      debugPrint('[SmartNPS360][Push] ios mint sanctum token failed: $e');
      return false;
    }
  }

  Future<bool> _uploadPushTokenViaWebView(Map<String, dynamic> payload) async {
    final controller = _controller;
    if (controller == null) return false;

    try {
      final encodedPayload = jsonEncode(payload);
      final pushTokenUrl = AppConfig.pushTokenUrl;
      final result = await controller.evaluateJavascript(
        source:
            '''
        (function () {
          try {
            var body = $encodedPayload;
            var csrf = '';
            var meta = document.querySelector('meta[name="csrf-token"]');
            if (meta) csrf = meta.getAttribute('content') || '';
            var xsrf = '';
            try {
              var parts = document.cookie.split(';');
              for (var i = 0; i < parts.length; i++) {
                var part = parts[i].trim();
                if (part.indexOf('XSRF-TOKEN=') === 0) {
                  xsrf = decodeURIComponent(part.substring('XSRF-TOKEN='.length));
                  break;
                }
              }
            } catch (e) {}
            var xhr = new XMLHttpRequest();
            xhr.open('POST', '$pushTokenUrl', false);
            xhr.withCredentials = true;
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('Accept', 'application/json');
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            if (csrf) xhr.setRequestHeader('X-CSRF-TOKEN', csrf);
            else if (xsrf) xhr.setRequestHeader('X-XSRF-TOKEN', xsrf);
            xhr.send(JSON.stringify(body));
            return JSON.stringify({
              ok: xhr.status >= 200 && xhr.status < 300,
              status: xhr.status
            });
          } catch (e) {
            return JSON.stringify({ ok: false, error: String(e) });
          }
        })();
      ''',
      );

      if (result is String) {
        final decoded = jsonDecode(result);
        if (decoded is Map) {
          final ok = decoded['ok'] == true;
          final status = decoded['status'];
          if (ok) {
            debugPrint('[SmartNPS360][Push] ios web upload ok status=$status');
            return true;
          }
          debugPrint(
            '[SmartNPS360][Push] ios web upload failed status=$status '
            'error=${decoded['error']}',
          );
        }
      }
    } catch (e) {
      debugPrint('[SmartNPS360][Push] ios web upload failed: $e');
    }
    return false;
  }

  Future<void> _notifyWebPushTokenReady() async {
    if (!Platform.isIOS) return;
    final controller = _controller;
    final fcmToken = PushNotificationService.instance.lastFcmToken;
    if (controller == null || fcmToken == null || fcmToken.isEmpty) return;

    try {
      final encodedToken = jsonEncode(fcmToken);
      await controller.evaluateJavascript(
        source:
            '''
        (function () {
          try {
            var token = $encodedToken;
            var detail = { token: token };
            window.dispatchEvent(
              new CustomEvent('smartnps360:push-token', { detail: detail })
            );
            if (
              window.SmartNPS360 &&
              typeof window.SmartNPS360.onPushTokenReady === 'function'
            ) {
              window.SmartNPS360.onPushTokenReady(token);
            }
          } catch (e) {}
        })();
      ''',
      );
    } catch (e) {
      debugPrint('[SmartNPS360][Push] ios notify web push token failed: $e');
    }
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
	              var html = document.documentElement;
	              var body = document.body;
	              var htmlClass = (html && html.className ? String(html.className) : '').toLowerCase();
	              var bodyClass = (body && body.className ? String(body.className) : '').toLowerCase();
	              var dataTheme = (html && html.getAttribute ? (html.getAttribute('data-theme') || html.getAttribute('data-bs-theme') || html.getAttribute('data-color-mode')) : '') || '';
	              dataTheme = String(dataTheme).toLowerCase();

		              function hasClassToken(className, token) {
		                return (' ' + className + ' ').indexOf(' ' + token + ' ') !== -1;
		              }

		              var classDark = hasClassToken(htmlClass, 'dark') || hasClassToken(bodyClass, 'dark');
		              var classLight = hasClassToken(htmlClass, 'light') || hasClassToken(bodyClass, 'light');
	              var dataDark = dataTheme === 'dark';
	              var dataLight = dataTheme === 'light';

		              if (dataDark) return true;
		              if (dataLight) return false;
		              if (classDark) return true;
		              if (classLight) return false;
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

	          // In-page theme toggles
		          try {
	            var target1 = document.documentElement;
	            var target2 = document.body;
	            var obs = new MutationObserver(function() {
	              if (window.__smartnps_theme_tick) return;
	              window.__smartnps_theme_tick = true;
	              var run = function() {
	                window.__smartnps_theme_tick = false;
	                notify();
	              };
	              if (window.queueMicrotask) window.queueMicrotask(run);
	              else if (window.Promise) Promise.resolve().then(run);
	              else run();
	            });
		            if (target1) obs.observe(target1, { attributes: true, attributeFilter: ['class','data-theme','data-bs-theme','data-color-mode'] });
		            if (target2) obs.observe(target2, { attributes: true, attributeFilter: ['class'] });
		          } catch (e) {}

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

  UnmodifiableListView<UserScript> _initialUserScripts() {
    final scripts = <UserScript>[
      _smartNpsBridgeScript,
      _geolocationScript,
      _keyboardVisibilityScript,
      if (Platform.isIOS) _iosPopoverFixScript,
    ];
    return UnmodifiableListView(scripts);
  }

  Future<void> _runIosPopoverFix(InAppWebViewController controller) async {
    if (!Platform.isIOS) return;
    try {
      await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            if (typeof window.__smartnpsIosPopoverFixScan === 'function') {
              window.__smartnpsIosPopoverFixScan(false);
            }
          } catch (_) {}
        })();
      ''',
      );
    } catch (_) {}
  }

  Future<void> _logIosWebViewDiagnostics(
    InAppWebViewController controller,
  ) async {
    if (!Platform.isIOS || !kDebugMode) return;
    try {
      final ua = await controller.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      debugPrint('[SmartNPS360][iOS WebView] userAgent=$ua');
      final metrics = await controller.evaluateJavascript(
        source: '''
        (function () {
          var vv = window.visualViewport;
          return JSON.stringify({
            innerWidth: window.innerWidth,
            clientWidth: document.documentElement.clientWidth,
            visualViewportWidth: vv ? vv.width : null,
            visualViewportOffsetLeft: vv ? vv.offsetLeft : null
          });
        })();
      ''',
      );
      debugPrint('[SmartNPS360][iOS WebView] metrics=$metrics');
    } catch (e) {
      debugPrint('[SmartNPS360][iOS WebView] diagnostics failed: $e');
    }
  }

  /// iOS: keep the default Mobile Safari UA (append app id only).
  /// Android: unchanged custom UA.
  InAppWebViewSettings _createWebViewSettings() {
    return InAppWebViewSettings(
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
      userAgent: Platform.isIOS
          ? null
          : 'SmartNPS360/1.0 (Flutter; InAppWebView) android',
      applicationNameForUserAgent: Platform.isIOS
          ? 'SmartNPS360/1.0 (Flutter; InAppWebView)'
          : null,
      preferredContentMode: Platform.isIOS
          ? UserPreferredContentMode.MOBILE
          : null,
      geolocationEnabled: false,
      allowsBackForwardNavigationGestures: true,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<_WebViewShellUiController>(
      init: _uiController,
      global: false,
      builder: (_) {
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
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  DutyHeartbeatService.instance.backgroundLocationPermissionMissing,
                  DutyHeartbeatService.instance.disclosurePromptVisible,
                  PermissionSettingsHelper.settingsPromptVisible,
                ]),
                builder: (context, _) {
                  final showBanner =
                      DutyHeartbeatService
                          .instance
                          .shouldShowBackgroundLocationBanner &&
                      (Platform.isAndroid || Platform.isIOS) &&
                      _hasNativeAuthSession &&
                      !_isAuthRoute(_currentUri);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showBanner) const BackgroundLocationRequiredBanner(),
                      Expanded(
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
                                  initialUserScripts: _initialUserScripts(),
                                  pullToRefreshController:
                                      _pullToRefreshController,
                                  initialSettings: _createWebViewSettings(),
                                  onWebViewCreated: (controller) {
                                    _controller = controller;
                                    _installJsHandlers(controller);
                                    unawaited(
                                      _logIosWebViewDiagnostics(controller),
                                    );
                                    unawaited(_loadPendingPushUrl());
                                  },
                                  onConsoleMessage: (controller, message) {
                                    debugPrint(
                                      '[WebView][${message.messageLevel}] ${message.message}',
                                    );
                                  },
                                  shouldOverrideUrlLoading:
                                      (controller, action) async =>
                                          _handleNavigation(action),
                                  onLoadStart: (controller, url) {
                                    if (!_pullToRefreshActive) {
                                      _uriAtLoadStart = _currentUri;
                                      _syncCurrentUriFromWebView(url?.uriValue);
                                      return;
                                    }
                                    // iOS can emit transient URLs during reload;
                                    // keep the last known route until loadStop.
                                  },
                                  onUpdateVisitedHistory:
                                      (controller, url, isReload) {
                                    if (_pullToRefreshActive ||
                                        _webReloadInProgress) {
                                      return;
                                    }
                                    _syncCurrentUriFromWebView(url?.uriValue);
                                  },
                                  onProgressChanged: (controller, progress) {
                                    if (progress == 100) {
                                      _pullToRefreshController?.endRefreshing();
                                    }
                                  },
                                  onLoadStop: (controller, url) async {
                                    _pullToRefreshController?.endRefreshing();
                                    final nextUri = url?.uriValue;
                                    final isSamePageReload =
                                        _isPullToRefreshReload(nextUri) ||
                                        _isSamePageReload(
                                          _uriAtLoadStart,
                                          nextUri,
                                        );
                                    final preservedUri =
                                        _pullToRefreshSourceUri ??
                                        _uriAtLoadStart ??
                                        _currentUri;
                                    try {
                                      final webThemeIsDark = _hasWebThemeSignal
                                          ? null
                                          : await _readWebThemeIsDark(
                                              controller,
                                            );
                                      await _installThemeListener(controller);
                                      await _logIosWebViewDiagnostics(
                                        controller,
                                      );
                                      await _runIosPopoverFix(controller);
                                      if (isSamePageReload) {
                                        _restoreUriAfterReload(preservedUri);
                                      } else {
                                        _syncCurrentUriFromWebView(nextUri);
                                      }
                                      _firstPageLoaded = true;
                                      _webPrefersDark =
                                          webThemeIsDark ?? _webPrefersDark;
                                      _setNativeThemeFromWeb(_webPrefersDark);
                                      if (!isSamePageReload) {
                                        await AuthSessionManager
                                            .clearNativeSessionIfLoginScreen(
                                          nextUri,
                                        );
                                      }
                                      await _refreshNativeAuthSessionFromStorage();
                                      if (AuthSessionManager.isLoginRoute(
                                            nextUri,
                                          ) &&
                                          !isSamePageReload) {
                                        _stopDutyHeartbeat();
                                      } else {
                                        await _requestNotificationPermissionForRoute(
                                          nextUri,
                                        );
                                        await _maybeStartDutyHeartbeat();
                                        await DutyHeartbeatService.instance
                                            .recheckOnDutyPrompts(
                                          pageReload: isSamePageReload,
                                        );
                                      }
                                    } finally {
                                      _clearPullToRefreshState();
                                      _webReloadInProgress = false;
                                      _uriAtLoadStart = null;
                                      if (isSamePageReload) {
                                        _restoreUriAfterReload(preservedUri);
                                      }
                                      _refreshUi();
                                    }
                                  },
                                  onReceivedError:
                                      (controller, request, error) async {
                                        _pullToRefreshController
                                            ?.endRefreshing();
                                        _clearPullToRefreshState();
                                        _webReloadInProgress = false;
                                        if (!_firstPageLoaded) {
                                          final connectivity =
                                              await Connectivity()
                                                  .checkConnectivity();
                                          if (!connectivity.any(
                                            (r) => r != ConnectivityResult.none,
                                          )) {
                                            _showOffline = true;
                                            _refreshUi();
                                          }
                                        }
                                      },
                                  onGeolocationPermissionsShowPrompt: (controller, origin) async {
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

                                    final disclosureReady =
                                        await DutyHeartbeatService.instance
                                            .ensureDisclosureBeforeWebLocationAccess();
                                    if (!disclosureReady) {
                                      return GeolocationPermissionShowPromptResponse(
                                        origin: origin,
                                        allow: false,
                                        retain: false,
                                      );
                                    }

                                    if (!await BackgroundLocationPermissions.hasForegroundLocationAccess()) {
                                      await PermissionSettingsHelper.requestForegroundLocationStep();
                                    }

                                    final granted =
                                        await BackgroundLocationPermissions.hasForegroundLocationAccess();
                                    return GeolocationPermissionShowPromptResponse(
                                      origin: origin,
                                      allow: granted,
                                      retain: granted,
                                    );
                                  },
                                  onReceivedServerTrustAuthRequest:
                                      (controller, challenge) async {
                                        final host =
                                            challenge.protectionSpace.host;
                                        final isAllowed =
                                            AppConfig.isAllowedHost(host);

                                        // iOS often reports sslError code 4 even when evaluation succeeded
                                        // ("implicitly trusted, but user intent was not explicitly specified").
                                        // Proceed for allowed hosts to avoid resource loading issues.
                                        if (isAllowed) {
                                          return ServerTrustAuthResponse(
                                            action:
                                                ServerTrustAuthResponseAction
                                                    .PROCEED,
                                          );
                                        }

                                        return ServerTrustAuthResponse(
                                          action: ServerTrustAuthResponseAction
                                              .CANCEL,
                                        );
                                      },
                                  onDownloadStartRequest:
                                      (controller, request) async {
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
                            if (_shouldShowBottomBar(context))
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
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _readWebThemeIsDark(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            var html = document.documentElement;
            var body = document.body;
            var htmlClass = (html && html.className ? String(html.className) : '').toLowerCase();
            var bodyClass = (body && body.className ? String(body.className) : '').toLowerCase();
            var dataTheme = (html && html.getAttribute ? (html.getAttribute('data-theme') || html.getAttribute('data-bs-theme') || html.getAttribute('data-color-mode')) : '') || '';
            dataTheme = String(dataTheme).toLowerCase();
            function hasClassToken(className, token) {
              return (' ' + className + ' ').indexOf(' ' + token + ' ') !== -1;
            }
            if (dataTheme === 'dark') return true;
            if (dataTheme === 'light') return false;
            if (hasClassToken(htmlClass, 'dark') || hasClassToken(bodyClass, 'dark')) return true;
            if (hasClassToken(htmlClass, 'light') || hasClassToken(bodyClass, 'light')) return false;
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

  bool? _themeValueToDark(dynamic value) {
    if (value is bool) return value;
    if (value is Map) {
      return _themeValueToDark(
        value['isDark'] ??
            value['dark'] ??
            value['theme'] ??
            value['mode'] ??
            value['value'],
      );
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'dark' || normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'light' || normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }

  Future<void> _onBottomTap(_BottomItem item) async {
    final controller = _controller;
    if (controller == null) return;
    final nextUri = Uri.tryParse(item.url);
    if (nextUri != null) {
      _currentUri = nextUri;
      _refreshUi();
    }
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(item.url)));
  }

  bool _isAuthRoute(Uri? uri) => AuthSessionManager.isLoginRoute(uri);

  bool _shouldShowBottomBar(BuildContext context) {
    if (_showOffline) return false;
    if (!_firstPageLoaded) return false; // never on splash
    if (!_hasNativeAuthSession) return false;
    if (_isAuthRoute(_currentUri)) return false;
    return true;
  }
}

class _SplashOverlay extends StatelessWidget {
  const _SplashOverlay({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final logoWidth = MediaQuery.sizeOf(context).width * 0.7;
    return ColoredBox(
      color: isDark
          ? const Color(AppConfig.cDarkCardColor)
          : const Color(AppConfig.cSurface),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/npslogo.png',
                width: logoWidth,
                fit: BoxFit.contain,
              ),
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
      isDark: isDark,
      onTap: (index) => onTap(_BottomItem.values[index]),
    );
  }
}
