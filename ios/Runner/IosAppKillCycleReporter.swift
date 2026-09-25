import CoreLocation
import Foundation
import Security
import UIKit
import UserNotifications

/// Best-effort `app_cycle=killed` reporter for swipe/terminate while on duty.
/// Always persists locally first; sync upload is optional and time-boxed.
final class IosAppKillCycleReporter {
  static let shared = IosAppKillCycleReporter()

  private let permissionStatusURL =
    URL(string: "https://smartnps360.com/api/native-app/permission-status")!
  private let refreshURL = URL(string: "https://smartnps360.com/api/auth/refresh")!
  private let keychainService = "com.smartnps360.app.native-duty"
  private let accessTokenAccount = "access_token"
  private let refreshTokenAccount = "refresh_token"
  private let deviceIdDefaultsKey = "smartnps360.ios_duty.device_id"
  private let pendingKilledAtKey = "smartnps360.ios_app_cycle.pending_killed_at"
  private let pendingOpenedAtKey = "smartnps360.ios_app_cycle.pending_opened_at"
  private let pendingBackgroundAtKey = "smartnps360.ios_app_cycle.pending_background_at"
  private let debugLogsKey = "smartnps360.ios_app_cycle.debug_logs"
  private let killCaptureEnabledKey = "smartnps360.ios_app_cycle.kill_debug_capture"
  private let lastWakeServiceKey = "smartnps360.ios_app_cycle.last_wake_service"
  private let lastWakeAtKey = "smartnps360.ios_app_cycle.last_wake_at"
  private let lastWakeDetailKey = "smartnps360.ios_app_cycle.last_wake_detail"
  private let killedUploadedKey = "smartnps360.ios_app_cycle.killed_uploaded"
  private let cachedPermissionsKey = "smartnps360.ios_app_cycle.cached_permissions"
  /// Full Flutter permission snapshot for kill/wake lightweight POSTs.
  private let fullCachedPermissionsKey = "smartnps360.ios_app_cycle.full_cached_permissions"
  private let killSecurityNotificationId = "smartnps360.kill_security.pending"
  private let suppressOpenedAtKey = "smartnps360.ios_app_cycle.suppress_opened_at"
  private let maxDebugLogs = 100
  /// Delay so willTerminate add can complete; terminate-only (not background).
  private let killSecurityAlertDelaySeconds: TimeInterval = 4
  /// Terminate-time sync wait (iOS willTerminate ceiling).
  private let syncUploadTimeout: TimeInterval = 5
  /// Location-wake / reopen attempt.
  private let reopenUploadTimeout: TimeInterval = 12

  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 12
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
  }()

  private let lock = NSLock()
  private var flushInFlight = false
  private var killedFlushInFlight = false

  private init() {}

  /// Block opened_at stamping during background location relaunch until the user
  /// really brings the UI forward (`sceneWillEnterForeground`).
  func setSuppressOpenedAtUntilUserForeground(_ suppress: Bool) {
    UserDefaults.standard.set(suppress, forKey: suppressOpenedAtKey)
    UserDefaults.standard.synchronize()
    appendDebugLog(
      suppress
        ? "opened_at suppress ON (location wake)"
        : "opened_at suppress OFF (user foreground)"
    )
  }

  private func isOpenedAtSuppressedUntilUserForeground() -> Bool {
    UserDefaults.standard.bool(forKey: suppressOpenedAtKey)
  }

  /// Persisted ring buffer for TestFlight Debug Env screen (survives swipe-kill).
  /// Only writes while Flutter Session debug Run is active with Kill selected.
  func appendDebugLog(_ message: String) {
    guard isKillDebugCaptureEnabled() else { return }
    let line = "\(Date().toISO8601UTC()) \(message)"
    NSLog("[SmartNPS360][KillCycle] \(message)")
    lock.lock()
    var logs = UserDefaults.standard.stringArray(forKey: debugLogsKey) ?? []
    logs.append(line)
    if logs.count > maxDebugLogs {
      logs = Array(logs.suffix(maxDebugLogs))
    }
    UserDefaults.standard.set(logs, forKey: debugLogsKey)
    lock.unlock()
    // synchronize outside lock — avoid nested lock if another log arrives.
    UserDefaults.standard.synchronize()
  }

  func setKillDebugCaptureEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: killCaptureEnabledKey)
    UserDefaults.standard.synchronize()
  }

  func isKillDebugCaptureEnabled() -> Bool {
    UserDefaults.standard.bool(forKey: killCaptureEnabledKey)
  }

  func clearDebugLogs() {
    UserDefaults.standard.removeObject(forKey: debugLogsKey)
    UserDefaults.standard.synchronize()
  }

  /// Records which system/service relaunched the app after a kill (TestFlight debug).
  func recordWakeService(_ service: String, detail: String? = nil) {
    let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let at = Date().toISO8601UTC()
    UserDefaults.standard.set(trimmed, forKey: lastWakeServiceKey)
    UserDefaults.standard.set(at, forKey: lastWakeAtKey)
    if let detail, !detail.isEmpty {
      UserDefaults.standard.set(detail, forKey: lastWakeDetailKey)
    } else {
      UserDefaults.standard.removeObject(forKey: lastWakeDetailKey)
    }
    UserDefaults.standard.synchronize()
    let suffix = (detail?.isEmpty == false) ? " detail=\(detail!)" : ""
    appendDebugLog("app awoken by service=\(trimmed)\(suffix)")
  }

  /// Snapshot for Debug Env screen (does not clear queue).
  func debugSnapshot(
    onDuty: Bool,
    unpaidBreak: Bool,
    slcArmed: Bool,
    hasAccessToken: Bool
  ) -> [String: Any] {
    let timeline = peekTimeline() ?? [:]
    let backgroundAt = UserDefaults.standard.string(forKey: pendingBackgroundAtKey) ?? ""
    let logs = UserDefaults.standard.stringArray(forKey: debugLogsKey) ?? []
    // Do not call getNotificationSettings + wait here — Flutter method channel
    // runs on the main thread and that would deadlock.
    let notificationAuth =
      UserDefaults.standard.string(forKey: "smartnps360.ios_app_cycle.notif_auth_cache")
      ?? "unknown"

    return [
      "platform": "ios",
      "onDuty": onDuty,
      "unpaidBreak": unpaidBreak,
      "slcArmed": slcArmed,
      "hasAccessToken": hasAccessToken,
      "notificationAuth": notificationAuth,
      "killed_at": timeline["killed_at"] ?? "",
      "opened_at": timeline["opened_at"] ?? "",
      "background_at": backgroundAt,
      "wake_service": UserDefaults.standard.string(forKey: lastWakeServiceKey) ?? "",
      "wake_at": UserDefaults.standard.string(forKey: lastWakeAtKey) ?? "",
      "wake_detail": UserDefaults.standard.string(forKey: lastWakeDetailKey) ?? "",
      "killed_uploaded": UserDefaults.standard.bool(forKey: killedUploadedKey),
      "logs": logs,
    ]
  }

  /// Call from `applicationWillTerminate` while on duty and not unpaid break.
  func handleTerminateWhileOnDuty() {
    let killedAtIso = UserDefaults.standard.string(forKey: pendingBackgroundAtKey)
      ?? Date().toISO8601UTC()

    // Always refresh kill stamp for this swipe.
    UserDefaults.standard.set(killedAtIso, forKey: pendingKilledAtKey)
    UserDefaults.standard.removeObject(forKey: pendingOpenedAtKey)
    UserDefaults.standard.set(false, forKey: killedUploadedKey)
    UserDefaults.standard.removeObject(forKey: pendingBackgroundAtKey)
    UserDefaults.standard.synchronize()
    appendDebugLog("queued killed_at=\(killedAtIso) (willTerminate)")

    // Only schedule kill alert on real terminate — never on plain background.
    scheduleKillSecurityAlertForTerminate()

    // Lightweight sync POST — no full permission rebuild beyond cached/light snapshot.
    let uploaded = postAppCycleSync(
      appCycle: "killed",
      killedAt: killedAtIso,
      openedAt: nil,
      timeout: syncUploadTimeout,
      lightweight: true
    )
    if uploaded {
      UserDefaults.standard.set(true, forKey: killedUploadedKey)
      UserDefaults.standard.synchronize()
    }
    appendDebugLog(
      "terminate upload \(uploaded ? "ok" : "missed"); "
        + "queue kept for killed_at+opened_at"
    )
  }

  /// Call from `applicationDidEnterBackground` while on duty.
  /// Records kill-candidate timestamp only — do NOT schedule the kill
  /// notification here (normal background would false-trigger in ~4s).
  func noteEnteredBackground() {
    let at = Date().toISO8601UTC()
    UserDefaults.standard.set(at, forKey: pendingBackgroundAtKey)
    // Cache a light permission snapshot now so kill/wake POSTs stay fast.
    cachePermissionsSnapshot()
    UserDefaults.standard.synchronize()
    appendDebugLog("noted background_at=\(at)")
  }

  /// Real process death only (willTerminate / recover) — never plain background.
  func scheduleKillSecurityAlertForTerminate() {
    scheduleKillSecurityAlert(forceReschedule: true)
  }

  /// Call from `applicationDidBecomeActive` / sceneDidBecomeActive when the
  /// user is visibly back. Do not call on background location wake.
  /// Native stamps `opened_at`; Flutter `resumed` owns the primary reopen POST.
  func cancelKillSecurityAlertOnForeground() {
    cancelKillSecurityAlert(reason: "user_foreground")
  }

  /// Drop a pending kill alert when duty is not armed (e.g. unpaid break).
  func cancelKillSecurityAlertNotArmed() {
    cancelKillSecurityAlert(reason: "not_armed")
  }

  /// Cold launch: promote background_at → killed_at if process died without willTerminate.
  func recoverKillFromBackgroundIfNeeded() {
    guard pendingKilledAt() == nil else {
      UserDefaults.standard.removeObject(forKey: pendingBackgroundAtKey)
      appendDebugLog("recover skip; killed_at already queued")
      return
    }
    guard let backgroundAt = UserDefaults.standard.string(forKey: pendingBackgroundAtKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !backgroundAt.isEmpty
    else {
      return
    }
    UserDefaults.standard.set(backgroundAt, forKey: pendingKilledAtKey)
    UserDefaults.standard.removeObject(forKey: pendingOpenedAtKey)
    UserDefaults.standard.set(false, forKey: killedUploadedKey)
    UserDefaults.standard.removeObject(forKey: pendingBackgroundAtKey)
    UserDefaults.standard.synchronize()
    appendDebugLog("recovered killed_at from background_at=\(backgroundAt)")
    // Process died without willTerminate — notify once on recovery wake.
    scheduleKillSecurityAlertForTerminate()
  }

  /// Near-realtime kill POST when terminate was missed (location wake / cold launch).
  /// Does not stamp opened_at and does not clear the kill queue.
  func uploadKilledEventIfNeeded(reason: String) {
    guard let killedAt = pendingKilledAt() else { return }
    if UserDefaults.standard.bool(forKey: killedUploadedKey) {
      appendDebugLog("killed upload skip (\(reason)); already uploaded")
      return
    }

    lock.lock()
    if killedFlushInFlight {
      lock.unlock()
      appendDebugLog("killed upload skip (\(reason)); already in flight")
      return
    }
    killedFlushInFlight = true
    lock.unlock()

    appendDebugLog("killed upload attempt (\(reason)) killed_at=\(killedAt)")
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let ok = self.postAppCycleSync(
        appCycle: "killed",
        killedAt: killedAt,
        openedAt: nil,
        timeout: self.reopenUploadTimeout,
        lightweight: true
      )
      if ok {
        UserDefaults.standard.set(true, forKey: self.killedUploadedKey)
        UserDefaults.standard.synchronize()
        self.appendDebugLog("killed upload ok (\(reason)); waiting for opened_at")
      } else {
        self.appendDebugLog("killed upload failed (\(reason)); will retry")
      }
      self.lock.lock()
      self.killedFlushInFlight = false
      self.lock.unlock()
    }
  }

  /// Only after a real kill queue exists.
  /// - Blocks stamping during background location relaunch (suppress flag).
  /// - Always requires `applicationState == .active` (even Flutter prepare).
  func markOpenedAfterKillIfNeeded(forceForReopenUpload: Bool = false) {
    guard pendingKilledAt() != nil else { return }
    guard pendingOpenedAt() == nil else { return }
    if isOpenedAtSuppressedUntilUserForeground() {
      appendDebugLog("skip opened_at; location-wake suppress (awaiting user open)")
      return
    }
    // forceForReopenUpload no longer bypasses active — prevents false open on SLC wake.
    guard UIApplication.shared.applicationState == .active else {
      appendDebugLog(
        "skip opened_at; app not active "
          + "(state=\(UIApplication.shared.applicationState.rawValue)"
          + " force=\(forceForReopenUpload))"
      )
      return
    }

    let openedAt = Date().toISO8601UTC()
    UserDefaults.standard.set(openedAt, forKey: pendingOpenedAtKey)
    UserDefaults.standard.synchronize()
    if ((UserDefaults.standard.string(forKey: lastWakeServiceKey) ?? "").isEmpty) {
      recordWakeService("user_open", detail: "UI became active after kill (no prior location wake)")
    }
    let wake = UserDefaults.standard.string(forKey: lastWakeServiceKey) ?? "unknown"
    appendDebugLog(
      "queued opened_at=\(openedAt) (from killed state) wake_service=\(wake)"
    )
  }

  /// Stamp opened_at if needed and return full timeline for Flutter reopen upload.
  func prepareTimelineForReopen() -> [String: String]? {
    // Flutter resume can run while UI is already active but after we missed the
    // inactive→active scene callback — claim real foreground if safe.
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      _ = appDelegate.claimRealUserForegroundIfActive()
    }
    markOpenedAfterKillIfNeeded(forceForReopenUpload: true)
    let timeline = peekTimeline()
    appendDebugLog("prepareTimelineForReopen=\(String(describing: timeline))")
    return timeline
  }

  /// Backup if Flutter does not clear the kill-reopen queue in time.
  func scheduleReopenFlushBackup() {
    guard pendingKilledAt() != nil else { return }
    markOpenedAfterKillIfNeeded(forceForReopenUpload: true)
    // Backup sooner so it still runs before Flutter delayed clear (~8s).
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) { [weak self] in
      guard let self else { return }
      guard self.pendingKilledAt() != nil else {
        self.appendDebugLog("reopen backup skip; Flutter already cleared queue")
        return
      }
      self.markOpenedAfterKillIfNeeded(forceForReopenUpload: true)
      self.flushPendingIfNeeded(reason: "reopen_backup")
    }
  }

  /// Upload killed+opened only when both are queued.
  func flushPendingIfNeeded(reason: String) {
    guard let killedAt = pendingKilledAt() else { return }
    guard let openedAt = pendingOpenedAt() else {
      appendDebugLog(
        "flush skip (\(reason)); waiting for foreground open after kill"
      )
      return
    }

    lock.lock()
    if flushInFlight {
      lock.unlock()
      return
    }
    flushInFlight = true
    lock.unlock()

    appendDebugLog(
      "flush attempt (\(reason)) killed_at=\(killedAt) opened_at=\(openedAt)"
    )

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let ok = self.postAppCycleSync(
        appCycle: "resumed",
        killedAt: killedAt,
        openedAt: openedAt,
        timeout: self.reopenUploadTimeout
      )
      if ok {
        self.clearPending()
        self.appendDebugLog("timeline uploaded; queue cleared")
      } else {
        self.appendDebugLog("upload failed/offline; queue kept for retry")
      }
      self.lock.lock()
      self.flushInFlight = false
      self.lock.unlock()
    }
  }

  /// Snapshot for Flutter permission-status reopen upload (does not clear).
  func peekTimeline() -> [String: String]? {
    guard let killedAt = pendingKilledAt() else { return nil }
    var map: [String: String] = [
      "killed_at": killedAt,
    ]
    if let openedAt = pendingOpenedAt() {
      map["opened_at"] = openedAt
    }
    return map
  }

  /// Called after Flutter successfully POSTs the kill/reopen timeline.
  func clearPendingAfterFlutterUpload() {
    clearPending()
    appendDebugLog("pending cleared by Flutter upload")
  }

  private func pendingKilledAt() -> String? {
    let value = UserDefaults.standard.string(forKey: pendingKilledAtKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  private func pendingOpenedAt() -> String? {
    let value = UserDefaults.standard.string(forKey: pendingOpenedAtKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  private func clearPending() {
    UserDefaults.standard.removeObject(forKey: pendingKilledAtKey)
    UserDefaults.standard.removeObject(forKey: pendingOpenedAtKey)
    UserDefaults.standard.removeObject(forKey: killedUploadedKey)
    UserDefaults.standard.synchronize()
  }

  private func scheduleKillSecurityAlert(forceReschedule: Bool = false) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [killSecurityNotificationId])

    let content = UNMutableNotificationContent()
    content.title = "SMARTNPS360 APP CLOSED ⚠️"
    content.body = "SmartNPS360 was force-closed. Reopen the app immediately and keep it running in the background while on duty."
    content.sound = .default
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
    }

    // Short delay so willTerminate async add can complete; not used for background.
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: killSecurityAlertDelaySeconds,
      repeats: false
    )
    let request = UNNotificationRequest(
      identifier: killSecurityNotificationId,
      content: content,
      trigger: trigger
    )

    center.add(request) { [weak self] error in
      if let error {
        self?.appendDebugLog(
          "kill alert schedule failed: \(error.localizedDescription)"
        )
      } else {
        self?.appendDebugLog(
          "kill alert scheduled in \(Int(self?.killSecurityAlertDelaySeconds ?? 4))s (terminate)"
        )
      }
    }
  }

  private func cancelKillSecurityAlert(reason: String) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [killSecurityNotificationId])
    center.removeDeliveredNotifications(withIdentifiers: [killSecurityNotificationId])
    appendDebugLog("kill alert cancelled (\(reason))")
  }

  @discardableResult
  private func postAppCycleSync(
    appCycle: String,
    killedAt: String,
    openedAt: String?,
    timeout: TimeInterval,
    lightweight: Bool = false
  ) -> Bool {
    guard var token = readKeychain(account: accessTokenAccount), !token.isEmpty else {
      appendDebugLog("skip upload; no access token")
      return false
    }

    var payload = buildPayload(
      appCycle: appCycle,
      killedAt: killedAt,
      openedAt: openedAt,
      lightweight: lightweight
    )
    var result = postJSONSync(
      url: permissionStatusURL,
      token: token,
      body: payload,
      timeout: timeout
    )

    if result.statusCode == 401 || result.statusCode == 403 {
      if refreshAccessTokenSync(timeout: min(timeout, 2)) {
        token = readKeychain(account: accessTokenAccount) ?? token
        payload = buildPayload(
          appCycle: appCycle,
          killedAt: killedAt,
          openedAt: openedAt,
          lightweight: lightweight
        )
        result = postJSONSync(
          url: permissionStatusURL,
          token: token,
          body: payload,
          timeout: timeout
        )
      }
    }

    let ok = (200...299).contains(result.statusCode)
    if ok {
      appendDebugLog(
        "POST permission-status app_cycle=\(appCycle) status=\(result.statusCode)"
          + " lightweight=\(lightweight)"
      )
    } else {
      let bodyPreview: String
      if let data = result.data,
         let text = String(data: data, encoding: .utf8),
         !text.isEmpty
      {
        bodyPreview = String(text.prefix(240))
      } else {
        bodyPreview = "(empty)"
      }
      appendDebugLog(
        "POST permission-status app_cycle=\(appCycle) status=\(result.statusCode)"
          + " lightweight=\(lightweight) body=\(bodyPreview)"
      )
    }
    return ok
  }

  private func buildPayload(
    appCycle: String,
    killedAt: String,
    openedAt: String?,
    lightweight: Bool
  ) -> [String: Any] {
    let info = Bundle.main.infoDictionary
    let version = (info?["CFBundleShortVersionString"] as? String) ?? ""
    let build = (info?["CFBundleVersion"] as? String) ?? ""
    let deviceIdRaw = UserDefaults.standard.string(forKey: deviceIdDefaultsKey) ?? ""
    let deviceId = deviceIdRaw.isEmpty
      ? (UIDevice.current.identifierForVendor?.uuidString ?? "")
      : deviceIdRaw

    var payload: [String: Any] = [
      "platform": "ios",
      "appVersion": version,
      "build": build,
      "app_cycle": appCycle,
      "killed_at": killedAt,
      "checkedAt": Date().toISO8601UTC(),
      "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled
        ? "enabled" : "disabled",
      "permissions": lightweight
        ? cachedOrMinimalPermissionsSnapshot()
        : lightPermissionsSnapshot(),
    ]
    // deviceId is required by API — never omit.
    payload["deviceId"] = deviceId.isEmpty ? "unknown-ios-device" : deviceId
    if let openedAt, !openedAt.isEmpty {
      payload["opened_at"] = openedAt
    }
    let deviceName = UIDevice.current.name
    if !deviceName.isEmpty {
      payload["deviceName"] = deviceName
    }
    return payload
  }

  private func cachePermissionsSnapshot() {
    UserDefaults.standard.set(lightPermissionsSnapshot(), forKey: cachedPermissionsKey)
  }

  /// Called from Flutter whenever a full permission payload is built while alive.
  func cacheFullPermissionsSnapshot(_ permissions: [String: String]) {
    guard !permissions.isEmpty else { return }
    UserDefaults.standard.set(sanitizePermissions(permissions), forKey: fullCachedPermissionsKey)
    UserDefaults.standard.synchronize()
    appendDebugLog("cached full permission snapshot (\(permissions.count) keys)")
  }

  private func cachedOrMinimalPermissionsSnapshot() -> [String: String] {
    // Prefer last full Flutter snapshot (real denied/granted), then light, then minimal.
    if let full = UserDefaults.standard.dictionary(forKey: fullCachedPermissionsKey)
      as? [String: String],
      !full.isEmpty
    {
      return sanitizePermissions(full)
    }
    if let cached = UserDefaults.standard.dictionary(forKey: cachedPermissionsKey)
      as? [String: String],
      !cached.isEmpty
    {
      return sanitizePermissions(cached)
    }
    return sanitizePermissions(minimalPermissionsSnapshot())
  }

  /// API accepts only documented enums — never `not_applicable` / push `unknown`.
  private func sanitizePermissions(_ raw: [String: String]) -> [String: String] {
    var permissions = raw
    let push = permissions["push"] ?? "enabled"
    permissions["push"] = (push == "disabled") ? "disabled" : "enabled"
    let batteryOpt = permissions["batteryOptimization"] ?? "unknown"
    permissions["batteryOptimization"] =
      (batteryOpt == "granted") ? "granted" : "unknown"
    let bar = permissions["backgroundAppRefresh"] ?? "unknown"
    if !["enabled", "disabled", "restricted", "unknown"].contains(bar) {
      permissions["backgroundAppRefresh"] = "unknown"
    }
    for key in [
      "foregroundLocation", "backgroundLocation", "preciseLocation",
      "notifications", "motionActivity",
    ] {
      let value = permissions[key] ?? "unknown"
      if !["granted", "denied", "unknown"].contains(value) {
        permissions[key] = "unknown"
      }
    }
    return permissions
  }

  private func minimalPermissionsSnapshot() -> [String: String] {
    // Fast fallback — location auth only (no notification / motion probes).
    var permissions: [String: String] = [
      "foregroundLocation": "unknown",
      "backgroundLocation": "unknown",
      "preciseLocation": "unknown",
      "notifications": "unknown",
      "motionActivity": "unknown",
      "batteryOptimization": "unknown",
      "backgroundAppRefresh": "unknown",
      "push": UserDefaults.standard.string(forKey: "smartnps360.ios_duty.push")
        ?? "enabled",
    ]
    switch CLLocationManager.authorizationStatus() {
    case .authorizedAlways:
      permissions["foregroundLocation"] = "granted"
      permissions["backgroundLocation"] = "granted"
    case .authorizedWhenInUse:
      permissions["foregroundLocation"] = "granted"
      permissions["backgroundLocation"] = "denied"
    case .denied, .restricted:
      permissions["foregroundLocation"] = "denied"
      permissions["backgroundLocation"] = "denied"
    case .notDetermined:
      break
    @unknown default:
      break
    }
    switch UIApplication.shared.backgroundRefreshStatus {
    case .available:
      permissions["backgroundAppRefresh"] = "enabled"
    case .denied:
      permissions["backgroundAppRefresh"] = "disabled"
    case .restricted:
      permissions["backgroundAppRefresh"] = "restricted"
    @unknown default:
      permissions["backgroundAppRefresh"] = "unknown"
    }
    return permissions
  }

  private func lightPermissionsSnapshot() -> [String: String] {
    var permissions: [String: String] = [
      "foregroundLocation": "unknown",
      "backgroundLocation": "unknown",
      "preciseLocation": "unknown",
      "notifications": "unknown",
      "motionActivity": "unknown",
      "batteryOptimization": "unknown",
      "backgroundAppRefresh": backgroundAppRefreshStatus(),
      "push": UserDefaults.standard.string(forKey: "smartnps360.ios_duty.push")
        ?? "enabled",
    ]

    switch CLLocationManager.authorizationStatus() {
    case .authorizedAlways:
      permissions["foregroundLocation"] = "granted"
      permissions["backgroundLocation"] = "granted"
    case .authorizedWhenInUse:
      permissions["foregroundLocation"] = "granted"
      permissions["backgroundLocation"] = "denied"
    case .denied, .restricted:
      permissions["foregroundLocation"] = "denied"
      permissions["backgroundLocation"] = "denied"
    case .notDetermined:
      break
    @unknown default:
      break
    }

    if #available(iOS 14.0, *) {
      let manager = CLLocationManager()
      switch manager.authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse:
        permissions["preciseLocation"] =
          manager.accuracyAuthorization == .fullAccuracy ? "granted" : "denied"
      default:
        permissions["preciseLocation"] = "unknown"
      }
    } else {
      permissions["preciseLocation"] = "granted"
    }

    return sanitizePermissions(permissions)
  }

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

  private func refreshAccessTokenSync(timeout: TimeInterval) -> Bool {
    guard let refresh = readKeychain(account: refreshTokenAccount), !refresh.isEmpty else {
      return false
    }
    let result = postJSONSync(
      url: refreshURL,
      token: nil,
      body: ["refresh_token": refresh],
      timeout: timeout
    )
    guard (200...299).contains(result.statusCode),
          let data = result.data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return false
    }
    let payload = (json["data"] as? [String: Any]) ?? json
    guard let access = firstString(payload, keys: ["access_token", "accessToken", "token"]),
          !access.isEmpty
    else {
      return false
    }
    writeKeychain(account: accessTokenAccount, value: access)
    if let newRefresh = firstString(payload, keys: ["refresh_token", "refreshToken"]),
       !newRefresh.isEmpty
    {
      writeKeychain(account: refreshTokenAccount, value: newRefresh)
    }
    return true
  }

  private struct HttpResult {
    let statusCode: Int
    let data: Data?
  }

  private func postJSONSync(
    url: URL,
    token: String?,
    body: [String: Any],
    timeout: TimeInterval
  ) -> HttpResult {
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
      return HttpResult(statusCode: 0, data: nil)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = timeout
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let semaphore = DispatchSemaphore(value: 0)
    var statusCode = 0
    var responseData: Data?

    session.dataTask(with: request) { data, response, _ in
      statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      responseData = data
      semaphore.signal()
    }.resume()

    _ = semaphore.wait(timeout: .now() + timeout)
    return HttpResult(statusCode: statusCode, data: responseData)
  }

  private func firstString(_ map: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = map[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return nil
  }

  private func writeKeychain(account: String, value: String) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var add = query
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }

  private func readKeychain(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

private extension Date {
  func toISO8601UTC() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    // Millisecond-resolution clock; pad the microsecond part with 000 to match
    // the 6-digit ISO-8601 used by updated_at (e.g. ...:00.123000Z).
    return formatter.string(from: self) + "000Z"
  }
}
