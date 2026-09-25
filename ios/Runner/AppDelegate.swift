import Flutter
import CoreLocation
import UIKit
import UserNotifications
import flutter_background_service_ios

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate, FlutterStreamHandler,
  FlutterImplicitEngineDelegate
{
  private let settingsChannel = "com.smartnps360.app/settings"
  private let slcChannelName = "com.smartnps360.app/ios_slc"
  private let slcEventChannelName = "com.smartnps360.app/ios_slc_events"
  private let slcEnabledKey = "smartnps360.ios_slc.enabled"
  private let onDutyKey = "smartnps360.ios_duty.on_duty"
  private let unpaidBreakKey = "smartnps360.ios_duty.unpaid_break"
  private let slcPendingLocationsKey = "smartnps360.ios_slc.pending_locations"
  private let geofenceLatKey = "smartnps360.ios_geofence.lat"
  private let geofenceLonKey = "smartnps360.ios_geofence.lon"
  private let dutyGeofenceIdPrefix = "smartnps360.duty.geofence."
  private let dutyGeofenceLegacyIdentifier = "smartnps360.duty.geofence.v1"
  private let dutyGeofenceRadius: CLLocationDistance = 100
  private let dutyGeofenceRingOffset: CLLocationDistance = 75
  private let dutyGeofenceRecenterMeters: CLLocationDistance = 50
  private var settingsChannelRegistered = false
  private var slcChannelRegistered = false
  private var motionChannelRegistered = false
  private var deviceCheckChannelRegistered = false
  private var nativeCameraChannelRegistered = false
  private var settingsMethodChannel: FlutterMethodChannel?
  private var slcMethodChannel: FlutterMethodChannel?
  private var launchedForLocation = false
  private var awaitingFlutterDutyConfirm = false
  /// After a background location relaunch, ignore scene-active until the user
  /// really brings the UI forward. Prevents false opened_at + Flutter resume
  /// side-effects that can disarm SLC.
  private var suppressKillCycleForegroundUntilUserOpen = false
  /// When suppress was armed (for brief false-active debounce after SLC wake).
  private var locationWakeSuppressStartedAt: Date?
  /// Ignore false foreground for this long after a location relaunch.
  private let locationWakeForegroundDebounce: TimeInterval = 8
  /// Avoid stacking many deferred foreground rechecks.
  private var pendingForegroundRecheck = false
  private var slcLocationManager: CLLocationManager?
  private var dutyGpsLocationManager: CLLocationManager?
  private var dutyPollLocationManager: CLLocationManager?
  private var gpsPollInFlight = false
  private var gpsPollTimer: Timer?
  private var lastNativeGpsAt: Date?
  private let dutyGpsDistanceFilter: CLLocationDistance = kCLDistanceFilterNone
  /// Quiet-poll backup while native keep-alive stream is silent (matches Flutter stationary band).
  private let gpsPollInterval: TimeInterval = 30
  private var lastGeofenceCoordinate: CLLocationCoordinate2D?
  private var slcEventSink: FlutterEventSink?
  private var motionActivityManager: MotionActivityManager?
  private var deviceCheckManager: DeviceCheckManager?
  private var nativeCameraPlugin: NativeCameraPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // UIScene delivers the plugin's didFinishLaunching after launch has
    // already finished, which crashes BGTaskScheduler. Register first.
    if #available(iOS 13.0, *) {
      SwiftFlutterBackgroundServicePlugin.registerTaskIdentifier(
        taskIdentifier: SwiftFlutterBackgroundServicePlugin.taskIdentifier
      )
    }

    let didLaunch = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    wireDutyWakeUploader()
    restoreSlcMonitoringIfNeeded(application: application, launchOptions: launchOptions)
    registerPlatformChannelsIfNeeded()
    observeLowPowerModeChanges()
    observeBackgroundAppRefreshChanges()
    notifyFlutterOfLocationWakeIfNeeded()
    application.registerForRemoteNotifications()
    IosAppKillCycleReporter.shared.recoverKillFromBackgroundIfNeeded()
    // Near-realtime killed POST if terminate was missed (location wake / relaunch).
    IosAppKillCycleReporter.shared.uploadKilledEventIfNeeded(reason: "didFinishLaunching")
    // Retry upload only if both timestamps already queued (never stamp opened_at here).
    IosAppKillCycleReporter.shared.flushPendingIfNeeded(reason: "didFinishLaunching")

    return didLaunch
  }

  /// On-duty swipe/terminate: save local kill stamp, best-effort sync upload, local alert.
  override func applicationWillTerminate(_ application: UIApplication) {
    let onDuty = isOnDuty()
    let unpaidBreak = isUnpaidBreak()
    guard onDuty, !unpaidBreak else {
      IosAppKillCycleReporter.shared.appendDebugLog(
        "skip terminate report; onDuty=\(onDuty) unpaidBreak=\(unpaidBreak)"
      )
      super.applicationWillTerminate(application)
      return
    }

    IosAppKillCycleReporter.shared.handleTerminateWhileOnDuty()
    super.applicationWillTerminate(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPlatformChannels(
      with: engineBridge.applicationRegistrar.messenger()
    )
    notifyFlutterOfLocationWakeIfNeeded()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    // With UIScene, this often does not run — SceneDelegate.sceneDidBecomeActive owns it.
    onUserSceneBecameActive()
    super.applicationDidBecomeActive(application)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    // With UIScene, this often does not run — SceneDelegate.sceneDidEnterBackground owns it.
    onUserSceneEnteredBackground()
    super.applicationDidEnterBackground(application)
  }

  /// Shared by AppDelegate + SceneDelegate (UIScene no longer calls app-level active/background).
  func onUserSceneWillEnterForeground() {
    // SLC relaunch often fires this without a real open. Don't clear suppress yet.
    if suppressKillCycleForegroundUntilUserOpen {
      if let started = locationWakeSuppressStartedAt,
         Date().timeIntervalSince(started) < locationWakeForegroundDebounce
      {
        IosAppKillCycleReporter.shared.appendDebugLog(
          "willEnterForeground ignored; within \(Int(locationWakeForegroundDebounce))s wake debounce"
        )
        return
      }
      IosAppKillCycleReporter.shared.appendDebugLog(
        "willEnterForeground; scheduling active recheck"
      )
      scheduleForegroundRecheck(reason: "willEnterForeground", after: foregroundRecheckDelay())
      return
    }
    if hasQueuedKillTimeline() {
      IosAppKillCycleReporter.shared.appendDebugLog(
        "willEnterForeground; scheduling active recheck (kill queued)"
      )
      scheduleForegroundRecheck(reason: "willEnterForeground_kill", after: 0.75)
    }
  }

  func onUserSceneBecameActive() {
    guard UIApplication.shared.applicationState == .active else {
      IosAppKillCycleReporter.shared.appendDebugLog(
        "skip foreground; applicationState=\(UIApplication.shared.applicationState.rawValue)"
      )
      // Only retry after wake debounce — early inactive→active is common on SLC wake.
      if shouldScheduleForegroundRecheckWhileSuppressed() {
        scheduleForegroundRecheck(reason: "becameActive_inactive", after: 1.0)
      }
      return
    }
    guard hasForegroundActiveWindowScene() else {
      IosAppKillCycleReporter.shared.appendDebugLog(
        "skip foreground; no foregroundActive scene"
      )
      if shouldScheduleForegroundRecheckWhileSuppressed() {
        scheduleForegroundRecheck(reason: "no_foregroundActive_scene", after: 1.0)
      }
      return
    }

    if suppressKillCycleForegroundUntilUserOpen,
       let started = locationWakeSuppressStartedAt,
       Date().timeIntervalSince(started) < locationWakeForegroundDebounce
    {
      IosAppKillCycleReporter.shared.appendDebugLog(
        "defer foreground; location wake too recent — recheck after debounce"
      )
      scheduleForegroundRecheck(
        reason: "wake_debounce",
        after: locationWakeForegroundDebounce - Date().timeIntervalSince(started)
      )
      return
    }

    if suppressKillCycleForegroundUntilUserOpen {
      suppressKillCycleForegroundUntilUserOpen = false
      locationWakeSuppressStartedAt = nil
      IosAppKillCycleReporter.shared.setSuppressOpenedAtUntilUserForeground(false)
      IosAppKillCycleReporter.shared.appendDebugLog(
        "cleared location-wake suppress (app active)"
      )
    }

    registerPlatformChannelsIfNeeded()
    notifyFlutterOfLocationWakeIfNeeded()
    // Same-process resume: drop background candidate (cold launch already recovered).
    UserDefaults.standard.removeObject(forKey: "smartnps360.ios_app_cycle.pending_background_at")
    // User is visibly back — cancel pending kill alert (not on background location wake).
    IosAppKillCycleReporter.shared.cancelKillSecurityAlertOnForeground()
    // Stamp opened_at; Flutter owns reopen POST (native backup if Flutter is late).
    IosAppKillCycleReporter.shared.markOpenedAfterKillIfNeeded(forceForReopenUpload: true)
    IosAppKillCycleReporter.shared.scheduleReopenFlushBackup()
    IosAppKillCycleReporter.shared.appendDebugLog("user foreground (scene/app active)")
  }

  /// Called from Flutter prepare when UI is already active (covers missed scene callbacks).
  @discardableResult
  func claimRealUserForegroundIfActive() -> Bool {
    guard UIApplication.shared.applicationState == .active else { return false }
    guard hasForegroundActiveWindowScene() else { return false }
    if suppressKillCycleForegroundUntilUserOpen,
       let started = locationWakeSuppressStartedAt,
       Date().timeIntervalSince(started) < locationWakeForegroundDebounce
    {
      return false
    }
    onUserSceneBecameActive()
    return true
  }

  func onUserSceneEnteredBackground() {
    pendingForegroundRecheck = false
    if isOnDuty(), !isUnpaidBreak() {
      IosAppKillCycleReporter.shared.noteEnteredBackground()
    } else {
      IosAppKillCycleReporter.shared.appendDebugLog(
        "skip background_at; onDuty=\(isOnDuty()) unpaidBreak=\(isUnpaidBreak())"
      )
      IosAppKillCycleReporter.shared.cancelKillSecurityAlertNotArmed()
    }
  }

  private func hasForegroundActiveWindowScene() -> Bool {
    if #available(iOS 13.0, *) {
      return UIApplication.shared.connectedScenes.contains { scene in
        guard let windowScene = scene as? UIWindowScene else { return false }
        return windowScene.activationState == .foregroundActive
      }
    }
    return true
  }

  private func hasQueuedKillTimeline() -> Bool {
    let killed = UserDefaults.standard.string(
      forKey: "smartnps360.ios_app_cycle.pending_killed_at"
    )?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !killed.isEmpty
  }

  private func shouldScheduleForegroundRecheckWhileSuppressed() -> Bool {
    guard suppressKillCycleForegroundUntilUserOpen || hasQueuedKillTimeline() else {
      return false
    }
    if suppressKillCycleForegroundUntilUserOpen,
       let started = locationWakeSuppressStartedAt,
       Date().timeIntervalSince(started) < locationWakeForegroundDebounce
    {
      return false
    }
    return true
  }

  private func foregroundRecheckDelay() -> TimeInterval {
    if let started = locationWakeSuppressStartedAt {
      return max(1.0, locationWakeForegroundDebounce - Date().timeIntervalSince(started))
    }
    return 1.0
  }

  private func scheduleForegroundRecheck(reason: String, after: TimeInterval) {
    guard !pendingForegroundRecheck else { return }
    let delay = max(0.5, after)
    pendingForegroundRecheck = true
    IosAppKillCycleReporter.shared.appendDebugLog(
      "schedule foreground recheck in \(String(format: "%.1f", delay))s (\(reason))"
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      self.pendingForegroundRecheck = false
      self.onUserSceneBecameActive()
    }
  }

  /// Registers custom channels on the active Flutter engine messenger.
  func registerPlatformChannels(with messenger: FlutterBinaryMessenger) {
    registerSettingsChannelIfNeeded(with: messenger)
    registerSlcChannelIfNeeded(with: messenger)
    registerMotionActivityChannelIfNeeded(with: messenger)
    registerDeviceCheckChannelIfNeeded(with: messenger)
    registerNativeCameraChannelIfNeeded(with: messenger)
  }

  /// Fallback for engines created before implicit-engine callback wiring.
  func registerPlatformChannelsIfNeeded() {
    if slcChannelRegistered
      && settingsChannelRegistered
      && motionChannelRegistered
      && deviceCheckChannelRegistered
      && nativeCameraChannelRegistered
    {
      return
    }
    if let messenger = flutterViewController()?.binaryMessenger {
      registerPlatformChannels(with: messenger)
    }
  }

  private func registerDeviceCheckChannelIfNeeded(with messenger: FlutterBinaryMessenger) {
    guard !deviceCheckChannelRegistered else { return }
    let manager = deviceCheckManager ?? DeviceCheckManager()
    manager.register(with: messenger)
    deviceCheckManager = manager
    deviceCheckChannelRegistered = true
  }

  private func registerNativeCameraChannelIfNeeded(with messenger: FlutterBinaryMessenger) {
    guard !nativeCameraChannelRegistered else { return }
    let plugin = nativeCameraPlugin ?? NativeCameraPlugin()
    plugin.register(with: messenger)
    nativeCameraPlugin = plugin
    nativeCameraChannelRegistered = true
  }

  private func registerMotionActivityChannelIfNeeded(with messenger: FlutterBinaryMessenger) {
    guard !motionChannelRegistered else { return }
    let manager = motionActivityManager ?? MotionActivityManager()
    manager.onSignificantMotion = { [weak self] activity in
      self?.handleSignificantMotion(activity)
    }
    manager.register(with: messenger)
    motionActivityManager = manager
    motionChannelRegistered = true
  }

  private func flutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }

    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for sceneWindow in windowScene.windows {
          if let controller = sceneWindow.rootViewController as? FlutterViewController {
            return controller
          }
        }
      }
    }

    return nil
  }

  private func registerSettingsChannelIfNeeded(with messenger: FlutterBinaryMessenger) {
    guard !settingsChannelRegistered else { return }

    let channel = FlutterMethodChannel(
      name: settingsChannel,
      binaryMessenger: messenger
    )
    settingsMethodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "openAppSettings", "openLocationPermissionSettings":
        self?.openAppSettings(result: result)
      case "lowPowerModeStatus":
        result(self?.lowPowerModeStatus() ?? "unknown")
      case "backgroundAppRefreshStatus":
        result(self?.backgroundAppRefreshStatus() ?? "unknown")
      case "hasPreciseLocationPermission":
        result(self?.hasPreciseLocationPermission() ?? false)
      case "peekAppKillTimeline":
        result(IosAppKillCycleReporter.shared.peekTimeline())
      case "prepareAppKillTimelineForReopen":
        result(IosAppKillCycleReporter.shared.prepareTimelineForReopen())
      case "clearAppKillTimeline":
        IosAppKillCycleReporter.shared.clearPendingAfterFlutterUpload()
        result(true)
      case "getAppKillCycleDebugSnapshot":
        result(self?.appKillCycleDebugSnapshot() ?? [:])
      case "clearAppKillCycleDebugLogs":
        IosAppKillCycleReporter.shared.clearDebugLogs()
        result(true)
      case "setKillDebugCaptureEnabled":
        let enabled: Bool
        if let value = call.arguments as? Bool {
          enabled = value
        } else if let map = call.arguments as? [String: Any] {
          enabled = (map["enabled"] as? Bool) ?? false
        } else {
          enabled = false
        }
        IosAppKillCycleReporter.shared.setKillDebugCaptureEnabled(enabled)
        result(true)
      case "appendAppKillCycleDebugLog":
        if let message = call.arguments as? String, !message.isEmpty {
          IosAppKillCycleReporter.shared.appendDebugLog("flutter: \(message)")
        } else if let map = call.arguments as? [String: Any],
                  let message = map["message"] as? String,
                  !message.isEmpty
        {
          IosAppKillCycleReporter.shared.appendDebugLog("flutter: \(message)")
        }
        result(true)
      case "cacheFullPermissionSnapshot":
        if let map = call.arguments as? [String: Any] {
          var asStrings: [String: String] = [:]
          for (key, value) in map {
            let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, text != "null" {
              asStrings[key] = text
            }
          }
          IosAppKillCycleReporter.shared.cacheFullPermissionsSnapshot(asStrings)
          result(true)
        } else {
          result(
            FlutterError(
              code: "bad_args",
              message: "cacheFullPermissionSnapshot expects a string map",
              details: nil
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    settingsChannelRegistered = true
  }

  /// Mirrors Android ACCESS_FINE check: iOS 14+ Precise Location from Settings.
  private func hasPreciseLocationPermission() -> Bool {
    if #available(iOS 14.0, *) {
      // Always use a fresh manager so Settings changes are not stale vs SLC.
      let manager = CLLocationManager()
      switch manager.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
        return manager.accuracyAuthorization == .fullAccuracy
      case .denied, .restricted, .notDetermined:
        return false
      @unknown default:
        return false
      }
    }
    // Pre-iOS 14 has no Precise Location toggle.
    return true
  }

  private func observeLowPowerModeChanges() {
    NotificationCenter.default.removeObserver(
      self,
      name: .NSProcessInfoPowerStateDidChange,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lowPowerModeDidChange),
      name: .NSProcessInfoPowerStateDidChange,
      object: nil
    )
  }

  @objc private func lowPowerModeDidChange() {
    let status = lowPowerModeStatus()
    DispatchQueue.main.async { [weak self] in
      self?.settingsMethodChannel?.invokeMethod(
        "lowPowerModeChanged",
        arguments: ["low_power_mode": status]
      )
    }
  }

  private func lowPowerModeStatus() -> String {
    return ProcessInfo.processInfo.isLowPowerModeEnabled ? "enabled" : "disabled"
  }

  private func observeBackgroundAppRefreshChanges() {
    NotificationCenter.default.removeObserver(
      self,
      name: UIApplication.backgroundRefreshStatusDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(backgroundAppRefreshDidChange),
      name: UIApplication.backgroundRefreshStatusDidChangeNotification,
      object: nil
    )
  }

  @objc private func backgroundAppRefreshDidChange() {
    let status = backgroundAppRefreshStatus()
    DispatchQueue.main.async { [weak self] in
      self?.settingsMethodChannel?.invokeMethod(
        "backgroundAppRefreshChanged",
        arguments: ["backgroundAppRefresh": status]
      )
    }
  }

  /// Settings → General → Background App Refresh (and Low Power Mode effects).
  private func backgroundAppRefreshStatus() -> String {
    switch UIApplication.shared.backgroundRefreshStatus {
    case .available:
      return "enabled"
    case .denied:
      return "disabled"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  private func registerSlcChannelIfNeeded(with messenger: FlutterBinaryMessenger) {
    guard !slcChannelRegistered else { return }

    let channel = FlutterMethodChannel(
      name: slcChannelName,
      binaryMessenger: messenger
    )
    slcMethodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "SLC manager unavailable", details: nil))
        return
      }

      switch call.method {
      case "startMonitoring":
        result(self.startSlcMonitoring())
      case "stopMonitoring":
        self.stopSlcMonitoring()
        result(["ok": true, "running": false])
      case "setOnDuty":
        let onDuty = (call.arguments as? [String: Any])?["onDuty"] as? Bool ?? false
        self.setOnDuty(onDuty)
        result([
          "ok": true,
          "onDuty": onDuty,
          "running": UserDefaults.standard.bool(forKey: self.slcEnabledKey),
        ])
      case "setUnpaidBreak":
        let unpaid = (call.arguments as? [String: Any])?["unpaid"] as? Bool ?? false
        self.setUnpaidBreak(unpaid)
        result([
          "ok": true,
          "unpaidBreak": unpaid,
          "onDuty": self.isOnDuty(),
        ])
      case "isOnDuty":
        result(self.slcStatusMap())
      case "isMonitoring":
        result(self.slcStatusMap())
      case "drainPendingLocations":
        result(self.drainPendingSlcLocations())
      case "syncAuthSession":
        let args = call.arguments as? [String: Any]
        if args?["clear"] as? Bool == true {
          DutyWakeUploader.shared.clearSession()
        } else {
          DutyWakeUploader.shared.syncSession(
            accessToken: args?["accessToken"] as? String,
            refreshToken: args?["refreshToken"] as? String,
            deviceId: args?["deviceId"] as? String
          )
        }
        result(["ok": true])
      case "claimWakeUpload":
        DutyWakeUploader.shared.claimByFlutter()
        result(["ok": true, "owner": "flutter"])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: slcEventChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
    slcChannelRegistered = true
    notifyFlutterOfLocationWakeIfNeeded()
  }

  private func slcStatusMap() -> [String: Any] {
    return [
      "ok": true,
      "running": UserDefaults.standard.bool(forKey: slcEnabledKey),
      "onDuty": isOnDuty(),
      "launchedForLocation": launchedForLocation,
      "awaitingDutyConfirm": awaitingFlutterDutyConfirm,
      "geofenceArmed": lastGeofenceCoordinate != nil && isOnDuty(),
      "geofenceRadiusMeters": dutyGeofenceRadius,
      "geofenceRingCount": dutyGeofenceRingSlots.count,
      "wakeTrigger": UserDefaults.standard.string(forKey: "smartnps360.ios_wake.trigger") ?? "unknown",
      "motionRunning": motionActivityManager?.running == true,
      "authorization": authorizationStatusString(),
    ]
  }

  private func restoreSlcMonitoringIfNeeded(
    application: UIApplication,
    launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) {
    let locationKey = launchOptions?[UIApplication.LaunchOptionsKey.location] != nil
    let wasOnDuty = UserDefaults.standard.bool(forKey: onDutyKey)
    let wasArmed = UserDefaults.standard.bool(forKey: slcEnabledKey)
    let backgroundLaunch = application.applicationState == .background
    launchedForLocation = locationKey || (backgroundLaunch && wasOnDuty && wasArmed)
    if launchedForLocation {
      // Stay silent for kill-cycle "open" until the app is truly .active.
      suppressKillCycleForegroundUntilUserOpen = true
      locationWakeSuppressStartedAt = Date()
      IosAppKillCycleReporter.shared.setSuppressOpenedAtUntilUserForeground(true)
    } else {
      // Fresh icon/cold open — never inherit a stale location-wake suppress.
      suppressKillCycleForegroundUntilUserOpen = false
      locationWakeSuppressStartedAt = nil
      IosAppKillCycleReporter.shared.setSuppressOpenedAtUntilUserForeground(false)
    }

    // Classify what woke/relaunched the process after a kill (Debug Env panel).
    let hadKillCandidate =
      UserDefaults.standard.string(forKey: "smartnps360.ios_app_cycle.pending_killed_at") != nil
      || UserDefaults.standard.string(forKey: "smartnps360.ios_app_cycle.pending_background_at") != nil
    if hadKillCandidate || launchedForLocation {
      if locationKey {
        IosAppKillCycleReporter.shared.recordWakeService(
          "ios_location_launch",
          detail: "LaunchOptions.location (SLC or geofence)"
        )
        UserDefaults.standard.set("ios_location_launch", forKey: "smartnps360.ios_wake.trigger")
      } else if backgroundLaunch && wasOnDuty && wasArmed {
        IosAppKillCycleReporter.shared.recordWakeService(
          "ios_background_location_relaunch",
          detail: "background launch while onDuty+SLC armed"
        )
        UserDefaults.standard.set(
          "ios_background_location_relaunch",
          forKey: "smartnps360.ios_wake.trigger"
        )
      } else if hadKillCandidate {
        IosAppKillCycleReporter.shared.recordWakeService(
          "user_open",
          detail: "cold launch / icon tap after kill"
        )
        UserDefaults.standard.set("user_open", forKey: "smartnps360.ios_wake.trigger")
      }
    }

    if !launchedForLocation {
      // Tap/open while still flagged on duty: keep SLC + start optimistic GPS
      // so tracking resumes after kill even without an SLC wake first.
      // Without a stored session token, disarm — e.g. login screen / logged out.
      if wasOnDuty,
         wasArmed,
         CLLocationManager.authorizationStatus() == .authorizedAlways,
         DutyWakeUploader.shared.hasAccessToken
      {
        NSLog("[SmartNPS360][SLC] cold launch on duty; keeping SLC + optimistic GPS")
        restoreSlcAfterLocationWake(startNativePing: true)
        return
      }
      if wasOnDuty || wasArmed {
        NSLog(
          "[SmartNPS360][SLC] cold launch cleared; "
            + "wasOnDuty=\(wasOnDuty) wasArmed=\(wasArmed) "
            + "hasToken=\(DutyWakeUploader.shared.hasAccessToken)"
        )
      }
      setOnDuty(false)
      return
    }

    guard wasOnDuty, wasArmed else {
      NSLog("[SmartNPS360][SLC] location wake ignored; native duty/slc not armed")
      setOnDuty(false)
      return
    }

    guard DutyWakeUploader.shared.hasAccessToken else {
      NSLog("[SmartNPS360][SLC] location wake ignored; no auth token")
      setOnDuty(false)
      return
    }

    let status = CLLocationManager.authorizationStatus()
    guard status == .authorizedAlways else {
      NSLog("[SmartNPS360][SLC] location wake ignored; Always permission missing")
      setOnDuty(false)
      return
    }

    NSLog(
      "[SmartNPS360][SLC] location wake restore locationKey=\(locationKey) background=\(backgroundLaunch)"
    )
    restoreSlcAfterLocationWake(startNativePing: true)
  }

  /// Restores SLC + GPS ring without stopping existing iOS region monitoring.
  /// On location wake: start duty GPS immediately from local on_duty (optimistic),
  /// then reconcile via native/Flutter heartbeat (stop if API says off_duty).
  private func restoreSlcAfterLocationWake(startNativePing: Bool) {
    awaitingFlutterDutyConfirm = true
    UserDefaults.standard.set(true, forKey: onDutyKey)
    UserDefaults.standard.set(true, forKey: slcEnabledKey)

    let manager = ensureWakeLocationManager()

    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      manager.startMonitoringSignificantLocationChanges()
      NSLog("[SmartNPS360][SLC] restored SLC after location wake")
    } else {
      NSLog("[SmartNPS360][SLC] SLC unavailable after location wake")
    }

    if let saved = savedGeofenceCoordinate() {
      lastGeofenceCoordinate = saved
      syncDutyGeofenceRing(around: saved, manager: manager)
    }
    requestGpsFix(reason: "wake_restore")

    if startNativePing {
      // Optimistic duty GPS from local storage — do not wait for API/UI.
      if startOptimisticDutyGpsIfArmed(reason: "location_wake") {
        IosAppKillCycleReporter.shared.appendDebugLog(
          "optimistic duty GPS started (local on_duty)"
        )
      } else {
        NSLog("[SmartNPS360][SLC] optimistic GPS skipped; awaiting confirm")
      }

      // Start native wake ping immediately — do not wait for Flutter (Geolocator
      // is often silent after kill relaunch; native ping is the reliable first hit).
      DutyWakeUploader.shared.beginLocationWake(flutterTimeout: 0)
      // Location/SLC relaunch after swipe-kill — upload killed without waiting for user open.
      IosAppKillCycleReporter.shared.recoverKillFromBackgroundIfNeeded()
      IosAppKillCycleReporter.shared.uploadKilledEventIfNeeded(reason: "location_wake")

      // Let Flutter attach pinger; native ping already in flight.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.notifyFlutterOfLocationWakeIfNeeded()
      }
    }
  }

  /// Start continuous duty GPS when native local on_duty is armed (post-kill wake).
  @discardableResult
  private func startOptimisticDutyGpsIfArmed(reason: String) -> Bool {
    guard isOnDuty() else { return false }
    guard !isUnpaidBreak() else { return false }
    guard DutyWakeUploader.shared.hasAccessToken else { return false }
    guard CLLocationManager.authorizationStatus() == .authorizedAlways else { return false }

    awaitingFlutterDutyConfirm = false
    startDutyGpsMonitoring()
    startDutyMotionIfAllowed()
    NSLog("[SmartNPS360][DutyGPS] optimistic start reason=\(reason)")
    return true
  }

  private func wireDutyWakeUploader() {
    DutyWakeUploader.shared.onConfirmedOffDuty = { [weak self] in
      self?.setOnDuty(false)
    }
    DutyWakeUploader.shared.onDutyConfirmed = { [weak self] in
      guard let self else { return }
      self.awaitingFlutterDutyConfirm = false
      self.startDutyGpsMonitoring()
      self.startDutyMotionIfAllowed()
      self.notifyFlutterOfLocationWakeIfNeeded()
    }
    DutyWakeUploader.shared.onNeedsGps = { [weak self] in
      self?.requestNativeWakeGps()
    }
  }

  private func ensureWakeLocationManager() -> CLLocationManager {
    let manager = slcLocationManager ?? CLLocationManager()
    manager.delegate = self
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    slcLocationManager = manager
    return manager
  }

  private func notifyFlutterOfLocationWakeIfNeeded() {
    guard isOnDuty() else { return }
    guard UserDefaults.standard.bool(forKey: slcEnabledKey) else { return }
    // After optimistic GPS, awaitingFlutterDutyConfirm is false — still notify
    // Flutter whenever this process was launched for location OR GPS is already live.
    let gpsLive = dutyGpsLocationManager != nil
    guard launchedForLocation || awaitingFlutterDutyConfirm || gpsLive else { return }
    guard let channel = slcMethodChannel else { return }
    channel.invokeMethod(
      "onLocationWake",
      arguments: slcStatusMap()
    ) { [weak self] result in
      guard let self else { return }
      // Never claim on location/SLC relaunch — that cancelled DutyWakeUploader
      // before any ping left the device while Flutter Geolocator stayed silent.
      if (result as? Bool) == true, !self.launchedForLocation {
        DutyWakeUploader.shared.claimByFlutter()
      } else if self.launchedForLocation {
        NSLog(
          "[SmartNPS360][SLC] location wake: Flutter running=\(result as? Bool ?? false); "
            + "keeping native wake ping"
        )
        IosAppKillCycleReporter.shared.appendDebugLog(
          "location wake: keep native GPS ping (flutterClaim blocked)"
        )
      }
      self.startDutyGpsMonitoring()
      self.startDutyMotionIfAllowed()
    }
  }

  private func isOnDuty() -> Bool {
    return UserDefaults.standard.bool(forKey: onDutyKey)
  }

  private func appKillCycleDebugSnapshot() -> [String: Any] {
    IosAppKillCycleReporter.shared.debugSnapshot(
      onDuty: isOnDuty(),
      unpaidBreak: isUnpaidBreak(),
      slcArmed: UserDefaults.standard.bool(forKey: slcEnabledKey),
      hasAccessToken: DutyWakeUploader.shared.hasAccessToken
    )
  }

  private func setOnDuty(_ onDuty: Bool) {
    UserDefaults.standard.set(onDuty, forKey: onDutyKey)
    if !onDuty {
      awaitingFlutterDutyConfirm = false
      UserDefaults.standard.set(false, forKey: unpaidBreakKey)
      DutyWakeUploader.shared.cancel()
      stopSlcMonitoring()
    }
  }

  private func isUnpaidBreak() -> Bool {
    return UserDefaults.standard.bool(forKey: unpaidBreakKey)
  }

  private func setUnpaidBreak(_ unpaid: Bool) {
    UserDefaults.standard.set(unpaid, forKey: unpaidBreakKey)
    if unpaid {
      NSLog("[SmartNPS360][SLC] unpaid break — pausing duty GPS (SLC stays armed if on duty)")
      stopDutyGpsMonitoring()
    } else if isOnDuty() && !awaitingFlutterDutyConfirm {
      NSLog("[SmartNPS360][SLC] unpaid break ended — resuming duty GPS")
      startDutyGpsMonitoring()
    }
  }

  private func startSlcMonitoring() -> [String: Any] {
    guard isOnDuty() else {
      stopSlcMonitoring()
      return [
        "ok": false,
        "running": false,
        "onDuty": false,
        "launchedForLocation": launchedForLocation,
        "error": [
          "code": "off_duty",
          "message": "Background location is only allowed while the officer is on duty"
        ]
      ]
    }

    let status = CLLocationManager.authorizationStatus()
    guard status == .authorizedAlways else {
      stopSlcMonitoring()
      return [
        "ok": false,
        "running": false,
        "authorization": authorizationStatusString(status),
        "error": [
          "code": "location_always_required",
          "message": "Always location permission is required for iOS background location"
        ]
      ]
    }

    awaitingFlutterDutyConfirm = false
    // On location/SLC relaunch, keep DutyWakeUploader alive as a one-shot ping
    // backup. Claiming here races Flutter recover and cancelled native uploads
    // before any GPS ping left the device.
    if !launchedForLocation {
      DutyWakeUploader.shared.claimByFlutter()
    }
    if isUnpaidBreak() {
      stopDutyGpsMonitoring()
    } else {
      startDutyGpsMonitoring()
    }
    startDutyMotionIfAllowed()

    let manager = ensureWakeLocationManager()
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      manager.startMonitoringSignificantLocationChanges()
    } else {
      NSLog("[SmartNPS360][SLC] significant-change unavailable; duty GPS keep-alive still running")
    }

    if let saved = savedGeofenceCoordinate() {
      lastGeofenceCoordinate = saved
      syncDutyGeofenceRing(around: saved, manager: manager)
    }

    UserDefaults.standard.set(true, forKey: slcEnabledKey)

    return [
      "ok": true,
      "running": true,
      "onDuty": true,
      "unpaidBreak": isUnpaidBreak(),
      "gpsKeepAlive": !isUnpaidBreak(),
      "launchedForLocation": launchedForLocation,
      "awaitingDutyConfirm": false,
      "distanceFilterMeters": 0,
      "geofenceRadiusMeters": dutyGeofenceRadius,
      "geofenceArmed": lastGeofenceCoordinate != nil,
      "geofenceRingCount": dutyGeofenceRingSlots.count,
      "motionRunning": motionActivityManager?.running == true,
      "authorization": authorizationStatusString(status)
    ]
  }

  private func startDutyGpsMonitoring() {
    guard isOnDuty() else { return }
    guard !isUnpaidBreak() else {
      NSLog("[SmartNPS360][DutyGPS] skip start; unpaid break active")
      return
    }
    let manager = dutyGpsLocationManager ?? CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.distanceFilter = dutyGpsDistanceFilter
    manager.activityType = .otherNavigation
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    if #available(iOS 11.0, *) {
      manager.showsBackgroundLocationIndicator = true
    }
    dutyGpsLocationManager = manager
    manager.startUpdatingLocation()
    startGpsPollTimer()
  }

  private func stopDutyGpsMonitoring() {
    gpsPollTimer?.invalidate()
    gpsPollTimer = nil
    gpsPollInFlight = false
    lastNativeGpsAt = nil
    dutyPollLocationManager?.stopUpdatingLocation()
    dutyPollLocationManager?.delegate = nil
    dutyPollLocationManager = nil
    dutyGpsLocationManager?.stopUpdatingLocation()
    dutyGpsLocationManager?.delegate = nil
    dutyGpsLocationManager = nil
  }

  private func startGpsPollTimer() {
    gpsPollTimer?.invalidate()
    let timer = Timer(timeInterval: gpsPollInterval, repeats: true) { [weak self] _ in
      self?.requestFreshGpsPoll(reason: "timer")
    }
    RunLoop.main.add(timer, forMode: .common)
    gpsPollTimer = timer
  }

  /// One-shot current GPS (not last-known). Used while stationary and on SLC wake.
  private func requestFreshGpsPoll(reason: String) {
    guard isOnDuty(), UserDefaults.standard.bool(forKey: slcEnabledKey) else { return }
    if isUnpaidBreak() { return }
    if awaitingFlutterDutyConfirm { return }
    if let lastGps = lastNativeGpsAt, Date().timeIntervalSince(lastGps) < gpsPollInterval {
      return
    }
    if gpsPollInFlight { return }
    requestGpsFix(reason: reason)
  }

  private func requestNativeWakeGps() {
    guard isOnDuty(), UserDefaults.standard.bool(forKey: slcEnabledKey) else { return }
    if isUnpaidBreak() {
      NSLog("[SmartNPS360][DutyGPS] skip native wake GPS; unpaid break active")
      return
    }
    requestGpsFix(reason: "native_wake")
  }

  private func requestGpsFix(reason: String) {
    if gpsPollInFlight { return }
    gpsPollInFlight = true

    let manager = dutyPollLocationManager ?? CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.distanceFilter = kCLDistanceFilterNone
    manager.activityType = .otherNavigation
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    if #available(iOS 11.0, *) {
      manager.showsBackgroundLocationIndicator = true
    }
    dutyPollLocationManager = manager
    NSLog("[SmartNPS360][DutyGPS] requesting fresh GPS poll (\(reason))")
    manager.requestLocation()
  }

  private func stopSlcMonitoring() {
    awaitingFlutterDutyConfirm = false
    startDutyMotionStopped()
    gpsPollTimer?.invalidate()
    gpsPollTimer = nil
    gpsPollInFlight = false
    lastNativeGpsAt = nil
    dutyPollLocationManager?.stopUpdatingLocation()
    dutyPollLocationManager?.delegate = nil
    dutyPollLocationManager = nil
    dutyGpsLocationManager?.stopUpdatingLocation()
    dutyGpsLocationManager?.delegate = nil
    dutyGpsLocationManager = nil
    let manager = slcLocationManager ?? CLLocationManager()
    stopDutyGeofence(using: manager)
    manager.stopMonitoringSignificantLocationChanges()
    manager.delegate = nil
    slcLocationManager = nil
    DutyWakeUploader.shared.cancel()
    UserDefaults.standard.set(false, forKey: slcEnabledKey)
    clearPendingSlcLocations()
  }

  private func startDutyMotionIfAllowed() {
    guard isOnDuty() else {
      startDutyMotionStopped()
      return
    }
    let result = motionActivityManager?.startDutyUpdates()
    NSLog("[SmartNPS360][Motion] duty start ok=\(result?["ok"] as? Bool ?? false)")
  }

  private func startDutyMotionStopped() {
    motionActivityManager?.stopDutyUpdates()
  }

  // MARK: - Duty geofence ring (~100m overlapping circles around last GPS)

  private var dutyGeofenceRingSlots: [(id: String, north: CLLocationDistance, east: CLLocationDistance)] {
    let diagonal = dutyGeofenceRingOffset * 0.7071
    return [
      ("center", 0, 0),
      ("n", dutyGeofenceRingOffset, 0),
      ("ne", diagonal, diagonal),
      ("e", 0, dutyGeofenceRingOffset),
      ("se", -diagonal, diagonal),
      ("s", -dutyGeofenceRingOffset, 0),
      ("sw", -diagonal, -diagonal),
      ("w", 0, -dutyGeofenceRingOffset),
      ("nw", diagonal, -diagonal),
    ]
  }

  /// Adds/updates the 9-fence ring without dropping iOS monitoring unless the center moved.
  private func syncDutyGeofenceRing(around coordinate: CLLocationCoordinate2D, manager: CLLocationManager) {
    guard isOnDuty() else {
      stopDutyGeofence(using: slcLocationManager)
      return
    }
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      NSLog("[SmartNPS360][Geofence] region monitoring unavailable")
      return
    }

    let desiredIds = Set(dutyGeofenceRingSlots.map { dutyGeofenceIdPrefix + $0.id })
    if let current = lastGeofenceCoordinate ?? savedGeofenceCoordinate() {
      let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
        .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
      let existingIds = Set(manager.monitoredRegions.filter { isDutyGeofence($0) }.map(\.identifier))
      if distance < dutyGeofenceRecenterMeters, desiredIds.isSubset(of: existingIds) {
        lastGeofenceCoordinate = current
        return
      }
    }

    for region in manager.monitoredRegions where isDutyGeofence(region) && !desiredIds.contains(region.identifier) {
      manager.stopMonitoring(for: region)
    }

    for slot in dutyGeofenceRingSlots {
      let center = coordinateByOffsetting(coordinate, north: slot.north, east: slot.east)
      let identifier = dutyGeofenceIdPrefix + slot.id
      if let existing = manager.monitoredRegions.first(where: { $0.identifier == identifier }) as? CLCircularRegion {
        let shift = CLLocation(latitude: existing.center.latitude, longitude: existing.center.longitude)
          .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
        if shift < 15 {
          continue
        }
        manager.stopMonitoring(for: existing)
      }
      let region = CLCircularRegion(
        center: center,
        radius: dutyGeofenceRadius,
        identifier: identifier
      )
      region.notifyOnEntry = true
      region.notifyOnExit = true
      manager.startMonitoring(for: region)
    }

    lastGeofenceCoordinate = coordinate
    UserDefaults.standard.set(coordinate.latitude, forKey: geofenceLatKey)
    UserDefaults.standard.set(coordinate.longitude, forKey: geofenceLonKey)
    NSLog(
      "[SmartNPS360][Geofence] armed \(dutyGeofenceRingSlots.count)x\(Int(dutyGeofenceRadius))m ring at \(coordinate.latitude), \(coordinate.longitude)"
    )
  }

  private func startDutyGeofence(around coordinate: CLLocationCoordinate2D, manager: CLLocationManager) {
    syncDutyGeofenceRing(around: coordinate, manager: manager)
  }

  private func updateDutyGeofenceIfNeeded(from location: CLLocation, force: Bool = false) {
    guard isOnDuty() else { return }
    guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }

    let manager = ensureWakeLocationManager()
    if !force, let current = lastGeofenceCoordinate ?? savedGeofenceCoordinate() {
      let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
        .distance(from: location)
      if distance < dutyGeofenceRecenterMeters {
        syncDutyGeofenceRing(around: current, manager: manager)
        return
      }
    }
    syncDutyGeofenceRing(around: location.coordinate, manager: manager)
  }

  private func stopDutyGeofence(using manager: CLLocationManager? = nil, clearSavedCenter: Bool = true) {
    let monitor = manager ?? slcLocationManager ?? CLLocationManager()
    for region in monitor.monitoredRegions where isDutyGeofence(region) {
      monitor.stopMonitoring(for: region)
    }
    if clearSavedCenter {
      lastGeofenceCoordinate = nil
      UserDefaults.standard.removeObject(forKey: geofenceLatKey)
      UserDefaults.standard.removeObject(forKey: geofenceLonKey)
    }
  }

  private func isDutyGeofence(_ region: CLRegion) -> Bool {
    region.identifier.hasPrefix(dutyGeofenceIdPrefix) ||
      region.identifier == dutyGeofenceLegacyIdentifier
  }

  private func coordinateByOffsetting(
    _ coordinate: CLLocationCoordinate2D,
    north: CLLocationDistance,
    east: CLLocationDistance
  ) -> CLLocationCoordinate2D {
    guard north != 0 || east != 0 else { return coordinate }
    let metersPerDegreeLat = 111_111.0
    let metersPerDegreeLon = 111_111.0 * max(cos(coordinate.latitude * .pi / 180), 0.01)
    return CLLocationCoordinate2D(
      latitude: coordinate.latitude + (north / metersPerDegreeLat),
      longitude: coordinate.longitude + (east / metersPerDegreeLon)
    )
  }

  private func savedGeofenceCoordinate() -> CLLocationCoordinate2D? {
    if let memory = lastGeofenceCoordinate {
      return memory
    }
    guard UserDefaults.standard.object(forKey: geofenceLatKey) != nil,
          UserDefaults.standard.object(forKey: geofenceLonKey) != nil
    else {
      return nil
    }
    let lat = UserDefaults.standard.double(forKey: geofenceLatKey)
    let lon = UserDefaults.standard.double(forKey: geofenceLonKey)
    guard lat != 0 || lon != 0 else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  private func handleSignificantMotion(_ activity: String) {
    guard isOnDuty(), !awaitingFlutterDutyConfirm else { return }
    NSLog("[SmartNPS360][Motion] significant activity=\(activity); requesting GPS")
    IosAppKillCycleReporter.shared.recordWakeService(
      "ios_motion",
      detail: activity
    )
    requestFreshGpsPoll(reason: "motion_\(activity)")
  }

  private func handleGeofenceWake(region: CLRegion, event: String) {
    guard isOnDuty(), UserDefaults.standard.bool(forKey: slcEnabledKey) else { return }
    NSLog("[SmartNPS360][Geofence] \(event) \(region.identifier)")
    IosAppKillCycleReporter.shared.recordWakeService(
      "ios_geofence",
      detail: "\(event) \(region.identifier)"
    )
    UserDefaults.standard.set("ios_geofence_\(event)", forKey: "smartnps360.ios_wake.trigger")
    IosAppKillCycleReporter.shared.uploadKilledEventIfNeeded(reason: "geofence_\(event)")

    if let coord = lastGeofenceCoordinate ?? savedGeofenceCoordinate() {
      let marker = CLLocation(
        coordinate: coord,
        altitude: 0,
        horizontalAccuracy: dutyGeofenceRadius,
        verticalAccuracy: -1,
        timestamp: Date()
      )
      emitLocation(marker, source: "ios_geofence")
    }

    if awaitingFlutterDutyConfirm {
      notifyFlutterOfLocationWakeIfNeeded()
    }
    requestGpsFix(reason: "geofence_\(event)")
  }

  private func authorizationStatusString(_ status: CLAuthorizationStatus = CLLocationManager.authorizationStatus()) -> String {
    switch status {
    case .authorizedAlways:
      return "authorizedAlways"
    case .authorizedWhenInUse:
      return "authorizedWhenInUse"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  private func locationPayload(_ location: CLLocation, source: String) -> [String: Any] {
    var payload: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "altitude": location.altitude,
      "altitudeAccuracy": location.verticalAccuracy,
      "heading": location.course,
      "speed": location.speed,
      "timestampMs": Int64(location.timestamp.timeIntervalSince1970 * 1000),
      "source": source
    ]

    if #available(iOS 13.4, *) {
      payload["speedAccuracy"] = location.speedAccuracy
      payload["headingAccuracy"] = location.courseAccuracy
    } else {
      payload["speedAccuracy"] = -1.0
      payload["headingAccuracy"] = -1.0
    }

    if #available(iOS 15.0, *) {
      payload["isSimulatedBySoftware"] = location.sourceInformation?.isSimulatedBySoftware ?? false
      payload["isProducedByAccessory"] = location.sourceInformation?.isProducedByAccessory ?? false
    }

    return payload
  }

  private func appendPendingSlcLocation(_ payload: [String: Any]) {
    var pending = pendingSlcLocations()
    pending.append(payload)
    if pending.count > 50 {
      pending.removeFirst(pending.count - 50)
    }
    UserDefaults.standard.set(pending, forKey: slcPendingLocationsKey)
  }

  private func pendingSlcLocations() -> [[String: Any]] {
    return UserDefaults.standard.array(forKey: slcPendingLocationsKey) as? [[String: Any]] ?? []
  }

  private func drainPendingSlcLocations() -> [[String: Any]] {
    let pending = pendingSlcLocations()
    clearPendingSlcLocations()
    return pending
  }

  private func clearPendingSlcLocations() {
    UserDefaults.standard.removeObject(forKey: slcPendingLocationsKey)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    slcEventSink = events
    // Flush any GPS fixes that arrived before Flutter attached the event channel
    // (common right after kill/SLC relaunch while optimistic GPS is already live).
    let pending = drainPendingSlcLocations()
    for payload in pending {
      events(payload)
    }
    if !pending.isEmpty {
      NSLog("[SmartNPS360][SLC] flushed \(pending.count) pending GPS events to Flutter")
      IosAppKillCycleReporter.shared.appendDebugLog(
        "flushed \(pending.count) pending GPS events to Flutter"
      )
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    slcEventSink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard isOnDuty(), UserDefaults.standard.bool(forKey: slcEnabledKey) else { return }
    guard let location = locations.last else { return }

    let isPoll = manager === dutyPollLocationManager
    let isKeepAlive = manager === dutyGpsLocationManager
    let isPreciseGps = isPoll || isKeepAlive

    if isPoll {
      gpsPollInFlight = false
    }

    if DutyWakeUploader.shared.consumeWakeGps(location) {
      lastNativeGpsAt = Date()
      updateDutyGeofenceIfNeeded(from: location, force: true)
      // Still emit to Flutter so continuous tracking continues after the
      // one-shot native wake ping — previously this return dropped ios_gps.
      emitLocation(location, source: "ios_gps")
      return
    }

    if isPreciseGps {
      lastNativeGpsAt = Date()
      emitLocation(location, source: "ios_gps")
      updateDutyGeofenceIfNeeded(from: location, force: true)
      if DutyWakeUploader.shared.wantsWakeGps {
        requestGpsFix(reason: "wake_retry")
      }
      return
    }

    if awaitingFlutterDutyConfirm {
      IosAppKillCycleReporter.shared.recordWakeService(
        "ios_slc",
        detail: "significant location change while awaiting duty confirm"
      )
      UserDefaults.standard.set("ios_slc", forKey: "smartnps360.ios_wake.trigger")
      IosAppKillCycleReporter.shared.uploadKilledEventIfNeeded(reason: "slc_wake")
      emitLocation(location, source: "ios_slc")
      requestGpsFix(reason: "slc_wake")
      return
    }

    emitLocation(location, source: "ios_slc")
    requestFreshGpsPoll(reason: "slc_wake")
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard isDutyGeofence(region) else { return }
    handleGeofenceWake(region: region, event: "exit")
  }

  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard isDutyGeofence(region) else { return }
    handleGeofenceWake(region: region, event: "enter")
  }

  func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    guard isDutyGeofence(region) else { return }
    manager.requestState(for: region)
  }

  func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    guard isDutyGeofence(region) else { return }
    guard state == .outside else { return }
    // After swipe-kill, iOS may already be outside the saved ring. Do not use
    // this on live GPS recenter or it retriggers every time fences re-arm.
    guard awaitingFlutterDutyConfirm else { return }
    handleGeofenceWake(region: region, event: "outside")
  }

  func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    NSLog("[SmartNPS360][Geofence] monitoring failed: \(error.localizedDescription)")
  }

  private func emitLocation(_ location: CLLocation, source: String) {
    let payload = locationPayload(location, source: source)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if let sink = self.slcEventSink {
        sink(payload)
      } else {
        self.appendPendingSlcLocation(payload)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if manager === dutyPollLocationManager {
      gpsPollInFlight = false
    }
    NSLog("[SmartNPS360][DutyGPS] location failed: \(error.localizedDescription)")
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if CLLocationManager.authorizationStatus() != .authorizedAlways {
      stopSlcMonitoring()
    }
  }

  /// Apple-approved entry point: opens Settings > SmartNPS360 for this app.
  private func openAppSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }

    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:]) { success in
        result(success)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[SmartNPS360][Push] APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
