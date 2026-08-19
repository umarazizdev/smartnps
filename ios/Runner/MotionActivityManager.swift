import CoreMotion
import Flutter
import Foundation

/// Streams Core Motion activity updates to Flutter via EventChannel.
final class MotionActivityManager: NSObject, FlutterStreamHandler {
  static let methodChannelName = "com.smartnps360.app/motion_activity"
  static let eventChannelName = "com.smartnps360.app/motion_activity_events"

  private let activityManager = CMMotionActivityManager()
  private let activityQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.smartnps360.app.motion_activity"
    queue.maxConcurrentOperationCount = 1
    // Prefer snappy delivery for the Motion UI / fusion.
    queue.qualityOfService = .userInitiated
    return queue
  }()

  private let onDutyKey = "smartnps360.ios_duty.on_duty"

  private var eventSink: FlutterEventSink?
  private var isStreaming = false
  private var methodChannel: FlutterMethodChannel?
  private var lastPayload: [String: Any]?
  private var lastSignificantActivity: String?

  /// Called on walking / running / driving / cycling while on duty.
  var onSignificantMotion: ((String) -> Void)?

  var running: Bool { isStreaming }

  func register(with messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    methodChannel = methods
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }

    let events = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: messenger
    )
    events.setStreamHandler(self)
  }

  func dispose() {
    stopDutyUpdates()
    methodChannel?.setMethodCallHandler(nil)
    methodChannel = nil
    eventSink = nil
  }

  @discardableResult
  func startDutyUpdates() -> [String: Any] {
    return startUpdates()
  }

  func stopDutyUpdates() {
    stopUpdates()
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    if let lastPayload {
      DispatchQueue.main.async {
        events(lastPayload)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    // Clear sink only — duty GPS / fusion may still need recognition.
    // Flutter stops explicitly via MethodChannel stop().
    eventSink = nil
    return nil
  }

  // MARK: - MethodChannel

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(CMMotionActivityManager.isActivityAvailable())
    case "checkPermission":
      result(permissionStatusString())
    case "requestPermission":
      requestPermission(result: result)
    case "start":
      result(startUpdates())
    case "stop":
      stopUpdates()
      result(["ok": true, "running": false])
    case "isRunning":
      result(["ok": true, "running": isStreaming])
    case "queryLatest":
      queryLatest(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func permissionStatusString() -> String {
    if #available(iOS 11.0, *) {
      switch CMMotionActivityManager.authorizationStatus() {
      case .authorized:
        return "granted"
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
    return CMMotionActivityManager.isActivityAvailable() ? "granted" : "unavailable"
  }

  /// Triggers the system Motion & Fitness prompt when status is notDetermined.
  private func requestPermission(result: @escaping FlutterResult) {
    guard CMMotionActivityManager.isActivityAvailable() else {
      result("unavailable")
      return
    }

    if #available(iOS 11.0, *) {
      let status = CMMotionActivityManager.authorizationStatus()
      if status == .authorized {
        result("granted")
        return
      }
      if status == .denied || status == .restricted {
        result(permissionStatusString())
        return
      }
    }

    let now = Date()
    activityManager.queryActivityStarting(
      from: now.addingTimeInterval(-60),
      to: now,
      to: activityQueue
    ) { [weak self] _, error in
      DispatchQueue.main.async {
        if let error = error as NSError?,
          error.domain == CMErrorDomain,
          error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue)
        {
          result("denied")
          return
        }
        result(self?.permissionStatusString() ?? "unknown")
      }
    }
  }

  private func startUpdates() -> [String: Any] {
    guard UserDefaults.standard.bool(forKey: onDutyKey) else {
      stopUpdates()
      return [
        "ok": false,
        "running": false,
        "onDuty": false,
        "error": [
          "code": "off_duty",
          "message": "Motion activity is only allowed while the officer is on duty",
        ],
      ]
    }

    guard CMMotionActivityManager.isActivityAvailable() else {
      return [
        "ok": false,
        "running": false,
        "error": [
          "code": "unavailable",
          "message": "Motion activity recognition is not available on this device",
        ],
      ]
    }

    if #available(iOS 11.0, *) {
      let status = CMMotionActivityManager.authorizationStatus()
      if status == .denied || status == .restricted {
        return [
          "ok": false,
          "running": false,
          "permission": permissionStatusString(),
          "error": [
            "code": "permission_denied",
            "message": "Motion & Fitness permission is required",
          ],
        ]
      }
    }

    if isStreaming {
      // Refresh snapshot so UI isn't stuck waiting for the next OS event.
      emitRecentSnapshot()
      return [
        "ok": true,
        "running": true,
        "permission": permissionStatusString(),
      ]
    }

    activityManager.startActivityUpdates(to: activityQueue) { [weak self] activity in
      guard let self = self, let activity = activity else { return }
      guard UserDefaults.standard.bool(forKey: self.onDutyKey) else {
        DispatchQueue.main.async {
          self.stopUpdates()
        }
        return
      }
      // Skip unknown-only samples when we already have a better last payload.
      let mapped = self.mapActivity(activity)
      if mapped.activity == "unknown", self.lastPayload != nil {
        // Still accept unknown if confidence is high (genuine unknown).
        if activity.confidence == .low {
          return
        }
      }
      let payload = self.payload(from: activity)
      self.lastPayload = payload
      DispatchQueue.main.async {
        self.eventSink?(payload)
        self.emitSignificantMotionIfNeeded(mapped.activity)
      }
    }
    isStreaming = true
    emitRecentSnapshot()

    return [
      "ok": true,
      "running": true,
      "permission": permissionStatusString(),
    ]
  }

  private func stopUpdates() {
    lastSignificantActivity = nil
    guard isStreaming else { return }
    activityManager.stopActivityUpdates()
    isStreaming = false
    NSLog("[SmartNPS360][Motion] stopped")
  }

  private func emitSignificantMotionIfNeeded(_ activity: String) {
    switch activity {
    case "walking", "running", "driving", "cycling":
      break
    default:
      lastSignificantActivity = activity
      return
    }
    if lastSignificantActivity == activity { return }
    lastSignificantActivity = activity
    onSignificantMotion?(activity)
  }

  /// Immediate historical query so the screen paints without waiting on live OS lag.
  private func queryLatest(result: @escaping FlutterResult) {
    guard CMMotionActivityManager.isActivityAvailable() else {
      result(["ok": false, "update": NSNull()])
      return
    }

    let now = Date()
    activityManager.queryActivityStarting(
      from: now.addingTimeInterval(-120),
      to: now,
      to: activityQueue
    ) { [weak self] activities, error in
      DispatchQueue.main.async {
        guard let self = self else {
          result(["ok": false, "update": NSNull()])
          return
        }
        if error != nil {
          result(["ok": true, "update": self.lastPayload as Any? ?? NSNull()])
          return
        }
        guard let best = self.pickBest(from: activities ?? []) else {
          result(["ok": true, "update": self.lastPayload as Any? ?? NSNull()])
          return
        }
        let payload = self.payload(from: best)
        self.lastPayload = payload
        self.eventSink?(payload)
        result(["ok": true, "update": payload])
      }
    }
  }

  private func emitRecentSnapshot() {
    let now = Date()
    activityManager.queryActivityStarting(
      from: now.addingTimeInterval(-90),
      to: now,
      to: activityQueue
    ) { [weak self] activities, _ in
      guard let self = self, let best = self.pickBest(from: activities ?? []) else { return }
      let payload = self.payload(from: best)
      self.lastPayload = payload
      DispatchQueue.main.async {
        self.eventSink?(payload)
      }
    }
  }

  /// Prefer the newest non-unknown activity; fall back to newest overall.
  private func pickBest(from activities: [CMMotionActivity]) -> CMMotionActivity? {
    guard !activities.isEmpty else { return nil }
    let sorted = activities.sorted { $0.startDate > $1.startDate }
    if let concrete = sorted.first(where: { activity in
      let mapped = mapActivity(activity).activity
      return mapped != "unknown"
    }) {
      return concrete
    }
    return sorted.first
  }

  private func payload(from activity: CMMotionActivity) -> [String: Any] {
    let mapped = mapActivity(activity)
    return [
      "activity": mapped.activity,
      "confidence": mapped.confidence,
      "timestampMs": Int64(activity.startDate.timeIntervalSince1970 * 1000),
      "source": "ios_core_motion",
      "raw": [
        "stationary": activity.stationary,
        "walking": activity.walking,
        "running": activity.running,
        "automotive": activity.automotive,
        "cycling": activity.cycling,
        "unknown": activity.unknown,
        "confidence": confidenceLabel(activity.confidence),
      ],
    ]
  }

  private func mapActivity(_ activity: CMMotionActivity) -> (activity: String, confidence: Int) {
    let confidence = confidencePercent(activity.confidence)

    // Prefer more specific motion states when multiple flags are set.
    if activity.running {
      return ("running", confidence)
    }
    if activity.cycling {
      return ("cycling", confidence)
    }
    if activity.automotive {
      return ("driving", confidence)
    }
    if activity.walking {
      return ("walking", confidence)
    }
    if activity.stationary {
      return ("stationary", confidence)
    }
    return ("unknown", confidence)
  }

  private func confidencePercent(_ confidence: CMMotionActivityConfidence) -> Int {
    switch confidence {
    case .high:
      return 90
    case .medium:
      return 60
    case .low:
      return 30
    @unknown default:
      return 0
    }
  }

  private func confidenceLabel(_ confidence: CMMotionActivityConfidence) -> String {
    switch confidence {
    case .high:
      return "high"
    case .medium:
      return "medium"
    case .low:
      return "low"
    @unknown default:
      return "unknown"
    }
  }
}
