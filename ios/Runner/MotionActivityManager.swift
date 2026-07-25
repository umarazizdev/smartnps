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
    queue.qualityOfService = .utility
    return queue
  }()

  private var eventSink: FlutterEventSink?
  private var isStreaming = false
  private var methodChannel: FlutterMethodChannel?

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
    stopUpdates()
    methodChannel?.setMethodCallHandler(nil)
    methodChannel = nil
    eventSink = nil
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    stopUpdates()
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
      return [
        "ok": true,
        "running": true,
        "permission": permissionStatusString(),
      ]
    }

    activityManager.startActivityUpdates(to: activityQueue) { [weak self] activity in
      guard let self = self, let activity = activity else { return }
      let payload = self.payload(from: activity)
      DispatchQueue.main.async {
        self.eventSink?(payload)
      }
    }
    isStreaming = true

    return [
      "ok": true,
      "running": true,
      "permission": permissionStatusString(),
    ]
  }

  private func stopUpdates() {
    guard isStreaming else { return }
    activityManager.stopActivityUpdates()
    isStreaming = false
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
