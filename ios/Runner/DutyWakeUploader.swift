import CoreLocation
import Foundation
import Security
import UIKit

/// Native heartbeat + GPS ping used after SLC/geofence relaunch.
/// Never uploads unless the API confirms the officer is on duty.
final class DutyWakeUploader {
  static let shared = DutyWakeUploader()

  private let heartbeatURL = URL(string: "https://smartnps360.com/api/heartbeat")!
  private let pingURL = URL(string: "https://smartnps360.com/api/gps/ping")!
  private let refreshURL = URL(string: "https://smartnps360.com/api/auth/refresh")!
  private let keychainService = "com.smartnps360.app.native-duty"
  private let accessTokenAccount = "access_token"
  private let refreshTokenAccount = "refresh_token"
  private let deviceIdDefaultsKey = "smartnps360.ios_duty.device_id"
  private let onDutyDefaultsKey = "smartnps360.ios_duty.on_duty"
  private let slcEnabledDefaultsKey = "smartnps360.ios_slc.enabled"
  private let maxAccuracyMeters: CLLocationAccuracy = 50

  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 12
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
  }()

  private let lock = NSLock()
  private var inFlight = false
  private var waitingForGps = false
  private var flutterOwnsWake = false
  private var cancelled = false
  private var fallbackWorkItem: DispatchWorkItem?
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid

  var onConfirmedOffDuty: (() -> Void)?
  var onDutyConfirmed: (() -> Void)?
  var onNeedsGps: (() -> Void)?

  private init() {}

  func syncSession(accessToken: String?, refreshToken: String?, deviceId: String?) {
    if let accessToken, !accessToken.isEmpty {
      writeKeychain(account: accessTokenAccount, value: accessToken)
    }
    if let refreshToken, !refreshToken.isEmpty {
      writeKeychain(account: refreshTokenAccount, value: refreshToken)
    }
    if let deviceId, !deviceId.isEmpty {
      UserDefaults.standard.set(deviceId, forKey: deviceIdDefaultsKey)
    }
  }

  func clearSession() {
    deleteKeychain(account: accessTokenAccount)
    deleteKeychain(account: refreshTokenAccount)
    UserDefaults.standard.removeObject(forKey: deviceIdDefaultsKey)
    cancel()
  }

  func cancel() {
    fallbackWorkItem?.cancel()
    fallbackWorkItem = nil
    lock.lock()
    cancelled = true
    inFlight = false
    waitingForGps = false
    lock.unlock()
    endBackgroundTask()
  }

  /// Flutter is alive and will handle GPS. Native ping must not run.
  func claimByFlutter() {
    lock.lock()
    flutterOwnsWake = true
    lock.unlock()
    NSLog("[SmartNPS360][WakeUpload] Flutter claimed wake; native ping skipped")
    cancel()
  }

  /// Prefer Flutter. Native ping runs only if Flutter does not claim in time.
  func beginLocationWake(flutterTimeout: TimeInterval = 3) {
    fallbackWorkItem?.cancel()
    lock.lock()
    flutterOwnsWake = false
    cancelled = false
    inFlight = false
    waitingForGps = false
    lock.unlock()

    let work = DispatchWorkItem { [weak self] in
      self?.startAfterLocationWake()
    }
    fallbackWorkItem = work
    NSLog("[SmartNPS360][WakeUpload] waiting \(Int(flutterTimeout))s for Flutter before native ping")
    DispatchQueue.main.asyncAfter(deadline: .now() + flutterTimeout, execute: work)
  }

  /// Called only after iOS relaunches for SLC/geofence and Flutter missed the window.
  func startAfterLocationWake() {
    lock.lock()
    let skip = flutterOwnsWake || cancelled
    lock.unlock()
    guard !skip else {
      NSLog("[SmartNPS360][WakeUpload] skipped; Flutter owns wake or cancelled")
      return
    }

    guard UserDefaults.standard.bool(forKey: onDutyDefaultsKey),
          UserDefaults.standard.bool(forKey: slcEnabledDefaultsKey)
    else {
      NSLog("[SmartNPS360][WakeUpload] skipped; native duty/slc not armed")
      return
    }

    lock.lock()
    if inFlight {
      lock.unlock()
      return
    }
    inFlight = true
    waitingForGps = false
    lock.unlock()

    beginBackgroundTask()
    NSLog("[SmartNPS360][WakeUpload] confirming duty before native GPS ping")

    confirmDuty { [weak self] status in
      guard let self else { return }
      if self.shouldSkipNativeWork() {
        NSLog("[SmartNPS360][WakeUpload] Flutter claimed during heartbeat; native ping skipped")
        self.finish()
        return
      }
      switch status {
      case .offDuty:
        NSLog("[SmartNPS360][WakeUpload] heartbeat off_duty; stopping native services")
        self.finish()
        DispatchQueue.main.async {
          self.onConfirmedOffDuty?()
        }
      case .onDuty:
        if self.shouldSkipNativeWork() {
          self.finish()
          return
        }
        NSLog("[SmartNPS360][WakeUpload] heartbeat on_duty; requesting GPS")
        self.lock.lock()
        self.waitingForGps = true
        self.lock.unlock()
        DispatchQueue.main.async {
          self.onDutyConfirmed?()
          self.onNeedsGps?()
        }
      case .unknown:
        NSLog("[SmartNPS360][WakeUpload] duty unknown; not uploading")
        self.finish()
      }
    }
  }

  /// True while the native wake ping is waiting for a GPS fix ≤50m.
  var wantsWakeGps: Bool {
    lock.lock()
    defer { lock.unlock() }
    return waitingForGps && inFlight && !flutterOwnsWake && !cancelled
  }

  /// Returns true when this GPS fix was consumed for the native wake ping.
  func consumeWakeGps(_ location: CLLocation) -> Bool {
    lock.lock()
    let waiting = waitingForGps && inFlight && !flutterOwnsWake && !cancelled
    lock.unlock()
    guard waiting else { return false }

    guard UserDefaults.standard.bool(forKey: onDutyDefaultsKey),
          UserDefaults.standard.bool(forKey: slcEnabledDefaultsKey)
    else {
      NSLog("[SmartNPS360][WakeUpload] GPS ignored; no longer on duty")
      finish()
      return true
    }

    guard location.horizontalAccuracy > 0,
          location.horizontalAccuracy <= maxAccuracyMeters
    else {
      NSLog(
        "[SmartNPS360][WakeUpload] GPS acc=\(location.horizontalAccuracy)m held; waiting for a tighter fix"
      )
      return false
    }

    lock.lock()
    waitingForGps = false
    lock.unlock()
    uploadPing(location)
    return true
  }

  private enum DutyStatus {
    case onDuty
    case offDuty
    case unknown
  }

  private func confirmDuty(completion: @escaping (DutyStatus) -> Void) {
    authorizedRequest(url: heartbeatURL, method: "GET", body: nil) { [weak self] data, statusCode in
      guard let self else {
        completion(.unknown)
        return
      }
      if statusCode == 401 || statusCode == 403 {
        self.refreshAccessToken { refreshed in
          guard refreshed else {
            completion(.unknown)
            return
          }
          self.authorizedRequest(url: self.heartbeatURL, method: "GET", body: nil) { data, statusCode in
            completion(self.parseDutyStatus(data: data, statusCode: statusCode))
          }
        }
        return
      }
      completion(self.parseDutyStatus(data: data, statusCode: statusCode))
    }
  }

  private func parseDutyStatus(data: Data?, statusCode: Int) -> DutyStatus {
    guard (200..<300).contains(statusCode), let data else { return .unknown }
    if let text = String(data: data, encoding: .utf8) {
      let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if normalized == "on_duty" { return .onDuty }
      if normalized == "off_duty" { return .offDuty }
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) else {
      return .unknown
    }
    return parseDutyValue(json)
  }

  private func parseDutyValue(_ value: Any) -> DutyStatus {
    if let text = value as? String {
      return normalizeDuty(text)
    }
    guard let map = value as? [String: Any] else { return .unknown }
    for key in ["status", "duty_status", "dutyStatus", "duty", "state"] {
      if let nested = map[key] {
        let parsed = parseDutyValue(nested)
        if parsed != .unknown { return parsed }
      }
    }
    for key in ["data", "payload", "result"] {
      if let nested = map[key] {
        let parsed = parseDutyValue(nested)
        if parsed != .unknown { return parsed }
      }
    }
    return .unknown
  }

  private func normalizeDuty(_ raw: String) -> DutyStatus {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "on_duty" || value == "onduty" || value == "on-duty" {
      return .onDuty
    }
    if value == "off_duty" || value == "offduty" || value == "off-duty" {
      return .offDuty
    }
    return .unknown
  }

  private func shouldSkipNativeWork() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return flutterOwnsWake || cancelled
  }

  private func uploadPing(_ location: CLLocation) {
    if shouldSkipNativeWork() {
      NSLog("[SmartNPS360][WakeUpload] ping aborted; Flutter owns wake")
      finish()
      return
    }
    guard UserDefaults.standard.bool(forKey: onDutyDefaultsKey) else {
      NSLog("[SmartNPS360][WakeUpload] ping aborted; off duty")
      finish()
      return
    }

    let recordedAt = location.timestamp.toISO8601UTC()
    let timestampMs = Int64(location.timestamp.timeIntervalSince1970 * 1000)
    let deviceId = UserDefaults.standard.string(forKey: deviceIdDefaultsKey) ?? ""
    var body: [String: Any] = [
      "app": "SmartNPS360",
      "platform": "ios",
      "source": "ios_native_wake",
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "timestampMs": timestampMs,
      "timestamp": recordedAt,
      "altitude": location.altitude,
    ]
    if !deviceId.isEmpty {
      body["device_id"] = deviceId
      body["deviceId"] = deviceId
    }
    if location.speed >= 0 {
      body["speed"] = location.speed
    }
    if location.course >= 0 {
      body["heading"] = location.course
    }

    authorizedRequest(url: pingURL, method: "POST", body: body) { [weak self] _, statusCode in
      NSLog("[SmartNPS360][WakeUpload] ping status=\(statusCode)")
      self?.finish()
    }
  }

  private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
    guard let refresh = readKeychain(account: refreshTokenAccount), !refresh.isEmpty else {
      completion(false)
      return
    }
    postJSON(url: refreshURL, headers: ["Accept": "application/json"], body: [
      "refresh_token": refresh,
    ]) { [weak self] data, statusCode in
      guard let self, (200..<300).contains(statusCode), let data else {
        completion(false)
        return
      }
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let payload = (json?["data"] as? [String: Any]) ?? json
      let access = (payload?["access_token"] ?? payload?["accessToken"] ?? payload?["token"]) as? String
      let newRefresh = (payload?["refresh_token"] ?? payload?["refreshToken"]) as? String
      guard let access, !access.isEmpty else {
        completion(false)
        return
      }
      self.writeKeychain(account: self.accessTokenAccount, value: access)
      if let newRefresh, !newRefresh.isEmpty {
        self.writeKeychain(account: self.refreshTokenAccount, value: newRefresh)
      }
      completion(true)
    }
  }

  private func authorizedRequest(
    url: URL,
    method: String,
    body: [String: Any]?,
    completion: @escaping (Data?, Int) -> Void
  ) {
    guard let token = readKeychain(account: accessTokenAccount), !token.isEmpty else {
      NSLog("[SmartNPS360][WakeUpload] no access token")
      completion(nil, 0)
      return
    }
    var headers = [
      "Accept": "application/json",
      "Authorization": "Bearer \(token)",
    ]
    if method == "POST" {
      headers["Content-Type"] = "application/json"
    }
    if method == "GET" {
      get(url: url, headers: headers, completion: completion)
      return
    }
    postJSON(url: url, headers: headers, body: body ?? [:], completion: completion)
  }

  private func get(
    url: URL,
    headers: [String: String],
    completion: @escaping (Data?, Int) -> Void
  ) {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    session.dataTask(with: request) { data, response, _ in
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      completion(data, code)
    }.resume()
  }

  private func postJSON(
    url: URL,
    headers: [String: String],
    body: [String: Any],
    completion: @escaping (Data?, Int) -> Void
  ) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    session.dataTask(with: request) { data, response, _ in
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      completion(data, code)
    }.resume()
  }

  private func finish() {
    lock.lock()
    inFlight = false
    waitingForGps = false
    lock.unlock()
    endBackgroundTask()
  }

  private func beginBackgroundTask() {
    endBackgroundTask()
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "smartnps360.duty.wake-upload") {
      self.finish()
    }
  }

  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
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

  private func deleteKeychain(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
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
