import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum NativeCameraFlashMode: Int, CaseIterable {
  case off
  case on
  case auto

  var next: NativeCameraFlashMode {
    switch self {
    case .off: return .on
    case .on: return .auto
    case .auto: return .off
    }
  }

  var avFlashMode: AVCaptureDevice.FlashMode {
    switch self {
    case .off: return .off
    case .on: return .on
    case .auto: return .auto
    }
  }

  var title: String {
    switch self {
    case .off: return "Off"
    case .on: return "On"
    case .auto: return "Auto"
    }
  }
}

enum NativeCameraCaptureQuality: String {
  case maximum
  case balanced
}

struct NativeCameraZoomChip: Equatable {
  /// Factor passed to AVCaptureDevice.videoZoomFactor.
  let deviceFactor: CGFloat
  /// Factor shown in UI (Camera.app style: 0.5 / 1 / 2 / 3…).
  let displayFactor: CGFloat
  let label: String

  /// Backward-compatible alias used by older call sites.
  var factor: CGFloat { deviceFactor }
}

struct NativeCameraCapabilitiesSnapshot {
  var rearCameraAvailable = false
  var logicalMultiCamera = false
  /// iOS has no public HDR/Night extension API — these stay false so the UI
  /// never renders extension chips that AVFoundation cannot honour.
  var hdrPhoto = false
  var nightPhoto = false
  var autoExtension = false
  var flash = false
  var torch = false
  var tapToFocus = true
  var continuousAutofocus = false
  var exposureCompensation = false
  var minExposureBias: Double?
  var maxExposureBias: Double?
  var stabilization = false
  var heic = false
  var lowLightBoost = false
  var virtualDeviceFusion = false
  var distortionCorrection = false
  var ultraWide = false
  var telephoto = false
  var hdrVideo = false
  var videoHd = false
  var videoFhd = false
  var videoUhd = false
  var highQualityCapture = false
  var maxPhotoWidth: Int?
  var maxPhotoHeight: Int?
  var usefulZoomLevels: [Double] = [1]
  var minZoom: Double = 1
  var maxZoom: Double = 1
  /// Always empty on iOS: CameraX-style selectable extensions do not exist here.
  var supportedExtensionModes: [String] = []

  func asDictionary() -> [String: Any] {
    var map: [String: Any] = [
      "rearCameraAvailable": rearCameraAvailable,
      "logicalMultiCamera": logicalMultiCamera,
      "hdrPhoto": hdrPhoto,
      "nightPhoto": nightPhoto,
      "autoExtension": autoExtension,
      "flash": flash,
      "torch": torch,
      "tapToFocus": tapToFocus,
      "continuousAutofocus": continuousAutofocus,
      "exposureCompensation": exposureCompensation,
      "stabilization": stabilization,
      "heic": heic,
      "lowLightBoost": lowLightBoost,
      "virtualDeviceFusion": virtualDeviceFusion,
      "distortionCorrection": distortionCorrection,
      "ultraWide": ultraWide,
      "telephoto": telephoto,
      "hdrVideo": hdrVideo,
      "videoHd": videoHd,
      "videoFhd": videoFhd,
      "videoUhd": videoUhd,
      "highQualityCapture": highQualityCapture,
      "usefulZoomLevels": usefulZoomLevels,
      "minZoom": minZoom,
      "maxZoom": maxZoom,
      "supportedExtensionModes": supportedExtensionModes,
    ]
    if let minExposureBias {
      map["minExposureBias"] = minExposureBias
    }
    if let maxExposureBias {
      map["maxExposureBias"] = maxExposureBias
    }
    if let maxPhotoWidth {
      map["maxPhotoWidth"] = maxPhotoWidth
    }
    if let maxPhotoHeight {
      map["maxPhotoHeight"] = maxPhotoHeight
    }
    return map
  }
}

protocol NativeCameraSessionDelegate: AnyObject {
  func sessionDidFinishConfiguration(_ session: NativeCameraSession)
  func session(_ session: NativeCameraSession, didFailWithCode code: String, message: String)
  func session(_ session: NativeCameraSession, didUpdateZoomFactor factor: CGFloat)
  func session(_ session: NativeCameraSession, didChangeRecording isRecording: Bool)
  func session(
    _ session: NativeCameraSession,
    didCapturePhotoAt url: URL,
    metadata: [String: Any]
  )
  func session(
    _ session: NativeCameraSession,
    didFinishRecordingAt url: URL,
    metadata: [String: Any]
  )
  func session(_ session: NativeCameraSession, recordingDidFail code: String, message: String)
  func sessionWasInterrupted(_ session: NativeCameraSession, reason: String)
  func sessionInterruptionEnded(_ session: NativeCameraSession)
}

/// Owns AVCaptureSession, photo / movie outputs, zoom, focus, flash, and torch.
final class NativeCameraSession: NSObject {
  static let logPrefix = "[SmartNPS360Camera]"
  /// AVFoundation can advertise extreme digital factors (for example 64x).
  /// Six-times display zoom is the maximum useful evidence-capture range.
  private static let maximumUserDisplayZoom: CGFloat = 6

  let session = AVCaptureSession()
  let previewLayer: AVCaptureVideoPreviewLayer

  private let sessionQueue = DispatchQueue(label: "com.smartnps360.app.native_camera.session")
  /// Encode / disk write for stills — never block AVFoundation's photo callback queue.
  private let photoProcessingQueue = DispatchQueue(
    label: "com.smartnps360.app.native_camera.photo_processing",
    qos: .userInitiated
  )
  private let photoOutput = AVCapturePhotoOutput()
  private let movieOutput = AVCaptureMovieFileOutput()

  private var videoDeviceInput: AVCaptureDeviceInput?
  private var audioDeviceInput: AVCaptureDeviceInput?

  private(set) var currentDevice: AVCaptureDevice?
  private(set) var isVideoMode = false
  private(set) var quality: NativeCameraCaptureQuality = .maximum
  private(set) var preferHeic = false
  private(set) var rearCameraOnly = true
  private(set) var isUsingFrontCamera = false
  private(set) var flashMode: NativeCameraFlashMode = .auto
  private var photoFlashMode: NativeCameraFlashMode = .auto
  private var preferredTorchOn = false
  private(set) var zoomChips: [NativeCameraZoomChip] = []
  /// Device zoom that maps to Camera.app "1x".
  private(set) var wideDeviceZoomFactor: CGFloat = 1
  /// Survives configureLocked so photo↔video keeps the officer's zoom (e.g. 1x).
  private var preferredZoomFactor: CGFloat?
  private(set) var isConfigured = false
  private(set) var isInterrupted = false
  /// Applied EV bias; survives camera / mode switches (re-clamped per device).
  private(set) var exposureTargetBias: Float = 0
  private(set) var lowLightBoostEnabled = false
  private(set) var distortionCorrectionEnabled = false
  /// Largest photo dimensions negotiated with the photo output (iOS 16+).
  private(set) var activeMaxPhotoDimensions: CMVideoDimensions?

  private var videoStartDate: Date?
  private var pendingVideoURL: URL?
  private var focusResetWorkItem: DispatchWorkItem?
  private var videoOrientation: AVCaptureVideoOrientation = .landscapeRight
  /// Ordered tokens describing every quality fallback taken during configure.
  private var fallbackTokens: [String] = []

  weak var delegate: NativeCameraSessionDelegate?

  var cameraPositionWireName: String {
    isUsingFrontCamera ? "front" : "back"
  }

  /// Wire label for the capture path in use — always `.quality` prioritization.
  /// Responsive / zero-shutter-lag (iOS 17+) may be enabled for latency only;
  /// they do not switch to a speed or fast-capture-prioritization path.
  var captureModeWireName: String { "avfoundation_quality" }

  /// `nil` when no fallback was needed.
  var fallbackLevelWireName: String? {
    fallbackTokens.isEmpty ? nil : fallbackTokens.joined(separator: "+")
  }

  var minExposureTargetBias: Float {
    currentDevice?.minExposureTargetBias ?? 0
  }

  var maxExposureTargetBias: Float {
    currentDevice?.maxExposureTargetBias ?? 0
  }

  var supportsExposureCompensation: Bool {
    maxExposureTargetBias > minExposureTargetBias
  }

  override init() {
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    // Fit (not fill): never crop the sensor FOV to the screen. Letterboxing
    // matches Camera.app Photo framing so 0.5x looks as wide as stock.
    previewLayer.videoGravity = .resizeAspect
    super.init()
    previewLayer.session = session
    // A new evidence-camera session always starts from predictable, safe
    // lighting defaults. Mode switches within this session still preserve the
    // user's separate photo and video selections.
    photoFlashMode = .auto
    preferredTorchOn = false
    flashMode = photoFlashMode
  }

  deinit {
    focusResetWorkItem?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Lifecycle

  func configure(
    isVideoMode: Bool,
    quality: NativeCameraCaptureQuality,
    preferHeic: Bool,
    rearCameraOnly: Bool,
    completion: ((Bool) -> Void)? = nil
  ) {
    self.isVideoMode = isVideoMode
    flashMode = isVideoMode ? (preferredTorchOn ? .on : .off) : photoFlashMode
    self.quality = quality
    self.preferHeic = preferHeic
    self.rearCameraOnly = rearCameraOnly

    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.configureLocked()
        DispatchQueue.main.async {
          self.applyPreviewMirroring()
          self.delegate?.sessionDidFinishConfiguration(self)
          completion?(true)
        }
      } catch {
        let nsError = error as NSError
        NSLog("\(Self.logPrefix) configure failed: \(nsError.localizedDescription)")
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            didFailWithCode: nsError.domain,
            message: nsError.localizedDescription
          )
          completion?(false)
        }
      }
    }
  }

  func startRunning() {
    sessionQueue.async { [weak self] in
      guard let self, self.isConfigured else { return }
      if !self.session.isRunning {
        NSLog("\(Self.logPrefix) SESSION_START_RUNNING_START")
        let t0 = CFAbsoluteTimeGetCurrent()
        self.session.startRunning()
        let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        NSLog("\(Self.logPrefix) SESSION_START_RUNNING_END +\(ms)ms")
        DispatchQueue.main.async {
          NSLog("\(Self.logPrefix) PREVIEW_LAYER_READY / FIRST_PREVIEW_FRAME (session running)")
        }
      }
      let lightOn = self.isVideoMode ? self.preferredTorchOn : self.photoFlashMode == .on
      self.setTorch(enabled: !self.isUsingFrontCamera && lightOn)
    }
  }

  func stopRunning() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.movieOutput.isRecording {
        self.movieOutput.stopRecording()
      }
      if self.session.isRunning {
        self.session.stopRunning()
        NSLog("\(Self.logPrefix) session stopped")
      }
      self.setTorch(enabled: false)
    }
  }

  func setVideoMode(_ video: Bool) {
    guard isVideoMode != video else {
      // Already in the requested mode — still notify so pending shutter
      // actions (photo after mode switch) are not left spinning forever.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.delegate?.sessionDidFinishConfiguration(self)
      }
      return
    }
    // Snapshot zoom before configure resets hardware to min (often 0.5x).
    if let live = currentDevice?.videoZoomFactor, live > 0.01 {
      preferredZoomFactor = live
    }
    isVideoMode = video
    // Photos are always rear-only — snap back to the back camera.
    if !video {
      isUsingFrontCamera = false
      flashMode = photoFlashMode
      setTorch(enabled: false)
    } else {
      flashMode = preferredTorchOn ? .on : .off
    }
    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        // Full reconfigure; photo and video share the same photo FOV framing so
        // long-press video does not change on-screen zoom/frame size.
        try self.configureLocked()
        let lightOn = video ? self.preferredTorchOn : self.photoFlashMode == .on
        self.setTorch(enabled: !self.isUsingFrontCamera && lightOn)
        DispatchQueue.main.async {
          self.delegate?.sessionDidFinishConfiguration(self)
        }
      } catch {
        let nsError = error as NSError
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            didFailWithCode: nsError.domain,
            message: nsError.localizedDescription
          )
        }
      }
    }
  }

  /// Switches between rear and front cameras (video only, when allowed).
  func flipCamera() {
    guard !rearCameraOnly, isVideoMode, !movieOutput.isRecording else { return }
    isUsingFrontCamera.toggle()
    setTorch(enabled: false)
    flashMode = isUsingFrontCamera || !preferredTorchOn ? .off : .on
    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.configureLocked()
        if !self.session.isRunning {
          self.session.startRunning()
        }
        DispatchQueue.main.async {
          self.applyPreviewMirroring()
          self.delegate?.sessionDidFinishConfiguration(self)
        }
      } catch {
        self.isUsingFrontCamera.toggle()
        let nsError = error as NSError
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            didFailWithCode: nsError.domain,
            message: nsError.localizedDescription
          )
        }
      }
    }
  }

  func updateVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
    videoOrientation = orientation
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if let connection = self.previewLayer.connection,
         connection.isVideoOrientationSupported
      {
        connection.videoOrientation = orientation
      }
      self.applyPreviewMirroring()
    }
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if let connection = self.photoOutput.connection(with: .video),
         connection.isVideoOrientationSupported
      {
        connection.videoOrientation = orientation
      }
      if let connection = self.movieOutput.connection(with: .video),
         connection.isVideoOrientationSupported
      {
        connection.videoOrientation = orientation
      }
    }
  }

  private func applyPreviewMirroring() {
    guard let connection = previewLayer.connection else { return }
    if connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = isUsingFrontCamera
    }
  }

  private func applyPreferredStabilization(on connection: AVCaptureConnection) {
    guard connection.isVideoStabilizationSupported else { return }
    // Prefer cinematic when available; fall back to auto then standard.
    connection.preferredVideoStabilizationMode = .cinematic
    if connection.activeVideoStabilizationMode == .off {
      connection.preferredVideoStabilizationMode = .auto
    }
    if connection.activeVideoStabilizationMode == .off {
      connection.preferredVideoStabilizationMode = .standard
    }
  }

  // MARK: - Capture

  func capturePhoto() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      CamPerf.stage("CAPTURE_PHOTO_SESSION_QUEUE_ENTER")
      guard !self.isVideoMode else {
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            didFailWithCode: "wrong_mode",
            message: "Camera is still switching modes. Please try again."
          )
        }
        return
      }
      guard self.session.isRunning, !self.isInterrupted else {
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            didFailWithCode: "interrupted",
            message: "Camera is interrupted"
          )
        }
        return
      }

      if #available(iOS 17.0, *) {
        // Accept captures while briefly not-ready; only hard-block when the
        // session itself is down. Readiness is logged for Pro Max diagnostics.
        let readiness = self.photoOutput.captureReadiness
        NSLog("\(Self.logPrefix) captureReadiness=\(readiness.rawValue)")
      }

      let settings: AVCapturePhotoSettings
      let heicSupported = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
      if self.preferHeic, heicSupported {
        settings = AVCapturePhotoSettings(
          format: [AVVideoCodecKey: AVVideoCodecType.hevc]
        )
      } else if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
        settings = AVCapturePhotoSettings(
          format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
        )
      } else {
        settings = AVCapturePhotoSettings()
      }

      if let device = self.currentDevice,
         device.hasFlash,
         self.photoOutput.supportedFlashModes.contains(self.flashMode.avFlashMode),
         device.torchMode != .on
      {
        settings.flashMode = self.flashMode.avFlashMode
      } else {
        settings.flashMode = .off
      }

      if #available(iOS 13.0, *) {
        // Best public computational photography path (no private Night Mode).
        settings.photoQualityPrioritization = .quality
      }

      if #available(iOS 16.0, *) {
        let dimensions = self.photoOutput.maxPhotoDimensions
        if dimensions.width > 0, dimensions.height > 0 {
          settings.maxPhotoDimensions = dimensions
        }
      } else if self.photoOutput.isHighResolutionCaptureEnabled {
        settings.isHighResolutionPhotoEnabled = true
      }

      if #available(iOS 14.1, *) {
        if self.photoOutput.isContentAwareDistortionCorrectionSupported {
          settings.isAutoContentAwareDistortionCorrectionEnabled = true
        }
      }

      let device = self.currentDevice
      let formatDesc = device.map { "\($0.activeFormat.formatDescription)" } ?? "nil"
      let lowLightSupported = device?.isLowLightBoostSupported ?? false
      let lowLightEnabled = device?.isLowLightBoostEnabled ?? false
      let prioritization: String
      if #available(iOS 13.0, *) {
        prioritization = "\(settings.photoQualityPrioritization.rawValue)"
      } else {
        prioritization = "n/a"
      }
      var responsiveFlags = "responsive=n/a"
      if #available(iOS 17.0, *) {
        responsiveFlags =
          "zsl=\(self.photoOutput.isZeroShutterLagEnabled) "
          + "responsive=\(self.photoOutput.isResponsiveCaptureEnabled)"
      }
      CamPerf.log(
        nil,
        "CAPTURE_CONFIG",
        "photoQualityPrioritization=\(prioritization) " +
          "maxPhotoDims=\(self.activeMaxPhotoDimensions.map { "\($0.width)x\($0.height)" } ?? "legacy") " +
          "format=\(formatDesc) lowLightSupported=\(lowLightSupported) " +
          "lowLightEnabled=\(lowLightEnabled) " +
          "autoLowLight=\(device?.automaticallyEnablesLowLightBoostWhenAvailable ?? false) " +
          "device=\(device?.localizedName ?? "nil") " +
          "zoom=\(device?.videoZoomFactor ?? 0) ev=\(self.exposureTargetBias) " +
          "flash=\(self.flashMode.title) \(responsiveFlags)"
      )

      CamPerf.markCapturePhotoInvoke(captureId: nil)
      CamPerf.stage("CAMERA_CAPTURE_STARTED")
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  func toggleRecording() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.movieOutput.isRecording {
        self.movieOutput.stopRecording()
        return
      }

      guard self.isVideoMode else { return }
      guard self.session.isRunning, !self.isInterrupted else {
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            recordingDidFail: "interrupted",
            message: "Camera is interrupted"
          )
        }
        return
      }

      if !self.hasEnoughStorage(minimumBytes: 50 * 1024 * 1024) {
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            recordingDidFail: "insufficient_storage",
            message: "Not enough storage to record video"
          )
        }
        return
      }

      do {
        let url = try Self.makeTempMediaURL(extension: "mov")
        self.pendingVideoURL = url
        self.videoStartDate = Date()

        if let connection = self.movieOutput.connection(with: .video) {
          if connection.isVideoOrientationSupported {
            connection.videoOrientation = self.videoOrientation
          }
          self.applyPreferredStabilization(on: connection)
        }

        if let device = self.currentDevice, device.hasTorch, device.isTorchAvailable {
          // Torch follows flash "on" while recording.
          self.setTorch(enabled: self.flashMode == .on)
        }

        self.movieOutput.startRecording(to: url, recordingDelegate: self)
        NSLog("\(Self.logPrefix) recording started → \(url.lastPathComponent)")
        DispatchQueue.main.async {
          self.delegate?.session(self, didChangeRecording: true)
        }
      } catch {
        DispatchQueue.main.async {
          self.delegate?.session(
            self,
            recordingDidFail: "file_create_failed",
            message: error.localizedDescription
          )
        }
      }
    }
  }

  var isRecording: Bool {
    movieOutput.isRecording
  }

  // MARK: - Zoom / focus / flash

  func setZoomFactor(_ factor: CGFloat, animated: Bool) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.currentDevice else { return }
      let minZ = device.minAvailableVideoZoomFactor
      let hardwareMax = min(
        device.maxAvailableVideoZoomFactor,
        device.activeFormat.videoMaxZoomFactor
      )
      let maxZ = min(hardwareMax, self.wideDeviceZoomFactor * Self.maximumUserDisplayZoom)
      let clamped = max(minZ, min(maxZ, factor))
      self.preferredZoomFactor = clamped
      do {
        try device.lockForConfiguration()
        if animated {
          device.ramp(toVideoZoomFactor: clamped, withRate: 8)
        } else {
          device.videoZoomFactor = clamped
        }
        device.unlockForConfiguration()
        DispatchQueue.main.async {
          self.delegate?.session(self, didUpdateZoomFactor: clamped)
        }
      } catch {
        NSLog("\(Self.logPrefix) zoom failed: \(error.localizedDescription)")
      }
    }
  }

  func currentZoomFactor() -> CGFloat {
    currentDevice?.videoZoomFactor ?? 1
  }

  func zoomFactorRange() -> ClosedRange<CGFloat> {
    guard let device = currentDevice else { return 1...1 }
    let minimum = device.minAvailableVideoZoomFactor
    let hardwareMaximum = min(
      device.maxAvailableVideoZoomFactor,
      device.activeFormat.videoMaxZoomFactor
    )
    let maximum = min(
      hardwareMaximum,
      wideDeviceZoomFactor * Self.maximumUserDisplayZoom
    )
    return minimum...max(minimum, maximum)
  }

  func focusAndExpose(at devicePoint: CGPoint) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.currentDevice else { return }
      self.focusResetWorkItem?.cancel()
      do {
        try device.lockForConfiguration()
        if device.isFocusPointOfInterestSupported {
          device.focusPointOfInterest = devicePoint
          if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
          } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
          }
        }
        if device.isExposurePointOfInterestSupported {
          device.exposurePointOfInterest = devicePoint
          // Keep metering the selected area as lighting changes. `.autoExpose`
          // performs only one adjustment and can leave a night scene too dark.
          if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
          } else if device.isExposureModeSupported(.autoExpose) {
            device.exposureMode = .autoExpose
          }
        }
        if device.isSubjectAreaChangeMonitoringEnabled == false {
          device.isSubjectAreaChangeMonitoringEnabled = true
        }
        device.unlockForConfiguration()
        self.scheduleContinuousAutoFocusRestore(for: device)
      } catch {
        NSLog("\(Self.logPrefix) focus failed: \(error.localizedDescription)")
      }
    }
  }

  /// Tap-to-focus is temporary. Like Camera.app, return to continuous center
  /// autofocus automatically so the officer never has to manage focus.
  private func scheduleContinuousAutoFocusRestore(for device: AVCaptureDevice) {
    let work = DispatchWorkItem { [weak self, weak device] in
      guard let self, let device, self.currentDevice === device else { return }
      self.restoreContinuousAutoFocus(on: device, resetPoint: true)
    }
    focusResetWorkItem = work
    sessionQueue.asyncAfter(deadline: .now() + 3, execute: work)
  }

  private func restoreContinuousAutoFocus(
    on device: AVCaptureDevice,
    resetPoint: Bool
  ) {
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      let center = CGPoint(x: 0.5, y: 0.5)
      if resetPoint, device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = center
      }
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      } else if device.isFocusModeSupported(.autoFocus) {
        device.focusMode = .autoFocus
      }
      if resetPoint, device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = center
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.isSubjectAreaChangeMonitoringEnabled = true
      NSLog("\(Self.logPrefix) continuous autofocus restored")
    } catch {
      NSLog("\(Self.logPrefix) autofocus restore failed: \(error.localizedDescription)")
    }
  }

  /// Applies EV compensation clamped to the active device range.
  /// Returns the value that will actually be applied.
  @discardableResult
  func setExposureTargetBias(_ bias: Float) -> Float {
    guard let device = currentDevice, supportsExposureCompensation else { return 0 }
    let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
    exposureTargetBias = clamped
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.applyExposureTargetBiasLocked(on: device)
    }
    return clamped
  }

  private func applyExposureTargetBiasLocked(on device: AVCaptureDevice) {
    guard device.maxExposureTargetBias > device.minExposureTargetBias else { return }
    let clamped = max(
      device.minExposureTargetBias,
      min(device.maxExposureTargetBias, exposureTargetBias)
    )
    exposureTargetBias = clamped
    do {
      try device.lockForConfiguration()
      device.setExposureTargetBias(clamped)
      device.unlockForConfiguration()
    } catch {
      NSLog("\(Self.logPrefix) exposure bias failed: \(error.localizedDescription)")
    }
  }

  func cycleFlashMode() -> NativeCameraFlashMode {
    guard supportsFlashOrTorch else { return flashMode }
    if isVideoMode {
      // Torch is binary on/off (no auto).
      flashMode = flashMode == .on ? .off : .on
      preferredTorchOn = flashMode == .on
      setTorch(enabled: flashMode == .on)
    } else {
      flashMode = flashMode.next
      photoFlashMode = flashMode
      // "On" illuminates the preview immediately; Auto still lets the camera
      // decide whether a capture-time flash is needed.
      setTorch(enabled: flashMode == .on)
    }
    return flashMode
  }

  /// Applies an explicit flash choice from the camera chrome and persists it.
  /// Photo supports Off / On / Auto; video torch is intentionally binary.
  @discardableResult
  func setFlashMode(_ mode: NativeCameraFlashMode) -> NativeCameraFlashMode {
    guard supportsFlashOrTorch else { return flashMode }
    if isVideoMode {
      flashMode = mode == .on ? .on : .off
      preferredTorchOn = flashMode == .on
      setTorch(enabled: preferredTorchOn)
    } else {
      flashMode = mode
      photoFlashMode = mode
      // On lights the preview immediately; Auto remains capture-time flash.
      setTorch(enabled: mode == .on)
    }
    return flashMode
  }

  var supportsFlashOrTorch: Bool {
    guard let device = currentDevice else { return false }
    if isVideoMode {
      return device.hasTorch && device.isTorchAvailable
    }
    return device.hasFlash
  }

  func capabilitiesSnapshot() -> NativeCameraCapabilitiesSnapshot {
    var caps = NativeCameraCapabilitiesSnapshot()
    guard let device = currentDevice ?? Self.discoverBestBackCamera() else {
      return caps
    }

    caps.rearCameraAvailable = device.position == .back
      || Self.discoverBestBackCamera() != nil
    caps.flash = device.hasFlash
    caps.torch = device.hasTorch
    caps.tapToFocus = device.isFocusPointOfInterestSupported
    caps.continuousAutofocus = device.isFocusModeSupported(.continuousAutoFocus)
    caps.exposureCompensation = device.maxExposureTargetBias > device.minExposureTargetBias
    if caps.exposureCompensation {
      caps.minExposureBias = Double(device.minExposureTargetBias)
      caps.maxExposureBias = Double(device.maxExposureTargetBias)
    }
    caps.lowLightBoost = device.isLowLightBoostSupported
    caps.distortionCorrection = device.isGeometricDistortionCorrectionSupported
    if #available(iOS 14.1, *) {
      caps.distortionCorrection = caps.distortionCorrection
        || photoOutput.isContentAwareDistortionCorrectionSupported
    }
    caps.heic = Self.deviceSupportsHeic()
      || photoOutput.availablePhotoCodecTypes.contains(.hevc)
    caps.minZoom = Double(device.minAvailableVideoZoomFactor / max(wideDeviceZoomFactor, 0.01))
    caps.maxZoom = Double(
      min(
        Self.maximumUserDisplayZoom,
        min(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor)
          / max(wideDeviceZoomFactor, 0.01)
      )
    )
    let builtChips = zoomChips.isEmpty ? Self.buildZoomChips(for: device).chips : zoomChips
    caps.usefulZoomLevels = builtChips.map { Double($0.displayFactor) }

    caps.ultraWide = builtChips.contains(where: { $0.displayFactor < 0.85 })
    caps.telephoto = builtChips.contains(where: { $0.displayFactor >= 1.9 })

    // iOS exposes no public HDR / Night extension API. Reporting them as
    // available would surface capture chips AVFoundation cannot honour, so both
    // stay false and the extension list stays empty. `autoExtension` only
    // reflects the real virtual multi-cam fusion path.
    caps.hdrPhoto = false
    caps.nightPhoto = false
    caps.supportedExtensionModes = []
    if #available(iOS 13.0, *) {
      caps.virtualDeviceFusion = device.isVirtualDevice
      caps.logicalMultiCamera = device.isVirtualDevice
      caps.autoExtension = device.isVirtualDevice
    }

    caps.stabilization = movieOutput.connection(with: .video)?.isVideoStabilizationSupported
      ?? true
    caps.hdrVideo = false

    let video = Self.videoResolutionSupport(for: device)
    caps.videoHd = video.hd
    caps.videoFhd = video.fhd
    caps.videoUhd = video.uhd

    let photoDimensions = activeMaxPhotoDimensions ?? Self.largestPhotoDimensions(for: device)
    if let photoDimensions, photoDimensions.width > 0, photoDimensions.height > 0 {
      caps.maxPhotoWidth = Int(photoDimensions.width)
      caps.maxPhotoHeight = Int(photoDimensions.height)
    }
    caps.highQualityCapture = caps.rearCameraAvailable
    return caps
  }

  /// Best-effort scan of the device's formats for HD / FHD / UHD video support.
  static func videoResolutionSupport(
    for device: AVCaptureDevice
  ) -> (hd: Bool, fhd: Bool, uhd: Bool) {
    var hd = false
    var fhd = false
    var uhd = false
    for format in device.formats {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      let height = max(dims.height, 0)
      if height >= 2160 { uhd = true }
      if height >= 1080 { fhd = true }
      if height >= 720 { hd = true }
    }
    return (hd, fhd, uhd)
  }

  /// Largest still size across every format — used when the session has not
  /// negotiated dimensions yet (capability probe path).
  static func largestPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
    if #available(iOS 16.0, *) {
      let all = device.formats.flatMap(\.supportedMaxPhotoDimensions)
      return all.max { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
    }
    return device.formats
      .map { CMVideoFormatDescriptionGetDimensions($0.formatDescription) }
      .max { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
  }

  // MARK: - Private configuration

  private func configureLocked() throws {
    let t0 = CFAbsoluteTimeGetCurrent()
    func ms() -> Int { Int((CFAbsoluteTimeGetCurrent() - t0) * 1000) }
    NSLog("\(Self.logPrefix) SESSION_CONFIG_START")
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    fallbackTokens.removeAll()
    activeMaxPhotoDimensions = nil
    lowLightBoostEnabled = false
    distortionCorrectionEnabled = false

    for input in session.inputs {
      session.removeInput(input)
    }
    for output in session.outputs {
      session.removeOutput(output)
    }
    videoDeviceInput = nil
    audioDeviceInput = nil

    NSLog("\(Self.logPrefix) DEVICE_DISCOVERY_START +\(ms())ms")
    guard let device = Self.discoverBestCamera(front: isUsingFrontCamera) else {
      throw Self.error(
        code: isUsingFrontCamera ? "init_failed" : "no_rear_camera",
        message: isUsingFrontCamera ? "No front camera available" : "No rear camera available"
      )
    }
    NSLog("\(Self.logPrefix) DEVICE_DISCOVERY_END +\(ms())ms")

    let videoInput: AVCaptureDeviceInput
    do {
      videoInput = try AVCaptureDeviceInput(device: device)
    } catch {
      let ns = error as NSError
      if ns.code == AVError.applicationIsNotAuthorizedToUseDevice.rawValue {
        throw Self.error(code: "permission_denied", message: "Camera permission denied")
      }
      if ns.code == AVError.deviceAlreadyUsedByAnotherSession.rawValue {
        throw Self.error(code: "camera_in_use", message: "Camera is in use by another app")
      }
      throw Self.error(code: "init_failed", message: error.localizedDescription)
    }

    guard session.canAddInput(videoInput) else {
      throw Self.error(code: "init_failed", message: "Unable to add camera input")
    }
    session.addInput(videoInput)
    videoDeviceInput = videoInput
    currentDevice = device
    NSLog("\(Self.logPrefix) INPUT_READY +\(ms())ms")

    if !isUsingFrontCamera, device.deviceType == .builtInWideAngleCamera {
      // Single physical lens: no virtual multi-cam fusion available.
      noteFallback("single_lens")
    }

    // Photo and video share Camera.app Photo FOV (.photo preset) so long-press
    // video does not widen/narrow the on-screen frame vs photo mode.
    // Video still records via movieOutput; quality may follow the photo pipeline.
    if session.canSetSessionPreset(.photo) {
      session.sessionPreset = .photo
      NSLog(
        "\(Self.logPrefix) sessionPreset=photo "
          + "(shared photo FOV; mode=\(isVideoMode ? "video" : "photo"))"
      )
    } else {
      session.sessionPreset = .inputPriority
      // Match photo FOV even in video mode when .photo preset is unavailable.
      try applyPreferredFormat(on: device, forcePhotoFov: true)
      noteFallback("photo_preset_unavailable")
    }

    applyDeviceEnhancements(on: device)
    let built = Self.buildZoomChips(for: device)
    zoomChips = built.chips
    wideDeviceZoomFactor = built.wideDeviceFactor
    restorePreferredZoom(on: device)

    try reconfigureOutputsLocked(inBeginConfiguration: true)
    NSLog("\(Self.logPrefix) PHOTO_OUTPUT_READY +\(ms())ms")
    registerNotificationsIfNeeded()
    isConfigured = true
    logConfigurationDiagnostics(device: device)
    NSLog("\(Self.logPrefix) SESSION_CONFIG_END +\(ms())ms")
  }

  /// Applies every per-device quality knob in a single configuration lock:
  /// low-light boost, distortion correction, virtual-device switching, EV bias.
  private func applyDeviceEnhancements(on device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }

      if device.isLowLightBoostSupported {
        device.automaticallyEnablesLowLightBoostWhenAvailable = true
        lowLightBoostEnabled = true
      } else {
        lowLightBoostEnabled = false
        noteFallback("no_low_light_boost")
      }

      if device.isGeometricDistortionCorrectionSupported {
        device.isGeometricDistortionCorrectionEnabled = true
        distortionCorrectionEnabled = true
      }

      // Keep virtual multi-cam fusion ON — never force a single physical lens.
      if device.isVirtualDevice,
         device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported
      {
        device.setPrimaryConstituentDeviceSwitchingBehavior(
          .auto,
          restrictedSwitchingBehaviorConditions: []
        )
      }

      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
      }
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      } else if device.isFocusModeSupported(.autoFocus) {
        device.focusMode = .autoFocus
      }
      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.isSubjectAreaChangeMonitoringEnabled = true

      if device.maxExposureTargetBias > device.minExposureTargetBias {
        let clamped = max(
          device.minExposureTargetBias,
          min(device.maxExposureTargetBias, exposureTargetBias)
        )
        exposureTargetBias = clamped
        device.setExposureTargetBias(clamped)
      } else {
        exposureTargetBias = 0
      }
    } catch {
      NSLog("\(Self.logPrefix) device enhancements failed: \(error.localizedDescription)")
    }
  }

  private func logConfigurationDiagnostics(device: AVCaptureDevice) {
    let dims = activeMaxPhotoDimensions
    let maxPhoto = dims.map { "\($0.width)x\($0.height)" } ?? "legacy_high_res"
    let heic = photoOutput.availablePhotoCodecTypes.contains(.hevc)
    let format = device.activeFormat
    let fov = format.videoFieldOfView
    let gdcFov = format.geometricDistortionCorrectedVideoFieldOfView
    var multiplierLog = "n/a"
    if #available(iOS 18.0, *) {
      multiplierLog = String(format: "%.4f", Double(device.displayVideoZoomFactorMultiplier))
    }
    NSLog(
      "\(Self.logPrefix) configured device=\(device.localizedName) "
        + "type=\(device.deviceType.rawValue) position=\(cameraPositionWireName) "
        + "preset=\(session.sessionPreset.rawValue) "
        + "fov=\(fov) gdcFov=\(gdcFov) zoomMultiplier=\(multiplierLog) "
        + "lowLightBoost=\(lowLightBoostEnabled) maxPhotoDimensions=\(maxPhoto) "
        + "virtualFusion=\(device.isVirtualDevice) "
        + "switching=\(device.activePrimaryConstituentDeviceSwitchingBehavior.rawValue) "
        + "distortionCorrection=\(distortionCorrectionEnabled) heic=\(heic) "
        + "exposureBias=[\(device.minExposureTargetBias)…\(device.maxExposureTargetBias)]"
        + "@\(exposureTargetBias) wideDevice=\(wideDeviceZoomFactor) "
        + "minZoom=\(device.minAvailableVideoZoomFactor) "
        + "zoom=\(zoomChips.map { "\($0.label)@\($0.deviceFactor)" }) "
        + "fallback=\(fallbackLevelWireName ?? "none")"
    )
  }

  /// Re-applies the officer's last zoom after configure resets the device to min.
  private func restorePreferredZoom(on device: AVCaptureDevice) {
    let minZ = device.minAvailableVideoZoomFactor
    let hardwareMax = min(
      device.maxAvailableVideoZoomFactor,
      device.activeFormat.videoMaxZoomFactor
    )
    let maxZ = min(hardwareMax, wideDeviceZoomFactor * Self.maximumUserDisplayZoom)
    // Prefer the remembered selection; fall back to Camera.app-style 1x (wide).
    let target = preferredZoomFactor ?? wideDeviceZoomFactor
    let clamped = max(minZ, min(maxZ, target))
    preferredZoomFactor = clamped
    guard abs(device.videoZoomFactor - clamped) > 0.02 else { return }
    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = clamped
      device.unlockForConfiguration()
      NSLog("\(Self.logPrefix) restored zoom=\(clamped) (preferred)")
    } catch {
      NSLog("\(Self.logPrefix) restore zoom failed: \(error.localizedDescription)")
    }
  }

  private func reconfigureOutputsLocked(inBeginConfiguration: Bool = false) throws {
    if !inBeginConfiguration {
      session.beginConfiguration()
    }
    defer {
      if !inBeginConfiguration {
        session.commitConfiguration()
      }
    }

    if session.outputs.contains(photoOutput) {
      session.removeOutput(photoOutput)
    }
    if session.outputs.contains(movieOutput) {
      session.removeOutput(movieOutput)
    }
    if let audio = audioDeviceInput {
      session.removeInput(audio)
      audioDeviceInput = nil
    }

    if isVideoMode {
      guard session.canAddOutput(movieOutput) else {
        throw Self.error(code: "init_failed", message: "Unable to add movie output")
      }
      session.addOutput(movieOutput)
      movieOutput.movieFragmentInterval = .invalid

      if let mic = AVCaptureDevice.default(for: .audio) {
        do {
          let audioInput = try AVCaptureDeviceInput(device: mic)
          if session.canAddInput(audioInput) {
            session.addInput(audioInput)
            audioDeviceInput = audioInput
          }
        } catch {
          NSLog("\(Self.logPrefix) audio input unavailable: \(error.localizedDescription)")
        }
      }

      if let connection = movieOutput.connection(with: .video) {
        if connection.isVideoOrientationSupported {
          connection.videoOrientation = videoOrientation
        }
        applyPreferredStabilization(on: connection)
      }
    } else {
      guard session.canAddOutput(photoOutput) else {
        throw Self.error(code: "init_failed", message: "Unable to add photo output")
      }
      session.addOutput(photoOutput)
      // Quality prioritization must be raised before dimensions are negotiated:
      // the largest still sizes are only offered on the quality path.
      if #available(iOS 13.0, *) {
        photoOutput.maxPhotoQualityPrioritization = .quality
      }
      applyMaxPhotoDimensions()
      applyResponsiveCaptureIfSupported()
      if #available(iOS 14.1, *) {
        if photoOutput.isContentAwareDistortionCorrectionSupported {
          photoOutput.isContentAwareDistortionCorrectionEnabled = true
          distortionCorrectionEnabled = true
        }
      }
      if let connection = photoOutput.connection(with: .video),
         connection.isVideoOrientationSupported
      {
        connection.videoOrientation = videoOrientation
      }
    }
  }

  /// Latency-only path for Pro-class stills. Keeps `.quality` prioritization and
  /// does **not** enable fast-capture prioritization (which can soften quality).
  private func applyResponsiveCaptureIfSupported() {
    guard #available(iOS 17.0, *) else { return }
    if photoOutput.isZeroShutterLagSupported {
      photoOutput.isZeroShutterLagEnabled = true
    }
    if photoOutput.isResponsiveCaptureSupported {
      photoOutput.isResponsiveCaptureEnabled = true
    }
    if photoOutput.isFastCapturePrioritizationSupported {
      // Keep full `.quality` stills even under rapid taps.
      photoOutput.isFastCapturePrioritizationEnabled = false
    }
    // Explicitly leave fastCapturePrioritizationEnabled off so
    // burst softening never trades quality for shot-to-shot speed.
    NSLog(
      "\(Self.logPrefix) responsive capture zsl=\(photoOutput.isZeroShutterLagEnabled) "
        + "responsive=\(photoOutput.isResponsiveCaptureEnabled) "
        + "fastPrio=\(photoOutput.isFastCapturePrioritizationEnabled) "
        + "supportedZsl=\(photoOutput.isZeroShutterLagSupported) "
        + "supportedResponsive=\(photoOutput.isResponsiveCaptureSupported)"
    )
  }

  private func applyPreferredFormat(
    on device: AVCaptureDevice,
    forcePhotoFov: Bool = false
  ) throws {
    let formats = device.formats
    guard !formats.isEmpty else { return }

    let best: AVCaptureDevice.Format
    if forcePhotoFov || !isVideoMode {
      // Photo FOV (widest) — also used for video when matching photo framing.
      best = Self.preferredPhotoFormat(from: formats)
    } else {
      best = Self.preferredVideoFormat(from: formats, quality: quality)
    }

    try device.lockForConfiguration()
    device.activeFormat = best
    let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
    // Prefer 30 fps for stability; bump only when format supports it cleanly.
    if let range = best.videoSupportedFrameRateRanges.first(where: {
      $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
    }) {
      device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
      device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
      _ = range
    }
    device.unlockForConfiguration()
    NSLog(
      "\(Self.logPrefix) active format \(dims.width)x\(dims.height) "
        + "fov=\(best.videoFieldOfView) mode=\(isVideoMode ? "video" : "photo") "
        + "forcePhotoFov=\(forcePhotoFov)"
    )
  }

  /// Video: prefer 4K / 1080p, then wider FOV among equals.
  private static func preferredVideoFormat(
    from formats: [AVCaptureDevice.Format],
    quality: NativeCameraCaptureQuality
  ) -> AVCaptureDevice.Format {
    let prefer4K = quality == .maximum
    let targetHeight: Int32 = prefer4K ? 2160 : 1080
    let fallbackHeight: Int32 = 1080

    func rank(_ format: AVCaptureDevice.Format) -> (Int, Int32, Int32, Float) {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      let height = dims.height
      let width = dims.width
      let exact = height == targetHeight || (prefer4K && height == 2160)
      let ok1080 = height == fallbackHeight
      let tier: Int
      if exact { tier = 0 }
      else if ok1080 { tier = 1 }
      else if height <= targetHeight { tier = 2 }
      else { tier = 3 }
      // Negate FOV so larger FOV sorts earlier within the same tier.
      return (tier, -height, -width, -format.videoFieldOfView)
    }

    return formats.sorted {
      let l = rank($0)
      let r = rank($1)
      if l.0 != r.0 { return l.0 < r.0 }
      if l.1 != r.1 { return l.1 < r.1 }
      if l.2 != r.2 { return l.2 < r.2 }
      return l.3 < r.3
    }.first!
  }

  /// Photo: maximize *effective* FOV after GDC, then still resolution.
  /// Ranking by uncorrected FOV can pick a format that GDC crops more tightly.
  private static func preferredPhotoFormat(
    from formats: [AVCaptureDevice.Format]
  ) -> AVCaptureDevice.Format {
    func maxPhotoPixels(_ format: AVCaptureDevice.Format) -> Int64 {
      if #available(iOS 16.0, *) {
        let best = format.supportedMaxPhotoDimensions.max {
          Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }
        if let best {
          return Int64(best.width) * Int64(best.height)
        }
      }
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      return Int64(dims.width) * Int64(dims.height)
    }

    func effectiveFOV(_ format: AVCaptureDevice.Format) -> Float {
      // GDC is enabled to match Camera.app; use the corrected FOV for ranking.
      let gdc = format.geometricDistortionCorrectedVideoFieldOfView
      return gdc > 0 ? gdc : format.videoFieldOfView
    }

    func rank(_ format: AVCaptureDevice.Format) -> (Float, Int64, Int32, Int32) {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      return (
        -effectiveFOV(format),
        -maxPhotoPixels(format),
        -dims.height,
        -dims.width
      )
    }

    return formats.sorted {
      let l = rank($0)
      let r = rank($1)
      if l.0 != r.0 { return l.0 < r.0 }
      if l.1 != r.1 { return l.1 < r.1 }
      if l.2 != r.2 { return l.2 < r.2 }
      return l.3 < r.3
    }.first!
  }

  private func noteFallback(_ token: String) {
    guard !fallbackTokens.contains(token) else { return }
    fallbackTokens.append(token)
  }

  /// Chooses a high-quality still size without blindly maximizing megapixels.
  ///
  /// AVFoundation does not expose an API that says "best computational photo
  /// resolution." Apple's processed stills are commonly in a mid/high range
  /// (roughly ≤ ~12 MP), while the absolute largest supportedMaxPhotoDimensions
  /// entry can be a specialized full-sensor mode that trades processing for
  /// pixel count. Strategy (public APIs only, no device model hardcoding):
  /// 1. Prefer ~4:3 (Camera.app Photo) so we never save a 16:9 center-crop.
  /// 2. Prefer the largest supported size whose pixel count is ≤ ~12.5 MP.
  /// 3. Else prefer the smallest size that is still ≥ ~8 MP (useful evidence).
  /// 4. Else use the median supported size (conservative middle).
  /// 5. Else the sole available size.
  /// Quality prioritization (.quality) is applied before this negotiation.
  private func applyMaxPhotoDimensions() {
    if #available(iOS 16.0, *) {
      let supported = (currentDevice?.activeFormat.supportedMaxPhotoDimensions ?? [])
        .filter { $0.width > 0 && $0.height > 0 }
      guard !supported.isEmpty else {
        activeMaxPhotoDimensions = nil
        noteFallback("no_max_photo_dimensions")
        return
      }

      func pixels(_ d: CMVideoDimensions) -> Int64 {
        Int64(d.width) * Int64(d.height)
      }

      /// Absolute deviation from 4:3 — Camera.app Photo aspect (no wide crop).
      func fourThreeDelta(_ d: CMVideoDimensions) -> Double {
        let longSide = Double(max(d.width, d.height))
        let shortSide = Double(min(d.width, d.height))
        guard shortSide > 0 else { return .greatestFiniteMagnitude }
        return abs((longSide / shortSide) - (4.0 / 3.0))
      }

      let sorted = supported.sorted { pixels($0) < pixels($1) }
      let maxProcessed: Int64 = 12_500_000
      let minUseful: Int64 = 8_000_000
      // Treat near-4:3 as Photo; reject clear 16:9 center-crops when 4:3 exists.
      let fourThree = sorted.filter { fourThreeDelta($0) <= 0.08 }

      let best: CMVideoDimensions
      if let underCap = fourThree.last(where: { pixels($0) <= maxProcessed }) {
        best = underCap
      } else if let underCap = sorted.last(where: { pixels($0) <= maxProcessed }) {
        best = underCap
        if fourThreeDelta(underCap) > 0.08 {
          noteFallback("max_photo_dims_non_4_3")
        }
      } else if let useful = fourThree.first(where: { pixels($0) >= minUseful })
                  ?? sorted.first(where: { pixels($0) >= minUseful })
      {
        best = useful
        noteFallback("max_photo_dims_above_12mp_floor")
      } else {
        best = (fourThree.isEmpty ? sorted : fourThree)[
          (fourThree.isEmpty ? sorted : fourThree).count / 2
        ]
        noteFallback("max_photo_dims_median")
      }

      photoOutput.maxPhotoDimensions = best
      activeMaxPhotoDimensions = best
      NSLog(
        "\(Self.logPrefix) selected maxPhotoDimensions "
          + "\(best.width)x\(best.height) from \(sorted.count) options "
          + "(prefer 4:3 ≤12.5MP for Camera.app-matching FOV)"
      )
      return
    }

    // iOS 15: keep legacy high-resolution path (compatible with .quality).
    photoOutput.isHighResolutionCaptureEnabled = true
    activeMaxPhotoDimensions = nil
    noteFallback("legacy_high_resolution")
  }

  private var didRegisterNotifications = false

  private func registerNotificationsIfNeeded() {
    guard !didRegisterNotifications else { return }
    didRegisterNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sessionRuntimeError(_:)),
      name: .AVCaptureSessionRuntimeError,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sessionWasInterrupted(_:)),
      name: .AVCaptureSessionWasInterrupted,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sessionInterruptionEnded(_:)),
      name: .AVCaptureSessionInterruptionEnded,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(subjectAreaDidChange(_:)),
      name: .AVCaptureDeviceSubjectAreaDidChange,
      object: nil
    )
  }

  @objc private func sessionRuntimeError(_ notification: Notification) {
    let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
    NSLog("\(Self.logPrefix) runtime error: \(error?.localizedDescription ?? "unknown")")
    if error?.code == .mediaServicesWereReset {
      sessionQueue.async { [weak self] in
        guard let self else { return }
        do {
          try self.configureLocked()
          if !self.session.isRunning {
            self.session.startRunning()
          }
        } catch {
          NSLog("\(Self.logPrefix) recover failed: \(error.localizedDescription)")
        }
      }
    }
  }

  @objc private func sessionWasInterrupted(_ notification: Notification) {
    isInterrupted = true
    var reason = "unknown"
    if let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
       let value = AVCaptureSession.InterruptionReason(rawValue: raw)
    {
      switch value {
      case .audioDeviceInUseByAnotherClient:
        reason = "audio_in_use"
      case .videoDeviceInUseByAnotherClient:
        reason = "camera_in_use"
      case .videoDeviceNotAvailableDueToSystemPressure:
        reason = "system_pressure"
      case .videoDeviceNotAvailableInBackground:
        reason = "background"
      case .videoDeviceNotAvailableWithMultipleForegroundApps:
        reason = "split_view"
      case .sensitiveContentMitigationActivated:
        reason = "sensitive_content"
      @unknown default:
        reason = "unknown"
      }
    }
    NSLog("\(Self.logPrefix) interrupted reason=\(reason)")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.sessionWasInterrupted(self, reason: reason)
    }
  }

  @objc private func sessionInterruptionEnded(_ notification: Notification) {
    isInterrupted = false
    NSLog("\(Self.logPrefix) interruption ended")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.sessionInterruptionEnded(self)
    }
    startRunning()
  }

  @objc private func subjectAreaDidChange(_ notification: Notification) {
    sessionQueue.async { [weak self] in
      guard let self, let device = self.currentDevice else { return }
      self.focusResetWorkItem?.cancel()
      self.restoreContinuousAutoFocus(on: device, resetPoint: true)
    }
  }

  private func setTorch(enabled: Bool) {
    guard let device = currentDevice, device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      if enabled, device.isTorchModeSupported(.on) {
        try device.setTorchModeOn(level: 1.0)
      } else if device.isTorchModeSupported(.off) {
        device.torchMode = .off
      }
      device.unlockForConfiguration()
    } catch {
      NSLog("\(Self.logPrefix) torch failed: \(error.localizedDescription)")
    }
  }

  private func hasEnoughStorage(minimumBytes: Int64) -> Bool {
    let path = NSTemporaryDirectory()
    guard let values = try? URL(fileURLWithPath: path)
      .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let capacity = values.volumeAvailableCapacityForImportantUsage
    else {
      return true
    }
    return capacity > minimumBytes
  }

  // MARK: - Discovery helpers

  static func discoverBestBackCamera() -> AVCaptureDevice? {
    discoverBestCamera(front: false)
  }

  static func discoverBestCamera(front: Bool) -> AVCaptureDevice? {
    if front {
      return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        ?? AVCaptureDevice.default(for: .video)
    }
    let types: [AVCaptureDevice.DeviceType] = [
      .builtInTripleCamera,
      .builtInDualWideCamera,
      .builtInDualCamera,
      .builtInWideAngleCamera,
    ]
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: types,
      mediaType: .video,
      position: .back
    )
    if let preferred = discovery.devices.first {
      return preferred
    }
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  }

  static func buildZoomChips(for device: AVCaptureDevice) -> (
    chips: [NativeCameraZoomChip],
    wideDeviceFactor: CGFloat
  ) {
    let minZ = device.minAvailableVideoZoomFactor
    let maxZ = min(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor)
    let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
      .map { CGFloat(truncating: $0) }
      .filter { $0 > minZ + 0.05 && $0 <= maxZ + 0.05 }
      .sorted()

    // Camera.app display zoom = deviceZoom * displayVideoZoomFactorMultiplier (iOS 18+).
    // wideDeviceFactor is the device zoom that maps to UI "1x".
    let wideDeviceFactor = Self.wideDeviceFactor(
      for: device,
      minZ: minZ,
      switchOvers: switchOvers
    )

    var deviceFactors: [CGFloat] = []
    func appendDevice(_ value: CGFloat) {
      let clamped = max(minZ, min(maxZ, value))
      if !deviceFactors.contains(where: { abs($0 - clamped) < 0.08 }) {
        deviceFactors.append(clamped)
      }
    }

    let minDisplayZoom = minZ / max(wideDeviceFactor, 0.01)
    let maxDisplayZoom = maxZ / max(wideDeviceFactor, 0.01)

    // 0.5x = exact hardware minimum zoom (full ultra-wide FOV). Never use a
    // slightly higher ratio that would digitally crop past Camera.app 0.5x.
    if minDisplayZoom <= 0.55, maxDisplayZoom >= 0.5 {
      appendDevice(minZ)
    }
    for whole in 1...4 {
      let display = CGFloat(whole)
      if display >= minDisplayZoom - 0.02, display <= maxDisplayZoom + 0.02 {
        appendDevice(wideDeviceFactor * display)
      }
    }
    if deviceFactors.isEmpty {
      appendDevice(minZ)
    }

    deviceFactors.sort()
    let chips = deviceFactors.map { deviceFactor -> NativeCameraZoomChip in
      let display = deviceFactor / max(wideDeviceFactor, 0.01)
      return NativeCameraZoomChip(
        deviceFactor: deviceFactor,
        displayFactor: display,
        label: formatDisplayZoomLabel(display)
      )
    }
    return (chips, wideDeviceFactor)
  }

  /// Device zoom factor that Camera.app labels as 1x.
  private static func wideDeviceFactor(
    for device: AVCaptureDevice,
    minZ: CGFloat,
    switchOvers: [CGFloat]
  ) -> CGFloat {
    if #available(iOS 18.0, *) {
      let multiplier = device.displayVideoZoomFactorMultiplier
      if multiplier > 0.01 {
        // displayZoom = deviceZoom * multiplier ⇒ deviceZoom@1x = 1 / multiplier
        return 1.0 / multiplier
      }
    }

    // Pre-iOS 18 fallback: Match Camera.app labeling from virtual switchovers.
    // Dual-wide / triple: device zoom 1 = UI 0.5x (UW), first switchover = UI 1x.
    // Dual (wide+tele) / single wide: device zoom 1 = UI 1x.
    switch device.deviceType {
    case .builtInDualWideCamera, .builtInTripleCamera:
      return switchOvers.first ?? max(minZ, 1)
    case .builtInDualCamera:
      return 1
    default:
      if minZ < 0.95 {
        return 1
      }
      if let first = switchOvers.first,
         first >= 1.8,
         minZ <= 1.05,
         device.constituentDevices.contains(where: {
           $0.deviceType == .builtInUltraWideCamera
         })
      {
        return first
      }
      return 1
    }
  }

  static func formatDisplayZoomLabel(_ display: CGFloat) -> String {
    if abs(display - 0.5) < 0.06 {
      return "0.5x"
    }
    if display < 1 {
      return String(format: "%.1fx", Double(display))
    }
    if abs(display - display.rounded()) < 0.06 {
      return "\(Int(display.rounded()))x"
    }
    return String(format: "%.1fx", Double(display))
  }

  /// Converts a device zoom factor into Camera.app-style display zoom.
  func displayZoomFactor(forDeviceZoom deviceZoom: CGFloat) -> CGFloat {
    deviceZoom / max(wideDeviceZoomFactor, 0.01)
  }

  static func probeCapabilities(forVideo: Bool) -> NativeCameraCapabilitiesSnapshot {
    let session = NativeCameraSession()
    guard let device = discoverBestBackCamera() else {
      return NativeCameraCapabilitiesSnapshot()
    }
    session.currentDevice = device
    let built = buildZoomChips(for: device)
    session.zoomChips = built.chips
    session.wideDeviceZoomFactor = built.wideDeviceFactor
    session.isVideoMode = forVideo
    return session.capabilitiesSnapshot()
  }

  static func makeTempMediaURL(extension ext: String) throws -> URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let folder = dir.appendingPathComponent("SmartNPS360Camera", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let name = "capture_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8)).\(ext)"
    return folder.appendingPathComponent(name)
  }

  static func error(code: String, message: String) -> NSError {
    NSError(domain: code, code: 0, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func lensLabel(for device: AVCaptureDevice, zoom: CGFloat) -> String {
    let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
    if device.minAvailableVideoZoomFactor < 0.9, zoom < (switchOvers.first ?? 1.0) - 0.05 {
      return "ultraWide"
    }
    if let first = switchOvers.first, zoom >= first - 0.05 {
      if switchOvers.count >= 2, zoom >= switchOvers[1] - 0.05 {
        return "telephoto"
      }
      // Between first switchover and second → typically wide after UW, or tele on dual.
      if device.deviceType == .builtInDualCamera || device.deviceType == .builtInTripleCamera {
        if switchOvers.count == 1 || zoom >= first {
          // Dual: switchover is tele; Triple: first is wide, second is tele.
          if device.deviceType == .builtInDualCamera {
            return "telephoto"
          }
          if switchOvers.count >= 2, zoom >= switchOvers[1] - 0.05 {
            return "telephoto"
          }
          return "wide"
        }
      }
    }
    return "wide"
  }
}

// MARK: - Photo delegate

extension NativeCameraSession: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings
  ) {
    CamPerf.stage("WILL_BEGIN_CAPTURE")
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
  ) {
    CamPerf.stage("WILL_CAPTURE_PHOTO")
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    CamPerf.markProcessedCallback(captureId: nil)
    if let error {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.delegate?.session(
          self,
          didFailWithCode: "capture_failed",
          message: error.localizedDescription
        )
      }
      return
    }

    // Pull bytes on the photo callback (AVCapturePhoto lifetime), then encode /
    // write off this queue so the capture pipeline can recover quickly on
    // Pro-class Fusion stills.
    CamPerf.stage("FILE_DATA_REPRESENTATION_START")
    guard let rawData = photo.fileDataRepresentation() else {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.delegate?.session(
          self,
          didFailWithCode: "capture_failed",
          message: "Photo data missing"
        )
      }
      return
    }
    CamPerf.markFileDataEnd(captureId: nil)

    let dims = photo.resolvedSettings.photoDimensions
    let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32
    let zoom = currentDevice?.videoZoomFactor ?? 1
    let lens = currentDevice.map { lensLabel(for: $0, zoom: zoom) } ?? "wide"
    let cameraPosition = cameraPositionWireName
    let captureMode = captureModeWireName
    let fallback = fallbackLevelWireName
    let preferHeic = self.preferHeic
    let extensionMode: String?
    if #available(iOS 13.0, *) {
      extensionMode = currentDevice?.isVirtualDevice == true ? "virtualMultiCam" : "single"
    } else {
      extensionMode = nil
    }

    photoProcessingQueue.async { [weak self] in
      guard let self else { return }
      do {
        let data = try self.finalizePhotoData(rawData, preferHeic: preferHeic)
        let heic = self.isHeicData(data)
        let ext = heic ? "heic" : "jpg"
        let mime = heic ? "image/heic" : "image/jpeg"

        if !self.hasEnoughStorage(minimumBytes: Int64(data.count) + 5 * 1024 * 1024) {
          throw Self.error(code: "insufficient_storage", message: "Not enough storage for photo")
        }

        let captureId = UUID().uuidString
        CamPerf.stage("FILE_WRITE_START", captureId: captureId, detail: "bytes=\(data.count)")
        let url = try Self.makeTempMediaURL(extension: ext)
        try data.write(to: url, options: .atomic)
        CamPerf.markWriteEnd(captureId: captureId)

        CamPerf.stage("PHOTO_VALIDATION_START", captureId: captureId)
        let cgOrientation =
          CGImagePropertyOrientation(rawValue: orientation ?? CGImagePropertyOrientation.right.rawValue)
          ?? .right
        let degrees = NativeCameraOrientation.degrees(from: cgOrientation)
        CamPerf.markValidationEnd(captureId: captureId)

        var metadata: [String: Any] = [
          "type": "photo",
          "captureId": captureId,
          "capturedAtMs": Int64(Date().timeIntervalSince1970 * 1000),
          "width": Int(dims.width),
          "height": Int(dims.height),
          "cameraPosition": cameraPosition,
          "lens": lens,
          "zoomFactor": Double(zoom),
          "fileSizeBytes": data.count,
          "mimeType": mime,
          "orientationDegrees": degrees,
          "captureMode": captureMode,
          "photoDimensions": "\(dims.width)x\(dims.height)",
        ]
        if let fallback {
          metadata["fallbackLevel"] = fallback
        }
        if let extensionMode {
          metadata["extensionMode"] = extensionMode
        }

        CamPerf.stage(
          "PHOTO_FILE_BYTES",
          captureId: captureId,
          detail: "bytes=\(data.count) dim=\(dims.width)x\(dims.height)"
        )
        CamPerf.markNativeResultFinish(captureId: captureId)
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.delegate?.session(self, didCapturePhotoAt: url, metadata: metadata)
        }
      } catch {
        let ns = error as NSError
        let code = ns.domain.contains("_") ? ns.domain : "capture_failed"
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.delegate?.session(
            self,
            didFailWithCode: code,
            message: ns.localizedDescription
          )
        }
      }
    }
  }

  private func finalizePhotoData(_ data: Data, preferHeic: Bool) throws -> Data {
    if preferHeic, isHeicData(data) {
      return data
    }

    // preferHeic=false (default): high-quality JPEG for server compatibility.
    if isHeicData(data) {
      return try convertImageDataToJPEG(data, quality: 0.97)
    }

    return data
  }

  /// Converts HEIC/HEIF → JPEG while preserving EXIF orientation metadata.
  private func convertImageDataToJPEG(_ data: Data, quality: CGFloat) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw Self.error(code: "capture_failed", message: "Unable to read image data")
    }
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw Self.error(code: "capture_failed", message: "Unable to decode image")
    }
    let properties =
      (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]

    let mutable = NSMutableData()
    let uti: CFString
    if #available(iOS 14.0, *) {
      uti = UTType.jpeg.identifier as CFString
    } else {
      uti = "public.jpeg" as CFString
    }
    guard let destination = CGImageDestinationCreateWithData(mutable, uti, 1, nil) else {
      throw Self.error(code: "capture_failed", message: "Unable to create JPEG encoder")
    }

    var destProps = properties
    destProps[kCGImageDestinationLossyCompressionQuality] = quality
    CGImageDestinationAddImage(destination, cgImage, destProps as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw Self.error(code: "capture_failed", message: "Unable to encode JPEG")
    }
    return mutable as Data
  }

  static func deviceSupportsHeic() -> Bool {
    if #available(iOS 14.0, *) {
      return UTType.heic.preferredMIMEType != nil
    }
    return true
  }

  private func isHeicData(_ data: Data) -> Bool {
    // ftyp....heic / heif brand in ISO BMFF header
    guard data.count > 12 else { return false }
    let brand = data.subdata(in: 8..<12)
    if let ascii = String(data: brand, encoding: .ascii)?.lowercased() {
      return ascii.contains("heic") || ascii.contains("heif") || ascii.contains("mif1")
    }
    return false
  }
}

// MARK: - Movie delegate

extension NativeCameraSession: AVCaptureFileOutputRecordingDelegate {
  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    setTorch(enabled: false)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.session(self, didChangeRecording: false)
    }

    if let error {
      let ns = error as NSError
      try? FileManager.default.removeItem(at: outputFileURL)
      let code: String
      if ns.code == AVError.diskFull.rawValue {
        code = "insufficient_storage"
      } else if ns.code == AVError.sessionWasInterrupted.rawValue {
        code = "interrupted"
      } else {
        code = "recording_failed"
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.delegate?.session(self, recordingDidFail: code, message: ns.localizedDescription)
      }
      return
    }

    let zoom = currentDevice?.videoZoomFactor ?? 1
    let lens = currentDevice.map { lensLabel(for: $0, zoom: zoom) } ?? "wide"
    let display = NativeCameraOrientation.videoDisplaySize(at: outputFileURL)
    let duration = NativeCameraOrientation.videoDurationMs(at: outputFileURL)
    let degrees = NativeCameraOrientation.videoOrientationDegrees(at: outputFileURL)
    let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? NSNumber)?
      .intValue

    var metadata: [String: Any] = [
      "type": "video",
      "captureId": UUID().uuidString,
      "capturedAtMs": Int64((videoStartDate ?? Date()).timeIntervalSince1970 * 1000),
      "cameraPosition": cameraPositionWireName,
      "lens": lens,
      "zoomFactor": Double(zoom),
      "mimeType": "video/quicktime",
      "durationMs": duration,
      "orientationDegrees": degrees,
      "captureMode": captureModeWireName,
    ]
    if let fallback = fallbackLevelWireName {
      metadata["fallbackLevel"] = fallback
    }
    if let display {
      metadata["width"] = display.width
      metadata["height"] = display.height
    }
    if let size {
      metadata["fileSizeBytes"] = size
    }
    if #available(iOS 13.0, *) {
      metadata["extensionMode"] = currentDevice?.isVirtualDevice == true ? "virtualMultiCam" : "single"
    }

    NSLog("\(Self.logPrefix) video saved \(outputFileURL.lastPathComponent)")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.session(self, didFinishRecordingAt: outputFileURL, metadata: metadata)
    }
  }
}
