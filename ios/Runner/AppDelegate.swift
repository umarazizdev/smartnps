import Flutter
import CoreLocation
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate, FlutterStreamHandler,
  FlutterImplicitEngineDelegate
{
  private let settingsChannel = "com.smartnps360.app/settings"
  private let slcChannelName = "com.smartnps360.app/ios_slc"
  private let slcEventChannelName = "com.smartnps360.app/ios_slc_events"
  private let slcEnabledKey = "smartnps360.ios_slc.enabled"
  private let slcPendingLocationsKey = "smartnps360.ios_slc.pending_locations"
  private var settingsChannelRegistered = false
  private var slcChannelRegistered = false
  private var settingsMethodChannel: FlutterMethodChannel?
  private var slcLocationManager: CLLocationManager?
  private var slcEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let didLaunch = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerPlatformChannelsIfNeeded()
    observeLowPowerModeChanges()
    observeBackgroundAppRefreshChanges()
    restoreSlcMonitoringIfNeeded(launchOptions: launchOptions)
    application.registerForRemoteNotifications()

    return didLaunch
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPlatformChannels(
      with: engineBridge.applicationRegistrar.messenger()
    )
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    registerPlatformChannelsIfNeeded()
    super.applicationDidBecomeActive(application)
  }

  /// Registers custom channels on the active Flutter engine messenger.
  func registerPlatformChannels(with messenger: FlutterBinaryMessenger) {
    registerSettingsChannelIfNeeded(with: messenger)
    registerSlcChannelIfNeeded(with: messenger)
  }

  /// Fallback for engines created before implicit-engine callback wiring.
  func registerPlatformChannelsIfNeeded() {
    if slcChannelRegistered && settingsChannelRegistered {
      return
    }
    if let messenger = flutterViewController()?.binaryMessenger {
      registerPlatformChannels(with: messenger)
    }
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
      case "isMonitoring":
        result([
          "ok": true,
          "running": UserDefaults.standard.bool(forKey: self.slcEnabledKey),
          "authorization": self.authorizationStatusString()
        ])
      case "drainPendingLocations":
        result(self.drainPendingSlcLocations())
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
  }

  private func restoreSlcMonitoringIfNeeded(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    let wasEnabled = UserDefaults.standard.bool(forKey: slcEnabledKey)
    let launchedForLocation = launchOptions?[UIApplication.LaunchOptionsKey.location] != nil
    if wasEnabled || launchedForLocation {
      _ = startSlcMonitoring()
    }
  }

  private func startSlcMonitoring() -> [String: Any] {
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
      return [
        "ok": false,
        "running": false,
        "error": [
          "code": "slc_unavailable",
          "message": "Significant location change monitoring is not available on this device"
        ]
      ]
    }

    let status = CLLocationManager.authorizationStatus()
    guard status == .authorizedAlways else {
      return [
        "ok": false,
        "running": false,
        "authorization": authorizationStatusString(status),
        "error": [
          "code": "location_always_required",
          "message": "Always location permission is required for iOS significant location changes"
        ]
      ]
    }

    let manager = slcLocationManager ?? CLLocationManager()
    manager.delegate = self
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    slcLocationManager = manager
    manager.startMonitoringSignificantLocationChanges()
    UserDefaults.standard.set(true, forKey: slcEnabledKey)

    return [
      "ok": true,
      "running": true,
      "authorization": authorizationStatusString(status)
    ]
  }

  private func stopSlcMonitoring() {
    slcLocationManager?.stopMonitoringSignificantLocationChanges()
    slcLocationManager?.delegate = nil
    slcLocationManager = nil
    UserDefaults.standard.set(false, forKey: slcEnabledKey)
    clearPendingSlcLocations()
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

  private func locationPayload(_ location: CLLocation) -> [String: Any] {
    var payload: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "altitude": location.altitude,
      "altitudeAccuracy": location.verticalAccuracy,
      "heading": location.course,
      "speed": location.speed,
      "timestampMs": Int64(location.timestamp.timeIntervalSince1970 * 1000),
      "source": "ios_slc"
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
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    slcEventSink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard UserDefaults.standard.bool(forKey: slcEnabledKey) else { return }
    guard let location = locations.last else { return }
    let payload = locationPayload(location)

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
    NSLog("[SmartNPS360][SLC] Significant location change failed: \(error.localizedDescription)")
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
