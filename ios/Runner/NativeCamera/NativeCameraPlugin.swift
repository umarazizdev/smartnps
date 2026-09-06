import AVFoundation
import Flutter
import UIKit

/// MethodChannel bridge for the native AVFoundation camera UI.
final class NativeCameraPlugin: NSObject {
  static let methodChannelName = "com.smartnps360.app/native_camera"
  static let logPrefix = "[SmartNPS360Camera]"

  private var channel: FlutterMethodChannel?
  private var isPresenting = false

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    NSLog("\(Self.logPrefix) plugin registered")
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      openCamera(arguments: call.arguments, result: result)
    case "getCapabilities":
      getCapabilities(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getCapabilities(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let type = (args?["type"] as? String)?.lowercased() ?? "photo"
    let forVideo = type == "video"
    DispatchQueue.global(qos: .userInitiated).async {
      let caps = NativeCameraSession.probeCapabilities(forVideo: forVideo)
      DispatchQueue.main.async {
        result(caps.asDictionary())
      }
    }
  }

  private func openCamera(arguments: Any?, result: @escaping FlutterResult) {
    guard !isPresenting else {
      result(
        FlutterError(
          code: "camera_in_use",
          message: "Native camera is already open",
          details: nil
        )
      )
      return
    }

    let args = arguments as? [String: Any] ?? [:]
    let type = (args["type"] as? String)?.lowercased() ?? "photo"
    let initialIsVideo = type == "video"
    let allowModeSwitch = args["allowModeSwitch"] as? Bool ?? true
    let landscapeOnly = args["landscapeOnly"] as? Bool ?? true
    // Photos always capture on the rear camera; this flag only gates video flip.
    let rearCameraOnly = args["rearCameraOnly"] as? Bool ?? true
    let qualityRaw = (args["quality"] as? String)?.lowercased() ?? "maximum"
    let quality = NativeCameraCaptureQuality(rawValue: qualityRaw) ?? .maximum
    let preferHeic = args["preferHeic"] as? Bool ?? false

    NSLog(
      "\(Self.logPrefix) CAMERA_OPEN_REQUEST type=\(type) modeSwitch=\(allowModeSwitch) "
        + "landscapeOnly=\(landscapeOnly) rearOnly=\(rearCameraOnly) "
        + "quality=\(quality.rawValue) preferHeic=\(preferHeic)"
    )

    ensurePermissions(needsMicrophone: initialIsVideo || allowModeSwitch) { [weak self] permissionError in
      guard let self else { return }
      if let permissionError {
        result(permissionError)
        return
      }

      DispatchQueue.main.async {
        self.presentCamera(
          configuration: NativeCameraViewController.Configuration(
            initialIsVideo: initialIsVideo,
            allowModeSwitch: allowModeSwitch,
            landscapeOnly: landscapeOnly,
            rearCameraOnly: rearCameraOnly,
            quality: quality,
            preferHeic: preferHeic
          ),
          result: result
        )
      }
    }
  }

  private func presentCamera(
    configuration: NativeCameraViewController.Configuration,
    result: @escaping FlutterResult
  ) {
    guard let presenter = Self.topViewController() else {
      result(
        FlutterError(
          code: "init_failed",
          message: "Unable to find a view controller to present the camera",
          details: nil
        )
      )
      return
    }

    isPresenting = true
    let camera = NativeCameraViewController(configuration: configuration)
    camera.onFinish = { [weak self] outcome in
      guard let self else { return }
      self.isPresenting = false
      switch outcome {
      case .success(let payload):
        let mapped = Self.mapResultPayload(payload)
        NSLog(
          "\(Self.logPrefix) capture success path=\(mapped["path"] ?? "") "
            + "mode=\(mapped["captureMode"] ?? "-") "
            + "dims=\(mapped["photoDimensions"] ?? "-") "
            + "position=\(mapped["cameraPosition"] ?? "-") "
            + "fallback=\(mapped["fallbackLevel"] ?? "none")"
        )
        result(mapped)
      case .canceled:
        NSLog("\(Self.logPrefix) capture canceled")
        result(["canceled": true])
      case .failure(let code, let message):
        NSLog("\(Self.logPrefix) capture failure \(code): \(message)")
        result(FlutterError(code: code, message: message, details: nil))
      }
    }

    presenter.present(camera, animated: true)
  }

  /// Session metadata is already wire-shaped. Defaults for optional diagnostics
  /// keys only — never fabricate `cameraPosition` (rear fail-closed depends on it).
  private static func mapResultPayload(_ payload: [String: Any]) -> [String: Any] {
    var mapped = payload
    if mapped["captureMode"] == nil {
      mapped["captureMode"] = "avfoundation_quality"
    }
    // Do NOT invent cameraPosition = "back". Missing/unknown must stay missing
    // so Flutter + native rear-only PHOTO validation can reject unverified media.
    if mapped["photoDimensions"] == nil,
       let width = mapped["width"] as? Int,
       let height = mapped["height"] as? Int,
       width > 0,
       height > 0
    {
      mapped["photoDimensions"] = "\(width)x\(height)"
    }
    return mapped
  }

  private func ensurePermissions(
    needsMicrophone: Bool,
    completion: @escaping (FlutterError?) -> Void
  ) {
    let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    switch cameraStatus {
    case .authorized:
      ensureMicrophoneIfNeeded(needsMicrophone: needsMicrophone, completion: completion)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        if granted {
          self.ensureMicrophoneIfNeeded(needsMicrophone: needsMicrophone, completion: completion)
        } else {
          completion(
            FlutterError(
              code: "permission_denied",
              message: "Camera permission denied",
              details: nil
            )
          )
        }
      }
    case .denied:
      completion(
        FlutterError(
          code: "permission_permanently_denied",
          message: "Camera permission permanently denied",
          details: nil
        )
      )
    case .restricted:
      completion(
        FlutterError(
          code: "permission_denied",
          message: "Camera permission restricted",
          details: nil
        )
      )
    @unknown default:
      completion(
        FlutterError(
          code: "unknown",
          message: "Unknown camera permission state",
          details: nil
        )
      )
    }
  }

  private func ensureMicrophoneIfNeeded(
    needsMicrophone: Bool,
    completion: @escaping (FlutterError?) -> Void
  ) {
    guard needsMicrophone else {
      completion(nil)
      return
    }

    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
      completion(nil)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        if granted {
          completion(nil)
        } else {
          completion(
            FlutterError(
              code: "microphone_permission_denied",
              message: "Microphone permission denied",
              details: nil
            )
          )
        }
      }
    case .denied, .restricted:
      completion(
        FlutterError(
          code: "microphone_permission_denied",
          message: "Microphone permission denied",
          details: nil
        )
      )
    @unknown default:
      completion(
        FlutterError(
          code: "microphone_permission_denied",
          message: "Unknown microphone permission state",
          details: nil
        )
      )
    }
  }

  private static func topViewController(
    base: UIViewController? = nil
  ) -> UIViewController? {
    let root: UIViewController?
    if let base {
      root = base
    } else if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let window = scenes
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
        ?? scenes.flatMap(\.windows).first
      root = window?.rootViewController
    } else {
      root = UIApplication.shared.keyWindow?.rootViewController
    }

    if let nav = root as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(base: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(base: presented)
    }
    return root
  }
}
