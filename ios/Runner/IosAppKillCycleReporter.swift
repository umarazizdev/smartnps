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
  private let pendingSlcAwakenedAtKey = "smartnps360.ios_app_cycle.pending_slc_awakened_at"
  private let slcAwakenedUploadedKey = "smartnps360.ios_app_cycle.slc_awakened_uploaded"
  /// Terminate-time sync wait (iOS willTerminate ceiling).
  private let syncUploadTimeout: TimeInterval = 5
  /// Short reopen attempt; queue + retry is the reliability path, not a long wait.
  private let reopenUploadTimeout: TimeInterval = 5

  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 5
    config.timeoutIntervalForResource = 5
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
  }()

  private let lock = NSLock()
  private var flushInFlight = false
  private var slcFlushInFlight = false

  private init() {}

  /// Call from `applicationWillTerminate` while on duty and not unpaid break.
  func handleTerminateWhileOnDuty() {
    let killedAtIso = Date().toISO8601UTC()

    // Queue first — timeline must not depend on network.
    // opened_at / slc_awakened_at cleared; set only on those later events.
    UserDefaults.standard.set(killedAtIso, forKey: pendingKilledAtKey)
    UserDefaults.standard.removeObject(forKey: pendingOpenedAtKey)
    UserDefaults.standard.removeObject(forKey: pendingSlcAwakenedAtKey)
    UserDefaults.standard.set(false, forKey: slcAwakenedUploadedKey)
    UserDefaults.standard.synchronize()
    NSLog("[SmartNPS360][KillCycle] queued killed_at=\(killedAtIso)")

    scheduleLocalSecurityAlert()

    // Best-effort only; pending stays until reopen uploads the full pair.
    let uploaded = postAppCycleSync(
      appCycle: "killed",
      killedAt: killedAtIso,
      openedAt: nil,
      slcAwakenedAt: nil,
      timeout: syncUploadTimeout
    )
    NSLog(
      "[SmartNPS360][KillCycle] terminate upload \(uploaded ? "ok" : "missed"); "
        + "queue kept for killed_at+opened_at"
    )
  }

  /// SLC/geofence relaunch after a queued kill — not a user open.
  /// Uploads `app_cycle=slc_awakened`; does not set opened_at.
  func handleSlcAwakenedAfterKillIfNeeded() {
    guard let killedAt = pendingKilledAt() else {
      NSLog("[SmartNPS360][KillCycle] SLC wake ignored; not after killed state")
      return
    }
    if UserDefaults.standard.bool(forKey: slcAwakenedUploadedKey) {
      NSLog("[SmartNPS360][KillCycle] SLC awakened already uploaded for this kill")
      return
    }

    let awakenedAt: String
    if let existing = pendingSlcAwakenedAt() {
      awakenedAt = existing
    } else {
      awakenedAt = Date().toISO8601UTC()
      UserDefaults.standard.set(awakenedAt, forKey: pendingSlcAwakenedAtKey)
      UserDefaults.standard.synchronize()
      NSLog("[SmartNPS360][KillCycle] queued slc_awakened_at=\(awakenedAt)")
    }

    flushSlcAwakenedIfNeeded(
      reason: "slc_wake",
      killedAt: killedAt,
      awakenedAt: awakenedAt
    )
  }

  /// Only from `applicationDidBecomeActive` after a real kill queue exists.
  /// Does not run for normal background → foreground (no pending killed_at).
  func markOpenedAfterKillIfNeeded() {
    guard pendingKilledAt() != nil else { return }
    guard pendingOpenedAt() == nil else { return }
    guard UIApplication.shared.applicationState == .active else {
      NSLog("[SmartNPS360][KillCycle] skip opened_at; app not active (wake/background)")
      return
    }

    let openedAt = Date().toISO8601UTC()
    UserDefaults.standard.set(openedAt, forKey: pendingOpenedAtKey)
    UserDefaults.standard.synchronize()
    NSLog("[SmartNPS360][KillCycle] queued opened_at=\(openedAt) (from killed state)")
  }

  /// Upload killed+opened only when both are queued.
  func flushPendingIfNeeded(reason: String) {
    // Retry SLC awakened upload if still pending after a kill.
    if let killedAt = pendingKilledAt(),
       let awakenedAt = pendingSlcAwakenedAt(),
       !UserDefaults.standard.bool(forKey: slcAwakenedUploadedKey)
    {
      flushSlcAwakenedIfNeeded(
        reason: reason,
        killedAt: killedAt,
        awakenedAt: awakenedAt
      )
    }

    guard let killedAt = pendingKilledAt() else { return }
    guard let openedAt = pendingOpenedAt() else {
      NSLog(
        "[SmartNPS360][KillCycle] flush skip (\(reason)); "
          + "waiting for foreground open after kill"
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

    let slcAwakenedAt = pendingSlcAwakenedAt()
    NSLog(
      "[SmartNPS360][KillCycle] flush attempt (\(reason)) "
        + "killed_at=\(killedAt) opened_at=\(openedAt)"
    )

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let ok = self.postAppCycleSync(
        appCycle: "killed",
        killedAt: killedAt,
        openedAt: openedAt,
        slcAwakenedAt: slcAwakenedAt,
        timeout: self.reopenUploadTimeout
      )
      if ok {
        self.clearPending()
        NSLog("[SmartNPS360][KillCycle] timeline uploaded; queue cleared")
      } else {
        NSLog("[SmartNPS360][KillCycle] upload failed/offline; queue kept for retry")
      }
      self.lock.lock()
      self.flushInFlight = false
      self.lock.unlock()
    }
  }

  private func flushSlcAwakenedIfNeeded(
    reason: String,
    killedAt: String,
    awakenedAt: String
  ) {
    lock.lock()
    if slcFlushInFlight {
      lock.unlock()
      return
    }
    slcFlushInFlight = true
    lock.unlock()

    NSLog(
      "[SmartNPS360][KillCycle] SLC awakened upload (\(reason)) "
        + "killed_at=\(killedAt) slc_awakened_at=\(awakenedAt)"
    )

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let ok = self.postAppCycleSync(
        appCycle: "slc_awakened",
        killedAt: killedAt,
        openedAt: nil,
        slcAwakenedAt: awakenedAt,
        timeout: self.reopenUploadTimeout
      )
      if ok {
        UserDefaults.standard.set(true, forKey: self.slcAwakenedUploadedKey)
        UserDefaults.standard.synchronize()
        NSLog("[SmartNPS360][KillCycle] slc_awakened uploaded")
      } else {
        NSLog("[SmartNPS360][KillCycle] slc_awakened upload failed; queued for retry")
      }
      self.lock.lock()
      self.slcFlushInFlight = false
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
    if let slcAwakenedAt = pendingSlcAwakenedAt() {
      map["slc_awakened_at"] = slcAwakenedAt
    }
    return map
  }

  /// Called after Flutter successfully POSTs the kill/reopen timeline.
  func clearPendingAfterFlutterUpload() {
    clearPending()
    NSLog("[SmartNPS360][KillCycle] pending cleared by Flutter upload")
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

  private func pendingSlcAwakenedAt() -> String? {
    let value = UserDefaults.standard.string(forKey: pendingSlcAwakenedAtKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  private func clearPending() {
    UserDefaults.standard.removeObject(forKey: pendingKilledAtKey)
    UserDefaults.standard.removeObject(forKey: pendingOpenedAtKey)
    UserDefaults.standard.removeObject(forKey: pendingSlcAwakenedAtKey)
    UserDefaults.standard.removeObject(forKey: slcAwakenedUploadedKey)
    UserDefaults.standard.synchronize()
  }

  private func scheduleLocalSecurityAlert() {
    let content = UNMutableNotificationContent()
    content.title = "Test Security Alert"
    content.body = "The app was manually swiped up and killed!"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
      identifier: "smartnps360.terminate.test",
      content: content,
      trigger: trigger
    )
    UNUserNotificationCenter.current().add(request)
    NSLog("[SmartNPS360][KillCycle] scheduled local notification (+1s)")
  }

  @discardableResult
  private func postAppCycleSync(
    appCycle: String,
    killedAt: String,
    openedAt: String?,
    slcAwakenedAt: String?,
    timeout: TimeInterval
  ) -> Bool {
    guard var token = readKeychain(account: accessTokenAccount), !token.isEmpty else {
      NSLog("[SmartNPS360][KillCycle] skip upload; no access token")
      return false
    }

    var payload = buildPayload(
      appCycle: appCycle,
      killedAt: killedAt,
      openedAt: openedAt,
      slcAwakenedAt: slcAwakenedAt
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
          slcAwakenedAt: slcAwakenedAt
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
    NSLog(
      "[SmartNPS360][KillCycle] POST permission-status "
        + "app_cycle=\(appCycle) status=\(result.statusCode)"
    )
    return ok
  }

  private func buildPayload(
    appCycle: String,
    killedAt: String,
    openedAt: String?,
    slcAwakenedAt: String?
  ) -> [String: Any] {
    let info = Bundle.main.infoDictionary
    let version = (info?["CFBundleShortVersionString"] as? String) ?? ""
    let build = (info?["CFBundleVersion"] as? String) ?? ""
    let deviceId = UserDefaults.standard.string(forKey: deviceIdDefaultsKey) ?? ""

    var payload: [String: Any] = [
      "platform": "ios",
      "appVersion": version,
      "build": build,
      "app_cycle": appCycle,
      "killed_at": killedAt,
      "checkedAt": Date().toISO8601UTC(),
      "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled
        ? "enabled" : "disabled",
      "permissions": lightPermissionsSnapshot(),
    ]
    if !deviceId.isEmpty {
      payload["deviceId"] = deviceId
    }
    if let openedAt, !openedAt.isEmpty {
      payload["opened_at"] = openedAt
    }
    if let slcAwakenedAt, !slcAwakenedAt.isEmpty {
      payload["slc_awakened_at"] = slcAwakenedAt
    }
    let deviceName = UIDevice.current.name
    if !deviceName.isEmpty {
      payload["deviceName"] = deviceName
    }
    return payload
  }

  private func lightPermissionsSnapshot() -> [String: String] {
    var permissions: [String: String] = [
      "foregroundLocation": "unknown",
      "backgroundLocation": "unknown",
      "preciseLocation": "unknown",
      "notifications": "unknown",
      "motionActivity": "unknown",
      "batteryOptimization": "not_applicable",
      "backgroundAppRefresh": backgroundAppRefreshStatus(),
      "push": "unknown",
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

    return permissions
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
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: self)
  }
}
