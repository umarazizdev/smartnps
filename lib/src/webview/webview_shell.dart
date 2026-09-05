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

import '../debug/location_path_curve_debug_screen.dart';
import '../utilities/app_config.dart';
import '../utilities/app_debug_log.dart';
import '../utilities/app_upgrade_reconciler.dart';
import '../utilities/app_version_info.dart';
import 'js_bridge.dart';
import '../app/offline_screen.dart';
import '../app/site_reachability.dart';
import '../widgets/chrome/platform_bottom_bar.dart';
import '../widgets/dialogs/clock_in_blocked_dialog.dart';
import '../widgets/dialogs/clock_in_permissions_dialog.dart';
import '../location/mock_location_detection.dart';
import '../location/mock_location_guard.dart';
import '../app/app_routes.dart';
import '../auth/auth_session_manager.dart';
import '../auth/auth_state.dart';
import '../auth/auth_repository.dart';
import '../api/api_client.dart';
import '../api/api_urls.dart';
import '../device/device_check_service.dart';
import '../background/duty/duty_heartbeat_service.dart';
import '../background/duty/clock_in_gate_service.dart';
import '../background/duty/on_duty_permissions_prompt_service.dart';
import '../background/duty/off_duty_push_prompt_service.dart';
import '../background/location/background_location_controller.dart';
import '../background/location/background_location_permissions.dart';
import '../background/duty/location_disclosure_consent.dart';
import '../background/ios/ios_duty_location_pinger.dart';
import '../utilities/app_lifecycle_resume_gate.dart';
import '../utilities/overlay_prompt_guard.dart';
import '../utilities/permission_settings_helper.dart';
import '../app/native_theme_controller.dart';
import '../push/announcements/officer_announcement_coordinator.dart';
import '../push/notifications/push_notification_service.dart';
import '../permissions/native_permission_status_service.dart';
import '../log_visit/flow/visit_draft_resume_dialog.dart';
import '../log_visit/flow/visit_gps_session.dart';
import '../log_visit/flow/visit_media_draft_store.dart';
import '../log_visit/flow/visit_video_flow_controller.dart';
import '../log_visit/preview/visit_video_preview_screen.dart';
import '../permissions/required_permissions_gate.dart';
import '../widgets/chrome/required_permissions_blocker.dart';
import '../widgets/dialogs/location_notice_dialog.dart';

class WebViewShell extends StatefulWidget {
  const WebViewShell({super.key});

  @override
  State<WebViewShell> createState() => _WebViewShellState();
}

class _WebViewShellUiController extends GetxController {
  final currentUri = Rxn<Uri>();
  final isNavigating = false.obs;
  final loadProgress = 0.obs;
  final firstPageLoaded = false.obs;
  final splashReleased = false.obs;
  final showOffline = false.obs;
  final offlineRetrying = false.obs;
  final offlineStatusMessage = RxnString();
  final hasNativeAuthSession = false.obs;
  final officerLoggedIn = false.obs;
  final webPrefersDark = false.obs;
  final pullToRefreshActive = false.obs;
  final selectedBottomTabIndex = 0.obs;
  final bottomTabNavigationActive = false.obs;
  final showingLogVisit = false.obs;
  final showingGpsCurveDebug = false.obs;
  final showLocationNotice = false.obs;

  final preserveBottomBarDuringLoad = false.obs;
  /// Web-driven hide (e.g. popup/modal open). Cleared on navigation / logout.
  final webHidesBottomBar = false.obs;
  final flutterKeyboardInset = 0.0.obs;

  void setFlutterKeyboardInset(double inset) {
    final clamped = inset <= AppConfig.keyboardOpenThreshold ? 0.0 : inset;
    if (flutterKeyboardInset.value == clamped) return;
    flutterKeyboardInset.value = clamped;
  }

  bool get isKeyboardOpen =>
      flutterKeyboardInset.value > AppConfig.keyboardOpenThreshold;

  void beginNavigation() {
    isNavigating.value = true;
    loadProgress.value = 0;
  }

  void setLoadProgress(int progress) {
    final clamped = progress.clamp(0, 100);
    if (loadProgress.value == clamped && isNavigating.value) return;
    isNavigating.value = true;
    loadProgress.value = clamped;
  }

  void endNavigation() {
    if (!isNavigating.value && loadProgress.value == 0) return;
    isNavigating.value = false;
    loadProgress.value = 0;
  }

  void setNativeAuthSession(bool value) {
    if (hasNativeAuthSession.value == value) return;
    hasNativeAuthSession.value = value;
  }

  void setOfficerLoggedIn(bool value) {
    if (officerLoggedIn.value == value) return;
    officerLoggedIn.value = value;
    if (value) {
      if (!showLocationNotice.value) {
        RequiredPermissionsGate.instance.start();
      }
    } else {
      RequiredPermissionsGate.instance.stop();
      showLocationNotice.value = false;
      showingLogVisit.value = false;
      showingGpsCurveDebug.value = false;
    }
  }
}

class _WebViewShellState extends State<WebViewShell>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefreshController;

  Uri? _uriAtLoadStart;
  Uri? _pullToRefreshSourceUri;
  bool _webReloadInProgress = false;
  bool _pendingBottomTabLoadStarted = false;
  bool _hasWebThemeSignal = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final Map<int, StreamSubscription<Position>> _nativeGeoWatches = {};
  final _WebViewShellUiController _ui = _WebViewShellUiController();
  String? _pendingPushUrl;
  bool _nativeLogoutInFlight = false;

  bool _suppressResidualKeyboardInsetAfterLogin = false;
  bool _draftResumePrompted = false;
  bool _syncPushAfterLocationNotice = true;
  bool _pendingLocationNoticeAfterLogin = false;
  Uri? _uriBeforeLogVisit;
  double? _scrollYBeforeLogVisit;

  bool _offlineNeedsReload = false;

  bool _holdOfflineUntilReload = false;

  bool _awaitingOfflineRecoveryLoad = false;

  static const _splashReleaseDelay = Duration(milliseconds: 2200);
  static const _firstPaintTimeout = Duration(seconds: 12);
  static const _recoveryTimeout = Duration(seconds: 10);
  static const _resumeHealthDelay = Duration(milliseconds: 450);
  static const _resumeStuckWatchdogDelay = Duration(seconds: 8);
  static const _resumeStaleReloadThreshold = Duration(minutes: 30);
  static const _maxSilentRecoveries = 2;

  DateTime? _lastBackgroundedAt;

  Timer? _splashReleaseTimer;
  Timer? _loadWatchdog;
  Timer? _recoveryWatchdog;
  Timer? _resumeStuckWatchdog;
  Timer? _loginTrackingStopTimer;
  int _loginTrackingStopGeneration = 0;
  int _webViewEpoch = 0;
  int _silentRecoveryAttempts = 0;
  int _startupTimeoutExtensions = 0;
  bool _recoveryInFlight = false;
  bool _awaitingRecoveryLoad = false;

  Timer? _offlineConnectivityDebounce;

  String? _lastBottomBarVisibilityLog;

  void _setNativeAuthSession(bool value) {
    final active = value && _ui.officerLoggedIn.value;
    _ui.setNativeAuthSession(active);
    if (_shouldUploadNativePermissionStatus) {
      NativePermissionStatusService.instance.startBatteryMonitoring();
    } else {
      NativePermissionStatusService.instance.stopBatteryMonitoring();
    }
  }

  void _cancelNativeGeoWatches() {
    if (_nativeGeoWatches.isEmpty) return;
    for (final sub in _nativeGeoWatches.values) {
      unawaited(sub.cancel());
    }
    _nativeGeoWatches.clear();
  }

  void _releaseUiLocationOnLogout() {
    _cancelNativeGeoWatches();
    unawaited(VisitGpsSession.instance.stop());
  }

  /// Login URL can flash for ~1s on cold start before redirect. Only stop GPS
  /// after the login route stays put.
  static const Duration _loginTrackingStopDelay = Duration(seconds: 3);

  Future<void> _pauseNativeSessionForLoginScreen() async {
    _suppressResidualKeyboardInsetAfterLogin = false;
    _pendingLocationNoticeAfterLogin = false;
    _ui.showLocationNotice.value = false;
    _ui.setOfficerLoggedIn(false);
    _setNativeAuthSession(false);
    _clearWebBottomBarHide();
    _draftResumePrompted = false;
    NativePermissionStatusService.instance.stopBatteryMonitoring();
    _releaseUiLocationOnLogout();
    // UI only for now — GPS stop is deferred so a brief login flash (cold
    // start redirect) does not kill on-duty tracking.
    _scheduleLoginTrackingStop();
  }

  void _cancelPendingLoginTrackingStop() {
    _loginTrackingStopTimer?.cancel();
    _loginTrackingStopTimer = null;
    _loginTrackingStopGeneration++;
  }

  void _scheduleLoginTrackingStop() {
    _loginTrackingStopTimer?.cancel();
    final generation = ++_loginTrackingStopGeneration;
    _loginTrackingStopTimer = Timer(_loginTrackingStopDelay, () {
      unawaited(_commitLoginTrackingStop(generation));
    });
  }

  Future<void> _commitLoginTrackingStop(int generation) async {
    if (generation != _loginTrackingStopGeneration) return;
    if (!mounted) return;
    if (!AuthSessionManager.isLoginRoute(_ui.currentUri.value)) return;

    if (kDebugMode) {
      debugPrint(
        '[SmartNPS360][Auth] login route stable '
        '(${_loginTrackingStopDelay.inSeconds}s) → stop duty GPS',
      );
    }
    await AuthRepository.instance.setOfficerLoggedIn(false);
    await _stopDutyHeartbeat(stopBackgroundLocation: true);
  }

  Future<bool> _performNativeLogout({
    required String reason,
    bool skipIfAlreadyLoggedOut = false,
  }) async {
    if (_nativeLogoutInFlight) return false;
    if (skipIfAlreadyLoggedOut && !await _hasActiveNativeSession()) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Auth] $reason skipped (session already cleared)',
        );
      }
      return false;
    }

    if (await DutyHeartbeatService.instance.isOnDutyAccordingToHeartbeat()) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Auth] logout skipped ($reason): officer on duty per heartbeat',
        );
      }
      return false;
    }

    _nativeLogoutInFlight = true;
    try {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Auth] native logout ($reason)');
      }

      _suppressResidualKeyboardInsetAfterLogin = false;
      _pendingLocationNoticeAfterLogin = false;
      _ui.showLocationNotice.value = false;
      _ui.setOfficerLoggedIn(false);
      _setNativeAuthSession(false);
      _ui.showingLogVisit.value = false;
      _clearWebBottomBarHide();
      _releaseUiLocationOnLogout();
      _draftResumePrompted = false;
      unawaited(
        _controller?.evaluateJavascript(
          source:
              "try { sessionStorage.removeItem('__smartnps_login'); } catch (e) {}",
        ),
      );

      await AuthSessionManager.clearNativeSession(deletePushToken: false);

      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Auth] native logout completed '
          '(officerLoggedIn=false, session cleared)',
        );
      }
      return true;
    } finally {
      _nativeLogoutInFlight = false;
    }
  }

  void _showLocationNoticeAfterLogin({bool syncPushAfterDismiss = true}) {
    if (!mounted) return;
    _syncPushAfterLocationNotice = syncPushAfterDismiss;

    if (AuthSessionManager.isLoginRoute(_ui.currentUri.value)) {
      _pendingLocationNoticeAfterLogin = true;
      _ui.showLocationNotice.value = false;
      return;
    }
    _pendingLocationNoticeAfterLogin = false;
    RequiredPermissionsGate.instance.stop();
    _ui.showLocationNotice.value = true;
  }

  void _activatePendingLocationNoticeIfNeeded() {
    if (!_pendingLocationNoticeAfterLogin) return;
    if (AuthSessionManager.isLoginRoute(_ui.currentUri.value)) return;
    _showLocationNoticeAfterLogin(
      syncPushAfterDismiss: _syncPushAfterLocationNotice,
    );
  }

  void _dismissLocationNotice() {
    _ui.showLocationNotice.value = false;
    if (!_ui.officerLoggedIn.value) return;

    final shouldSyncPush = _syncPushAfterLocationNotice;
    _syncPushAfterLocationNotice = true;
    unawaited(_runAfterLocationNoticeDismissed(syncPush: shouldSyncPush));
  }

  Future<void> _runAfterLocationNoticeDismissed({
    required bool syncPush,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted ||
        !_ui.officerLoggedIn.value ||
        _ui.showLocationNotice.value) {
      return;
    }

    RequiredPermissionsGate.instance.start();
    await RequiredPermissionsGate.instance.refresh(force: true);

    if (!mounted ||
        !_ui.officerLoggedIn.value ||
        _ui.showLocationNotice.value) {
      return;
    }

    // Let the privacy overlay finish dismissing, then ask for notifications
    // only (location/motion wait for clock-in Allow).
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted ||
        !_ui.officerLoggedIn.value ||
        _ui.showLocationNotice.value ||
        _pendingLocationNoticeAfterLogin) {
      return;
    }

    await PushNotificationService.instance
        .requestPermissionAfterPrivacyNotice();

    if (syncPush && Platform.isIOS) {
      await _prepareIosPushAuthFromWeb();
      await _notifyWebPushTokenReady();
    }

    if (!mounted || !_ui.officerLoggedIn.value) return;
    await _maybeStartDutyHeartbeat();
  }

  Future<bool> _hasActiveNativeSession() async {
    if (_ui.officerLoggedIn.value) return true;
    if (await AuthRepository.instance.isOfficerLoggedIn()) return true;
    final token = await AuthRepository.instance.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> _onRefreshSessionExpired() async {
    if (AuthState.instance.needsReauth.value) return;
    AuthState.instance.markNeedsReauth();
    if (kDebugMode) {
      debugPrint(
        '[SmartNPS360][Auth] refresh failed → token unavailable snackbar '
        '(no logout, tokens kept)',
      );
    }
    _showTokenUnavailableSnackbar();
  }

  void _showTokenUnavailableSnackbar() {
    Get.closeAllSnackbars();
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 4),
      titleText: const SizedBox.shrink(),
      messageText: const Text(
        'Token is not available. It will be available shortly.',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  void _clearSoftReauthAfterSuccessfulLogin() {
    AuthState.instance.clearNeedsReauth();
  }

  Future<void> _refreshNativeAuthSessionFromStorage() async {
    if (AuthSessionManager.isLoginRoute(_ui.currentUri.value)) {
      await _pauseNativeSessionForLoginScreen();
      return;
    }

    _cancelPendingLoginTrackingStop();

    final loggedIn = await AuthRepository.instance.isOfficerLoggedIn();
    final token = await AuthRepository.instance.getAccessToken();
    final hasToken = token != null && token.isNotEmpty;

    if (hasToken && !loggedIn) {
      await AuthRepository.instance.setOfficerLoggedIn(true);
    }
    final activeSession = hasToken;

    _ui.setOfficerLoggedIn(activeSession);
    _setNativeAuthSession(activeSession);
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
    _ui.pullToRefreshActive.value = false;
    _pullToRefreshSourceUri = null;
  }

  bool _isTransientReloadUri(Uri? uri) {
    if (uri == null) return true;
    if (!_ui.hasNativeAuthSession.value) return false;
    if (!_isAuthRoute(uri)) return false;
    final current = _ui.currentUri.value;
    if (current == null || _isAuthRoute(current)) return false;

    return _ui.bottomTabNavigationActive.value;
  }

  void _syncCurrentUriFromWebView(Uri? uri) {
    if (_shouldIgnoreWebViewNavigationEvent(uri)) return;
    final uriText = uri?.toString();
    if (_ui.currentUri.value?.toString() != uriText) {
      _ui.currentUri.value = uri;
      // Popups don't survive full navigations; restore bar unless web re-hides.
      _ui.webHidesBottomBar.value = false;
    }
    _recheckBottomBarForUri(uri);
  }

  void _clearWebBottomBarHide() {
    if (!_ui.webHidesBottomBar.value) return;
    _ui.webHidesBottomBar.value = false;
  }

  void _recheckBottomBarForUri(Uri? uri) {
    if (_ui.bottomTabNavigationActive.value) return;
    if (_ui.showingLogVisit.value) return;
    final tabIndex = _bottomTabIndexFromUri(uri);
    if (tabIndex != null && _ui.selectedBottomTabIndex.value != tabIndex) {
      _ui.selectedBottomTabIndex.value = tabIndex;
    }
  }

  void _logBottomBarVisibility({
    required bool show,
    required bool showPermissionBlocker,
    required bool uploadingFromDialog,
  }) {
    final uri = _ui.currentUri.value;
    final keyboardInset = _ui.flutterKeyboardInset.value;
    final isAuth = _isAuthRoute(uri);
    final isBottomRoute = _isBottomBarRoute(uri);
    final preserve = _ui.preserveBottomBarDuringLoad.value;
    final reasons = <String>[];
    if (showPermissionBlocker) reasons.add('permissionBlocker');
    if (_ui.showOffline.value) reasons.add('offline');
    if (!_ui.firstPageLoaded.value) reasons.add('firstPageNotLoaded');
    if (!_ui.officerLoggedIn.value) reasons.add('notLoggedIn');
    if (_ui.isKeyboardOpen) {
      reasons.add('keyboardOpen(inset=${keyboardInset.toStringAsFixed(1)})');
    }
    if (isAuth) reasons.add('authRoute');
    if (_ui.showingLogVisit.value) reasons.add('showingLogVisit');
    if (uploadingFromDialog) reasons.add('uploadingFromDialog');
    if (_ui.webHidesBottomBar.value) reasons.add('webHidesBottomBar');
    if (!isBottomRoute && !preserve) {
      reasons.add('notBottomBarRoute+noPreserve');
    }

    final signature =
        'show=$show uri=${uri?.toString() ?? 'null'} '
        'reasons=${reasons.isEmpty ? 'none' : reasons.join('|')} '
        'flags={permissionBlocker=$showPermissionBlocker '
        'offline=${_ui.showOffline.value} '
        'firstPageLoaded=${_ui.firstPageLoaded.value} '
        'officerLoggedIn=${_ui.officerLoggedIn.value} '
        'keyboardOpen=${_ui.isKeyboardOpen} '
        'keyboardInset=${keyboardInset.toStringAsFixed(1)} '
        'authRoute=$isAuth '
        'showingLogVisit=${_ui.showingLogVisit.value} '
        'uploadingFromDialog=$uploadingFromDialog '
        'webHidesBottomBar=${_ui.webHidesBottomBar.value} '
        'isBottomBarRoute=$isBottomRoute '
        'preserveDuringLoad=$preserve '
        'selectedTab=${_ui.selectedBottomTabIndex.value} '
        'platform=${Platform.isAndroid
            ? 'android'
            : Platform.isIOS
            ? 'ios'
            : 'other'}}';

    if (_lastBottomBarVisibilityLog == signature) return;
    _lastBottomBarVisibilityLog = signature;
    if (kDebugMode) {
      debugPrint('[SmartNPS360][BottomBar] $signature');
    }
  }

  Future<void> _reconcileBottomBarFromWebView(
    InAppWebViewController controller,
  ) async {
    if (_ui.pullToRefreshActive.value) return;
    try {
      final currentUrl = await controller.getUrl();
      _syncCurrentUriFromWebView(currentUrl?.uriValue);
    } catch (_) {}
  }

  void _onWebViewUrlCommitted(InAppWebViewController controller, Uri? uri) {
    if (_ui.pullToRefreshActive.value || _webReloadInProgress) return;
    _syncCurrentUriFromWebView(uri);
    unawaited(_reconcileBottomBarFromWebView(controller));
  }

  void _finishBottomTabNavigation() {
    _ui.bottomTabNavigationActive.value = false;
    _pendingBottomTabLoadStarted = false;
  }

  void _clearBottomBarLoadPreserve() {
    _ui.preserveBottomBarDuringLoad.value = false;
  }

  void _armBottomBarPreserveForNavigation({Uri? from, Uri? to}) {
    if (_ui.preserveBottomBarDuringLoad.value) return;

    if (_isAuthRoute(from)) return;
    if (_isBottomBarRoute(from) && to != null && _isBottomBarRoute(to)) {
      _ui.preserveBottomBarDuringLoad.value = true;
      return;
    }

    if (from == null &&
        _ui.officerLoggedIn.value &&
        _ui.firstPageLoaded.value &&
        !_isAuthRoute(_ui.currentUri.value)) {
      _ui.preserveBottomBarDuringLoad.value = true;
    }
  }

  void _onInWebBottomTabDestination(Uri uri) {
    final tabIndex = _bottomTabIndexFromUri(uri);
    if (tabIndex == null) return;
    if (_isAuthRoute(_ui.currentUri.value)) return;
    if (_ui.showingLogVisit.value) return;
    _ui.preserveBottomBarDuringLoad.value = true;
    if (_ui.bottomTabNavigationActive.value) return;
    if (_ui.selectedBottomTabIndex.value != tabIndex) {
      _ui.selectedBottomTabIndex.value = tabIndex;
    }
  }

  bool _isStalePreviousPageLoadStopDuringPreserve(
    Uri? nextUri,
    Uri? loadStartUri,
  ) {
    if (!_ui.preserveBottomBarDuringLoad.value) return false;
    if (loadStartUri == null || nextUri == null) return false;
    if (_normalizePageUrl(nextUri) != _normalizePageUrl(loadStartUri)) {
      return false;
    }
    return _isBottomBarRoute(loadStartUri);
  }

  void _endMainFrameNavigationChrome({bool clearPreserve = true}) {
    if (clearPreserve) {
      _clearBottomBarLoadPreserve();
    }
    _ui.endNavigation();
  }

  bool _shouldIgnoreWebViewNavigationEvent(Uri? uri) {
    if (uri == null) return true;

    if (_isTransientReloadUri(uri)) return true;

    final uriTab = _bottomTabIndexFromUri(uri);
    final selectedTab = _ui.selectedBottomTabIndex.value;

    if (_ui.bottomTabNavigationActive.value) {
      return uriTab != selectedTab;
    }

    if (!_ui.isNavigating.value &&
        uriTab != null &&
        uriTab != selectedTab &&
        _isBottomBarRoute(_ui.currentUri.value)) {
      return true;
    }
    return false;
  }

  void _restoreUriAfterReload(Uri? uri) {
    if (uri == null || _isAuthRoute(uri)) return;
    if (_ui.currentUri.value?.toString() == uri.toString()) {
      _recheckBottomBarForUri(uri);
      return;
    }
    _ui.currentUri.value = uri;
    _recheckBottomBarForUri(uri);
  }

  bool _isPullToRefreshReload(Uri? nextUri) {
    if (!_ui.pullToRefreshActive.value) return false;
    final source = _normalizePageUrl(_pullToRefreshSourceUri);
    final next = _normalizePageUrl(nextUri);
    if (source == null || next == null) return true;
    return source == next;
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

      'provider': 'flutter_geolocator',
      'is_mocked': location['isMocked'] == true,
      'is_simulated_by_software': location['isSimulatedBySoftware'] == true,
      'accepted_from_live_stream': location['acceptedFromLiveStream'] == true,
      'max_allowed_accuracy_meters': location['maxAllowedAccuracyMeters'] ?? 0,
      'timeout_ms': location['timeoutMs'] ?? 0,
    };
  }

  Map<String, dynamic> _toWebGeolocationPayloadFromPosition(Position position) {
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
      'max_allowed_accuracy_meters': 0,
      'timeout_ms': 0,
    };
  }

  static String _clockInBackgroundRequiredMessage() =>
      'Background location (${BackgroundLocationPermissions.alwaysAccessLabel()}) '
      'is required for shift attendance from the mobile app.';

  static String _enableAlwaysLocationInSettingsMessage() =>
      'Enable ${BackgroundLocationPermissions.alwaysAccessLabel()} location '
      'in Settings for shift attendance.';

  static String _enableBackgroundLocationMessage() =>
      'Enable background location (${BackgroundLocationPermissions.alwaysAccessLabel()}) '
      'for shift attendance.';

  static String _injectPlatformLocationLabels(String source) {
    return source
        .replaceAll(
          'Background location (Always or Allow all the time) is required for shift attendance from the mobile app.',
          _clockInBackgroundRequiredMessage(),
        )
        .replaceAll(
          'Enable Always or Allow all the time location in Settings for shift attendance.',
          _enableAlwaysLocationInSettingsMessage(),
        )
        .replaceAll(
          'Enable background location (Always / Allow all the time) for shift attendance.',
          _enableBackgroundLocationMessage(),
        );
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
        window.SmartNPS360.setBottomBarVisible = function (visible) {
          var next = false;
          if (typeof visible === 'boolean') {
            next = visible;
          } else if (typeof visible === 'number') {
            next = visible !== 0;
          } else if (typeof visible === 'string') {
            var text = visible.toLowerCase();
            next = text === 'true' || text === '1';
          } else if (visible && typeof visible === 'object') {
            if (Object.prototype.hasOwnProperty.call(visible, 'hidden')) {
              next = !(
                visible.hidden === true ||
                visible.hidden === 1 ||
                visible.hidden === '1' ||
                visible.hidden === 'true'
              );
            } else {
              var raw =
                visible.visible != null ? visible.visible : visible.show;
              next =
                raw === true ||
                raw === 1 ||
                raw === '1' ||
                raw === 'true';
            }
          }
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'setBottomBarVisible',
                { visible: next }
              );
            });
        };
        window.SmartNPS360.openLogVisit = function (payload) {
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'openLogVisit',
                payload == null ? {} : payload
              );
            });
        };
        window.SmartNPS360.isNativeApp = function () {
          try {
            return /SmartNPS360App/i.test(navigator.userAgent || '');
          } catch (_) {
            return false;
          }
        };
        window.SmartNPS360.getBackgroundLocationStatus = function () {
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'getBackgroundLocationStatus'
              );
            });
        };
        window.SmartNPS360.getPushNotificationStatus = function () {
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'getPushNotificationStatus'
              );
            });
        };
        window.SmartNPS360.setPushNotificationsEnabled = function (enabled) {
          var next =
            enabled === true ||
            enabled === 1 ||
            enabled === '1' ||
            enabled === 'true';
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'setPushNotificationsEnabled',
                { enabled: next }
              );
            })
            .then(function (status) {
              if (
                window.SmartNPS360 &&
                typeof window.SmartNPS360.broadcastPushNotificationStatus ===
                  'function'
              ) {
                window.SmartNPS360.broadcastPushNotificationStatus(status);
              }
              return status;
            });
        };
        window.SmartNPS360._syncAlpinePushNotificationState = function (
          enabled
        ) {
          if (!window.Alpine || typeof window.Alpine.$data !== 'function') {
            return;
          }
          try {
            var nodes = document.querySelectorAll('[x-data]');
            for (var i = 0; i < nodes.length; i++) {
              var data = window.Alpine.$data(nodes[i]);
              if (
                data &&
                Object.prototype.hasOwnProperty.call(
                  data,
                  'pushNotificationsEnabled'
                )
              ) {
                data.pushNotificationsEnabled = enabled === true;
              }
            }
          } catch (_) {}
        };
        function findAlpinePushNotificationButtons() {
          var byTitle = document.querySelectorAll(
            'button[title*="push notification" i]'
          );
          if (byTitle.length) {
            return Array.prototype.slice.call(byTitle);
          }
          var buttons = document.querySelectorAll('button[type="button"]');
          var found = [];
          for (var i = 0; i < buttons.length; i++) {
            var btn = buttons[i];
            var labels = btn.querySelectorAll('span');
            for (var j = 0; j < labels.length; j++) {
              var text = String(labels[j].textContent || '').trim();
              if (/^notifications$/i.test(text)) {
                found.push(btn);
                break;
              }
            }
          }
          return found;
        }
        window.SmartNPS360.broadcastPushNotificationStatus = function (
          status
        ) {
          if (!status || status.ok !== true) return;
          var enabled = status.enabled === true;
          window.SmartNPS360._syncAlpinePushNotificationState(enabled);
          var toggles = document.querySelectorAll(
            '[data-smartnps-push-toggle]'
          );
          for (var i = 0; i < toggles.length; i++) {
            window.SmartNPS360._applyPushNotificationToggleState(
              toggles[i],
              status
            );
          }
          var alpineButtons = findAlpinePushNotificationButtons();
          for (var k = 0; k < alpineButtons.length; k++) {
            window.SmartNPS360._applyAlpinePushNotificationToggleState(
              alpineButtons[k],
              enabled
            );
          }
          window.dispatchEvent(
            new CustomEvent('smartnps360:push-notifications', {
              detail: status,
            })
          );
          if (
            typeof window.SmartNPS360.onPushNotificationStatusChanged ===
            'function'
          ) {
            window.SmartNPS360.onPushNotificationStatusChanged(status);
          }
        };
        window.SmartNPS360.syncPushNotifications = function () {
          if (!window.SmartNPS360.isNativeApp()) {
            return Promise.resolve({ ok: false, reason: 'not_native' });
          }
          return window.SmartNPS360.getPushNotificationStatus().then(function (
            status
          ) {
            window.SmartNPS360.broadcastPushNotificationStatus(status);
            return status;
          });
        };
        window.SmartNPS360._applyPushNotificationToggleState = function (
          input,
          status
        ) {
          if (!input || !status || status.ok !== true) return;
          input.checked = status.enabled === true;
          input.setAttribute(
            'aria-checked',
            status.enabled === true ? 'true' : 'false'
          );
        };
        window.SmartNPS360.bindPushNotificationToggle = function (
          input,
          options
        ) {
          if (!input) return;
          options = options || {};

          function refresh() {
            if (!window.SmartNPS360.isNativeApp()) return;
            return window.SmartNPS360.syncPushNotifications().catch(function (
              err
            ) {
              if (typeof options.onError === 'function') {
                options.onError(err);
              }
            });
          }

          if (input.dataset.smartnpsPushBound !== '1') {
            input.dataset.smartnpsPushBound = '1';
            input.addEventListener('change', function () {
              if (!window.SmartNPS360.isNativeApp()) return;
              var next = input.checked === true;
              input.disabled = true;
              window.SmartNPS360.setPushNotificationsEnabled(next)
                .then(function (status) {
                  window.SmartNPS360._applyPushNotificationToggleState(
                    input,
                    status
                  );
                  if (typeof options.onChanged === 'function') {
                    options.onChanged(status);
                  }
                })
                .catch(function (err) {
                  input.checked = !next;
                  if (typeof options.onError === 'function') {
                    options.onError(err);
                  }
                })
                .finally(function () {
                  input.disabled = false;
                });
            });
            document.addEventListener('visibilitychange', function () {
              if (document.visibilityState === 'visible') refresh();
            });
          }

          refresh();
        };
        window.SmartNPS360._applyAlpinePushNotificationToggleState = function (
          button,
          enabled
        ) {
          if (!button) return;
          var on = enabled === true;
          button.setAttribute('aria-pressed', on ? 'true' : 'false');
          button.title = on
            ? 'Turn push notifications off'
            : 'Turn push notifications on';
          var spans = button.querySelectorAll('span');
          var track = spans.length > 1 ? spans[1] : null;
          var knob = spans.length > 2 ? spans[2] : null;
          if (track) {
            track.classList.toggle('bg-teal-600', on);
            track.classList.toggle('bg-slate-300', !on);
            track.classList.toggle('dark:bg-slate-700', !on);
          }
          if (knob) {
            knob.classList.toggle('translate-x-[18px]', on);
            knob.classList.toggle('translate-x-0.5', !on);
          }
        };
        window.SmartNPS360.bindAlpinePushNotificationToggle = function (
          button,
          options
        ) {
          if (!button || button.dataset.smartnpsAlpinePushBound === '1') return;
          options = options || {};
          button.dataset.smartnpsAlpinePushBound = '1';

          function refresh() {
            if (!window.SmartNPS360.isNativeApp()) return;
            return window.SmartNPS360.syncPushNotifications().catch(function (
              err
            ) {
              if (typeof options.onError === 'function') {
                options.onError(err);
              }
            });
          }

          function patchTogglePushNotifications() {
            if (window.__smartnps_toggle_push_patched === true) return;
            window.__smartnps_toggle_push_patched = true;
            window.togglePushNotifications = function () {
              if (!window.SmartNPS360.isNativeApp()) {
                return false;
              }
              return window.SmartNPS360.getPushNotificationStatus().then(
                function (status) {
                  var next = !(status && status.enabled === true);
                  return window.SmartNPS360.setPushNotificationsEnabled(next);
                }
              );
            };
          }

          patchTogglePushNotifications();

          button.addEventListener(
            'click',
            function (e) {
              if (!window.SmartNPS360.isNativeApp()) return;
              e.preventDefault();
              e.stopImmediatePropagation();
              var current = button.getAttribute('aria-pressed') === 'true';
              var next = !current;
              button.disabled = true;
              window.SmartNPS360.setPushNotificationsEnabled(next)
                .then(function (status) {
                  if (!(status && status.ok === true)) {
                    window.SmartNPS360._applyAlpinePushNotificationToggleState(
                      button,
                      current
                    );
                  }
                  if (typeof options.onChanged === 'function') {
                    options.onChanged(status);
                  }
                })
                .catch(function (err) {
                  window.SmartNPS360._applyAlpinePushNotificationToggleState(
                    button,
                    current
                  );
                  if (typeof options.onError === 'function') {
                    options.onError(err);
                  }
                })
                .finally(function () {
                  button.disabled = false;
                });
            },
            true
          );

          document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible') refresh();
          });

          refresh();
        };
        function bindPushNotificationToggles() {
          if (!window.SmartNPS360.isNativeApp()) return;
          var toggles = document.querySelectorAll(
            '[data-smartnps-push-toggle]'
          );
          for (var i = 0; i < toggles.length; i++) {
            window.SmartNPS360.bindPushNotificationToggle(toggles[i]);
          }
          var alpineButtons = findAlpinePushNotificationButtons();
          for (var k = 0; k < alpineButtons.length; k++) {
            window.SmartNPS360.bindAlpinePushNotificationToggle(alpineButtons[k]);
          }
          window.SmartNPS360.syncPushNotifications();
        }
        function startPushNotificationToggleObserver() {
          if (!window.SmartNPS360.isNativeApp()) return;
          if (window.__smartnps_push_toggle_observer) return;
          window.__smartnps_push_toggle_observer = true;
          var timer = null;
          var observer = new MutationObserver(function () {
            if (timer) clearTimeout(timer);
            timer = setTimeout(bindPushNotificationToggles, 250);
          });
          if (document.documentElement) {
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true
            });
          }
        }
        if (document.readyState === 'loading') {
          document.addEventListener(
            'DOMContentLoaded',
            function () {
              bindPushNotificationToggles();
              startPushNotificationToggleObserver();
            }
          );
        } else {
          bindPushNotificationToggles();
          startPushNotificationToggleObserver();
        }
        window.SmartNPS360.ensureCanClockIn = function () {
          if (window.SmartNPS360) {
            window.SmartNPS360._clockInGeoUnlocked = false;
            window.SmartNPS360._clockInGateInFlight = true;
          }
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler('prepareClockIn');
            })
            .then(function (gate) {
              if (window.SmartNPS360) {
                window.SmartNPS360._clockInGateInFlight = false;
              }
              if (!gate || gate.ok !== true) {
                if (window.SmartNPS360) {
                  window.SmartNPS360._clockInGeoUnlocked = false;
                }
                return {
                  ok: false,
                  reason: 'status_unavailable',
                  title: 'Location check failed',
                  message:
                    'Unable to verify location permissions. Please try again.',
                  status: gate || null
                };
              }
              if (gate.canClockIn === true) {
                if (window.SmartNPS360) {
                  window.SmartNPS360._clockInGeoUnlocked = true;
                }
                return { ok: true, status: gate };
              }
              if (window.SmartNPS360) {
                window.SmartNPS360._clockInGeoUnlocked = false;
              }
              return {
                ok: false,
                reason: gate.reason || 'background_location_required',
                title: gate.title || 'Background location required for shift attendance',
                message:
                  gate.message ||
                  'Background location (Always or Allow all the time) is required for shift attendance from the mobile app.',
                status: gate
              };
            })
            .catch(function (err) {
              if (window.SmartNPS360) {
                window.SmartNPS360._clockInGateInFlight = false;
                window.SmartNPS360._clockInGeoUnlocked = false;
              }
              throw err;
            });
        };
        window.SmartNPS360.notifyClockInSuccess = function (payload) {
          var data = payload == null ? {} : payload;
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'clock_in_success',
                data
              );
            });
        };
        window.SmartNPS360.notifyClockInCancelled = function (payload) {
          var data = payload == null ? {} : payload;
          return ensureFlutterBridge()
            .then(function () {
              return window.flutter_inappwebview.callHandler(
                'clock_in_cancelled',
                data
              );
            });
        };
        window.SmartNPS360._applyClockInButtonState = function (button, status) {
          if (!button) return;
          var canClockIn =
            !window.SmartNPS360.isNativeApp() ||
            (status &&
              status.ok === true &&
              status.canClockIn === true &&
              status.prepareInFlight !== true);
          button.disabled = !canClockIn;
          button.setAttribute('aria-disabled', canClockIn ? 'false' : 'true');
          if (canClockIn) {
            button.removeAttribute('title');
            button.classList.remove('smartnps-clockin-blocked');
          } else {
            button.setAttribute(
              'title',
              (status && status.message) ||
                'Enable Always or Allow all the time location in Settings for shift attendance.'
            );
            button.classList.add('smartnps-clockin-blocked');
          }
        };
        window.SmartNPS360.bindClockInGate = function (
          button,
          onAllowedClockIn,
          onBlocked
        ) {
          if (!button || typeof onAllowedClockIn !== 'function') return;

          function refresh() {
            return window.SmartNPS360.getBackgroundLocationStatus()
              .then(function (status) {
                window.SmartNPS360._applyClockInButtonState(button, status);
                return status;
              })
              .catch(function () {
                if (window.SmartNPS360.isNativeApp()) {
                  button.disabled = true;
                  button.setAttribute('aria-disabled', 'true');
                }
              });
          }

          if (button.dataset.smartnpsClockinBound !== '1') {
            button.dataset.smartnpsClockinBound = '1';
            button.addEventListener(
              'click',
              function (e) {
                if (!window.SmartNPS360.isNativeApp()) return;
                e.preventDefault();
                e.stopImmediatePropagation();
                window.SmartNPS360.ensureCanClockIn().then(function (gate) {
                  if (!gate.ok) {
                    if (window.SmartNPS360) {
                      window.SmartNPS360._clockInGeoUnlocked = false;
                    }
                    if (typeof onBlocked === 'function') {
                      onBlocked(gate);
                    } else {
                      alert(
                        gate.message ||
                          'Background location is required for shift attendance.'
                      );
                    }
                    return;
                  }
                  onAllowedClockIn();
                });
              },
              true
            );

            window.addEventListener(
              'smartnps360:background-location',
              function (ev) {
                window.SmartNPS360._applyClockInButtonState(
                  button,
                  ev && ev.detail
                );
              }
            );

            window.SmartNPS360.onBackgroundLocationStatusChanged = function (
              status
            ) {
              window.SmartNPS360._applyClockInButtonState(button, status);
            };

            document.addEventListener('visibilitychange', function () {
              if (document.visibilityState === 'visible') refresh();
            });
          }

          refresh();
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
              .catch(function () {})
              .then(function () {
                try {
                  form.submit();
                } catch (_) {
                  setLoginLoading(form, false);
                }
              });
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

        function log(message, data) {}

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

            nativeSource: true,
            ageMsWhenAccepted: Number(location.ageMsWhenAccepted || 0),
            isFreshLiveLocation: location.isFreshLiveLocation === true,
            isCachedLocation: location.isCachedLocation === true
          };
        }

        function toNativeOptions(options) {
          var nativeOptions = {
            timeout_ms: 12000
          };

          if (
            window.SmartNPS360 &&
            window.SmartNPS360._clockInGeoUnlocked === true
          ) {
            nativeOptions.for_clock_in = true;
          }

          if (options.allow_foreground_only === true) {
            nativeOptions.allow_foreground_only = true;
          }

          if (!options || typeof options !== 'object') {
            return nativeOptions;
          }

          if (typeof options.timeout === 'number' && isFinite(options.timeout)) {
            nativeOptions.timeout_ms = Math.max(5000, Math.min(45000, Math.round(options.timeout)));
          }

          return nativeOptions;
        }

        function requestNativePosition(success, error, options) {
          log('Native location requested from webpage');

          if (
            window.SmartNPS360 &&
            window.SmartNPS360.isNativeApp() &&
            window.SmartNPS360._clockInGateInFlight === true &&
            !(options && options.allow_foreground_only === true)
          ) {
            if (typeof error === 'function') {
              error(
                gpsError(
                  'Location permission check is still in progress. ' +
                    'Enable background location (Always / Allow all the time) for shift attendance.'
                )
              );
            }
            return;
          }

          var chain = waitForFlutterBridge();

          if (
            window.SmartNPS360 &&
            window.SmartNPS360.isNativeApp() &&
            !(options && options.allow_foreground_only === true)
          ) {
            chain = chain
              .then(function () {
                return window.SmartNPS360.ensureCanClockIn();
              })
              .then(function (gate) {
                if (!gate || gate.ok !== true) {
                  var msg =
                    (gate && gate.message) ||
                    'Background location (Always or Allow all the time) is required for shift attendance from the mobile app.';
                  throw gpsError(msg);
                }
              });
          }

          chain
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

        window.__smartnps_native_geo_emit = function (watchId, payload) {
          try {
            var cb = nativeWatchCallbacks[watchId];
            if (!cb || !nativeWatches[watchId]) return;
            if (cb.success) cb.success(payload);
          } catch (_) {}
        };

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
      } catch (exception) {}
    })();
  ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

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

  static final UserScript _iosKeyboardInputFixScript = UserScript(
    source: r'''
    (function () {
      'use strict';
      if (window.__smartnps_ios_keyboard_fix_installed) return;
      window.__smartnps_ios_keyboard_fix_installed = true;

      var SKIP_INPUT_TYPES = {
        password: true,
        hidden: true,
        submit: true,
        button: true,
        checkbox: true,
        radio: true,
        file: true,
        reset: true,
        image: true
      };

      function isEditable(el) {
        if (!el || el.nodeType !== 1) return false;
        var tag = el.tagName;
        if (tag === 'TEXTAREA') return true;
        if (tag === 'INPUT') {
          var type = (el.getAttribute('type') || 'text').toLowerCase();
          return !SKIP_INPUT_TYPES[type];
        }
        if (el.isContentEditable) return true;
        var editable = (el.getAttribute('contenteditable') || '').toLowerCase();
        return editable === '' || editable === 'true' || editable === 'plaintext-only';
      }

      function enableSuggestionsOnly(el) {
        if (!isEditable(el)) return;
        el.setAttribute('autocorrect', 'on');
        el.setAttribute('autocapitalize', 'sentences');
      }

      function scan(root) {
        if (!root || !root.querySelectorAll) return;
        var nodes = root.querySelectorAll(
          'textarea, input, [contenteditable], [contenteditable="true"], [contenteditable="plaintext-only"]'
        );
        for (var i = 0; i < nodes.length; i++) {
          enableSuggestionsOnly(nodes[i]);
        }
      }

      function insertSpace(el) {
        if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
          var start = el.selectionStart;
          var end = el.selectionEnd;
          if (start == null || end == null) return;
          var value = el.value || '';
          el.value = value.slice(0, start) + ' ' + value.slice(end);
          var pos = start + 1;
          el.setSelectionRange(pos, pos);
          try {
            el.dispatchEvent(new InputEvent('input', {
              bubbles: true,
              inputType: 'insertText',
              data: ' '
            }));
          } catch (_) {
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }
          return;
        }
        if (el.isContentEditable) {
          try {
            document.execCommand('insertText', false, ' ');
          } catch (_) {}
        }
      }

      var lastKeyWasSpace = false;

      document.addEventListener('keydown', function (event) {
        if (!isEditable(event.target)) return;
        lastKeyWasSpace = event.key === ' ' || event.keyCode === 32;
      }, true);

      document.addEventListener('beforeinput', function (event) {
        if (!isEditable(event.target)) return;
        if (!lastKeyWasSpace) return;

        if (event.inputType === 'insertReplacementText') {
          event.preventDefault();
          insertSpace(event.target);
        }

        lastKeyWasSpace = false;
      }, true);

      window.__smartnpsIosKeyboardInputFixScan = function () {
        scan(document);
      };

      document.addEventListener('focusin', function (event) {
        enableSuggestionsOnly(event.target);
      }, true);

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { scan(document); });
      } else {
        scan(document);
      }

      if (typeof MutationObserver !== 'undefined' && document.documentElement) {
        var observer = new MutationObserver(function (mutations) {
          for (var i = 0; i < mutations.length; i++) {
            var added = mutations[i].addedNodes;
            for (var j = 0; j < added.length; j++) {
              var node = added[j];
              if (node.nodeType !== 1) continue;
              enableSuggestionsOnly(node);
              scan(node);
            }
          }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
      }
    })();
  ''',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  late final JsBridge _bridge = JsBridge(
    getCurrentUrlHost: () => _ui.currentUri.value?.host,
    onDownloadRequested: _downloadAndReturn,
  );

  void _applySystemUi() {
    final isDark = _ui.webPrefersDark.value;
    final style = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final navColor = isDark ? const Color(0xFF0F1724) : const Color(0xFFF8FAFC);

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
    if (_ui.webPrefersDark.value != isDark) {
      _ui.webPrefersDark.value = isDark;
    }
    _applySystemUi();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    AuthRepository.instance.onRefreshSessionExpired = _onRefreshSessionExpired;

    unawaited(AppUpgradeReconciler.reconcileOsAfterEngineReady());
    RequiredPermissionsGate.privacyNoticeVisibleChecker = () =>
        _ui.showLocationNotice.value || _pendingLocationNoticeAfterLogin;
    OffDutyPushPromptService.currentUriChecker = () => _ui.currentUri.value;
    OnDutyPermissionsPromptService.currentUriChecker = () =>
        _ui.currentUri.value;
    PushNotificationService.instance.setDeferPermissionPromptWhile(
      () =>
          _ui.showLocationNotice.value ||
          _pendingLocationNoticeAfterLogin ||
          (_isAuthRoute(_ui.currentUri.value) && !_ui.officerLoggedIn.value),
    );
    _ui.webPrefersDark.value = false;
    NativeThemeController.instance.setDark(_ui.webPrefersDark.value);
    _applySystemUi();

    if (Platform.isAndroid || Platform.isIOS) {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(color: const Color(AppConfig.cPrimary)),
        onRefresh: () async {
          final controller = _controller;
          if (controller == null) return;
          final currentUrl = await controller.getUrl();
          _ui.pullToRefreshActive.value = true;
          _webReloadInProgress = true;
          _pullToRefreshSourceUri =
              currentUrl?.uriValue ?? _ui.currentUri.value;

          await controller.reload();
        },
      );
    }

    unawaited(_syncOfflineFromConnectivity());
    _scheduleStartupWatchdogs();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      unawaited(_handleConnectivityChanged(results));
    });

    DutyHeartbeatService.instance.backgroundLocationPermissionMissing
        .addListener(_onBackgroundLocationPermissionChanged);

    if (_shouldUploadNativePermissionStatus) {
      unawaited(
        NativePermissionStatusService.instance.uploadAppCycle(
          appCycle: AppLifecycleState.resumed.name,
        ),
      );
    }

    PushNotificationService.instance.setOnNotificationTap(
      _onPushNotificationTap,
    );
    OfficerAnnouncementCoordinator.instance.attach(
      deliverToWebView: _deliverAnnouncementToWebView,
      isDeliveryReady: _isReadyForAnnouncementDelivery,
      ensureOfficerWebViewVisible: _ensureOfficerWebViewForAnnouncement,
    );
    if (Platform.isIOS) {
      PushNotificationService.instance.setIosWebPushUploadHandler(
        _uploadPushTokenViaWebView,
      );
      PushNotificationService.instance.setIosWebPushDeleteHandler(
        _deletePushTokenViaWebView,
      );
    }
  }

  void _onPushNotificationTap(String url) {
    _pendingPushUrl = url;
    unawaited(_loadPendingPushUrl());
  }

  bool _isReadyForAnnouncementDelivery() {
    if (_controller == null) return false;
    final uri = _ui.currentUri.value;
    if (!AuthSessionManager.isOfficerApplicationUrl(uri)) return false;
    if (AuthSessionManager.isLoginRoute(uri)) return false;
    return true;
  }

  void _ensureOfficerWebViewForAnnouncement(Uri? destinationUrl) {
    if (_isReadyForAnnouncementDelivery()) return;

    final target = destinationUrl?.toString() ?? AppRoutes.defaultPushUrl;
    final normalized = PushNotificationService.normalizeNotificationUrl(target);
    _pendingPushUrl = normalized;
    unawaited(_loadPendingPushUrl());
  }

  Future<bool> _deliverAnnouncementToWebView(String recipientPublicId) async {
    final controller = _controller;
    if (controller == null) return false;
    if (!_isReadyForAnnouncementDelivery()) return false;

    final javascript = OfficerAnnouncementCoordinator.buildDeliveryJavaScript(
      recipientPublicId,
    );
    try {
      final result = await controller.evaluateJavascript(source: javascript);
      return OfficerAnnouncementCoordinator.normalizeJavaScriptBoolean(result);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Announcement] evaluateJavascript failed: $e');
      }
      return false;
    }
  }

  Future<void> _loadPendingPushUrl() async {
    final url = _pendingPushUrl;
    final controller = _controller;
    if (url == null || controller == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !_isInternalUrl(uri)) {
      _pendingPushUrl = null;
      return;
    }

    _pendingPushUrl = null;
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    await _reconcileBottomBarFromWebView(controller);
  }

  Future<void> _maybeStartDutyHeartbeat() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (AuthSessionManager.isLoginRoute(_ui.currentUri.value)) return;
    if (_ui.showLocationNotice.value || _pendingLocationNoticeAfterLogin) {
      return;
    }
    final token = await AuthRepository.instance.getAccessToken();
    if (token == null || token.isEmpty) return;
    DutyHeartbeatService.instance.start();
  }

  Future<void> _stopDutyHeartbeat({bool stopBackgroundLocation = true}) async {
    await DutyHeartbeatService.instance.stop(
      stopBackgroundLocation: stopBackgroundLocation,
    );
  }

  void _onBackgroundLocationPermissionChanged() {
    unawaited(() async {
      await _notifyWebBackgroundLocationStatus();
      if (_shouldUploadNativePermissionStatus) {
        await NativePermissionStatusService.instance.syncIfChanged();
      }
    }());
  }

  Future<void> _notifyWebBackgroundLocationStatus() async {
    if (!_shouldUploadNativePermissionStatus) return;
    final controller = _controller;
    if (controller == null) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final result = await _bridge.getBackgroundLocationStatus();
      final encoded = jsonEncode(result);
      await controller.evaluateJavascript(
        source:
            '''
        (function () {
          try {
            var status = $encoded;
            window.dispatchEvent(
              new CustomEvent('smartnps360:background-location', { detail: status })
            );
            if (
              window.SmartNPS360 &&
              typeof window.SmartNPS360.onBackgroundLocationStatusChanged === 'function'
            ) {
              window.SmartNPS360.onBackgroundLocationStatusChanged(status);
            }
          } catch (e) {}
        })();
      ''',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360] notify web background location status failed: $e',
        );
      }
    }
  }

  Future<void> _notifyWebPushNotificationStatus({bool reconcile = true}) async {
    if (!_shouldUploadNativePermissionStatus) return;
    final controller = _controller;
    if (controller == null) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final result = reconcile
          ? await PushNotificationService.instance.reconcileOnAppResume()
          : await PushNotificationService.instance.getNotificationStatus();
      final encoded = jsonEncode(result);
      await controller.evaluateJavascript(
        source:
            '''
        (function () {
          try {
            var status = $encoded;
            if (
              window.SmartNPS360 &&
              typeof window.SmartNPS360.broadcastPushNotificationStatus === 'function'
            ) {
              window.SmartNPS360.broadcastPushNotificationStatus(status);
            } else {
              window.dispatchEvent(
                new CustomEvent('smartnps360:push-notifications', { detail: status })
              );
            }
          } catch (e) {}
        })();
      ''',
      );
    } catch (e) {}
  }

  Future<void> _promptAfterWebPushDisabled() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_ui.showLocationNotice.value) return;
    if (AuthSessionManager.isLoginRoute(_ui.currentUri.value)) return;
    if (AppConfig.isAuthEntryRoute(_ui.currentUri.value)) return;

    await RequiredPermissionsGate.instance.refresh(force: true);

    await OnDutyPermissionsPromptService.instance.maybeShow(
      fromResume: false,
      forceImmediate: true,
    );

    if (_ui.officerLoggedIn.value && !_ui.showLocationNotice.value) {
      await OffDutyPushPromptService.instance.maybeShow(
        fromResume: false,
        forceImmediate: true,
      );
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (_suppressResidualKeyboardInsetAfterLogin) {
      if (inset <= AppConfig.keyboardOpenThreshold) {
        _ui.setFlutterKeyboardInset(0);
        return;
      }
      _suppressResidualKeyboardInsetAfterLogin = false;
    }
    _ui.setFlutterKeyboardInset(inset);
  }

  void _dismissKeyboardAfterLogin() {
    _suppressResidualKeyboardInsetAfterLogin = true;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.clearFocus());
    }
    _ui.setFlutterKeyboardInset(0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _shouldUploadNativePermissionStatus) {
      NativePermissionStatusService.instance.startBatteryMonitoring();
    } else {
      NativePermissionStatusService.instance.stopBatteryMonitoring();
    }

    if (_shouldUploadNativePermissionStatus) {
      unawaited(
        NativePermissionStatusService.instance.uploadAppCycle(
          appCycle: state.name,
        ),
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isIOS && state == AppLifecycleState.inactive) {
        unawaited(BackgroundLocationController.notifyAppBackgrounded());
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _lastBackgroundedAt = DateTime.now();
        unawaited(BackgroundLocationController.notifyAppBackgrounded());
      } else if (state == AppLifecycleState.resumed) {
        unawaited(BackgroundLocationController.notifyAppForegrounded());
      }
    }

    if (state == AppLifecycleState.resumed) {
      final staleBackground = _isStaleBackgroundResume();
      if (!staleBackground) {
        unawaited(_checkWebViewHealthAfterResume());
        _scheduleResumeStuckRecoveryWatchdog();
      }
      unawaited(_syncOfflineFromConnectivity());
      if (_ui.officerLoggedIn.value && !_ui.showLocationNotice.value) {
        unawaited(RequiredPermissionsGate.instance.refresh(force: true));
      }
    }

    if (state == AppLifecycleState.resumed &&
        !AuthSessionManager.isLoginRoute(_ui.currentUri.value)) {
      if (Platform.isAndroid &&
          PermissionSettingsHelper.isAwaitingSettingsReturn) {
        PermissionSettingsHelper.clearPopupRoutesImmediately();
      }
      if (!_ui.showLocationNotice.value) {
        DutyHeartbeatService.instance.reconcileDialogsAfterAppResume();
      }

      if (Platform.isAndroid &&
          !_ui.showLocationNotice.value &&
          !ClockInGateService.instance.isPrepareInFlight &&
          !PermissionSettingsHelper.isAwaitingSettingsReturn) {
        ClockInBlockedDialog.reconcileAfterAppResume();
      }
      AppLifecycleResumeGate.notifyResumed();
      final controller = _controller;
      unawaited(() async {
        if (_ui.showLocationNotice.value) {
          if (controller != null) {
            await _reconcileBottomBarFromWebView(controller);
          }
          await _maybeReloadWebViewAfterLongBackground();
          return;
        }

        await DutyHeartbeatService.instance
            .refreshBackgroundLocationPermissionBannerState();
        await RequiredPermissionsGate.instance.refresh(force: true);

        await AppUpgradeReconciler.reconcileOsAfterEngineReady();
        await LocationDisclosureConsent.reconcileFromOsIfBackgroundReady();
        if (controller != null) {
          await _reconcileBottomBarFromWebView(controller);
        }
        await _requestNotificationPermissionForRoute(_ui.currentUri.value);
        DutyHeartbeatService.instance.beginResumeDutyReconcile();
        try {
          await _maybeStartDutyHeartbeat();
          // Show before heavier duty reconcile so resume isn't blocked by
          // notification / tracking prompts racing this dialog.
          await OnDutyPermissionsPromptService.instance.maybeShow(
            fromResume: true,
          );
          await DutyHeartbeatService.instance.recheckOnDutyPrompts(
            fromResume: true,
          );
          await OnDutyPermissionsPromptService.instance.maybeShow(
            fromResume: false,
          );
          if (_ui.officerLoggedIn.value &&
              !_ui.showLocationNotice.value &&
              !AppConfig.isAuthEntryRoute(_ui.currentUri.value)) {
            await OffDutyPushPromptService.instance.maybeShow(fromResume: true);
          }
        } finally {
          DutyHeartbeatService.instance.endResumeDutyReconcile();
        }
        if (Platform.isIOS) {
          await IosDutyLocationPinger.flushPendingBatchNow();
        }
        await ClockInGateService.instance.recheckAfterAppResume();
        // Explicit Flutter FGS start after resume (native kill-watch does not
        // start FGS while the UI is open).
        await DutyHeartbeatService.instance.retryOnDutyTrackingIfReady();
        if (!ClockInGateService.instance.isPrepareInFlight &&
            !ClockInPermissionsDialog.isVisible) {
          await _notifyWebBackgroundLocationStatus();
          await _notifyWebPushNotificationStatus();
        }

        await NativePermissionStatusService.instance
            .ensureLatestPermissionsSynced();
        await OfficerAnnouncementCoordinator.instance.tryDeliverPending(
          source: 'resumed',
        );
        await _maybeReloadWebViewAfterLongBackground();
      }());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_maybeReloadWebViewAfterLongBackground());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (identical(
      AuthRepository.instance.onRefreshSessionExpired,
      _onRefreshSessionExpired,
    )) {
      AuthRepository.instance.onRefreshSessionExpired = null;
    }
    RequiredPermissionsGate.instance.stop();
    RequiredPermissionsGate.privacyNoticeVisibleChecker = null;
    OffDutyPushPromptService.currentUriChecker = null;
    OnDutyPermissionsPromptService.currentUriChecker = null;
    OfficerAnnouncementCoordinator.instance.detach();
    PushNotificationService.instance.setDeferPermissionPromptWhile(null);
    PushNotificationService.instance.setOnNotificationTap(null);
    if (Platform.isIOS) {
      PushNotificationService.instance.setIosWebPushUploadHandler(null);
      PushNotificationService.instance.setIosWebPushDeleteHandler(null);
    }
    _connectivitySub?.cancel();
    _offlineConnectivityDebounce?.cancel();
    _cancelPendingLoginTrackingStop();
    _cancelWebViewWatchdogs();
    DutyHeartbeatService.instance.backgroundLocationPermissionMissing
        .removeListener(_onBackgroundLocationPermissionChanged);
    NativePermissionStatusService.instance.stopBatteryMonitoring();
    unawaited(_stopDutyHeartbeat());
    _cancelNativeGeoWatches();
    _ui.dispose();
    super.dispose();
  }

  static bool _hasNetworkInterface(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _cancelOfflineConnectivityDebounce() {
    _offlineConnectivityDebounce?.cancel();
    _offlineConnectivityDebounce = null;
  }

  Future<void> _syncOfflineFromConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;

    await _handleConnectivityChanged(results);
  }

  void _clearOfflineRetryUi() {
    _ui.offlineRetrying.value = false;
    _ui.offlineStatusMessage.value = null;
  }

  void _dismissOfflineScreen() {
    _cancelOfflineConnectivityDebounce();
    _holdOfflineUntilReload = false;
    _ui.showOffline.value = false;
    _clearOfflineRetryUi();
    _silentRecoveryAttempts = 0;
  }

  void _showOffline({required bool needsReload}) {
    if (needsReload) _offlineNeedsReload = true;
    _ui.showOffline.value = true;
    _endMainFrameNavigationChrome();
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    if (!mounted) return;
    final hasInternet = _hasNetworkInterface(results);
    if (hasInternet) {
      _cancelOfflineConnectivityDebounce();
      if (!_ui.showOffline.value) return;
      _ui.offlineRetrying.value = true;
      _ui.offlineStatusMessage.value = null;
      await _recoverFromOffline();
      return;
    }

    _offlineConnectivityDebounce?.cancel();
    _offlineConnectivityDebounce = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_confirmOfflineFromConnectivity()),
    );
  }

  Future<void> _confirmOfflineFromConnectivity() async {
    _offlineConnectivityDebounce = null;
    if (!mounted) return;
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    if (_hasNetworkInterface(results) ||
        await SiteReachability.canReachSite()) {
      if (!mounted) return;
      if (_ui.showOffline.value) {
        _ui.offlineRetrying.value = true;
        _ui.offlineStatusMessage.value = null;
        await _recoverFromOffline();
      }
      return;
    }
    if (!mounted) return;
    if (_ui.showOffline.value) return;
    _clearOfflineRetryUi();
    _showOffline(needsReload: !_ui.firstPageLoaded.value);
  }

  Future<void> _recoverFromOffline() async {
    if (!mounted) return;
    final needsReload = _offlineNeedsReload || !_ui.firstPageLoaded.value;
    if (!needsReload) {
      _dismissOfflineScreen();
      return;
    }

    final controller = _controller;
    if (controller == null) {
      _ui.offlineRetrying.value = false;
      _ui.offlineStatusMessage.value =
          'Unable to reconnect right now. Please try again.';
      return;
    }

    final target = _ui.currentUri.value?.toString() ?? AppRoutes.webBaseUrl;
    try {
      _awaitingOfflineRecoveryLoad = true;

      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
    } catch (_) {
      _awaitingOfflineRecoveryLoad = false;
      if (await SiteReachability.canReachSite()) {
        if (!mounted) return;
        _holdOfflineUntilReload = false;
        _dismissOfflineScreen();
        return;
      }
      if (!mounted) return;
      _holdOfflineUntilReload = true;
      _ui.offlineRetrying.value = false;
      _ui.offlineStatusMessage.value =
          'Couldn\'t reconnect. Check your connection and try again.';
      _showOffline(needsReload: true);
    }
  }

  void _cancelWebViewWatchdogs() {
    _splashReleaseTimer?.cancel();
    _splashReleaseTimer = null;
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = null;
    _resumeStuckWatchdog?.cancel();
    _resumeStuckWatchdog = null;
  }

  void _scheduleStartupWatchdogs() {
    _splashReleaseTimer?.cancel();
    _splashReleaseTimer = Timer(_splashReleaseDelay, () {
      if (!mounted) return;
      _releaseSplash();
    });
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(_firstPaintTimeout, () {
      unawaited(_onStartupLoadTimedOut());
    });
  }

  void _releaseSplash() {
    if (_ui.splashReleased.value) return;
    _ui.splashReleased.value = true;
    if (!_ui.firstPageLoaded.value && !_ui.showOffline.value) {
      _ui.beginNavigation();
    }
  }

  void _markWebViewContentReady() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = null;
    _resumeStuckWatchdog?.cancel();
    _resumeStuckWatchdog = null;
    _silentRecoveryAttempts = 0;
    _recoveryInFlight = false;
    _awaitingRecoveryLoad = false;
    _startupTimeoutExtensions = 0;
    _ui.splashReleased.value = true;
    _ui.firstPageLoaded.value = true;
  }

  String _webViewRecoveryTarget() {
    return _ui.currentUri.value?.toString() ?? AppRoutes.webBaseUrl;
  }

  bool _isUsableWebViewUri(Uri? uri) {
    if (uri == null) return false;
    final text = uri.toString();
    return text.isNotEmpty && text != 'about:blank';
  }

  Future<void> _onStartupLoadTimedOut() async {
    if (!mounted) return;
    if (_ui.firstPageLoaded.value || _ui.showOffline.value) return;
    _releaseSplash();

    final controller = _controller;
    if (controller != null) {
      final health = await _probeWebViewHealth(controller);
      if (!mounted) return;
      if (_ui.firstPageLoaded.value || _ui.showOffline.value) return;
      if (health == _WebViewHealth.ok) {
        _markWebViewContentReady();
        unawaited(_refreshNativeAuthSessionFromStorage());
        unawaited(_maybeStartDutyHeartbeat());
        return;
      }
      final stillDownloading =
          _ui.loadProgress.value > 0 && _ui.loadProgress.value < 100;
      if (stillDownloading && _startupTimeoutExtensions < 1) {
        _startupTimeoutExtensions++;
        _loadWatchdog?.cancel();
        _loadWatchdog = Timer(_recoveryTimeout, () {
          unawaited(_onStartupLoadTimedOut());
        });
        return;
      }
    }

    if (await SiteReachability.canReachSite()) {
      if (!mounted) return;
      await _recoverWebView(reason: 'startup_timeout');
      return;
    }
    if (!mounted) return;
    _showOffline(needsReload: true);
  }

  bool _isStaleBackgroundResume() {
    final lastBackgrounded = _lastBackgroundedAt;
    if (lastBackgrounded == null) return false;
    return DateTime.now().difference(lastBackgrounded) >=
        _resumeStaleReloadThreshold;
  }

  Future<void> _maybeReloadWebViewAfterLongBackground() async {
    if (!mounted) return;
    if (_ui.showOffline.value) return;
    if (_ui.showingLogVisit.value) return;
    if (_ui.pullToRefreshActive.value) return;
    if (!_ui.firstPageLoaded.value) return;

    final lastBackgrounded = _lastBackgroundedAt;
    _lastBackgroundedAt = null;
    if (lastBackgrounded == null) return;

    final away = DateTime.now().difference(lastBackgrounded);
    if (away < _resumeStaleReloadThreshold) return;

    if (kDebugMode) {
      debugPrint(
        '[SmartNPS360][WebView] stale background reload after '
        '${away.inMinutes}m',
      );
    }
    await _recoverWebView(reason: 'resume_stale_background', recreate: true);
  }

  Future<_WebViewHealth> _probeWebViewHealth(
    InAppWebViewController controller,
  ) async {
    try {
      final url = await controller.getUrl().timeout(const Duration(seconds: 2));
      final urlText = url?.toString() ?? '';
      if (urlText.isEmpty || urlText == 'about:blank') {
        return _WebViewHealth.blank;
      }

      final result = await controller
          .evaluateJavascript(
            source: '''
              (function () {
                try {
                  var html = (document.documentElement &&
                    document.documentElement.outerHTML) || '';
                  if (!html || html.length < 80) return 'blank';
                  return 'ok';
                } catch (e) {
                  return 'dead';
                }
              })();
            ''',
          )
          .timeout(const Duration(seconds: 2));
      final text = result?.toString() ?? 'dead';
      if (text.contains('blank')) return _WebViewHealth.blank;
      if (text.contains('dead')) return _WebViewHealth.dead;
      return _WebViewHealth.ok;
    } catch (_) {
      return _WebViewHealth.dead;
    }
  }

  void _clearStuckWebViewRecoveryState({bool resetAttempts = false}) {
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = null;
    _recoveryInFlight = false;
    _awaitingRecoveryLoad = false;
    _ui.endNavigation();
    if (resetAttempts) {
      _silentRecoveryAttempts = 0;
    }
  }

  void _scheduleResumeStuckRecoveryWatchdog() {
    _resumeStuckWatchdog?.cancel();
    _resumeStuckWatchdog = Timer(_resumeStuckWatchdogDelay, () {
      unawaited(_recoverFromResumeStuckIfNeeded());
    });
  }

  Future<void> _recoverFromResumeStuckIfNeeded() async {
    if (!mounted) return;
    if (_ui.showOffline.value) return;
    if (_ui.showingLogVisit.value) return;
    if (_ui.pullToRefreshActive.value) return;
    if (!_ui.firstPageLoaded.value) return;

    final controller = _controller;
    final health = controller == null
        ? _WebViewHealth.blank
        : await _probeWebViewHealth(controller);
    if (!mounted) return;

    final stuckRecovery = _recoveryInFlight || _awaitingRecoveryLoad;
    final stuckNavigation =
        _ui.isNavigating.value && _ui.loadProgress.value < 100;

    if (health == _WebViewHealth.ok && !stuckRecovery && !stuckNavigation) {
      return;
    }

    if (health == _WebViewHealth.ok && (stuckRecovery || stuckNavigation)) {
      _clearStuckWebViewRecoveryState(resetAttempts: true);
      return;
    }

    _clearStuckWebViewRecoveryState(resetAttempts: true);
    await _recoverWebView(reason: 'resume_stuck_watchdog', recreate: true);
  }

  Future<void> _checkWebViewHealthAfterResume() async {
    await Future<void>.delayed(_resumeHealthDelay);
    if (!mounted) return;
    if (_ui.showOffline.value) return;
    if (_ui.showingLogVisit.value) return;
    if (_ui.pullToRefreshActive.value) return;
    if (!_ui.firstPageLoaded.value) return;

    final controller = _controller;
    final health = controller == null
        ? _WebViewHealth.blank
        : await _probeWebViewHealth(controller);
    if (!mounted) return;

    final stuckRecovery = _recoveryInFlight || _awaitingRecoveryLoad;
    final stuckNavigation =
        _ui.isNavigating.value && _ui.loadProgress.value < 100;

    if (health == _WebViewHealth.ok && !stuckRecovery && !stuckNavigation) {
      return;
    }

    if (health == _WebViewHealth.ok && (stuckRecovery || stuckNavigation)) {
      _clearStuckWebViewRecoveryState(resetAttempts: true);
      return;
    }

    _clearStuckWebViewRecoveryState(resetAttempts: true);
    await _recoverWebView(reason: 'resume_${health.name}', recreate: true);
  }

  void _armRecoveryWatchdog() {
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = Timer(_recoveryTimeout, () {
      unawaited(_onRecoveryTimedOut());
    });
  }

  Future<void> _onRecoveryTimedOut() async {
    if (!mounted) return;
    if (!_awaitingRecoveryLoad) return;
    _awaitingRecoveryLoad = false;
    _recoveryInFlight = false;
    if (_silentRecoveryAttempts < _maxSilentRecoveries) {
      await _recoverWebView(reason: 'recovery_timeout', recreate: true);
      return;
    }
    _failRecoveryToOffline();
  }

  void _failRecoveryToOffline() {
    _recoveryInFlight = false;
    _awaitingRecoveryLoad = false;
    _recoveryWatchdog?.cancel();
    _recoveryWatchdog = null;
    _ui.endNavigation();
    _holdOfflineUntilReload = true;
    _ui.offlineRetrying.value = false;
    _ui.offlineStatusMessage.value =
        'Couldn\'t load the app. Check your connection and try again.';
    _showOffline(needsReload: true);
  }

  Future<void> _recoverWebView({
    required String reason,
    bool recreate = false,
  }) async {
    if (!mounted) return;
    if (_recoveryInFlight) return;
    if (_ui.showingLogVisit.value) return;

    final forceRecreate =
        recreate ||
        reason.startsWith('resume_') ||
        reason == 'ios_content_process_terminated';

    _recoveryInFlight = true;
    _silentRecoveryAttempts++;
    _releaseSplash();
    _ui.beginNavigation();
    if (kDebugMode) {
      debugPrint(
        '[SmartNPS360][WebView] recover '
        'attempt=$_silentRecoveryAttempts/$_maxSilentRecoveries '
        'reason=$reason recreate=$recreate',
      );
    }

    if (_silentRecoveryAttempts > _maxSilentRecoveries) {
      _recoveryInFlight = false;
      _failRecoveryToOffline();
      return;
    }

    final shouldRecreate = forceRecreate || _controller == null;
    if (shouldRecreate) {
      _awaitingRecoveryLoad = true;
      _controller = null;
      _armRecoveryWatchdog();
      if (mounted) {
        setState(() => _webViewEpoch++);
      }
      return;
    }

    final target = _webViewRecoveryTarget();
    try {
      _awaitingRecoveryLoad = true;
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
      _armRecoveryWatchdog();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][WebView] recover loadUrl failed ($reason): $e',
        );
      }
      _recoveryInFlight = false;
      _awaitingRecoveryLoad = false;
      await _recoverWebView(reason: '${reason}_recreate', recreate: true);
    }
  }

  Future<void> _reloadWebViewAfterProcessDeath({
    required String reason,
    required bool recreate,
  }) async {
    if (!mounted) return;
    _recoveryInFlight = false;
    await _recoverWebView(reason: reason, recreate: recreate);
  }

  Future<void> _retry() async {
    if (_ui.offlineRetrying.value) return;
    _ui.offlineRetrying.value = true;
    _ui.offlineStatusMessage.value = null;
    _silentRecoveryAttempts = 0;
    _recoveryInFlight = false;

    if (await SiteReachability.canReachSite()) {
      if (!mounted) return;
      _offlineNeedsReload = true;
      await _recoverFromOffline();
      return;
    }
    if (!mounted) return;
    _holdOfflineUntilReload = true;
    _showOffline(needsReload: true);
    _ui.offlineRetrying.value = false;
    _ui.offlineStatusMessage.value =
        'Still no internet connection. Please check your network and try again.';
  }

  bool _isInternalUrl(Uri uri) => AppConfig.isAllowedHost(uri.host);

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final uri = action.request.url?.uriValue;
    if (uri == null) return NavigationActionPolicy.ALLOW;

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      if (_isInternalUrl(uri)) {
        if (action.isForMainFrame == true) {
          _onInWebBottomTabDestination(uri);
        }
        return NavigationActionPolicy.ALLOW;
      }

      if (action.isForMainFrame != true &&
          AppConfig.isTrustedSubresourceHost(uri.host)) {
        return NavigationActionPolicy.ALLOW;
      }

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

  Future<ServerTrustAuthResponse> _handleServerTrustAuthRequest(
    URLAuthenticationChallenge challenge,
  ) async {
    final host = challenge.protectionSpace.host;

    if (AppConfig.isAllowedHost(host)) {
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.PROCEED,
      );
    }

    if (AppConfig.isTrustedSubresourceHost(host)) {
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.PROCEED,
      );
    }

    final sslError = challenge.protectionSpace.sslError;
    if (sslError == null) {
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.PROCEED,
      );
    }

    return ServerTrustAuthResponse(
      action: ServerTrustAuthResponseAction.CANCEL,
    );
  }

  Future<bool> _onWillPop() async {
    if (_ui.showingLogVisit.value) {
      _dismissLogVisit();
      return false;
    }
    final controller = _controller;
    if (controller == null) return true;
    final canGoBack = await controller.canGoBack();
    if (canGoBack) {
      await controller.goBack();
      unawaited(_reconcileBottomBarFromWebView(controller));
      return false;
    }
    return true;
  }

  void _dismissLogVisit() {
    unawaited(_closeLogVisit(openDashboard: false));
  }

  Future<void> _persistActivePatrolDraft() async {
    if (!Get.isRegistered<VisitVideoFlowController>()) return;
    final flow = Get.find<VisitVideoFlowController>();
    await flow.persistCurrentDraft();
  }

  void _finishLogVisitUploadSuccess() {
    unawaited(_closeLogVisit(openDashboard: true));
  }

  Future<void> _closeLogVisit({required bool openDashboard}) async {
    await _persistActivePatrolDraft();
    final resumeUri = _uriBeforeLogVisit;
    final resumeScrollY = _scrollYBeforeLogVisit;
    _uriBeforeLogVisit = null;
    _scrollYBeforeLogVisit = null;
    _ui.showingLogVisit.value = false;
    unawaited(VisitGpsSession.instance.stop());

    if (openDashboard) {
      final dashboard = Uri.parse(_BottomItem.dashboard.url);
      await _navigateWebTo(dashboard);
      _ui.selectedBottomTabIndex.value = _BottomItem.dashboard.index;
      _ui.preserveBottomBarDuringLoad.value = true;
      return;
    }

    // Back from Patrol Draft: restore the page the officer left on without a
    // fresh load whenever possible (keeps dashboard scroll/SPA state).
    await _restoreWebAfterLogVisit(
      resumeUri: resumeUri,
      resumeScrollY: resumeScrollY,
    );
  }

  Future<void> _restoreWebAfterLogVisit({
    Uri? resumeUri,
    double? resumeScrollY,
  }) async {
    final controller = _controller;
    Uri? liveUri;
    if (controller != null) {
      try {
        final live = await controller.getUrl();
        liveUri = live?.uriValue ?? Uri.tryParse(live?.toString() ?? '');
      } catch (_) {}
    }

    if (liveUri != null) {
      _ui.currentUri.value = liveUri;
    }

    final target = resumeUri ?? liveUri ?? _ui.currentUri.value;
    final alreadyOnResume =
        liveUri != null &&
        target != null &&
        _normalizePageUrl(liveUri) == _normalizePageUrl(target);

    if (!alreadyOnResume && target != null && controller != null) {
      final restoredByHistory = await _tryWebHistoryBackTo(
        controller,
        target,
      );
      if (!restoredByHistory) {
        // Last resort only — avoids leaving the officer on an unrelated page.
        await _navigateWebTo(target);
      }
    } else if (target != null) {
      _recheckBottomBarForUri(target);
    }

    if (resumeScrollY != null) {
      await _restoreWebScrollY(resumeScrollY);
    }

    final tabUri = _ui.currentUri.value ?? target;
    final tab = _bottomTabIndexFromUri(tabUri);
    if (tab != null) {
      _ui.selectedBottomTabIndex.value = tab;
      _ui.preserveBottomBarDuringLoad.value = true;
    } else {
      _ui.preserveBottomBarDuringLoad.value = false;
    }
  }

  Future<bool> _tryWebHistoryBackTo(
    InAppWebViewController controller,
    Uri target,
  ) async {
    try {
      final canGoBack = await controller.canGoBack();
      if (!canGoBack) return false;
      await controller.goBack();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final live = await controller.getUrl();
      final liveUri = live?.uriValue ?? Uri.tryParse(live?.toString() ?? '');
      if (liveUri == null) return false;
      _ui.currentUri.value = liveUri;
      _recheckBottomBarForUri(liveUri);
      return _normalizePageUrl(liveUri) == _normalizePageUrl(target);
    } catch (_) {
      return false;
    }
  }

  Future<void> _captureWebResumePoint() async {
    final controller = _controller;
    if (controller != null) {
      try {
        final live = await controller.getUrl();
        final liveUri = live?.uriValue ?? Uri.tryParse(live?.toString() ?? '');
        if (liveUri != null) {
          _uriBeforeLogVisit = liveUri;
          _ui.currentUri.value = liveUri;
        }
      } catch (_) {
        _uriBeforeLogVisit ??= _ui.currentUri.value;
      }
      _scrollYBeforeLogVisit = await _readWebScrollY(controller);
    } else {
      _uriBeforeLogVisit ??= _ui.currentUri.value;
      _scrollYBeforeLogVisit = null;
    }
  }

  Future<double?> _readWebScrollY(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: '''
          (function () {
            const el = document.scrollingElement || document.documentElement;
            const y = (el && el.scrollTop) || window.scrollY || 0;
            return y;
          })();
        ''',
      );
      if (result is num) return result.toDouble();
      return double.tryParse(result?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreWebScrollY(double y) async {
    final controller = _controller;
    if (controller == null) return;
    final safeY = y.isFinite ? y : 0.0;
    try {
      await controller.evaluateJavascript(
        source: '''
          (function () {
            const y = $safeY;
            const el = document.scrollingElement || document.documentElement;
            if (el) el.scrollTop = y;
            window.scrollTo(0, y);
          })();
        ''',
      );
    } catch (_) {}
  }

  Future<void> _navigateWebTo(Uri uri) async {
    final controller = _controller;
    _ui.currentUri.value = uri;
    _recheckBottomBarForUri(uri);
    if (controller == null) return;
    _ui.beginNavigation();
    if (Platform.isAndroid) {
      try {
        await controller.stopLoading();
      } catch (_) {}
    }
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(uri.toString())),
    );
  }

  Future<PolicyDocumentContent?> _fetchOfficerDocumentHtml(Uri uri) async {
    final controller = _controller;
    if (controller == null) return null;

    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          const response = await fetch(url, {
            credentials: 'include',
            headers: {
              'Accept': 'application/pdf,text/html,application/xhtml+xml,*/*;q=0.8'
            }
          });
          if (!response.ok) {
            return JSON.stringify({ ok: false, status: response.status });
          }
          const contentType = (response.headers.get('content-type') || '').toLowerCase();
          const buffer = await response.arrayBuffer();
          const bytes = new Uint8Array(buffer);
          const isPdfHeader =
            bytes.length >= 4 &&
            bytes[0] === 0x25 &&
            bytes[1] === 0x50 &&
            bytes[2] === 0x44 &&
            bytes[3] === 0x46;
          const isPdf = contentType.indexOf('pdf') !== -1 || isPdfHeader;

          if (isPdf) {
            let binary = '';
            const chunk = 0x8000;
            for (let i = 0; i < bytes.length; i += chunk) {
              binary += String.fromCharCode.apply(
                null,
                bytes.subarray(i, i + chunk)
              );
            }
            return JSON.stringify({
              ok: true,
              isPdf: true,
              base64: btoa(binary),
              contentType: contentType
            });
          }

          const html = new TextDecoder('utf-8').decode(bytes);
          return JSON.stringify({
            ok: true,
            isPdf: false,
            html: html,
            contentType: contentType
          });
        ''',
        arguments: {'url': uri.toString()},
      );

      if (result?.error != null) {
        if (kDebugMode) {
          debugPrint('[PolicyDocument] fetch JS error: ${result!.error}');
        }
        return null;
      }

      final raw = result?.value;
      if (raw is! String || raw.isEmpty) {
        if (kDebugMode) {
          debugPrint('[PolicyDocument] fetch empty result: $raw');
        }
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['ok'] != true) {
        if (kDebugMode) {
          debugPrint(
            '[PolicyDocument] fetch not ok status=${decoded['status']}',
          );
        }
        return null;
      }

      final isPdf = decoded['isPdf'] == true;
      if (isPdf) {
        final base64 = decoded['base64'];
        if (base64 is! String || base64.isEmpty) return null;
        final bytes = base64Decode(base64);
        if (kDebugMode) {
          debugPrint('[PolicyDocument] fetch pdf bytes=${bytes.length}');
        }
        return PolicyDocumentContent.pdf(bytes);
      }

      final html = decoded['html'];
      if (html is! String || html.isEmpty) return null;
      if (kDebugMode) {
        debugPrint('[PolicyDocument] fetch html bytes=${html.length}');
      }
      return PolicyDocumentContent.html(html);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PolicyDocument] fetch failed: $e');
      }
      return null;
    }
  }

  void _openLogVisitTab() {
    VisitDraftResumeDialog.ensureFlowController();
    _uriBeforeLogVisit ??= _ui.currentUri.value;
    unawaited(_ensureScrollCapturedBeforeLogVisit());
    _ui.showingLogVisit.value = true;
    _ui.bottomTabNavigationActive.value = false;
    _ui.preserveBottomBarDuringLoad.value = true;
    unawaited(VisitGpsSession.instance.start());
  }

  Future<void> _ensureScrollCapturedBeforeLogVisit() async {
    if (_scrollYBeforeLogVisit != null) return;
    final controller = _controller;
    if (controller == null) return;
    _scrollYBeforeLogVisit = await _readWebScrollY(controller);
  }

  Future<Map<String, dynamic>> _openLogVisitScreen([Map? payload]) async {
    final flow = VisitDraftResumeDialog.ensureFlowController();
    unawaited(VisitGpsSession.instance.start());
    final normalized = _normalizeBridgeMap(payload);

    await _captureWebResumePoint();

    final reopenedPending = await flow.applyBridgePatrolContext(normalized);
    final ctx = flow.patrolContext.value;

    patrolLogDebugLog(
      '[SmartNPS360] patrol draft ready '
      'reopenedPending=$reopenedPending '
      'items=${flow.mediaItems.length} '
      'checkpoints=${ctx?.checkpoints.length ?? 0} '
      'siteId=${ctx?.siteId} regionId=${ctx?.regionId} '
      'siteName=${ctx?.siteName} regionName=${ctx?.regionName} '
      'clientDraftId=${ctx?.clientDraftId} '
      'sitePatrolWindowId=${ctx?.sitePatrolWindowId} '
      'resumeUri=$_uriBeforeLogVisit '
      'scrollY=$_scrollYBeforeLogVisit '
      'payload=$normalized',
    );

    if (Get.currentRoute == AppRoutes.visitVideoPreview) {
      Get.back();
    }
    _openLogVisitTab();

    return <String, dynamic>{
      'ok': true,
      'reopenedPending': reopenedPending,
      'itemCount': flow.mediaItems.length,
      'siteId': ctx?.siteId,
      'regionId': ctx?.regionId,
      'siteName': ctx?.siteName,
      'regionName': ctx?.regionName,
      'clientDraftId': ctx?.clientDraftId,
    };
  }

  Map<String, dynamic>? _normalizeBridgeMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        return _normalizeBridgeMap(decoded);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      out[key.toString()] = value;
    });
    for (final nestedKey in const [
      'payload',
      'data',
      'context',
      'patrolDraft',
      'patrolDraftContext',
    ]) {
      final nested = out[nestedKey];
      if (nested is Map) {
        nested.forEach((key, value) {
          out.putIfAbsent(key.toString(), () => value);
        });
      }
    }
    return out;
  }

  String? _stringFromPayload(Map? payload, List<String> keys) {
    final value = _valueFromPayload(payload, keys);
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  dynamic _valueFromPayload(Map? payload, List<String> keys) {
    if (payload == null) return null;
    for (final key in keys) {
      if (!payload.containsKey(key)) continue;
      final value = payload[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  bool? _parseClockInSuccessFlag(dynamic raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is num) {
      if (raw == 1) return true;
      if (raw == 0) return false;
      return null;
    }
    if (raw is String) {
      final text = raw.trim().toLowerCase();
      if (text == 'true' || text == '1') return true;
      if (text == 'false' || text == '0') return false;
      final map = _normalizeBridgeMap(raw);
      if (map != null) {
        return _parseClockInSuccessFlag(
          _valueFromPayload(map, const [
            'clock_in_success',
            'clockInSuccess',
            'success',
          ]),
        );
      }
      return null;
    }
    if (raw is Map) {
      final map = _normalizeBridgeMap(raw);
      return _parseClockInSuccessFlag(
        _valueFromPayload(map, const [
          'clock_in_success',
          'clockInSuccess',
          'success',
        ]),
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readPatrolDraftContextFromWeb() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final result = await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            var ctx = null;
            if (window.SmartNPS360) {
              if (typeof window.SmartNPS360.getPatrolDraftContext === 'function') {
                try { ctx = window.SmartNPS360.getPatrolDraftContext(); } catch (e) {}
              }
              if (!ctx) ctx = window.SmartNPS360.patrolDraftContext || null;
            }
            if (!ctx && window.SmartNPSWeb &&
                typeof window.SmartNPSWeb.getPatrolDraftContext === 'function') {
              try { ctx = window.SmartNPSWeb.getPatrolDraftContext(); } catch (e) {}
            }
            if (!ctx) return null;

            var checkpoints = null;
            if (window.SmartNPS360 &&
                typeof window.SmartNPS360.getPatrolCheckpoints === 'function') {
              try { checkpoints = window.SmartNPS360.getPatrolCheckpoints(); } catch (e) {}
            }
            if ((!checkpoints || !checkpoints.length) &&
                window.SmartNPSWeb &&
                typeof window.SmartNPSWeb.getPatrolCheckpoints === 'function') {
              try { checkpoints = window.SmartNPSWeb.getPatrolCheckpoints(); } catch (e) {}
            }
            if (checkpoints && checkpoints.length &&
                (!ctx.checkpoints || !ctx.checkpoints.length)) {
              ctx = Object.assign({}, ctx, { checkpoints: checkpoints });
            }
            return JSON.stringify(ctx);
          } catch (e) {
            return null;
          }
        })();
        ''',
      );
      if (result == null) return null;
      var text = result.toString().trim();
      if (text.isEmpty || text == 'null') return null;
      if ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'"))) {
        text = text.substring(1, text.length - 1);
        text = text.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      return _normalizeBridgeMap(text);
    } catch (e) {
      patrolLogDebugLog(
        '[SmartNPS360] read patrolDraftContext failed: $e',
      );
      return null;
    }
  }

  Future<List<dynamic>?> _readPatrolCheckpointsFromWeb() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final result = await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            var checkpoints = null;
            if (window.SmartNPS360 &&
                typeof window.SmartNPS360.getPatrolCheckpoints === 'function') {
              try { checkpoints = window.SmartNPS360.getPatrolCheckpoints(); } catch (e) {}
            }
            if ((!checkpoints || !checkpoints.length) &&
                window.SmartNPS360 && window.SmartNPS360.patrolDraftContext &&
                window.SmartNPS360.patrolDraftContext.checkpoints) {
              checkpoints = window.SmartNPS360.patrolDraftContext.checkpoints;
            }
            if ((!checkpoints || !checkpoints.length) &&
                window.SmartNPSWeb &&
                typeof window.SmartNPSWeb.getPatrolCheckpoints === 'function') {
              try { checkpoints = window.SmartNPSWeb.getPatrolCheckpoints(); } catch (e) {}
            }
            if (!checkpoints) return null;
            return JSON.stringify(checkpoints);
          } catch (e) {
            return null;
          }
        })();
        ''',
      );
      if (result == null) return null;
      var text = result.toString().trim();
      if (text.isEmpty || text == 'null') return null;
      if ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'"))) {
        text = text.substring(1, text.length - 1);
        text = text.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      final decoded = jsonDecode(text);
      if (decoded is List) return decoded;
      return null;
    } catch (e) {
      patrolLogDebugLog('[SmartNPS360] read patrol checkpoints failed: $e');
      return null;
    }
  }

  void _logRawCheckpoints(dynamic raw) {
    if (raw is! List) {
      patrolLogDebugLog(
        '[SmartNPS360] checkpoints raw type=${raw.runtimeType} value=$raw',
      );
      return;
    }
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) {
        patrolLogDebugLog(
          '[SmartNPS360] checkpoint[$i] non-map type=${entry.runtimeType} value=$entry',
        );
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      patrolLogDebugLog(
        '[SmartNPS360] checkpoint[$i] keys=${map.keys.toList()} '
        'id=${map['id'] ?? map['site_checkpoint_id'] ?? map['checkpoint_id']} '
        'name=${map['name']} '
        'photo_url=${map['photo_url'] ?? map['photoUrl']} '
        'photo_path=${map['photo_path'] ?? map['photoPath']} '
        'image_url=${map['image_url'] ?? map['imageUrl']} '
        'image=${map['image']} photo=${map['photo']} '
        'raw=$map',
      );
    }
  }

  bool _checkpointsMissingPhotos(dynamic raw) {
    if (raw is! List || raw.isEmpty) return true;
    for (final entry in raw) {
      if (entry is! Map) return true;
      final map = Map<String, dynamic>.from(entry);
      final hasUrl = _checkpointMapHasPhoto(map);
      if (!hasUrl) return true;
    }
    return false;
  }

  bool _checkpointMapHasPhoto(Map<String, dynamic> map) {
    for (final key in const [
      'photo_url',
      'photoUrl',
      'image_url',
      'imageUrl',
      'thumbnail_url',
      'thumbnailUrl',
      'photo_path',
      'photoPath',
      'image_path',
      'imagePath',
      'file_url',
      'fileUrl',
      'url',
      'src',
    ]) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return true;
    }
    for (final key in const [
      'photo',
      'image',
      'media',
      'file',
      'attachment',
      'reference_photo',
      'referencePhoto',
    ]) {
      final nested = map[key];
      if (nested == null) continue;
      if (nested is String && nested.trim().isNotEmpty) return true;
      if (nested is Map && nested.isNotEmpty) return true;
    }
    return false;
  }

  List<dynamic> _mergeCheckpointPhotos(
    dynamic existingRaw,
    List<dynamic> fromWeb,
  ) {
    if (existingRaw is! List) return fromWeb;
    final byId = <int, Map<String, dynamic>>{};
    for (final entry in fromWeb) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final id = _checkpointIdFromMap(map);
      if (id == null) continue;
      byId[id] = map;
    }

    return existingRaw.map((entry) {
      if (entry is! Map) return entry;
      final current = Map<String, dynamic>.from(entry);
      if (_checkpointMapHasPhoto(current)) return current;
      final id = _checkpointIdFromMap(current);
      if (id == null) return current;
      final richer = byId[id];
      if (richer == null) return current;
      return <String, dynamic>{
        ...current,
        ...richer,
      };
    }).toList();
  }

  int? _checkpointIdFromMap(Map<String, dynamic> map) {
    final raw =
        map['site_checkpoint_id'] ??
        map['siteCheckpointId'] ??
        map['checkpoint_id'] ??
        map['checkpointId'] ??
        map['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  String _checkpointPhotoDebugSummary(dynamic raw) {
    if (raw is! List || raw.isEmpty) return '[]';
    final parts = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) {
        parts.add('#$i:type=${entry.runtimeType}');
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      parts.add(
        '#$i:{id=${map['id'] ?? map['site_checkpoint_id']},'
        'keys=${map.keys.toList()},'
        'photo_url=${map['photo_url'] ?? map['photoUrl']},'
        'photo_path=${map['photo_path'] ?? map['photoPath']},'
        'image_url=${map['image_url'] ?? map['imageUrl']},'
        'image=${map['image']},'
        'photo=${map['photo']}}',
      );
    }
    return parts.join(' | ');
  }

  Future<void> _maybePromptUnfinishedDraft() async {
    if (_draftResumePrompted) return;
    if (!_ui.officerLoggedIn.value) return;
    if (!_ui.firstPageLoaded.value) return;
    if (_ui.showOffline.value) return;
    if (_ui.showingLogVisit.value) return;
    if (_isAuthRoute(_ui.currentUri.value)) return;

    final pending = await VisitMediaDraftStore.instance.listPendingDrafts();
    if (pending.isEmpty) return;

    _draftResumePrompted = true;

    final flow = VisitDraftResumeDialog.ensureFlowController();
    await flow.ensureDraftLoaded();

    final result = await VisitDraftResumeDialog.showPending(drafts: pending);
    if (result == null) return;

    await flow.activateDraft(result.draft.draftKey);

    switch (result.action) {
      case VisitDraftResumeAction.continueReport:
        _openLogVisitTab();
        break;
      case VisitDraftResumeAction.submitReport:
        unawaited(
          VisitVideoPreviewScreen.uploadCurrentDraft(
            onSuccess: _finishLogVisitUploadSuccess,
            skipCompletionConfirm: true,
          ),
        );
        break;
      case VisitDraftResumeAction.discardReport:
        await flow.clearAll();
        break;
    }
  }

  void _installJsHandlers(InAppWebViewController controller) {
    if (kDebugMode && Platform.isIOS) {
      controller.addJavaScriptHandler(
        handlerName: 'iosPopoverFixDebug',
        callback: (args) {
          if (kDebugMode) {
            debugPrint('[SmartNPS360][iOS PopoverFix] event received');
          }
        },
      );
    }

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
        final result = await _bridge.getCurrentLocation(
          args.isEmpty ? null : args.first,
        );
        final error = result['error'];
        final errorCode = error is Map ? error['code']?.toString() : null;
        final errorMessage = error is Map ? error['message']?.toString() : null;
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360] getCurrentLocation ok=${result['ok'] == true}'
            '${errorCode != null ? ' error=$errorCode' : ''}'
            '${errorMessage != null ? ' message=$errorMessage' : ''}'
            '${result['bestAccuracySeenMeters'] != null ? ' bestAccuracy=${result['bestAccuracySeenMeters']}' : ''}',
          );
        }
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
            if (!position.latitude.isFinite || !position.longitude.isFinite) {
              return;
            }
            final payload = _toWebGeolocationPayloadFromPosition(position);
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
      handlerName: 'getPushNotificationStatus',
      callback: (args) =>
          _bridge.getPushNotificationStatus(args.isEmpty ? null : args.first),
    );
    controller.addJavaScriptHandler(
      handlerName: 'setPushNotificationsEnabled',
      callback: (args) async {
        final result = await _bridge.setPushNotificationsEnabled(
          args.isEmpty ? null : args.first,
        );
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360] setPushNotificationsEnabled ok=${result['ok'] == true}',
          );
        }
        final disabled = result['ok'] == true &&
            result['enabled'] == false &&
            result['unchanged'] != true;
        if (disabled) {
          unawaited(_promptAfterWebPushDisabled());
        }
        return result;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'getBackgroundLocationStatus',
      callback: (args) async {
        final result = await _bridge.getBackgroundLocationStatus(
          args.isEmpty ? null : args.first,
        );
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360] getBackgroundLocationStatus '
            'ok=${result['ok'] == true} '
            'canClockIn=${result['canClockIn'] == true} '
            'backgroundReady=${result['backgroundReady'] == true} '
            'disclosureAccepted=${result['disclosureAccepted'] == true} '
            'serviceEnabled=${result['serviceEnabled'] == true}'
            '${result['deniedReason'] != null ? ' deniedReason=${result['deniedReason']}' : ''}',
          );
        }
        return result;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'prepareClockIn',
      callback: (args) async {
        try {
          final result = await _bridge.prepareClockIn(
            args.isEmpty ? null : args.first,
          );
          final canClockIn = result['canClockIn'] == true;
          final reason = result['reason']?.toString();
          final message = result['message']?.toString();
          if (kDebugMode) {
            debugPrint(
              '[SmartNPS360] prepareClockIn ok=${result['ok'] == true} '
              'canClockIn=$canClockIn'
              '${reason != null ? ' reason=$reason' : ''}'
              '${message != null ? ' message=$message' : ''}',
            );
          }
          return result;
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[SmartNPS360] prepareClockIn failed: $e\n$st');
          }
          rethrow;
        }
      },
    );
    Future<Map<String, dynamic>> handleClockInSuccess(
      List<dynamic> args,
    ) async {
      final currentHost = _ui.currentUri.value?.host;
      if (!AppConfig.isAllowedHost(currentHost)) {
        return {
          'ok': false,
          'error': {'code': 'untrusted_origin', 'message': 'Untrusted origin'},
        };
      }

      final raw = args.isNotEmpty ? args.first : null;
      final payload = _normalizeBridgeMap(raw);
      var clockInSuccess = _parseClockInSuccessFlag(raw);
      final action = _stringFromPayload(payload, const ['action']);

      if (clockInSuccess == null &&
          action == 'clock_in_success' &&
          payload != null) {
        clockInSuccess = _parseClockInSuccessFlag(
          _valueFromPayload(payload, const ['ok']),
        );
      }

      if (clockInSuccess == true) {
        DutyHeartbeatService.instance.onClockInSuccessFromBridge();
      } else if (clockInSuccess == false) {
        unawaited(
          ClockInGateService.instance.abandonClockInAttempt(
            reason: 'clock_in_success_false',
          ),
        );
      }

      return {'ok': true, 'clock_in_success': clockInSuccess};
    }

    Future<Map<String, dynamic>> handleClockInCancelled(
      List<dynamic> args,
    ) async {
      final currentHost = _ui.currentUri.value?.host;
      if (!AppConfig.isAllowedHost(currentHost)) {
        return {
          'ok': false,
          'error': {'code': 'untrusted_origin', 'message': 'Untrusted origin'},
        };
      }

      final raw = args.isNotEmpty ? args.first : null;
      final payload = _normalizeBridgeMap(raw);
      final reason =
          _stringFromPayload(payload, const ['reason', 'source', 'action']) ??
          'webview_cancelled';

      await ClockInGateService.instance.abandonClockInAttempt(reason: reason);
      return {'ok': true, 'cancelled': true, 'reason': reason};
    }

    controller.addJavaScriptHandler(
      handlerName: 'clock_in_cancelled',
      callback: handleClockInCancelled,
    );
    controller.addJavaScriptHandler(
      handlerName: 'notifyClockInCancelled',
      callback: handleClockInCancelled,
    );
    controller.addJavaScriptHandler(
      handlerName: 'clock_in_success',
      callback: handleClockInSuccess,
    );
    controller.addJavaScriptHandler(
      handlerName: 'notifyClockInSuccess',
      callback: handleClockInSuccess,
    );
    controller.addJavaScriptHandler(
      handlerName: 'attendance_status_changed',
      callback: (args) async {
        final currentHost = _ui.currentUri.value?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          return {
            'ok': false,
            'error': {
              'code': 'untrusted_origin',
              'message': 'Untrusted origin',
            },
          };
        }

        final raw = args.isNotEmpty ? args.first : null;
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360] attendance_status_changed bridge payload=$raw',
          );
        }
        dutyHeartbeatDebugLog(
          '[SmartNPS360] attendance_status_changed bridge payload=$raw',
        );

        await DutyHeartbeatService.instance
            .onAttendanceStatusChangedFromBridge(raw);
        return {'ok': true};
      },
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
      handlerName: 'setBottomBarVisible',
      callback: (args) {
        final currentHost = _ui.currentUri.value?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          return {
            'ok': false,
            'error': {
              'code': 'untrusted_origin',
              'message': 'Untrusted origin',
            },
          };
        }

        final value = args.isNotEmpty ? args.first : null;
        final visible = _parseBottomBarVisibleArg(value);
        if (visible == null) {
          return {
            'ok': false,
            'error': {
              'code': 'invalid_args',
              'message':
                  'Expected boolean or {visible/show/hidden}',
            },
          };
        }

        final hide = !visible;
        if (_ui.webHidesBottomBar.value != hide) {
          _ui.webHidesBottomBar.value = hide;
        }
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][BottomBar] setBottomBarVisible '
            'visible=$visible hide=$hide',
          );
        }
        return {'ok': true, 'visible': visible};
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'openLogVisit',
      callback: (args) async {
        patrolLogDebugLog(
          '[SmartNPS360] openLogVisit called argsCount=${args.length} '
          'rawArgs=$args',
        );

        final currentHost = _ui.currentUri.value?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          patrolLogDebugLog(
            '[SmartNPS360] denied openLogVisit from host=$currentHost',
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
        var payload = _normalizeBridgeMap(first);

        if (payload == null ||
            (_valueFromPayload(payload, const ['siteId', 'site_id']) == null &&
                _valueFromPayload(payload, const ['regionId', 'region_id']) ==
                    null)) {
          final fromContext = await _readPatrolDraftContextFromWeb();
          if (fromContext != null) {
            patrolLogDebugLog(
              '[SmartNPS360] openLogVisit using patrolDraftContext '
              'keys=${fromContext.keys.toList()} context=$fromContext',
            );
            payload = {...?payload, ...fromContext};
          }
        }

        final existingCheckpoints = payload?['checkpoints'];
        final hasCheckpoints =
            existingCheckpoints is List && existingCheckpoints.isNotEmpty;
        if (!hasCheckpoints) {
          final fromWeb = await _readPatrolCheckpointsFromWeb();
          if (fromWeb != null && fromWeb.isNotEmpty) {
            payload = {...?payload, 'checkpoints': fromWeb};
            patrolLogDebugLog(
              '[SmartNPS360] openLogVisit merged checkpoints '
              'count=${fromWeb.length}',
            );
          }
        } else {
          _logRawCheckpoints(existingCheckpoints);
          final needsPhotos = _checkpointsMissingPhotos(existingCheckpoints);
          if (needsPhotos) {
            final fromWeb = await _readPatrolCheckpointsFromWeb();
            if (fromWeb != null && fromWeb.isNotEmpty) {
              payload = {
                ...?payload,
                'checkpoints': _mergeCheckpointPhotos(
                  existingCheckpoints,
                  fromWeb,
                ),
              };
              patrolLogDebugLog(
                '[SmartNPS360] openLogVisit enriched checkpoint photos '
                'from getPatrolCheckpoints count=${fromWeb.length}',
              );
              _logRawCheckpoints(payload!['checkpoints']);
            }
          }
        }

        final siteId = _valueFromPayload(payload, const ['siteId', 'site_id']);
        final regionId = _valueFromPayload(payload, const [
          'regionId',
          'region_id',
        ]);
        final siteName = _stringFromPayload(payload, const [
          'siteName',
          'site_name',
          'site',
        ]);
        final regionName = _stringFromPayload(payload, const [
          'regionName',
          'region_name',
          'region',
        ]);
        final checkpointCount = payload?['checkpoints'] is List
            ? (payload!['checkpoints'] as List).length
            : 0;
        final checkpointPhotoDebug = _checkpointPhotoDebugSummary(
          payload?['checkpoints'],
        );

        patrolLogDebugLog(
          '[SmartNPS360] openLogVisit site/region '
          'siteId=$siteId regionId=$regionId '
          'siteName=$siteName regionName=$regionName '
          'checkpoints=$checkpointCount '
          'checkpointPhotos=$checkpointPhotoDebug',
        );

        final result = await _openLogVisitScreen(payload);
        patrolLogDebugLog(
          '[SmartNPS360] openLogVisit ok=${result['ok']} '
          'reopenedPending=${result['reopenedPending']} '
          'itemCount=${result['itemCount']} '
          'result=$result',
        );
        return result;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'loginWithSanctum',
      callback: (args) async {
        final currentHost = _ui.currentUri.value?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          if (kDebugMode) {
            debugPrint(
              '[SmartNPS360][Auth] denied loginWithSanctum from host=$currentHost',
            );
          }
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

        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][Auth] loginWithSanctum request host=$currentHost',
          );
        }

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
        final currentHost = _ui.currentUri.value?.host;
        if (!AppConfig.isAllowedHost(currentHost)) {
          if (kDebugMode) {
            debugPrint(
              '[SmartNPS360][Auth] denied authEvent from host=$currentHost',
            );
          }
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
          if (kDebugMode) {
            debugPrint(
              '[SmartNPS360][Auth] authEvent logout received from web (primary) '
              '(host=$currentHost path=${_ui.currentUri.value?.path})',
            );
          }
          final completed = await _performNativeLogout(
            reason: 'primary: authEvent',
          );
          if (!completed) {
            return {
              'ok': false,
              'action': 'logout',
              'error': {
                'code': 'logout_blocked_on_duty',
                'message':
                    'You are still on duty. End your shift before logging out.',
              },
            };
          }
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
          final authMap = AuthRepository.mergeAuthPayload(
            Map<String, dynamic>.from(payload),
            session: session,
          );
          await AuthRepository.instance.saveLoginFromAuthResponse(
            map: authMap,
            user: user,
          );
          _clearSoftReauthAfterSuccessfulLogin();
          _showLocationNoticeAfterLogin();
          _ui.setOfficerLoggedIn(true);
          _setNativeAuthSession(true);
          _draftResumePrompted = false;
          _dismissKeyboardAfterLogin();
          unawaited(
            OfficerAnnouncementCoordinator.instance.tryDeliverPending(
              source: 'auth-ready',
            ),
          );
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
          final authMap = AuthRepository.mergeAuthPayload(
            Map<String, dynamic>.from(payload),
            session: session,
          );
          await AuthRepository.instance.saveLoginFromAuthResponse(
            map: authMap,
            user: AuthState.instance.user.value,
          );
          _clearSoftReauthAfterSuccessfulLogin();
          _showLocationNoticeAfterLogin();
          _ui.setOfficerLoggedIn(true);
          _setNativeAuthSession(true);
          _draftResumePrompted = false;
          _dismissKeyboardAfterLogin();
          unawaited(
            OfficerAnnouncementCoordinator.instance.tryDeliverPending(
              source: 'auth-ready',
            ),
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

  Future<bool> _performSanctumLogin({
    required String username,
    required String password,
    bool syncPush = true,
    bool promptLocationNotice = true,
  }) async {
    ApiClient.instance.ensureAuthInterceptorInstalled();
    final dio = ApiClient.instance.dio;
    try {
      final deviceCheckExtras = await DeviceCheckService.authPayloadExtras();
      final response = await dio.postUri(
        Uri.parse(ApiUrls.sanctumLoginUrl),
        data: {
          'employee_no': username,
          'password': password,
          'device_name': 'mobile-app',
          ...deviceCheckExtras,
        },
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][Auth] sanctum login rejected status=$statusCode',
          );
        }
        return false;
      }

      final dynamic body = response.data;
      final Map<String, dynamic>? map = body is Map
          ? Map<String, dynamic>.from(body)
          : null;
      if (map == null || AuthRepository.extractAccessToken(map) == null) {
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][Auth] sanctum login missing token in response',
          );
        }
        return false;
      }

      await AuthRepository.instance.saveLoginFromAuthResponse(map: map);
      await AuthRepository.instance.saveCredentials(
        employeeNo: username,
        password: password,
      );

      final token = await AuthRepository.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][Auth] sanctum login missing access token after save',
          );
        }
        return false;
      }

      _clearSoftReauthAfterSuccessfulLogin();
      if (promptLocationNotice) {
        _showLocationNoticeAfterLogin(syncPushAfterDismiss: syncPush);
      }
      if (!AuthSessionManager.isLoginRoute(_ui.currentUri.value)) {
        _ui.setOfficerLoggedIn(true);
        _setNativeAuthSession(true);
        _draftResumePrompted = false;
        _dismissKeyboardAfterLogin();
        await OfficerAnnouncementCoordinator.instance.tryDeliverPending(
          source: 'auth-ready',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Auth] sanctum login failed: $e');
      }
      return false;
    }
  }

  Future<void> _requestNotificationPermissionForRoute(Uri? uri) async {
    if (_ui.showOffline.value) return;
    if (!AppConfig.isAllowedHost(uri?.host)) return;
    if (_isAuthRoute(uri)) return;
    if (_ui.showLocationNotice.value || _pendingLocationNoticeAfterLogin) {
      return;
    }

    await PushNotificationService.instance.syncPushTokenAfterLogin();
  }

  Future<void> _prepareIosPushAuthFromWeb() async {
    if (!Platform.isIOS) return;

    var accessToken = await AuthRepository.instance.ensureValidAccessToken();
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
      url: WebUri(AppRoutes.webBaseUrl),
    );
    if (cookies.isEmpty) {
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
        await AuthRepository.instance.setOfficerLoggedIn(true);
        _ui.setOfficerLoggedIn(true);
        _setNativeAuthSession(true);
        return result;
      }
    } catch (e) {}
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

      return _performSanctumLogin(
        username: username,
        password: password,
        syncPush: false,
        promptLocationNotice: false,
      );
    } catch (e) {
      return false;
    }
  }

  Future<bool> _uploadPushTokenViaWebView(Map<String, dynamic> payload) async {
    final controller = _controller;
    if (controller == null) return false;

    try {
      final encodedPayload = jsonEncode(payload);
      final pushTokenUrl = ApiUrls.pushTokenUrl;
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
          if (decoded['ok'] == true) {
            return true;
          }
        }
      }
    } catch (e) {}
    return false;
  }

  Future<bool> _deletePushTokenViaWebView(Map<String, dynamic> payload) async {
    final controller = _controller;
    if (controller == null) return false;

    try {
      final encodedPayload = jsonEncode(payload);
      final pushTokenUrl = ApiUrls.pushTokenUrl;
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
            xhr.open('DELETE', '$pushTokenUrl', false);
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
          if (decoded['ok'] == true) {
            return true;
          }
        }
      }
    } catch (e) {}
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
    } catch (e) {}
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
      UserScript(
        source: _injectPlatformLocationLabels(_smartNpsBridgeScript.source),
        injectionTime: _smartNpsBridgeScript.injectionTime,
      ),
      UserScript(
        source: _injectPlatformLocationLabels(_geolocationScript.source),
        injectionTime: _geolocationScript.injectionTime,
      ),
      if (Platform.isIOS) _iosPopoverFixScript,
      if (Platform.isIOS) _iosKeyboardInputFixScript,
    ];
    return UnmodifiableListView(scripts);
  }

  Future<void> _runIosKeyboardInputFix(InAppWebViewController controller) async {
    if (!Platform.isIOS) return;
    try {
      await controller.evaluateJavascript(
        source: '''
        (function () {
          try {
            if (typeof window.__smartnpsIosKeyboardInputFixScan === 'function') {
              window.__smartnpsIosKeyboardInputFixScan();
            }
          } catch (_) {}
        })();
      ''',
      );
    } catch (_) {}
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
          : AppVersionInfo.webViewUserAgentToken(platform: 'Android'),
      applicationNameForUserAgent: Platform.isIOS
          ? AppVersionInfo.webViewUserAgentToken(platform: 'iOS')
          : null,
      preferredContentMode: Platform.isIOS
          ? UserPreferredContentMode.MOBILE
          : null,
      disableInputAccessoryView: Platform.isIOS ? true : null,
      geolocationEnabled: false,
      allowsBackForwardNavigationGestures: true,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: false,

      disableDefaultErrorPage: Platform.isAndroid ? true : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_ui.showLocationNotice.value) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Obx(() {
        final isDark = _ui.webPrefersDark.value;
        final officerLoggedIn = _ui.officerLoggedIn.value;
        final locationNoticeVisible = _ui.showLocationNotice.value;

        final safeAreaColor = isDark
            ? const Color(0xFF0F1724)
            : const Color(AppConfig.cSurface);
        return Scaffold(
          backgroundColor: safeAreaColor,
          body: ColoredBox(
            color: safeAreaColor,
            child: SafeArea(
              bottom: Platform.isAndroid,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  DutyHeartbeatService
                      .instance
                      .backgroundLocationPermissionMissing,
                  DutyHeartbeatService.instance.disclosurePromptVisible,
                  PermissionSettingsHelper.settingsPromptVisible,
                  OverlayPromptGuard.overlayVisibilityListenable,
                  ClockInGateService.instance.prepareInFlightVisible,
                  RequiredPermissionsGate.instance.isBlocking,
                ]),
                builder: (context, _) {
                  final showPermissionBlocker =
                      officerLoggedIn &&
                      !locationNoticeVisible &&
                      RequiredPermissionsGate.instance.isBlocking.value &&
                      (Platform.isAndroid || Platform.isIOS);
                  // final showBanner =
                  //     !showPermissionBlocker &&
                  //     DutyHeartbeatService
                  //         .instance
                  //         .shouldShowBackgroundLocationBanner &&
                  //     (Platform.isAndroid || Platform.isIOS) &&
                  //     _ui.officerLoggedIn.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // if (showBanner) const BackgroundLocationRequiredBanner(),
                      Expanded(
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 0),
                              child: InAppWebView(
                                key: ValueKey(
                                  'smartnps-webview-$_webViewEpoch',
                                ),
                                initialUrlRequest: URLRequest(
                                  url: WebUri(_webViewRecoveryTarget()),
                                ),
                                initialUserScripts: _initialUserScripts(),
                                pullToRefreshController:
                                    _pullToRefreshController,
                                initialSettings: _createWebViewSettings(),
                                onWebViewCreated: (controller) {
                                  _controller = controller;
                                  _installJsHandlers(controller);
                                  unawaited(_loadPendingPushUrl());
                                  if (_ui.showOffline.value) {
                                    unawaited(() async {
                                      if (await SiteReachability.canReachSite()) {
                                        if (!mounted) return;
                                        await _recoverFromOffline();
                                      }
                                    }());
                                  }
                                },
                                shouldOverrideUrlLoading:
                                    (controller, action) async =>
                                        _handleNavigation(action),
                                onLoadStart: (controller, url) {
                                  if (_awaitingOfflineRecoveryLoad) {
                                    _awaitingOfflineRecoveryLoad = false;
                                    _holdOfflineUntilReload = false;
                                  }
                                  if (!_ui.pullToRefreshActive.value) {
                                    final startUri = url?.uriValue;

                                    if (_shouldIgnoreWebViewNavigationEvent(
                                      startUri,
                                    )) {
                                      return;
                                    }

                                    _armBottomBarPreserveForNavigation(
                                      from: _ui.currentUri.value,
                                      to: startUri,
                                    );
                                    _uriAtLoadStart =
                                        _ui.currentUri.value ?? startUri;
                                    _syncCurrentUriFromWebView(startUri);
                                    _pendingBottomTabLoadStarted = true;
                                    _ui.beginNavigation();
                                    return;
                                  }
                                },
                                onUpdateVisitedHistory:
                                    (controller, url, isReload) {
                                      if (_ui.pullToRefreshActive.value ||
                                          _webReloadInProgress) {
                                        return;
                                      }
                                      if (_shouldIgnoreWebViewNavigationEvent(
                                        url?.uriValue,
                                      )) {
                                        return;
                                      }
                                      _onWebViewUrlCommitted(
                                        controller,
                                        url?.uriValue,
                                      );
                                    },
                                onPageCommitVisible: (controller, url) {
                                  if (_isUsableWebViewUri(url?.uriValue)) {
                                    _releaseSplash();
                                  }
                                  if (_shouldIgnoreWebViewNavigationEvent(
                                    url?.uriValue,
                                  )) {
                                    return;
                                  }
                                  _onWebViewUrlCommitted(
                                    controller,
                                    url?.uriValue,
                                  );
                                },
                                onProgressChanged: (controller, progress) {
                                  if (_ui.bottomTabNavigationActive.value &&
                                      !_pendingBottomTabLoadStarted) {
                                    return;
                                  }
                                  if (progress > 0 && progress < 100) {
                                    _ui.setLoadProgress(progress);
                                  }
                                  if (progress == 100) {
                                    _pullToRefreshController?.endRefreshing();
                                  }
                                },
                                onLoadStop: (controller, url) async {
                                  _pullToRefreshController?.endRefreshing();
                                  final nextUri = url?.uriValue;
                                  final recoveryLoad = _awaitingRecoveryLoad;

                                  final ignoreEvent =
                                      _shouldIgnoreWebViewNavigationEvent(
                                        nextUri,
                                      );
                                  var isSamePageReload = false;
                                  Uri? preservedUri;
                                  var androidBottomTabNavComplete = false;

                                  if (!ignoreEvent || recoveryLoad) {
                                    if (_isUsableWebViewUri(nextUri)) {
                                      _markWebViewContentReady();
                                    }
                                    final isBottomTabNavigationComplete =
                                        _ui.bottomTabNavigationActive.value &&
                                        _bottomTabIndexFromUri(nextUri) ==
                                            _ui.selectedBottomTabIndex.value;
                                    androidBottomTabNavComplete =
                                        Platform.isAndroid &&
                                        isBottomTabNavigationComplete;

                                    if (isBottomTabNavigationComplete &&
                                        !Platform.isAndroid) {
                                      _finishBottomTabNavigation();
                                    }
                                    isSamePageReload =
                                        !isBottomTabNavigationComplete &&
                                        (_isPullToRefreshReload(nextUri) ||
                                            _isSamePageReload(
                                              _uriAtLoadStart,
                                              nextUri,
                                            ));
                                    preservedUri =
                                        _pullToRefreshSourceUri ??
                                        _uriAtLoadStart ??
                                        _ui.currentUri.value;
                                    try {
                                      final webThemeIsDark = _hasWebThemeSignal
                                          ? null
                                          : await _readWebThemeIsDark(
                                              controller,
                                            );
                                      await _installThemeListener(controller);
                                      await _runIosPopoverFix(controller);
                                      await _runIosKeyboardInputFix(controller);
                                      if (isSamePageReload) {
                                        _restoreUriAfterReload(preservedUri);
                                      } else {
                                        _syncCurrentUriFromWebView(nextUri);
                                      }
                                      unawaited(_maybePromptUnfinishedDraft());

                                      if (!_holdOfflineUntilReload) {
                                        _offlineNeedsReload = false;
                                        if (_ui.showOffline.value) {
                                          _dismissOfflineScreen();
                                        }
                                      }
                                      _setNativeThemeFromWeb(
                                        webThemeIsDark ??
                                            _ui.webPrefersDark.value,
                                      );
                                      if (AuthSessionManager.isLoginRoute(
                                            nextUri,
                                          ) &&
                                          !isSamePageReload) {
                                        await _pauseNativeSessionForLoginScreen();
                                      } else {
                                        _cancelPendingLoginTrackingStop();
                                        await _refreshNativeAuthSessionFromStorage();
                                        _activatePendingLocationNoticeIfNeeded();
                                        await _requestNotificationPermissionForRoute(
                                          nextUri,
                                        );
                                        await _maybeStartDutyHeartbeat();
                                        await DutyHeartbeatService.instance
                                            .recheckOnDutyPrompts(
                                              pageReload: isSamePageReload,
                                            );
                                        await OnDutyPermissionsPromptService
                                            .instance
                                            .maybeShow(fromResume: false);
                                        if (_ui.officerLoggedIn.value &&
                                            !_ui.showLocationNotice.value &&
                                            !AppConfig.isAuthEntryRoute(
                                              nextUri,
                                            )) {
                                          await OffDutyPushPromptService
                                              .instance
                                              .maybeShow(fromResume: false);
                                        }
                                        await _notifyWebBackgroundLocationStatus();
                                        await _notifyWebPushNotificationStatus();
                                        await NativePermissionStatusService
                                            .instance
                                            .syncIfChanged();
                                      }
                                    } catch (_) {}
                                  }

                                  _clearPullToRefreshState();
                                  _webReloadInProgress = false;
                                  final loadStartUri = _uriAtLoadStart;
                                  _uriAtLoadStart = null;
                                  if (!ignoreEvent && isSamePageReload) {
                                    _restoreUriAfterReload(preservedUri);
                                  }
                                  final clearPreserve =
                                      !ignoreEvent &&
                                      !_isStalePreviousPageLoadStopDuringPreserve(
                                        nextUri,
                                        loadStartUri,
                                      );
                                  _endMainFrameNavigationChrome(
                                    clearPreserve: clearPreserve,
                                  );
                                  await _reconcileBottomBarFromWebView(
                                    controller,
                                  );

                                  if (Platform.isAndroid &&
                                      androidBottomTabNavComplete) {
                                    _finishBottomTabNavigation();
                                  }
                                  if (!ignoreEvent) {
                                    await OfficerAnnouncementCoordinator
                                        .instance
                                        .tryDeliverPending(
                                          source: 'webview-ready',
                                        );
                                  }
                                },
                                onReceivedError: (controller, request, error) async {
                                  _pullToRefreshController?.endRefreshing();
                                  _clearPullToRefreshState();
                                  _webReloadInProgress = false;
                                  _finishBottomTabNavigation();
                                  _endMainFrameNavigationChrome();

                                  if (error.type ==
                                      WebResourceErrorType.CANCELLED) {
                                    return;
                                  }
                                  if (request.isForMainFrame == false) {
                                    return;
                                  }

                                  if (await SiteReachability.canReachSite()) {
                                    if (!mounted) return;
                                    if (_recoveryInFlight ||
                                        _awaitingRecoveryLoad) {
                                      return;
                                    }
                                    unawaited(
                                      _recoverWebView(
                                        reason: 'main_frame_error',
                                      ),
                                    );
                                    return;
                                  }
                                  if (!mounted) return;
                                  final wasRetrying = _ui.offlineRetrying.value;
                                  _cancelOfflineConnectivityDebounce();
                                  _holdOfflineUntilReload = true;
                                  _ui.offlineRetrying.value = false;
                                  if (wasRetrying) {
                                    _ui.offlineStatusMessage.value =
                                        'Couldn\'t reconnect. Check your connection and try again.';
                                  }
                                  _showOffline(needsReload: true);
                                },
                                onGeolocationPermissionsShowPrompt: (controller, origin) async {
                                  if (_ui.showLocationNotice.value) {
                                    return GeolocationPermissionShowPromptResponse(
                                      origin: origin,
                                      allow: false,
                                      retain: false,
                                    );
                                  }

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

                                  final disclosureReady = await DutyHeartbeatService
                                      .instance
                                      .ensureDisclosureBeforeWebLocationAccess();
                                  if (!disclosureReady) {
                                    return GeolocationPermissionShowPromptResponse(
                                      origin: origin,
                                      allow: false,
                                      retain: false,
                                    );
                                  }

                                  if (!await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled()) {
                                    if (!await BackgroundLocationPermissions.hasForegroundLocationAccess()) {
                                      await PermissionSettingsHelper.requestForegroundLocationStep();
                                      await BackgroundLocationPermissions.refreshPermissionStateFromOs();
                                    }
                                  }

                                  await BackgroundLocationPermissions.refreshPermissionStateFromOs();
                                  final granted =
                                      await BackgroundLocationPermissions.isBackgroundLocationFullyEnabled();
                                  return GeolocationPermissionShowPromptResponse(
                                    origin: origin,
                                    allow: granted,
                                    retain: granted,
                                  );
                                },
                                onReceivedServerTrustAuthRequest:
                                    (controller, challenge) async =>
                                        _handleServerTrustAuthRequest(
                                          challenge,
                                        ),
                                onDownloadStartRequest:
                                    (controller, request) async {
                                      final uri = request.url.uriValue;
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                                onWebContentProcessDidTerminate: (controller) {
                                  unawaited(
                                    _reloadWebViewAfterProcessDeath(
                                      reason: 'ios_content_process_terminated',
                                      recreate: true,
                                    ),
                                  );
                                },
                                onRenderProcessGone: (controller, detail) {
                                  if (!detail.didCrash) return;
                                  unawaited(
                                    _reloadWebViewAfterProcessDeath(
                                      reason: 'android_render_process_gone',
                                      recreate: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (showPermissionBlocker)
                              const Positioned.fill(
                                child: RequiredPermissionsBlocker(),
                              ),
                            Obx(
                              () => _ui.showOffline.value
                                  ? Positioned.fill(
                                      child: OfflineScreen(
                                        onRetry: _retry,
                                        isDark: _ui.webPrefersDark.value,
                                        isRetrying: _ui.offlineRetrying.value,
                                        statusMessage:
                                            _ui.offlineStatusMessage.value,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            Obx(() {
                              if (!_ui.firstPageLoaded.value &&
                                  !_ui.showOffline.value &&
                                  !_ui.splashReleased.value) {
                                return _SplashOverlay(
                                  isDark: _ui.webPrefersDark.value,
                                );
                              }
                              return const SizedBox.shrink();
                            }),
                            Obx(() {
                              final waitingOnFirstPaint =
                                  _ui.splashReleased.value &&
                                  !_ui.firstPageLoaded.value;
                              if (_ui.showOffline.value ||
                                  _ui.pullToRefreshActive.value) {
                                return const SizedBox.shrink();
                              }
                              if (!_ui.isNavigating.value &&
                                  !waitingOnFirstPaint) {
                                return const SizedBox.shrink();
                              }
                              return Align(
                                alignment: Alignment.topCenter,
                                child: _NavigationProgressBar(
                                  progress: waitingOnFirstPaint
                                      ? (_ui.loadProgress.value == 0
                                            ? 12
                                            : _ui.loadProgress.value)
                                      : _ui.loadProgress.value,
                                ),
                              );
                            }),
                            Obx(() {
                              if (!_ui.showingLogVisit.value) {
                                return const SizedBox.shrink();
                              }
                              return Positioned.fill(
                                child: VisitVideoPreviewScreen(
                                  onBack: _dismissLogVisit,
                                  onUploadSuccess: _finishLogVisitUploadSuccess,
                                  bottomBarClearance: 0,
                                ),
                              );
                            }),
                            Obx(() {
                              if (!_ui.showingGpsCurveDebug.value) {
                                return const SizedBox.shrink();
                              }
                              return const Positioned.fill(
                                child: LocationPathCurveDebugScreen(),
                              );
                            }),
                            Obx(() {
                              final uploadingFromDialog =
                                  !_ui.showingLogVisit.value &&
                                  _ui.officerLoggedIn.value &&
                                  VisitDraftResumeDialog.ensureFlowController()
                                      .isUploading
                                      .value;
                              final showBottomBar =
                                  !showPermissionBlocker &&
                                  !_ui.showOffline.value &&
                                  _ui.firstPageLoaded.value &&
                                  _ui.officerLoggedIn.value &&
                                  !_ui.isKeyboardOpen &&
                                  !_isAuthRoute(_ui.currentUri.value) &&
                                  !_ui.showingLogVisit.value &&
                                  !_ui.webHidesBottomBar.value &&
                                  !uploadingFromDialog &&
                                  (_ui.showingGpsCurveDebug.value ||
                                      kDebugMode ||
                                      _isBottomBarRoute(_ui.currentUri.value) ||
                                      _ui.preserveBottomBarDuringLoad.value);
                              _logBottomBarVisibility(
                                show: showBottomBar,
                                showPermissionBlocker: showPermissionBlocker,
                                uploadingFromDialog: uploadingFromDialog,
                              );
                              if (!showBottomBar) {
                                return const SizedBox.shrink();
                              }
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: _BottomBar(
                                  selectedTabIndex:
                                      _ui.selectedBottomTabIndex.value,
                                  isDark: _ui.webPrefersDark.value,
                                  onTap: _onBottomTap,
                                ),
                              );
                            }),
                            Obx(() {
                              if (!_ui.showLocationNotice.value) {
                                return const SizedBox.shrink();
                              }
                              return Positioned.fill(
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: Center(
                                    child: LocationNoticeDialog(
                                      onClose: _dismissLocationNotice,
                                      onFetchPolicyDocument:
                                          _fetchOfficerDocumentHtml,
                                    ),
                                  ),
                                ),
                              );
                            }),
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
      }),
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

  bool? _parseBottomBarVisibleArg(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is Map) {
      if (value.containsKey('hidden')) {
        final hidden = _parseBottomBarVisibleArg(value['hidden']);
        return hidden == null ? null : !hidden;
      }
      return _parseBottomBarVisibleArg(
        value['visible'] ?? value['show'] ?? value['value'],
      );
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'true' || normalized == '1' || normalized == 'show') {
      return true;
    }
    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'hide' ||
        normalized == 'hidden') {
      return false;
    }
    return null;
  }

  Future<void> _onBottomTap(_BottomItem item) async {
    final controller = _controller;
    if (controller == null) return;

    if (item == _BottomItem.gpsDebug) {
      _ui.selectedBottomTabIndex.value = item.index;
      if (_ui.showingLogVisit.value) {
        unawaited(VisitGpsSession.instance.stop());
      }
      _ui.showingLogVisit.value = false;
      _ui.showingGpsCurveDebug.value = true;
      _ui.bottomTabNavigationActive.value = false;
      _clearWebBottomBarHide();
      return;
    }

    if (_ui.selectedBottomTabIndex.value == item.index &&
        !_ui.isNavigating.value &&
        !_ui.showingLogVisit.value &&
        !_ui.showingGpsCurveDebug.value) {
      return;
    }

    _ui.selectedBottomTabIndex.value = item.index;
    if (_ui.showingLogVisit.value) {
      unawaited(VisitGpsSession.instance.stop());
    }
    _ui.showingLogVisit.value = false;
    _ui.showingGpsCurveDebug.value = false;
    _clearWebBottomBarHide();
    _ui.bottomTabNavigationActive.value = true;
    _pendingBottomTabLoadStarted = false;
    final nextUri = Uri.tryParse(item.url);
    if (nextUri != null) {
      _ui.currentUri.value = nextUri;
      if (!_isBottomBarRoute(nextUri)) {
        _ui.preserveBottomBarDuringLoad.value = false;
      }
      _recheckBottomBarForUri(nextUri);
    }
    _ui.beginNavigation();
    if (Platform.isAndroid) {
      try {
        await controller.stopLoading();
      } catch (_) {}
    }
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(item.url)));
  }

  bool _isAuthRoute(Uri? uri) => AuthSessionManager.isLoginRoute(uri);

  bool get _shouldUploadNativePermissionStatus {
    return _ui.officerLoggedIn.value && _ui.hasNativeAuthSession.value;
  }
}

bool _isBottomBarRoute(Uri? uri) => AppConfig.isBottomBarRoute(uri);

int? _bottomTabIndexFromUri(Uri? uri) => AppConfig.bottomTabIndexForUri(uri);

class _NavigationProgressBar extends StatelessWidget {
  const _NavigationProgressBar({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: double.infinity,
        height: 2.5,
        child: LinearProgressIndicator(
          value: progress > 0 ? progress / 100.0 : null,
          minHeight: 2.5,
          backgroundColor: Colors.transparent,
          color: const Color(AppConfig.cPrimary),
        ),
      ),
    );
  }
}

enum _WebViewHealth { ok, blank, dead }

class _SplashOverlay extends StatelessWidget {
  const _SplashOverlay({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final logoWidth = MediaQuery.sizeOf(context).width * 0.7;

    return ColoredBox(
      color: isDark ? const Color(0xFF0F1724) : const Color(AppConfig.cSurface),
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
    '/officer/dashboard',
  ),
  shiftLog('Shift Log', '', '', '/officer/shift-log'),
  timesheet(
    'TimeSheet',
    'assets/calendar_outline.png',
    'assets/schedule.png',
    '/officer/timesheet/monthly',
  ),
  profile(
    'Profile',
    'assets/avatar.png',
    'assets/profile.png',
    '/officer/profile',
  ),
  gpsDebug('GPS', '', '', '/__native__/gps-curve-debug');

  const _BottomItem(
    this.label,
    this.iconAsset,
    this.iconAssetSelected,
    this.path,
  );
  final String label;
  final String iconAsset;
  final String iconAssetSelected;
  final String path;

  String get url {
    final base = AppRoutes.webBaseUrl;
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$root$path';
  }

  String get normalizedPath => path;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.selectedTabIndex,
    required this.isDark,
    required this.onTap,
  });

  final int selectedTabIndex;
  final bool isDark;
  final ValueChanged<_BottomItem> onTap;

  @override
  Widget build(BuildContext context) {
    const visibleItems = <_BottomItem>[
      _BottomItem.dashboard,
      _BottomItem.shiftLog,
      _BottomItem.timesheet,
      _BottomItem.profile,
      _BottomItem.gpsDebug,
    ];

    final tabs = <PlatformBottomTab>[
      for (final (index, item) in visibleItems.indexed)
        PlatformBottomTab(
          label: item.label,
          index: index,
          iosSymbolName: switch (item) {
            _BottomItem.dashboard => 'house.fill',
            _BottomItem.shiftLog => 'list.clipboard',
            _BottomItem.timesheet => 'calendar',
            _BottomItem.profile => 'person.crop.circle.fill',
            _BottomItem.gpsDebug => 'location.fill',
          },
          iosSymbolPointSize: switch (item) {
            _BottomItem.shiftLog => 19,
            _BottomItem.gpsDebug => 20,
            _ => null,
          },
          materialIcon: switch (item) {
            _BottomItem.shiftLog => Icons.assignment_outlined,
            _BottomItem.gpsDebug => Icons.gps_fixed,
            _ => null,
          },
          activeAssetIcon: item.iconAssetSelected.isEmpty
              ? null
              : item.iconAssetSelected,
          inactiveAssetIcon: item.iconAsset.isEmpty ? null : item.iconAsset,
        ),
    ];
    final visibleSelectedIndex = visibleItems.indexWhere(
      (item) => item.index == selectedTabIndex,
    );

    return PlatformBottomBar(
      tabs: tabs,
      currentIndex: visibleSelectedIndex < 0 ? 0 : visibleSelectedIndex,
      tint: const Color(AppConfig.cBottomBarActive),
      surface: const Color(AppConfig.cSurface),
      darkSurface: const Color(AppConfig.cDarkCardColor),
      isDark: isDark,
      onTap: (index) => onTap(visibleItems[index]),
    );
  }
}
