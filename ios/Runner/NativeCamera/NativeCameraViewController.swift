import AVFoundation
import UIKit

/// Full-screen chrome host: empty (transparent) areas return `nil` from hit
/// testing so touches reach the preview / zoom pills underneath. Subviews
/// (flash, shutter, close, etc.) still receive taps normally.
private final class NativeCameraControlsOverlayView: UIView {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

/// Camera.app-inspired continuous zoom dial. The dial is presentation-only;
/// AVFoundation remains the single source of truth for the applied zoom.
private final class NativeCameraZoomWheelView: UIView {
  private var minimumZoom: CGFloat = 1
  private var maximumZoom: CGFloat = 1
  private var currentZoom: CGFloat = 1
  private var stops: [CGFloat] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = true
    accessibilityElementsHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(
    minimum: CGFloat,
    maximum: CGFloat,
    current: CGFloat,
    stops: [CGFloat]
  ) {
    minimumZoom = max(minimum, 0.01)
    maximumZoom = max(maximum, minimumZoom)
    currentZoom = max(minimumZoom, min(maximumZoom, current))
    self.stops = stops
    setNeedsDisplay()
  }

  func update(current: CGFloat) {
    currentZoom = max(minimumZoom, min(maximumZoom, current))
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext(), rect.width > 0, rect.height > 0 else {
      return
    }

    // In landscape the control follows the shutter rail: a vertical arc with
    // larger values above the fixed marker and smaller values below it.
    // Clip from the trailing edge only so the left/top/bottom arc silhouette
    // stays intact while the dial clears the shutter.
    let trailingClip: CGFloat = 40
    let visibleWidth = max(rect.width - trailingClip, 1)
    context.saveGState()
    context.clip(to: CGRect(x: rect.minX, y: rect.minY, width: visibleWidth, height: rect.height))

    let center = CGPoint(x: rect.minX + visibleWidth + 60, y: rect.midY)
    let radius = min(rect.height * 0.54, visibleWidth + 10)
    let startAngle = CGFloat.pi * 0.66
    let endAngle = CGFloat.pi * 1.34
    let arcSpan = endAngle - startAngle
    // Keep the live selection near the low end of the dial (20% from the
    // bottom) so 0.5x starts there instead of mid-arc (50%).
    let markerAngle = startAngle + arcSpan * 0.20
    let radiansPerZoomUnit: CGFloat = 0.42

    func angle(for value: CGFloat) -> CGFloat {
      markerAngle + (value - currentZoom) * radiansPerZoomUnit
    }

    func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
      CGPoint(
        x: center.x + cos(angle) * radius,
        y: center.y + sin(angle) * radius
      )
    }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: UIColor.black.cgColor)
    context.setFillColor(UIColor(white: 0.05, alpha: 0.64).cgColor)
    let background = UIBezierPath()
    background.addArc(
      withCenter: center,
      radius: radius + 24,
      startAngle: startAngle,
      endAngle: endAngle,
      clockwise: true
    )
    background.addArc(
      withCenter: center,
      radius: radius - 42,
      startAngle: endAngle,
      endAngle: startAngle,
      clockwise: false
    )
    background.close()
    background.fill()
    context.restoreGState()

    // Linear 0.1x divisions keep every zoom interval physically consistent.
    // In particular, 4x–5x and 5x–6x no longer collapse together while the
    // low end consumes most of the wheel.
    let minorStep: CGFloat = 0.1
    let minorCount = max(Int(ceil((maximumZoom - minimumZoom) / minorStep)), 1)
    for index in 0...minorCount {
      let value = minimumZoom + CGFloat(index) * minorStep
      guard value <= maximumZoom * 1.001 else { continue }
      let tickAngle = angle(for: value)
      guard tickAngle >= startAngle, tickAngle <= endAngle else { continue }
      let isMedium = index % 5 == 0
      let tickStart = point(angle: tickAngle, radius: radius - (isMedium ? 13 : 8))
      let tickEnd = point(angle: tickAngle, radius: radius)
      context.setStrokeColor(UIColor(white: 1, alpha: isMedium ? 0.76 : 0.42).cgColor)
      context.setLineWidth(isMedium ? 1.35 : 0.85)
      context.move(to: tickStart)
      context.addLine(to: tickEnd)
      context.strokePath()
    }

    // Draw only useful major levels. Up to 5x each whole factor is shown;
    // larger cameras add 5x milestones plus their exact maximum endpoint.
    var majorLevels = stops.filter { $0 >= minimumZoom && $0 <= maximumZoom }
    if minimumZoom <= 0.5, maximumZoom >= 0.5 { majorLevels.append(0.5) }
    let wholeMaximum = Int(floor(maximumZoom))
    if wholeMaximum >= 1 {
      for value in 1...min(wholeMaximum, 5) { majorLevels.append(CGFloat(value)) }
      if wholeMaximum > 5 {
        for value in stride(from: 10, through: wholeMaximum, by: 5) {
          majorLevels.append(CGFloat(value))
        }
      }
    }
    // Always expose the real endpoint (including the recommended 6x cap).
    if maximumZoom > 5 {
      majorLevels.append(maximumZoom)
    }
    majorLevels.sort()
    majorLevels = majorLevels.reduce(into: []) { result, value in
      if !result.contains(where: { abs($0 - value) < 0.06 }) { result.append(value) }
    }

    let majorAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: UIColor(white: 1, alpha: 0.92),
    ]
    for value in majorLevels {
      let majorAngle = angle(for: value)
      guard majorAngle >= startAngle + 0.03, majorAngle <= endAngle - 0.03 else { continue }
      let majorStart = point(angle: majorAngle, radius: radius - 18)
      let majorEnd = point(angle: majorAngle, radius: radius + 1)
      context.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
      context.setLineWidth(1.8)
      context.move(to: majorStart)
      context.addLine(to: majorEnd)
      context.strokePath()

      let text = NativeCameraSession.formatDisplayZoomLabel(value)
      let size = text.size(withAttributes: majorAttributes)
      let labelPoint = point(angle: majorAngle, radius: radius - 25)
      text.draw(
        at: CGPoint(x: labelPoint.x - size.width / 2, y: labelPoint.y - size.height / 2),
        withAttributes: majorAttributes
      )
    }

    // Fixed selection mark and current value, matching the native iPhone dial.
    let markerStart = point(angle: markerAngle, radius: radius - 21)
    let markerEnd = point(angle: markerAngle, radius: radius + 5)
    let yellow = UIColor(red: 1, green: 214 / 255, blue: 10 / 255, alpha: 1)
    context.setStrokeColor(yellow.cgColor)
    context.setLineWidth(3)
    context.move(to: markerStart)
    context.addLine(to: markerEnd)
    context.strokePath()

    let currentText = NativeCameraSession.formatDisplayZoomLabel(currentZoom)
    let currentAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold),
      .foregroundColor: yellow,
    ]
    let currentSize = currentText.size(withAttributes: currentAttributes)
    let currentLabelPoint = point(angle: markerAngle, radius: radius - 58)
    currentText.draw(
      at: CGPoint(
        x: currentLabelPoint.x - currentSize.width / 2,
        y: currentLabelPoint.y - currentSize.height / 2
      ),
      withAttributes: currentAttributes
    )

    context.restoreGState()
  }
}

/// Full-screen landscape camera UI matching VisitVideoRecorderScreen chrome.
final class NativeCameraViewController: UIViewController {
  static let logPrefix = "[SmartNPS360Camera]"

  struct Configuration {
    var initialIsVideo: Bool
    var allowModeSwitch: Bool
    var landscapeOnly: Bool
    var rearCameraOnly: Bool
    var quality: NativeCameraCaptureQuality
    var preferHeic: Bool
    var showOnboarding: Bool = false
    var onboardingSteps: [[String: Any]] = []
  }

  enum Outcome {
    case success([String: Any])
    case canceled(onboardingCompleted: Bool)
    case failure(code: String, message: String)
  }

  private enum Chrome {
    static let glassFill = UIColor(white: 0, alpha: 0.42)
    static let glassBorder = UIColor(white: 1, alpha: 0.24)
    static let zoomRail = UIColor(
      red: 58 / 255,
      green: 58 / 255,
      blue: 60 / 255,
      alpha: 110 / 255
    )
    static let zoomChip = UIColor(
      red: 44 / 255,
      green: 44 / 255,
      blue: 46 / 255,
      alpha: 153 / 255
    )
    static let zoomChipSelected = UIColor(
      red: 44 / 255,
      green: 44 / 255,
      blue: 46 / 255,
      alpha: 204 / 255
    )
    static let zoomSelectedText = UIColor(
      red: 1,
      green: 214 / 255,
      blue: 10 / 255,
      alpha: 1
    )
    static let orange = UIColor(
      red: 228 / 255,
      green: 142 / 255,
      blue: 21 / 255,
      alpha: 1
    )
    static let red = UIColor(
      red: 220 / 255,
      green: 38 / 255,
      blue: 38 / 255,
      alpha: 1
    )
    static let primary = UIColor(
      red: 2 / 255,
      green: 42 / 255,
      blue: 103 / 255,
      alpha: 1
    )
  }

  private enum PendingCaptureAction {
    case none
    case photo
    case startVideo
  }

  var onFinish: ((Outcome) -> Void)?

  private let configuration: Configuration
  private let cameraSession = NativeCameraSession()

  private let previewContainer = UIView()
  /// Hosts zoom pills over the aspect-fit video (not letterbox / shutter chrome).
  private let videoContentGuide = UILayoutGuide()
  private var videoGuideLeading: NSLayoutConstraint?
  private var videoGuideTop: NSLayoutConstraint?
  private var videoGuideWidth: NSLayoutConstraint?
  private var videoGuideHeight: NSLayoutConstraint?
  private var zoomTrailingToVideoConstraint: NSLayoutConstraint?
  private var flashLeadingConstraint: NSLayoutConstraint?
  /// Landscape-only trailing inset before the shutter rail. Portrait uses 0.
  private let previewTrailingPaddingLandscape: CGFloat = 0
  /// Landscape-only inset for flash from the leading safe edge.
  private let flashLeadingPaddingLandscape: CGFloat = 28
  private let flashLeadingPaddingPortrait: CGFloat = 18
  private var previewTrailingToRailConstraint: NSLayoutConstraint?
  private var previewTrailingToViewConstraint: NSLayoutConstraint?
  private var closeLandscapeConstraints: [NSLayoutConstraint] = []
  private var closePortraitConstraints: [NSLayoutConstraint] = []
  /// Full-screen chrome host: transparent areas pass touches through to the
  /// preview/zoom underneath; real controls still receive hits normally.
  private let controlsOverlay = NativeCameraControlsOverlayView()
  private let closeButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .system)
  private let flashLabel = UILabel()
  private let flashModeTray = UIView()
  private let flashModeStack = UIStackView()
  private let flipButton = UIButton(type: .system)
  private let shutterButton = UIButton(type: .custom)
  private let modeControl = UISegmentedControl(items: ["Photo", "Video"])
  private let recordingBadge = UIView()
  private let recordingDot = UIView()
  private let timerLabel = UILabel()
  private let zoomRail = UIView()
  private let zoomStack = UIStackView()
  private let zoomWheel = NativeCameraZoomWheelView()
  private let shutterRail = UIView()
  private let exposureStack = UIStackView()
  private let exposureSlider = UISlider()
  private let exposureValueLabel = UILabel()
  private let hintLabel = UILabel()
  private let onboardingOverlay = NativeCameraOnboardingOverlay()
  private let onboardingSpot = UIView()
  private var onboardingCompleted = false
  private var onboardingStarted = false
  private var onboardingFocusDemo = false
  private var onboardingZoomWheel = false
  private let focusIndicator = UIView()
  private let focusExposureControl = UIView()
  private let focusExposureTrack = UIView()
  private let focusExposureSun = UIImageView()
  private let busyOverlay = UIActivityIndicatorView(style: .large)
  private let portraitBlockOverlay = UIView()
  private let portraitCard = UIView()
  private let portraitTitleLabel = UILabel()
  private let portraitMessageLabel = UILabel()
  private let portraitIconView = UIImageView()
  private let rotateHintAnimationKey = "visit.rotateHint"

  private var zoomButtons: [UIButton] = []
  private var isVideoMode = false
  private var isFinishing = false
  private var isPortraitBlocked = false
  private var recordingTimer: Timer?
  private var recordingStartedAt: Date?
  private var currentZoomFactor: CGFloat = 1
  private var pinchStartZoom: CGFloat = 1
  private var verticalExposureStart: Float = 0
  private var shutterZoomStart: CGFloat = 1
  private var shutterWheelStartX: CGFloat = 0
  private var shutterWheelActive = false
  private var wheelZoomStart: CGFloat = 1
  private var wheelTouchStartY: CGFloat = 0
  private var wheelZoomArmed = false
  private var lastWheelHapticIndex: Int?
  private let zoomFeedback = UISelectionFeedbackGenerator()
  private lazy var zoomWheelDismissTap: UITapGestureRecognizer = {
    let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissZoomWheel(_:)))
    gesture.cancelsTouchesInView = false
    gesture.delegate = self
    return gesture
  }()
  private var pendingCaptureAction: PendingCaptureAction = .none
  private var shutterLongPressActive = false
  private var focusDismissWorkItem: DispatchWorkItem?
  private var photoCaptureTimeoutWorkItem: DispatchWorkItem?
  /// Upper bound for computational stills on Pro Fusion devices (no quality drop).
  private static let photoCaptureTimeoutSeconds: TimeInterval = 25
  /// Bumped on each shutter / timeout so late ISP callbacks cannot leave UI stuck
  /// or finish after the officer already dismissed a timeout alert.
  private var photoCaptureEpoch: UInt64 = 0
  private var activePhotoCaptureEpoch: UInt64?

  init(configuration: Configuration) {
    self.configuration = configuration
    self.isVideoMode = configuration.initialIsVideo
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
    modalTransitionStyle = .coverVertical
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    recordingTimer?.invalidate()
    focusDismissWorkItem?.cancel()
    photoCaptureTimeoutWorkItem?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  /// Allow portrait so we can show the same rotate-to-landscape prompt as before.
  /// Capture itself remains landscape-only when `landscapeOnly` is true.
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    [.portrait, .landscapeLeft, .landscapeRight]
  }

  override var shouldAutorotate: Bool { true }

  override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
    let current = NativeCameraOrientation.currentInterfaceOrientation()
    if NativeCameraOrientation.isInterfaceLandscape(current) {
      return current
    }
    // Prefer staying in the current orientation so the landscape prompt can appear.
    return .portrait
  }

  override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
    super.viewDidLoad()
    let t0 = CFAbsoluteTimeGetCurrent()
    func ms() -> Int { Int((CFAbsoluteTimeGetCurrent() - t0) * 1000) }
    NSLog("\(Self.logPrefix) VIEW_CONTROLLER_CREATED")
    view.backgroundColor = .black
    cameraSession.delegate = self
    buildUI()
    configureGestures()
    observeLifecycle()
    syncPortraitBlock()
    NSLog("\(Self.logPrefix) SESSION_CONFIG_START +\(ms())ms")

    cameraSession.configure(
      isVideoMode: isVideoMode,
      quality: configuration.quality,
      preferHeic: configuration.preferHeic,
      rearCameraOnly: configuration.rearCameraOnly
    ) { [weak self] ok in
      guard let self else { return }
      NSLog("\(Self.logPrefix) SESSION_CONFIG_END ok=\(ok) +\(ms())ms")
      if ok {
        // Start preview ASAP; secondary chrome can refresh after.
        self.cameraSession.startRunning()
        NSLog("\(Self.logPrefix) SESSION_START_RUNNING_REQUESTED +\(ms())ms")
        self.applyVideoOrientationFromInterface()
        self.syncPortraitBlock()
        self.refreshZoomChips()
        self.applyDefaultPhotoZoomIfNeeded()
        self.refreshFlashButton()
        self.refreshFlipButton()
        self.refreshExposureControls()
        NSLog("\(Self.logPrefix) CAMERA_READY +\(ms())ms")
        self.maybeStartOnboarding()
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    cameraSession.previewLayer.frame = previewContainer.bounds
    syncVideoContentGuide()
    applyVideoOrientationFromInterface()
    syncPortraitBlock()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    cameraSession.startRunning()
    syncPortraitBlock()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Start the guide as soon as Capture is on screen (not after taking a photo).
    maybeStartOnboarding()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if isBeingDismissed || isMovingFromParent {
      cameraSession.stopRunning()
    }
  }

  override func viewWillTransition(
    to size: CGSize,
    with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: { [weak self] _ in
      self?.applyVideoOrientationFromInterface()
      self?.syncPortraitBlock(using: size)
    }, completion: { [weak self] _ in
      self?.applyVideoOrientationFromInterface()
      self?.syncPortraitBlock()
    })
  }

  // MARK: - UI

  private func buildUI() {
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.backgroundColor = .black
    view.addSubview(previewContainer)
    cameraSession.previewLayer.frame = view.bounds
    previewContainer.layer.addSublayer(cameraSession.previewLayer)
    previewContainer.addLayoutGuide(videoContentGuide)

    controlsOverlay.translatesAutoresizingMaskIntoConstraints = false
    controlsOverlay.backgroundColor = .clear
    controlsOverlay.isMultipleTouchEnabled = true
    view.isMultipleTouchEnabled = true
    view.addSubview(controlsOverlay)

    NSLayoutConstraint.activate([
      previewContainer.topAnchor.constraint(equalTo: view.topAnchor),
      previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      // Flush to the left — no leading padding.
      previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      controlsOverlay.topAnchor.constraint(equalTo: view.topAnchor),
      controlsOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      controlsOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      controlsOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])

    styleGlassCircleButton(
      closeButton,
      systemName: "xmark",
      accessibility: "Close"
    )
    // Camera.app close on black chrome: soft fill, no harsh ring.
    closeButton.backgroundColor = UIColor(white: 1, alpha: 0.18)
    closeButton.layer.borderWidth = 0
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

    styleGlassCircleButton(
      flashButton,
      systemName: "bolt.badge.automatic",
      accessibility: "Flash"
    )
    flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)

    styleGlassCircleButton(
      flipButton,
      systemName: "camera.rotate",
      accessibility: "Flip camera"
    )
    flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
    flipButton.isHidden = true

    // Kept for compatibility; hidden from primary chrome (tap/hold shutter instead).
    modeControl.translatesAutoresizingMaskIntoConstraints = false
    modeControl.selectedSegmentIndex = isVideoMode ? 1 : 0
    modeControl.isHidden = true
    modeControl.isUserInteractionEnabled = false
    modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

    buildRecordingBadge()
    buildZoomRail()
    buildShutterRail()
    buildFlashModeTray()

    focusIndicator.frame = CGRect(x: 0, y: 0, width: 72, height: 72)
    focusIndicator.layer.borderColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1).cgColor
    focusIndicator.layer.borderWidth = 1.5
    focusIndicator.layer.cornerRadius = 8
    focusIndicator.alpha = 0
    focusIndicator.isUserInteractionEnabled = false
    previewContainer.addSubview(focusIndicator)

    buildFocusExposureControl()

    busyOverlay.translatesAutoresizingMaskIntoConstraints = false
    busyOverlay.color = .white
    busyOverlay.hidesWhenStopped = true

    controlsOverlay.addSubview(recordingBadge)
    controlsOverlay.addSubview(shutterRail)
    // Zoom controls on the preview so pills sit on the live video, not chrome.
    previewContainer.addSubview(zoomRail)
    previewContainer.addSubview(zoomWheel)
    // Flash lives on the leading black gutter (Camera.app layout).
    controlsOverlay.addSubview(flashButton)
    controlsOverlay.addSubview(flashLabel)
    controlsOverlay.addSubview(flashModeTray)
    controlsOverlay.addSubview(exposureStack)
    controlsOverlay.addSubview(modeControl)
    controlsOverlay.addSubview(busyOverlay)
    buildPortraitBlockOverlay()
    controlsOverlay.addSubview(portraitBlockOverlay)
    // Close on the trailing black chrome (sibling so it stays tappable in portrait).
    controlsOverlay.addSubview(closeButton)
    controlsOverlay.bringSubviewToFront(closeButton)

    onboardingOverlay.translatesAutoresizingMaskIntoConstraints = false
    onboardingOverlay.isHidden = true
    onboardingOverlay.onCompleted = { [weak self] in
      self?.onboardingCompleted = true
    }
    onboardingOverlay.onFinishedUi = { [weak self] in
      self?.clearOnboardingFocusDemo()
      self?.clearOnboardingZoomWheel()
    }
    onboardingOverlay.targetResolver = { [weak self] id in
      self?.resolveOnboardingTarget(id)
    }
    onboardingOverlay.stepPreparer = { [weak self] id in
      self?.prepareOnboardingStep(id)
    }
    onboardingSpot.isUserInteractionEnabled = false
    onboardingSpot.backgroundColor = .clear
    onboardingSpot.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.addSubview(onboardingSpot)
    view.addSubview(onboardingOverlay)
    view.bringSubviewToFront(onboardingOverlay)
    NSLayoutConstraint.activate([
      onboardingSpot.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
      onboardingSpot.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
      onboardingSpot.widthAnchor.constraint(equalToConstant: 100),
      onboardingSpot.heightAnchor.constraint(equalToConstant: 100),
      onboardingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
      onboardingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      onboardingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      onboardingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    let guide = controlsOverlay.safeAreaLayoutGuide
    let previewTrailingToRail = previewContainer.trailingAnchor.constraint(
      equalTo: shutterRail.leadingAnchor,
      constant: -previewTrailingPaddingLandscape
    )
    let previewTrailingToView = previewContainer.trailingAnchor.constraint(
      equalTo: view.trailingAnchor
    )
    previewTrailingToView.isActive = false
    previewTrailingToRailConstraint = previewTrailingToRail
    previewTrailingToViewConstraint = previewTrailingToView

    let videoLeading = videoContentGuide.leadingAnchor.constraint(
      equalTo: previewContainer.leadingAnchor
    )
    let videoTop = videoContentGuide.topAnchor.constraint(equalTo: previewContainer.topAnchor)
    let videoWidth = videoContentGuide.widthAnchor.constraint(equalToConstant: 100)
    let videoHeight = videoContentGuide.heightAnchor.constraint(equalToConstant: 100)
    videoGuideLeading = videoLeading
    videoGuideTop = videoTop
    videoGuideWidth = videoWidth
    videoGuideHeight = videoHeight

    // Landscape: Close on trailing black chrome — top of shutter rail.
    closeLandscapeConstraints = [
      closeButton.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      closeButton.topAnchor.constraint(
        equalTo: shutterRail.safeAreaLayoutGuide.topAnchor,
        constant: 16
      ),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),
    ]
    // Portrait: top-leading so Close stays reachable above the rotate prompt.
    closePortraitConstraints = [
      closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
      closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 18),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),
    ]
    NSLayoutConstraint.activate(closeLandscapeConstraints)

    let flashLeading = flashButton.leadingAnchor.constraint(
      equalTo: guide.leadingAnchor,
      constant: flashLeadingPaddingLandscape
    )
    flashLeadingConstraint = flashLeading

    let zoomTrailing = zoomRail.trailingAnchor.constraint(
      equalTo: videoContentGuide.trailingAnchor,
      constant: -6
    )
    zoomTrailingToVideoConstraint = zoomTrailing

    NSLayoutConstraint.activate([
      recordingBadge.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
      recordingBadge.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

      previewTrailingToRail,
      videoLeading,
      videoTop,
      videoWidth,
      videoHeight,
      // Extra trailing inset so hint text never clips on notched devices.
      shutterRail.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -6),
      shutterRail.topAnchor.constraint(equalTo: guide.topAnchor),
      shutterRail.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
      shutterRail.widthAnchor.constraint(equalToConstant: 112),

      // Flash on leading gutter — landscape uses extra leading inset.
      flashButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
      flashLeading,
      flashButton.widthAnchor.constraint(equalToConstant: 42),
      flashButton.heightAnchor.constraint(equalToConstant: 42),

      flashLabel.topAnchor.constraint(equalTo: flashButton.bottomAnchor, constant: 4),
      flashLabel.centerXAnchor.constraint(equalTo: flashButton.centerXAnchor),
      flashLabel.widthAnchor.constraint(equalToConstant: 72),
      flashLabel.heightAnchor.constraint(equalToConstant: 16),

      flashModeTray.leadingAnchor.constraint(equalTo: flashButton.trailingAnchor, constant: 8),
      flashModeTray.centerYAnchor.constraint(equalTo: flashButton.centerYAnchor),
      flashModeTray.heightAnchor.constraint(equalToConstant: 42),

      // Zoom pills on the live video rect (not letterbox / black chrome).
      zoomTrailing,
      zoomRail.centerYAnchor.constraint(equalTo: videoContentGuide.centerYAnchor),

      zoomWheel.trailingAnchor.constraint(
        equalTo: videoContentGuide.trailingAnchor,
        constant: -4
      ),
      zoomWheel.centerYAnchor.constraint(equalTo: videoContentGuide.centerYAnchor),
      zoomWheel.widthAnchor.constraint(equalToConstant: 160),
      zoomWheel.heightAnchor.constraint(equalToConstant: 280),

      exposureStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 18),
      exposureStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -18),

      modeControl.widthAnchor.constraint(equalToConstant: 0),
      modeControl.heightAnchor.constraint(equalToConstant: 0),
      modeControl.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      modeControl.topAnchor.constraint(equalTo: guide.topAnchor),

      busyOverlay.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
      busyOverlay.centerYAnchor.constraint(equalTo: guide.centerYAnchor),

      portraitBlockOverlay.topAnchor.constraint(equalTo: controlsOverlay.topAnchor),
      portraitBlockOverlay.bottomAnchor.constraint(equalTo: controlsOverlay.bottomAnchor),
      portraitBlockOverlay.leadingAnchor.constraint(equalTo: controlsOverlay.leadingAnchor),
      portraitBlockOverlay.trailingAnchor.constraint(equalTo: controlsOverlay.trailingAnchor),
    ])
  }

  /// Contextual exposure control shown beside the tap-to-focus reticle.
  private func buildFocusExposureControl() {
    focusExposureControl.frame = CGRect(x: 0, y: 0, width: 40, height: 132)
    focusExposureControl.alpha = 0
    focusExposureControl.isUserInteractionEnabled = false

    focusExposureTrack.frame = CGRect(x: 19, y: 14, width: 2, height: 104)
    focusExposureTrack.backgroundColor = UIColor(white: 1, alpha: 0.72)
    focusExposureTrack.layer.cornerRadius = 1

    focusExposureSun.frame = CGRect(x: 6, y: 0, width: 28, height: 28)
    let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    focusExposureSun.image = UIImage(systemName: "sun.max.fill", withConfiguration: config)
    focusExposureSun.tintColor = Chrome.zoomSelectedText
    focusExposureSun.backgroundColor = Chrome.glassFill
    focusExposureSun.contentMode = .center
    focusExposureSun.layer.cornerRadius = 14
    focusExposureSun.layer.borderWidth = 1
    focusExposureSun.layer.borderColor = Chrome.glassBorder.cgColor
    focusExposureSun.clipsToBounds = true

    focusExposureControl.addSubview(focusExposureTrack)
    focusExposureControl.addSubview(focusExposureSun)
    previewContainer.addSubview(focusExposureControl)
  }

  private func buildPortraitBlockOverlay() {
    portraitBlockOverlay.translatesAutoresizingMaskIntoConstraints = false
    portraitBlockOverlay.backgroundColor = UIColor(white: 0, alpha: 0.40)
    portraitBlockOverlay.isHidden = true
    portraitBlockOverlay.isUserInteractionEnabled = true

    portraitCard.translatesAutoresizingMaskIntoConstraints = false
    portraitCard.backgroundColor = UIColor(red: 0.09, green: 0.125, blue: 0.2, alpha: 0.95)
    portraitCard.layer.cornerRadius = 22
    portraitCard.layer.borderWidth = 1
    portraitCard.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor

    let iconWrap = UIView()
    iconWrap.translatesAutoresizingMaskIntoConstraints = false
    iconWrap.backgroundColor = Chrome.orange.withAlphaComponent(0.2)
    iconWrap.layer.cornerRadius = 28

    portraitIconView.translatesAutoresizingMaskIntoConstraints = false
    let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
    portraitIconView.image = UIImage(systemName: "rotate.right", withConfiguration: iconConfig)
    portraitIconView.tintColor = Chrome.orange
    portraitIconView.contentMode = .scaleAspectFit

    portraitTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    portraitTitleLabel.text = "Use Landscape Mode"
    portraitTitleLabel.textColor = UIColor(red: 0.945, green: 0.961, blue: 0.976, alpha: 1)
    portraitTitleLabel.font = .systemFont(ofSize: 18, weight: .bold)
    portraitTitleLabel.textAlignment = .center
    portraitTitleLabel.numberOfLines = 1

    portraitMessageLabel.translatesAutoresizingMaskIntoConstraints = false
    portraitMessageLabel.text =
      "Please rotate your device to landscape to capture photos and videos clearly."
    portraitMessageLabel.textColor = UIColor(red: 0.796, green: 0.835, blue: 0.882, alpha: 1)
    portraitMessageLabel.font = .systemFont(ofSize: 14, weight: .regular)
    portraitMessageLabel.textAlignment = .center
    portraitMessageLabel.numberOfLines = 0

    portraitBlockOverlay.addSubview(portraitCard)
    portraitCard.addSubview(iconWrap)
    iconWrap.addSubview(portraitIconView)
    portraitCard.addSubview(portraitTitleLabel)
    portraitCard.addSubview(portraitMessageLabel)

    NSLayoutConstraint.activate([
      portraitCard.centerXAnchor.constraint(equalTo: portraitBlockOverlay.centerXAnchor),
      portraitCard.centerYAnchor.constraint(equalTo: portraitBlockOverlay.centerYAnchor),
      portraitCard.leadingAnchor.constraint(
        greaterThanOrEqualTo: portraitBlockOverlay.leadingAnchor,
        constant: 28
      ),
      portraitCard.trailingAnchor.constraint(
        lessThanOrEqualTo: portraitBlockOverlay.trailingAnchor,
        constant: -28
      ),
      portraitCard.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

      iconWrap.topAnchor.constraint(equalTo: portraitCard.topAnchor, constant: 22),
      iconWrap.centerXAnchor.constraint(equalTo: portraitCard.centerXAnchor),
      iconWrap.widthAnchor.constraint(equalToConstant: 56),
      iconWrap.heightAnchor.constraint(equalToConstant: 56),

      portraitIconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
      portraitIconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
      portraitIconView.widthAnchor.constraint(equalToConstant: 28),
      portraitIconView.heightAnchor.constraint(equalToConstant: 28),

      portraitTitleLabel.topAnchor.constraint(equalTo: iconWrap.bottomAnchor, constant: 14),
      portraitTitleLabel.leadingAnchor.constraint(equalTo: portraitCard.leadingAnchor, constant: 22),
      portraitTitleLabel.trailingAnchor.constraint(equalTo: portraitCard.trailingAnchor, constant: -22),

      portraitMessageLabel.topAnchor.constraint(equalTo: portraitTitleLabel.bottomAnchor, constant: 8),
      portraitMessageLabel.leadingAnchor.constraint(equalTo: portraitCard.leadingAnchor, constant: 22),
      portraitMessageLabel.trailingAnchor.constraint(equalTo: portraitCard.trailingAnchor, constant: -22),
      portraitMessageLabel.bottomAnchor.constraint(equalTo: portraitCard.bottomAnchor, constant: -22),
    ])
  }

  private func syncPortraitBlock(using size: CGSize? = nil) {
    let boundsSize = size ?? view.bounds.size
    let portrait = boundsSize.height >= boundsSize.width

    guard configuration.landscapeOnly else {
      isPortraitBlocked = false
      portraitBlockOverlay.isHidden = true
      zoomRail.alpha = 1
      shutterRail.alpha = 1
      exposureStack.alpha = 1
      flashButton.alpha = 1
      flashLabel.alpha = 1
      zoomRail.isUserInteractionEnabled = true
      shutterRail.isUserInteractionEnabled = true
      exposureStack.isUserInteractionEnabled = true
      flashButton.isUserInteractionEnabled = true
      stopRotateHintAnimation()
      updatePreviewTrailingPadding(portrait: portrait)
      updateCloseChromePosition(portrait: portrait)
      return
    }
    isPortraitBlocked = portrait
    portraitBlockOverlay.isHidden = !portrait
    // Keep live preview under the dialog; only hide capture chrome.
    zoomRail.alpha = portrait ? 0 : 1
    shutterRail.alpha = portrait ? 0 : 1
    exposureStack.alpha = portrait ? 0 : 1
    flashButton.alpha = portrait ? 0 : 1
    flashLabel.alpha = portrait ? 0 : 1
    if portrait {
      setFlashModeTrayVisible(false, animated: false)
    }
    zoomRail.isUserInteractionEnabled = !portrait
    shutterRail.isUserInteractionEnabled = !portrait
    exposureStack.isUserInteractionEnabled = !portrait
    flashButton.isUserInteractionEnabled = !portrait
    // Landscape: 5pt before shutter rail. Portrait: 0 (full-bleed, no inset).
    updatePreviewTrailingPadding(portrait: portrait)
    updateCloseChromePosition(portrait: portrait)
    if portrait {
      zoomWheel.layer.removeAllAnimations()
      zoomWheel.alpha = 0
      zoomWheel.isHidden = true
      zoomStack.isHidden = false
      zoomRail.backgroundColor = Chrome.zoomRail
      hintLabel.alpha = 1
      startRotateHintAnimation()
      // Portrait live preview behind the dialog must stay upright.
      applyVideoOrientationFromInterface()
      pauseOnboardingForPortrait()
    } else {
      stopRotateHintAnimation()
      applyVideoOrientationFromInterface()
      // Tour is landscape-only; start once the officer rotates.
      maybeStartOnboarding()
    }
    if portrait, cameraSession.isRecording {
      cameraSession.toggleRecording()
    }
  }

  /// Right-edge gap before the shutter rail — landscape only; portrait = 0.
  private func updatePreviewTrailingPadding(portrait: Bool) {
    guard let toRail = previewTrailingToRailConstraint,
          let toView = previewTrailingToViewConstraint
    else { return }
    if portrait {
      toRail.isActive = false
      toView.isActive = true
    } else {
      toView.isActive = false
      toRail.constant = -previewTrailingPaddingLandscape
      toRail.isActive = true
    }
    view.setNeedsLayout()
  }

  /// Aspect-fit video, trail-aligned to the shutter chrome in landscape so zoom
  /// sits next to capture without changing the control UI.
  private func syncVideoContentGuide() {
    guard let leading = videoGuideLeading,
          let top = videoGuideTop,
          let width = videoGuideWidth,
          let height = videoGuideHeight
    else { return }

    let bounds = previewContainer.bounds
    guard bounds.width > 1, bounds.height > 1 else { return }

    let layer = cameraSession.previewLayer
    // Measure the aspect-fit size as if the layer filled the container.
    layer.frame = bounds
    layer.videoGravity = .resizeAspect
    var videoRect = layer.layerRectConverted(
      fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1)
    )
    if videoRect.isNull || videoRect.isInfinite || videoRect.width < 8 || videoRect.height < 8 {
      videoRect = bounds
    }

    let portrait = bounds.height >= bounds.width
    if portrait {
      // Center behind the rotate prompt.
      videoRect.origin.x = (bounds.width - videoRect.width) / 2
    } else {
      // Push the viewfinder against the black shutter rail — closes the gap
      // between zoom pills and the capture button.
      videoRect.origin.x = bounds.width - videoRect.width
    }
    videoRect.origin.y = (bounds.height - videoRect.height) / 2

    // Frame matches the fitted video exactly; resize fills without extra crop.
    layer.frame = videoRect
    layer.videoGravity = .resize

    leading.constant = videoRect.minX
    top.constant = videoRect.minY
    width.constant = videoRect.width
    height.constant = videoRect.height
  }

  /// Landscape: Close on black shutter chrome (top). Portrait: top-leading.
  private func updateCloseChromePosition(portrait: Bool) {
    if portrait {
      NSLayoutConstraint.deactivate(closeLandscapeConstraints)
      NSLayoutConstraint.activate(closePortraitConstraints)
    } else {
      NSLayoutConstraint.deactivate(closePortraitConstraints)
      NSLayoutConstraint.activate(closeLandscapeConstraints)
    }
    flashLeadingConstraint?.constant = portrait
      ? flashLeadingPaddingPortrait
      : flashLeadingPaddingLandscape
    closeButton.alpha = 1
    closeButton.isUserInteractionEnabled = true
    controlsOverlay.bringSubviewToFront(closeButton)
    view.setNeedsLayout()
  }

  private func pauseOnboardingForPortrait() {
    guard onboardingOverlay.isActive || !onboardingOverlay.isHidden else { return }
    clearOnboardingFocusDemo()
    clearOnboardingZoomWheel()
    onboardingOverlay.isHidden = true
    if !onboardingCompleted {
      onboardingStarted = false
    }
  }

  /// Matches Flutter VisitAnimatedOrientationHintIcon (toward landscape).
  private func startRotateHintAnimation() {
    guard portraitIconView.layer.animation(forKey: rotateHintAnimationKey) == nil else { return }
    let anim = CAKeyframeAnimation(keyPath: "transform.rotation.z")
    anim.values = [0, 0, -CGFloat.pi / 2, -CGFloat.pi / 2, 0] as [NSNumber]
    anim.keyTimes = [0, 0.12, 0.50, 0.74, 1] as [NSNumber]
    anim.timingFunctions = [
      CAMediaTimingFunction(name: .linear),
      CAMediaTimingFunction(name: .easeInEaseOut),
      CAMediaTimingFunction(name: .linear),
      CAMediaTimingFunction(name: .easeInEaseOut),
    ]
    anim.duration = 1.8
    anim.repeatCount = .infinity
    portraitIconView.layer.add(anim, forKey: rotateHintAnimationKey)
  }

  private func stopRotateHintAnimation() {
    portraitIconView.layer.removeAnimation(forKey: rotateHintAnimationKey)
    portraitIconView.transform = .identity
  }

  private func buildRecordingBadge() {
    recordingBadge.translatesAutoresizingMaskIntoConstraints = false
    recordingBadge.backgroundColor = Chrome.glassFill
    recordingBadge.layer.cornerRadius = 999
    recordingBadge.layer.borderWidth = 1
    recordingBadge.layer.borderColor = Chrome.glassBorder.cgColor
    recordingBadge.clipsToBounds = true
    recordingBadge.isHidden = true

    recordingDot.translatesAutoresizingMaskIntoConstraints = false
    recordingDot.backgroundColor = Chrome.red
    recordingDot.layer.cornerRadius = 4

    timerLabel.translatesAutoresizingMaskIntoConstraints = false
    timerLabel.textColor = .white
    timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
    timerLabel.textAlignment = .center
    timerLabel.text = "00:00"

    recordingBadge.addSubview(recordingDot)
    recordingBadge.addSubview(timerLabel)

    NSLayoutConstraint.activate([
      recordingDot.leadingAnchor.constraint(equalTo: recordingBadge.leadingAnchor, constant: 14),
      recordingDot.centerYAnchor.constraint(equalTo: recordingBadge.centerYAnchor),
      recordingDot.widthAnchor.constraint(equalToConstant: 8),
      recordingDot.heightAnchor.constraint(equalToConstant: 8),

      timerLabel.leadingAnchor.constraint(equalTo: recordingDot.trailingAnchor, constant: 8),
      timerLabel.trailingAnchor.constraint(equalTo: recordingBadge.trailingAnchor, constant: -14),
      timerLabel.topAnchor.constraint(equalTo: recordingBadge.topAnchor, constant: 8),
      timerLabel.bottomAnchor.constraint(equalTo: recordingBadge.bottomAnchor, constant: -8),
    ])
  }

  private func buildZoomRail() {
    zoomRail.translatesAutoresizingMaskIntoConstraints = false
    zoomRail.backgroundColor = Chrome.zoomRail
    zoomRail.layer.cornerRadius = 22
    zoomRail.clipsToBounds = true
    zoomRail.isMultipleTouchEnabled = true

    zoomWheel.translatesAutoresizingMaskIntoConstraints = false
    zoomWheel.alpha = 0
    zoomWheel.isHidden = true

    zoomStack.translatesAutoresizingMaskIntoConstraints = false
    zoomStack.axis = .vertical
    zoomStack.spacing = 6
    zoomStack.alignment = .center
    zoomStack.distribution = .equalSpacing

    zoomRail.addSubview(zoomStack)
    NSLayoutConstraint.activate([
      zoomStack.topAnchor.constraint(equalTo: zoomRail.topAnchor, constant: 6),
      zoomStack.bottomAnchor.constraint(equalTo: zoomRail.bottomAnchor, constant: -6),
      zoomStack.leadingAnchor.constraint(equalTo: zoomRail.leadingAnchor, constant: 5),
      zoomStack.trailingAnchor.constraint(equalTo: zoomRail.trailingAnchor, constant: -5),
    ])
  }

  private func buildShutterRail() {
    shutterRail.translatesAutoresizingMaskIntoConstraints = false
    shutterRail.isMultipleTouchEnabled = true
    // Solid black chrome (Camera.app right gutter).
    shutterRail.backgroundColor = .black

    flashLabel.translatesAutoresizingMaskIntoConstraints = false
    flashLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    flashLabel.textAlignment = .center
    flashLabel.textColor = .white
    flashLabel.adjustsFontSizeToFitWidth = true
    flashLabel.minimumScaleFactor = 0.75
    flashLabel.numberOfLines = 1
    flashLabel.lineBreakMode = .byTruncatingTail
    flashLabel.layer.shadowColor = UIColor.black.cgColor
    flashLabel.layer.shadowOpacity = 0.6
    flashLabel.layer.shadowRadius = 4
    flashLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
    flashLabel.isHidden = true

    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.isMultipleTouchEnabled = true
    shutterButton.isExclusiveTouch = false
    shutterButton.accessibilityLabel = "Tap for photo, hold for video, slide left to zoom"
    shutterButton.layer.cornerRadius = 36
    shutterButton.clipsToBounds = true
    updateShutterAppearance(recording: false)

    hintLabel.translatesAutoresizingMaskIntoConstraints = false
    hintLabel.numberOfLines = 3
    hintLabel.textAlignment = .center
    hintLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    hintLabel.adjustsFontSizeToFitWidth = true
    hintLabel.minimumScaleFactor = 0.8
    hintLabel.lineBreakMode = .byWordWrapping
    updateHint(recording: false)

    buildExposureControls()

    // Right chrome: close (top) → flip (below close when shown) → hint → shutter.
    // Flash is on the leading gutter, not here.
    shutterRail.addSubview(flipButton)
    shutterRail.addSubview(hintLabel)
    shutterRail.addSubview(shutterButton)

    NSLayoutConstraint.activate([
      // Below landscape close (top + 16 + 44 + 10); independent of portrait close.
      flipButton.topAnchor.constraint(
        equalTo: shutterRail.safeAreaLayoutGuide.topAnchor,
        constant: 70
      ),
      flipButton.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      flipButton.widthAnchor.constraint(equalToConstant: 42),
      flipButton.heightAnchor.constraint(equalToConstant: 42),

      shutterButton.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      shutterButton.centerYAnchor.constraint(equalTo: shutterRail.centerYAnchor),
      shutterButton.widthAnchor.constraint(equalToConstant: 72),
      shutterButton.heightAnchor.constraint(equalToConstant: 72),

      hintLabel.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      hintLabel.leadingAnchor.constraint(equalTo: shutterRail.leadingAnchor, constant: 4),
      hintLabel.trailingAnchor.constraint(equalTo: shutterRail.trailingAnchor, constant: -4),
      hintLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 48),
      hintLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -12),
    ])
  }

  private func buildFlashModeTray() {
    flashModeTray.translatesAutoresizingMaskIntoConstraints = false
    flashModeTray.backgroundColor = Chrome.zoomRail
    flashModeTray.layer.cornerRadius = 21
    flashModeTray.layer.borderWidth = 1
    flashModeTray.layer.borderColor = Chrome.glassBorder.cgColor
    flashModeTray.clipsToBounds = true
    flashModeTray.alpha = 0
    flashModeTray.isHidden = true
    flashModeTray.isMultipleTouchEnabled = true

    flashModeStack.translatesAutoresizingMaskIntoConstraints = false
    flashModeStack.axis = .horizontal
    flashModeStack.spacing = 4
    flashModeStack.alignment = .fill
    flashModeStack.distribution = .fillEqually
    flashModeTray.addSubview(flashModeStack)

    for mode in NativeCameraFlashMode.allCases {
      let button = UIButton(type: .system)
      button.tag = mode.rawValue
      button.setTitle(mode.title, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
      button.layer.cornerRadius = 17
      button.isExclusiveTouch = false
      button.accessibilityLabel = "Flash \(mode.title)"
      button.addTarget(self, action: #selector(flashModeSelected(_:)), for: .touchUpInside)
      flashModeStack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalToConstant: 54).isActive = true
    }

    NSLayoutConstraint.activate([
      flashModeStack.topAnchor.constraint(equalTo: flashModeTray.topAnchor, constant: 4),
      flashModeStack.bottomAnchor.constraint(equalTo: flashModeTray.bottomAnchor, constant: -4),
      flashModeStack.leadingAnchor.constraint(equalTo: flashModeTray.leadingAnchor, constant: 4),
      flashModeStack.trailingAnchor.constraint(equalTo: flashModeTray.trailingAnchor, constant: -4),
    ])
  }

  /// Compact continuous EV slider, shown only for supported camera devices.
  private func buildExposureControls() {
    exposureValueLabel.translatesAutoresizingMaskIntoConstraints = false
    exposureValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
    exposureValueLabel.textAlignment = .center
    exposureValueLabel.textColor = .white
    exposureValueLabel.accessibilityLabel = "Exposure compensation"

    exposureStack.translatesAutoresizingMaskIntoConstraints = false
    exposureStack.axis = .horizontal
    exposureStack.spacing = 8
    exposureStack.alignment = .center
    exposureStack.isLayoutMarginsRelativeArrangement = true
    exposureStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 6,
      leading: 12,
      bottom: 6,
      trailing: 10
    )
    exposureStack.backgroundColor = Chrome.glassFill
    exposureStack.layer.cornerRadius = 22
    exposureStack.layer.borderWidth = 1
    exposureStack.layer.borderColor = Chrome.glassBorder.cgColor
    exposureStack.clipsToBounds = true
    exposureStack.isHidden = true
    exposureStack.addArrangedSubview(exposureValueLabel)

    exposureSlider.translatesAutoresizingMaskIntoConstraints = false
    exposureSlider.minimumTrackTintColor = Chrome.zoomSelectedText
    exposureSlider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.35)
    exposureSlider.tintColor = Chrome.zoomSelectedText
    let symbolConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    exposureSlider.minimumValueImage = UIImage(
      systemName: "sun.min",
      withConfiguration: symbolConfig
    )
    exposureSlider.maximumValueImage = UIImage(
      systemName: "sun.max.fill",
      withConfiguration: symbolConfig
    )
    exposureSlider.accessibilityLabel = "Exposure compensation"
    exposureSlider.addTarget(self, action: #selector(exposureSliderChanged(_:)), for: .valueChanged)
    exposureStack.addArrangedSubview(exposureSlider)

    NSLayoutConstraint.activate([
      exposureValueLabel.widthAnchor.constraint(equalToConstant: 56),
      exposureSlider.widthAnchor.constraint(equalToConstant: 142),
      exposureSlider.heightAnchor.constraint(equalToConstant: 32),
    ])
  }

  private func styleGlassCircleButton(
    _ button: UIButton,
    systemName: String,
    accessibility: String
  ) {
    button.translatesAutoresizingMaskIntoConstraints = false
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
    button.tintColor = .white
    button.backgroundColor = Chrome.glassFill
    button.layer.cornerRadius = 21
    button.layer.borderWidth = 1
    button.layer.borderColor = Chrome.glassBorder.cgColor
    button.clipsToBounds = true
    button.accessibilityLabel = accessibility
  }

  private func configureGestures() {
    // Focus / pinch / EV live on the preview so chrome on the overlay is never
    // stolen. Overlay pass-through lets zoom pills (under the overlay) receive taps.
    previewContainer.addGestureRecognizer(zoomWheelDismissTap)

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
    tap.cancelsTouchesInView = false
    tap.delegate = self
    previewContainer.addGestureRecognizer(tap)

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    pinch.cancelsTouchesInView = false
    pinch.delegate = self
    previewContainer.addGestureRecognizer(pinch)

    let verticalExposure = UIPanGestureRecognizer(
      target: self,
      action: #selector(handleVerticalExposure(_:))
    )
    verticalExposure.minimumNumberOfTouches = 1
    verticalExposure.maximumNumberOfTouches = 1
    verticalExposure.cancelsTouchesInView = false
    verticalExposure.delegate = self
    previewContainer.addGestureRecognizer(verticalExposure)

    let shutterTap = UITapGestureRecognizer(target: self, action: #selector(shutterTapped))
    let shutterLongPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(shutterLongPressed(_:))
    )
    shutterLongPress.minimumPressDuration = 0.35
    shutterTap.require(toFail: shutterLongPress)
    let shutterZoom = UIPanGestureRecognizer(
      target: self,
      action: #selector(handleShutterZoom(_:))
    )
    shutterZoom.maximumNumberOfTouches = 1
    shutterZoom.delegate = self

    let zoomWheelPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleZoomWheel(_:))
    )
    zoomWheelPress.minimumPressDuration = 0.18
    zoomWheelPress.allowableMovement = .greatestFiniteMagnitude
    zoomWheelPress.numberOfTouchesRequired = 1
    zoomWheelPress.cancelsTouchesInView = true
    zoomWheelPress.delegate = self
    zoomRail.addGestureRecognizer(zoomWheelPress)

    let zoomWheelPan = UIPanGestureRecognizer(
      target: self,
      action: #selector(handleOpenZoomWheelPan(_:))
    )
    zoomWheelPan.minimumNumberOfTouches = 1
    zoomWheelPan.maximumNumberOfTouches = 1
    zoomWheelPan.cancelsTouchesInView = true
    zoomWheelPan.delegate = self
    zoomWheel.addGestureRecognizer(zoomWheelPan)

    shutterButton.addGestureRecognizer(shutterLongPress)
    shutterButton.addGestureRecognizer(shutterTap)
    shutterButton.addGestureRecognizer(shutterZoom)
  }

  private func observeLifecycle() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
  }

  // MARK: - Actions

  @objc private func closeTapped() {
    if onboardingOverlay.isActive {
      // Dismiss for this session only; do not persist completion.
      clearOnboardingFocusDemo()
      clearOnboardingZoomWheel()
      onboardingOverlay.isHidden = true
      return
    }
    if cameraSession.isRecording {
      cameraSession.toggleRecording()
    }
    finish(.canceled(onboardingCompleted: onboardingCompleted))
  }

  @objc private func flashTapped() {
    guard cameraSession.supportsFlashOrTorch, !cameraSession.isRecording else { return }
    setFlashModeTrayVisible(flashModeTray.isHidden)
  }

  @objc private func flashModeSelected(_ sender: UIButton) {
    guard let mode = NativeCameraFlashMode(rawValue: sender.tag) else { return }
    let applied = cameraSession.setFlashMode(mode)
    refreshFlashButton(mode: applied)
    setFlashModeTrayVisible(false)
  }

  @objc private func exposureSliderChanged(_ sender: UISlider) {
    guard cameraSession.supportsExposureCompensation else { return }
    let applied = cameraSession.setExposureTargetBias(sender.value)
    refreshExposureControls(bias: applied)
    NSLog("\(Self.logPrefix) exposure bias → \(applied)")
  }

  @objc private func flipTapped() {
    guard !configuration.rearCameraOnly, isVideoMode, !cameraSession.isRecording else { return }
    busyOverlay.startAnimating()
    cameraSession.flipCamera()
  }

  @objc private func modeChanged() {
    // Segmented control is hidden; gestures drive mode via setVideoMode.
    guard configuration.allowModeSwitch else { return }
    guard !cameraSession.isRecording else {
      modeControl.selectedSegmentIndex = isVideoMode ? 1 : 0
      return
    }
    let video = modeControl.selectedSegmentIndex == 1
    guard video != isVideoMode else { return }
    switchToMode(video: video, then: .none)
  }

  @objc private func shutterTapped() {
    guard !isFinishing, !cameraSession.isRecording, !shutterLongPressActive else { return }
    guard !isPortraitBlocked else { return }
    capturePhotoEnsuringMode()
  }

  @objc private func shutterLongPressed(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      guard !isFinishing, !cameraSession.isRecording else { return }
      guard !isPortraitBlocked else { return }
      shutterLongPressActive = true
      startVideoEnsuringMode()
    case .ended, .cancelled, .failed:
      let wasActive = shutterLongPressActive
      shutterLongPressActive = false
      if pendingCaptureAction == .startVideo {
        pendingCaptureAction = .none
        busyOverlay.stopAnimating()
        return
      }
      if wasActive, cameraSession.isRecording {
        cameraSession.toggleRecording()
      }
    default:
      break
    }
  }

  @objc private func zoomChipTapped(_ sender: UIButton) {
    let index = sender.tag
    guard index >= 0, index < cameraSession.zoomChips.count else { return }
    let chip = cameraSession.zoomChips[index]
    currentZoomFactor = chip.deviceFactor
    cameraSession.setZoomFactor(chip.deviceFactor, animated: true)
    highlightZoomChip(closestTo: chip.deviceFactor)
  }

  /// A separate finger can scrub this dial while the shutter finger continues
  /// holding the long-press that records video.
  @objc private func handleZoomWheel(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      wheelZoomStart = cameraSession.currentZoomFactor()
      wheelTouchStartY = gesture.location(in: controlsOverlay).y
      wheelZoomArmed = false
      lastWheelHapticIndex = nearestZoomStopIndex(to: wheelZoomStart)
      zoomFeedback.prepare()
      showZoomWheel()
    case .changed:
      let range = cameraSession.zoomFactorRange()
      guard range.upperBound > range.lowerBound else { return }
      let currentY = gesture.location(in: controlsOverlay).y
      let openingDrag = currentY - wheelTouchStartY
      // Opening the precision wheel is a distinct action. Ignore the movement
      // that triggered it; zoom begins only after the officer continues dragging.
      if !wheelZoomArmed {
        guard abs(openingDrag) >= 18 else { return }
        wheelZoomArmed = true
        wheelTouchStartY = currentY
        wheelZoomStart = cameraSession.currentZoomFactor()
        return
      }
      let dragY = currentY - wheelTouchStartY
      let usableHeight = max(zoomWheel.bounds.height * 0.82, 220)
      let zoomPerPoint = (range.upperBound - range.lowerBound) / usableHeight
      // Follow the visible scale: upward increases zoom, downward decreases it.
      let target = max(
        range.lowerBound,
        min(range.upperBound, wheelZoomStart - dragY * zoomPerPoint)
      )
      currentZoomFactor = target
      cameraSession.setZoomFactor(target, animated: false)
      highlightZoomChip(closestTo: target)
      updateZoomWheel(currentDeviceFactor: target)

      let stopIndex = nearestZoomStopIndex(to: target)
      if stopIndex != lastWheelHapticIndex {
        lastWheelHapticIndex = stopIndex
        zoomFeedback.selectionChanged()
        zoomFeedback.prepare()
      }
    case .ended, .cancelled, .failed:
      lastWheelHapticIndex = nil
      wheelZoomArmed = false
    default:
      break
    }
  }

  /// Allows the already-open photo wheel to be scrubbed directly. The opening
  /// long press lives on the compact zoom rail; subsequent drags live here on
  /// the full visible wheel surface.
  @objc private func handleOpenZoomWheelPan(_ gesture: UIPanGestureRecognizer) {
    guard !zoomWheel.isHidden else { return }

    switch gesture.state {
    case .began:
      wheelZoomStart = cameraSession.currentZoomFactor()
      lastWheelHapticIndex = nearestZoomStopIndex(to: wheelZoomStart)
      zoomFeedback.prepare()
    case .changed:
      let range = cameraSession.zoomFactorRange()
      guard range.upperBound > range.lowerBound else { return }
      let dragY = gesture.translation(in: zoomWheel).y
      let usableHeight = max(zoomWheel.bounds.height * 0.82, 220)
      let zoomPerPoint = (range.upperBound - range.lowerBound) / usableHeight
      let target = max(
        range.lowerBound,
        min(range.upperBound, wheelZoomStart - dragY * zoomPerPoint)
      )
      currentZoomFactor = target
      cameraSession.setZoomFactor(target, animated: false)
      highlightZoomChip(closestTo: target)
      updateZoomWheel(currentDeviceFactor: target)

      let stopIndex = nearestZoomStopIndex(to: target)
      if stopIndex != lastWheelHapticIndex {
        lastWheelHapticIndex = stopIndex
        zoomFeedback.selectionChanged()
        zoomFeedback.prepare()
      }
    case .ended, .cancelled, .failed:
      lastWheelHapticIndex = nil
    default:
      break
    }
  }

  @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
    // The first tap away from an open wheel dismisses it without also moving
    // focus, matching a modal precision-control interaction.
    if !zoomWheel.isHidden { return }
    let point = gesture.location(in: previewContainer)
    let devicePoint = cameraSession.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
    cameraSession.focusAndExpose(at: devicePoint)
    showFocusIndicator(at: point)
  }

  @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    if gesture.state == .began {
      pinchStartZoom = cameraSession.currentZoomFactor()
    }
    let target = pinchStartZoom * gesture.scale
    currentZoomFactor = target
    cameraSession.setZoomFactor(target, animated: false)
    highlightZoomChip(closestTo: target)
  }

  /// After tap-to-focus, a vertical preview drag adjusts camera EV.
  @objc private func handleVerticalExposure(_ gesture: UIPanGestureRecognizer) {
    if gesture.state == .began {
      verticalExposureStart = cameraSession.exposureTargetBias
      focusDismissWorkItem?.cancel()
      focusExposureControl.layer.removeAllAnimations()
      focusIndicator.layer.removeAllAnimations()
      focusExposureControl.alpha = 1
      focusIndicator.alpha = 1
    }
    if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
      scheduleFocusDismiss(after: 1.4)
      return
    }
    guard gesture.state == .began || gesture.state == .changed else { return }
    let minimum = cameraSession.minExposureTargetBias
    let maximum = cameraSession.maxExposureTargetBias
    guard maximum > minimum else { return }
    let dragY = gesture.translation(in: previewContainer).y
    let usableHeight = max(previewContainer.bounds.height * 0.65, 1)
    let target = verticalExposureStart - Float(dragY / usableHeight) * (maximum - minimum)
    let applied = cameraSession.setExposureTargetBias(target)
    refreshExposureControls(bias: applied)
  }

  /// During a held video recording, sliding left from the shutter reveals the
  /// landscape wheel. The movement used to reveal it never changes zoom.
  @objc private func handleShutterZoom(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      shutterZoomStart = cameraSession.currentZoomFactor()
      shutterWheelStartX = 0
      shutterWheelActive = false
    case .changed:
      guard shutterLongPressActive || cameraSession.isRecording else { return }
      let translation = gesture.translation(in: previewContainer)
      if !shutterWheelActive {
        // A deliberate left movement opens the wheel. Vertical jitter and the
        // opening movement itself are ignored.
        guard translation.x <= -18, abs(translation.x) > abs(translation.y) else { return }
        shutterWheelActive = true
        shutterWheelStartX = translation.x
        shutterZoomStart = cameraSession.currentZoomFactor()
        lastWheelHapticIndex = nearestZoomStopIndex(to: shutterZoomStart)
        zoomFeedback.prepare()
        showZoomWheel()
        return
      }

      let range = cameraSession.zoomFactorRange()
      guard range.upperBound > range.lowerBound else { return }
      let dragX = translation.x - shutterWheelStartX
      let usableWidth = max(previewContainer.bounds.width * 0.42, 220)
      let zoomPerPoint = (range.upperBound - range.lowerBound) / usableWidth
      // Keep the recording gesture continuous: after the initial reveal,
      // continuing left zooms in and moving back right zooms out. Requiring a
      // turn upward here makes a one-thumb recording gesture feel disjointed.
      let target = max(
        range.lowerBound,
        min(range.upperBound, shutterZoomStart - dragX * zoomPerPoint)
      )
      currentZoomFactor = target
      cameraSession.setZoomFactor(target, animated: false)
      highlightZoomChip(closestTo: target)
      updateZoomWheel(currentDeviceFactor: target)

      let stopIndex = nearestZoomStopIndex(to: target)
      if stopIndex != lastWheelHapticIndex {
        lastWheelHapticIndex = stopIndex
        zoomFeedback.selectionChanged()
        zoomFeedback.prepare()
      }
    case .ended, .cancelled, .failed:
      shutterWheelActive = false
      lastWheelHapticIndex = nil
    default:
      break
    }
  }

  @objc private func appDidEnterBackground() {
    if cameraSession.isRecording {
      cameraSession.toggleRecording()
    }
    cameraSession.stopRunning()
  }

  @objc private func appWillEnterForeground() {
    cameraSession.startRunning()
    applyVideoOrientationFromInterface()
  }

  // MARK: - Mode / capture orchestration

  private func capturePhotoEnsuringMode() {
    if isVideoMode {
      switchToMode(video: false, then: .photo)
    } else {
      performPhotoCapture()
    }
  }

  private func startVideoEnsuringMode() {
    if isVideoMode {
      cameraSession.toggleRecording()
    } else {
      switchToMode(video: true, then: .startVideo)
    }
  }

  private func switchToMode(video: Bool, then action: PendingCaptureAction) {
    guard !cameraSession.isRecording else { return }
    isVideoMode = video
    modeControl.selectedSegmentIndex = video ? 1 : 0
    pendingCaptureAction = action
    busyOverlay.startAnimating()
    cameraSession.setVideoMode(video)
    updateShutterAppearance(recording: false)
    updateHint(recording: false)
    refreshFlashButton()
    refreshFlipButton()
    NSLog("\(Self.logPrefix) mode → \(video ? "video" : "photo")")
  }

  private func performPhotoCapture() {
    CamPerf.markShutterTap()
    CamPerf.stage("SHUTTER_HANDLER_ENTER", detail: "main")
    busyOverlay.startAnimating()
    shutterButton.isEnabled = false
    CamPerf.stage("CAPTURE_PHOTO_REQUEST")
    photoCaptureEpoch &+= 1
    activePhotoCaptureEpoch = photoCaptureEpoch
    schedulePhotoCaptureTimeout(epoch: photoCaptureEpoch)
    cameraSession.capturePhoto()
  }

  private func schedulePhotoCaptureTimeout(epoch: UInt64) {
    photoCaptureTimeoutWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, !self.isFinishing else { return }
      guard self.activePhotoCaptureEpoch == epoch else { return }
      self.activePhotoCaptureEpoch = nil
      NSLog("\(Self.logPrefix) photo capture timed out after \(Self.photoCaptureTimeoutSeconds)s")
      self.busyOverlay.stopAnimating()
      self.shutterButton.isEnabled = true
      self.presentErrorAlert(
        message: "Photo is taking too long to process. Please try again."
      )
    }
    photoCaptureTimeoutWorkItem = work
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.photoCaptureTimeoutSeconds,
      execute: work
    )
  }

  private func cancelPhotoCaptureTimeout() {
    photoCaptureTimeoutWorkItem?.cancel()
    photoCaptureTimeoutWorkItem = nil
  }

  /// Returns false when this result belongs to a timed-out / superseded shutter.
  @discardableResult
  private func completeActivePhotoCaptureIfCurrent() -> Bool {
    cancelPhotoCaptureTimeout()
    guard activePhotoCaptureEpoch != nil else { return false }
    activePhotoCaptureEpoch = nil
    return true
  }

  private func returnToPhotoModeIfAllowed() {
    guard configuration.allowModeSwitch, isVideoMode, !isFinishing else { return }
    guard !cameraSession.isRecording else { return }
    switchToMode(video: false, then: .none)
  }

  private func consumePendingCaptureAction() {
    let action = pendingCaptureAction
    pendingCaptureAction = .none
    switch action {
    case .none:
      break
    case .photo:
      performPhotoCapture()
    case .startVideo:
      if shutterLongPressActive {
        cameraSession.toggleRecording()
      }
    }
  }

  // MARK: - Helpers

  private func applyVideoOrientationFromInterface() {
    let interface = NativeCameraOrientation.currentInterfaceOrientation()
    let video = NativeCameraOrientation.videoOrientation(from: interface)
    cameraSession.updateVideoOrientation(video)
  }

  private func refreshZoomChips() {
    zoomStack.arrangedSubviews.forEach {
      zoomStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    zoomButtons.removeAll()

    zoomRail.isHidden = cameraSession.zoomChips.count <= 1
    if zoomRail.isHidden {
      zoomWheel.isHidden = true
    }

    for (index, chip) in cameraSession.zoomChips.enumerated() {
      let button = UIButton(type: .custom)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.clipsToBounds = true
      button.layer.cornerRadius = 17
      button.setTitle(chip.label, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold)
      button.tag = index
      button.addTarget(self, action: #selector(zoomChipTapped(_:)), for: .touchUpInside)
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 34),
        button.heightAnchor.constraint(equalToConstant: 34),
      ])
      zoomStack.addArrangedSubview(button)
      zoomButtons.append(button)
    }
    currentZoomFactor = cameraSession.currentZoomFactor()
    configureZoomWheel(currentDeviceFactor: currentZoomFactor)
    highlightZoomChip(closestTo: currentZoomFactor)
  }

  /// Photo opens at Camera.app-style 1x (wide). Video keeps the device default.
  private func applyDefaultPhotoZoomIfNeeded() {
    guard !isVideoMode else { return }
    let target = cameraSession.wideDeviceZoomFactor
    guard target > 0.01 else { return }
    currentZoomFactor = target
    cameraSession.setZoomFactor(target, animated: false)
    configureZoomWheel(currentDeviceFactor: target)
    highlightZoomChip(closestTo: target)
  }

  private func highlightZoomChip(closestTo deviceFactor: CGFloat) {
    let display = cameraSession.displayZoomFactor(forDeviceZoom: deviceFactor)
    zoomWheel.update(current: display)
    var bestIndex = 0
    var bestDelta = CGFloat.greatestFiniteMagnitude
    for (index, chip) in cameraSession.zoomChips.enumerated() {
      let delta = abs(chip.displayFactor - display)
      if delta < bestDelta {
        bestDelta = delta
        bestIndex = index
      }
    }
    for (index, button) in zoomButtons.enumerated() {
      let selected = index == bestIndex
      if index < cameraSession.zoomChips.count {
        let title = selected
          ? NativeCameraSession.formatDisplayZoomLabel(display)
          : cameraSession.zoomChips[index].label
        button.setTitle(title, for: .normal)
      }
      button.backgroundColor = selected ? Chrome.zoomChipSelected : Chrome.zoomChip
      button.setTitleColor(selected ? Chrome.zoomSelectedText : .white, for: .normal)
      button.titleLabel?.font = .systemFont(
        ofSize: selected ? 11 : 10,
        weight: .semibold
      )
    }
  }

  private func configureZoomWheel(currentDeviceFactor: CGFloat) {
    let range = cameraSession.zoomFactorRange()
    zoomWheel.configure(
      minimum: cameraSession.displayZoomFactor(forDeviceZoom: range.lowerBound),
      maximum: cameraSession.displayZoomFactor(forDeviceZoom: range.upperBound),
      current: cameraSession.displayZoomFactor(forDeviceZoom: currentDeviceFactor),
      stops: cameraSession.zoomChips.map(\.displayFactor)
    )
  }

  private func updateZoomWheel(currentDeviceFactor: CGFloat) {
    zoomWheel.update(
      current: cameraSession.displayZoomFactor(forDeviceZoom: currentDeviceFactor)
    )
  }

  private func nearestZoomStopIndex(to deviceFactor: CGFloat) -> Int? {
    guard !cameraSession.zoomChips.isEmpty else { return nil }
    let display = cameraSession.displayZoomFactor(forDeviceZoom: deviceFactor)
    return cameraSession.zoomChips.indices.min { left, right in
      abs(cameraSession.zoomChips[left].displayFactor - display)
        < abs(cameraSession.zoomChips[right].displayFactor - display)
    }
  }

  private func showZoomWheel() {
    configureZoomWheel(currentDeviceFactor: cameraSession.currentZoomFactor())
    setFlashModeTrayVisible(false, animated: false)
    zoomWheel.layer.removeAllAnimations()
    zoomWheel.isHidden = false
    // Keep the transparent rail in the hierarchy so its active gesture keeps
    // receiving touches, while the chip UI is fully replaced by the wheel.
    zoomStack.isHidden = true
    zoomRail.backgroundColor = .clear
    hintLabel.layer.removeAllAnimations()
    UIView.animate(
      withDuration: 0.16,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseOut]
    ) {
      self.zoomWheel.alpha = 1
      self.hintLabel.alpha = 0
    }
  }

  private func hideZoomWheel() {
    UIView.animate(
      withDuration: 0.22,
      delay: 0.35,
      options: [.beginFromCurrentState, .curveEaseOut]
    ) {
      self.zoomWheel.alpha = 0
      self.hintLabel.alpha = self.isPortraitBlocked ? 0 : 1
    } completion: { [weak self] finished in
      if finished {
        guard let self else { return }
        self.zoomWheel.isHidden = true
        self.zoomStack.isHidden = false
        self.zoomRail.backgroundColor = Chrome.zoomRail
      }
    }
  }

  @objc private func dismissZoomWheel(_ gesture: UITapGestureRecognizer) {
    guard gesture.state == .ended, !zoomWheel.isHidden else { return }
    hideZoomWheel()
  }

  private func refreshFlashButton(mode: NativeCameraFlashMode? = nil) {
    let flashMode = mode ?? cameraSession.flashMode
    let supported = cameraSession.supportsFlashOrTorch
    flashButton.isHidden = !supported
    flashLabel.isHidden = !supported
    guard supported else {
      setFlashModeTrayVisible(false, animated: false)
      return
    }

    let name: String
    let tint: UIColor
    if isVideoMode {
      name = flashMode == .on ? "flashlight.on.fill" : "flashlight.off.fill"
      tint = flashMode == .on ? Chrome.zoomSelectedText : .white
      flashLabel.text = flashMode == .on ? "Torch on" : "Torch off"
    } else {
      switch flashMode {
      case .off:
        name = "bolt.slash.fill"
        tint = .white
      case .on:
        name = "bolt.fill"
        tint = Chrome.zoomSelectedText
      case .auto:
        name = "bolt.badge.automatic.fill"
        tint = Chrome.zoomSelectedText
      }
      flashLabel.text = "Flash \(flashMode.title.lowercased())"
    }
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    flashButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
    flashButton.tintColor = tint
    flashLabel.textColor = tint
    flashButton.accessibilityValue = flashMode.title
    refreshFlashModeTraySelection(mode: flashMode)
  }

  private func refreshFlashModeTraySelection(mode: NativeCameraFlashMode) {
    for case let button as UIButton in flashModeStack.arrangedSubviews {
      let selected = button.tag == mode.rawValue
      button.backgroundColor = selected ? Chrome.zoomChipSelected : .clear
      button.setTitleColor(selected ? Chrome.zoomSelectedText : .white, for: .normal)
      button.accessibilityTraits = selected ? [.button, .selected] : .button
      // Auto has no native continuous-video torch equivalent.
      button.isHidden = isVideoMode && button.tag == NativeCameraFlashMode.auto.rawValue
    }
  }

  private func setFlashModeTrayVisible(_ visible: Bool, animated: Bool = true) {
    guard visible != !flashModeTray.isHidden else { return }
    if visible {
      refreshFlashModeTraySelection(mode: cameraSession.flashMode)
      flashModeTray.isHidden = false
      flashModeTray.transform = CGAffineTransform(translationX: 10, y: 0).scaledBy(x: 0.92, y: 0.92)
      flashModeTray.alpha = 0
    }
    let changes = {
      self.flashModeTray.alpha = visible ? 1 : 0
      self.flashModeTray.transform = .identity
    }
    let completion: (Bool) -> Void = { [weak self] _ in
      if !visible { self?.flashModeTray.isHidden = true }
    }
    if animated {
      UIView.animate(
        withDuration: 0.18,
        delay: 0,
        options: [.beginFromCurrentState, .curveEaseOut],
        animations: changes,
        completion: completion
      )
    } else {
      changes()
      completion(true)
    }
  }

  private func refreshExposureControls(bias: Float? = nil) {
    let supported = cameraSession.supportsExposureCompensation
    // Exposure is contextual to tap-to-focus; keep the old persistent slider hidden.
    exposureStack.isHidden = true
    guard supported else { return }

    let value = bias ?? cameraSession.exposureTargetBias
    exposureSlider.minimumValue = cameraSession.minExposureTargetBias
    exposureSlider.maximumValue = cameraSession.maxExposureTargetBias
    exposureSlider.setValue(value, animated: false)
    let rounded = (value * 10).rounded() / 10
    if abs(rounded) < 0.05 {
      exposureValueLabel.text = "EV 0.0"
      exposureValueLabel.textColor = UIColor(white: 1, alpha: 0.92)
    } else {
      exposureValueLabel.text = String(format: "EV %+.1f", rounded)
      exposureValueLabel.textColor = Chrome.zoomSelectedText
    }
    exposureValueLabel.accessibilityValue = exposureValueLabel.text
    exposureSlider.accessibilityValue = exposureValueLabel.text
    updateFocusExposureIndicator(bias: value)
  }

  private func refreshFlipButton(isRecording: Bool = false) {
    let show = !configuration.rearCameraOnly && isVideoMode && !isRecording
    flipButton.isHidden = !show
  }

  private func updateShutterAppearance(recording: Bool) {
    shutterButton.backgroundColor = recording ? Chrome.red : .white
    shutterButton.layer.borderWidth = 3.5
    shutterButton.layer.borderColor = (recording ? UIColor.white : Chrome.orange).cgColor

    let symbolName = recording ? "stop.fill" : "camera.fill"
    let tint = recording ? UIColor.white : Chrome.primary
    let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
    shutterButton.setImage(UIImage(systemName: symbolName, withConfiguration: config), for: .normal)
    shutterButton.tintColor = tint
  }

  private func updateHint(recording: Bool) {
    if recording {
      hintLabel.text = "Slide left\nto zoom"
      hintLabel.textColor = Chrome.orange
    } else {
      hintLabel.text = "Tap for photo\nHold for video\nSlide left to zoom"
      hintLabel.textColor = UIColor(white: 1, alpha: 0.92)
    }
    hintLabel.layer.shadowColor = UIColor.black.cgColor
    hintLabel.layer.shadowOpacity = 0.6
    hintLabel.layer.shadowRadius = 4
    hintLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
  }

  private func showFocusIndicator(at point: CGPoint) {
    focusDismissWorkItem?.cancel()
    focusIndicator.layer.removeAllAnimations()
    focusExposureControl.layer.removeAllAnimations()

    let half = focusIndicator.bounds.width / 2
    let clampedPoint = CGPoint(
      x: min(max(point.x, half), max(previewContainer.bounds.width - half, half)),
      y: min(max(point.y, half), max(previewContainer.bounds.height - half, half))
    )
    focusIndicator.center = clampedPoint
    focusIndicator.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
    focusIndicator.alpha = 1
    positionFocusExposureControl(at: clampedPoint)
    focusExposureControl.alpha = cameraSession.supportsExposureCompensation ? 1 : 0
    updateFocusExposureIndicator()
    UIView.animate(withDuration: 0.22) {
      self.focusIndicator.transform = .identity
    }
    scheduleFocusDismiss(after: 3)
  }

  private func positionFocusExposureControl(at point: CGPoint) {
    let controlSize = focusExposureControl.bounds.size
    let focusHalf = focusIndicator.bounds.width / 2
    let gap: CGFloat = 8
    let rightX = point.x + focusHalf + gap
    let x = rightX + controlSize.width <= previewContainer.bounds.width
      ? rightX
      : max(0, point.x - focusHalf - gap - controlSize.width)
    let y = min(
      max(0, point.y - controlSize.height / 2),
      max(0, previewContainer.bounds.height - controlSize.height)
    )
    focusExposureControl.frame.origin = CGPoint(x: x, y: y)
  }

  private func updateFocusExposureIndicator(bias: Float? = nil) {
    guard cameraSession.supportsExposureCompensation else { return }
    let minimum = cameraSession.minExposureTargetBias
    let maximum = cameraSession.maxExposureTargetBias
    guard maximum > minimum else { return }
    let value = min(max(bias ?? cameraSession.exposureTargetBias, minimum), maximum)
    let fraction = CGFloat((maximum - value) / (maximum - minimum))
    focusExposureSun.transform = CGAffineTransform(translationX: 0, y: fraction * 104)
    focusExposureSun.accessibilityValue = String(format: "EV %+.1f", value)
  }

  private func scheduleFocusDismiss(after delay: TimeInterval) {
    focusDismissWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      UIView.animate(withDuration: 0.2) {
        self.focusIndicator.alpha = 0
        self.focusExposureControl.alpha = 0
      }
    }
    focusDismissWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func startRecordingTimer() {
    recordingStartedAt = Date()
    recordingBadge.isHidden = false
    timerLabel.text = "00:00"
    recordingTimer?.invalidate()
    recordingTimer = Timer.scheduledTimer(
      withTimeInterval: 0.25,
      repeats: true
    ) { [weak self] _ in
      guard let self, let start = self.recordingStartedAt else { return }
      let elapsed = Int(Date().timeIntervalSince(start))
      let minutes = elapsed / 60
      let seconds = elapsed % 60
      self.timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
    }
  }

  private func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    recordingStartedAt = nil
    recordingBadge.isHidden = true
  }

  private func presentPortraitAlert(isPhoto: Bool) {
    let message = isPhoto
      ? "Please rotate your device to landscape and take the photo again."
      : "Please rotate your device to landscape and record the video again."
    let alert = UIAlertController(
      title: "Landscape required",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
    NSLog("\(Self.logPrefix) portrait capture rejected (kept open)")
  }

  private func presentErrorAlert(message: String) {
    let alert = UIAlertController(
      title: "Camera",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func finish(_ outcome: Outcome) {
    guard !isFinishing else { return }
    isFinishing = true
    pendingCaptureAction = .none
    activePhotoCaptureEpoch = nil
    cancelPhotoCaptureTimeout()
    stopRecordingTimer()
    cameraSession.stopRunning()
    let callback = onFinish
    onFinish = nil
    dismiss(animated: true) {
      callback?(outcome)
    }
  }

  private func handleSuccessfulCapture(url: URL, metadata: [String: Any], isPhoto: Bool) {
    if isPhoto, !completeActivePhotoCaptureIfCurrent() {
      try? FileManager.default.removeItem(at: url)
      NSLog("\(Self.logPrefix) ignoring late photo after timeout/supersede")
      return
    }
    if !isPhoto {
      cancelPhotoCaptureTimeout()
    }
    busyOverlay.stopAnimating()
    shutterButton.isEnabled = true

    // Photos are contractually rear-camera captures. Fail closed rather than
    // shipping an unverified / front capture to the visit record.
    let position = (metadata["cameraPosition"] as? String)?.lowercased()
    if isPhoto, configuration.rearCameraOnly {
      let isRear = position == "back" || position == "rear"
      if !isRear {
        try? FileManager.default.removeItem(at: url)
        NSLog(
          "\(Self.logPrefix) rear-camera photo rejected "
            + "(position=\(position ?? "nil"))"
        )
        presentErrorAlert(message: "Please use the rear camera to take the photo.")
        return
      }
    }

    if configuration.landscapeOnly {
      let landscape = isPhoto
        ? NativeCameraOrientation.isLandscapePhoto(at: url)
        : NativeCameraOrientation.isLandscapeVideo(at: url)
      if !landscape {
        try? FileManager.default.removeItem(at: url)
        presentPortraitAlert(isPhoto: isPhoto)
        if !isPhoto {
          returnToPhotoModeIfAllowed()
        }
        return
      }
    }

    var payload = metadata
    payload["path"] = url.path
    payload["onboardingCompleted"] = onboardingCompleted
    finish(.success(payload))
  }

  private func maybeStartOnboarding() {
    guard configuration.showOnboarding, !onboardingStarted else { return }
    let steps = NativeCameraOnboardingOverlay.Step.parse(configuration.onboardingSteps)
    guard !steps.isEmpty else { return }
    // Landscape only — wait until the officer rotates the phone.
    guard !isPortraitBlocked else { return }
    guard shutterButton.bounds.width > 0 else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
        self?.maybeStartOnboarding()
      }
      return
    }
    onboardingStarted = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self, !self.isFinishing else { return }
      if self.isPortraitBlocked {
        self.onboardingStarted = false
        return
      }
      self.view.bringSubviewToFront(self.onboardingOverlay)
      self.onboardingOverlay.start(steps: steps)
    }
  }

  private func prepareOnboardingStep(_ id: String) {
    switch id.lowercased() {
    case "focus", "brightness", "pinch":
      clearOnboardingZoomWheel()
      showOnboardingFocusDemo()
    case "zoom_wheel":
      if onboardingFocusDemo {
        clearOnboardingFocusDemo()
      }
      showOnboardingZoomWheel()
    default:
      if onboardingFocusDemo {
        clearOnboardingFocusDemo()
      }
      clearOnboardingZoomWheel()
    }
  }

  private func showOnboardingFocusDemo() {
    let bounds = previewContainer.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }
    onboardingFocusDemo = true
    focusDismissWorkItem?.cancel()
    showFocusIndicator(at: CGPoint(x: bounds.midX, y: bounds.midY))
    focusDismissWorkItem?.cancel()
    if cameraSession.supportsExposureCompensation {
      focusExposureControl.alpha = 1
    }
  }

  private func clearOnboardingFocusDemo() {
    guard onboardingFocusDemo else { return }
    onboardingFocusDemo = false
    focusDismissWorkItem?.cancel()
    focusIndicator.layer.removeAllAnimations()
    focusExposureControl.layer.removeAllAnimations()
    focusIndicator.alpha = 0
    focusExposureControl.alpha = 0
  }

  /// Opens the precision zoom wheel so the coachmark can highlight it, the
  /// same way focus/brightness demos surface their controls.
  private func showOnboardingZoomWheel() {
    guard !zoomRail.isHidden, zoomRail.alpha >= 0.01 else { return }
    onboardingZoomWheel = true
    zoomWheel.layer.removeAllAnimations()
    hintLabel.layer.removeAllAnimations()
    showZoomWheel()
    // Coachmark needs the wheel fully visible immediately (no fade delay).
    zoomWheel.alpha = 1
    zoomWheel.isHidden = false
  }

  private func clearOnboardingZoomWheel() {
    guard onboardingZoomWheel else { return }
    onboardingZoomWheel = false
    zoomWheel.layer.removeAllAnimations()
    hintLabel.layer.removeAllAnimations()
    zoomWheel.alpha = 0
    zoomWheel.isHidden = true
    zoomStack.isHidden = false
    zoomRail.backgroundColor = Chrome.zoomRail
    hintLabel.alpha = isPortraitBlocked ? 0 : 1
  }

  private func resolveOnboardingTarget(_ id: String) -> UIView? {
    switch id.lowercased() {
    case "shutter":
      return shutterButton
    case "flash":
      return flashButton.isHidden ? nil : flashButton
    case "zoom":
      return zoomRail.isHidden || zoomRail.alpha < 0.01 ? nil : zoomRail
    case "zoom_wheel":
      guard !zoomRail.isHidden, zoomRail.alpha >= 0.01 else { return nil }
      return zoomWheel.isHidden ? nil : zoomWheel
    case "close":
      return closeButton
    case "hint":
      return hintLabel
    case "focus":
      return focusIndicator.alpha > 0.05 ? focusIndicator : onboardingSpot
    case "brightness":
      return focusExposureControl.alpha > 0.05 ? focusExposureControl : onboardingSpot
    case "pinch":
      return onboardingSpot
    default:
      return nil
    }
  }
}

// Only begin one-finger exposure adjustment after tap-to-focus and for a clearly
// vertical gesture. Horizontal motion and the initial focus tap stay intact.
extension NativeCameraViewController: UIGestureRecognizerDelegate {
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: previewContainer)
    if pan.view === shutterButton {
      // The landscape precision gesture intentionally starts toward the
      // preview (left), never toward the screen edge or vertically.
      return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.15
    }
    if pan.view === zoomWheel {
      return !zoomWheel.isHidden && abs(velocity.y) > abs(velocity.x) * 1.1
    }
    if pan.view === previewContainer {
      guard cameraSession.supportsExposureCompensation,
        focusExposureControl.alpha > 0.01
      else { return false }
    }
    return abs(velocity.y) > abs(velocity.x) * 1.15
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    guard let touchedView = touch.view else { return true }
    let onPreview = gestureRecognizer.view === previewContainer
    let onOverlay = gestureRecognizer.view === controlsOverlay
    guard onPreview || onOverlay else { return true }

    if gestureRecognizer === zoomWheelDismissTap {
      guard !zoomWheel.isHidden else { return false }
      // A touch on the zoom rail starts/restarts scrubbing; everything else
      // closes the persistent wheel while allowing the tapped control to work.
      let touchedZoomControl = touchedView === zoomRail
        || touchedView.isDescendant(of: zoomRail)
        || touchedView === zoomWheel
        || touchedView.isDescendant(of: zoomWheel)
      return !touchedZoomControl
    }
    // Preview / overlay gestures must never compete with camera chrome.
    let blockedRoots: [UIView] = [
      closeButton,
      shutterRail,
      zoomRail,
      zoomWheel,
      flashButton,
      flashLabel,
      flashModeTray,
      portraitBlockOverlay,
    ]
    return !blockedRoots.contains { root in
      touchedView === root || touchedView.isDescendant(of: root)
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    if gestureRecognizer === zoomWheelDismissTap
      || otherGestureRecognizer === zoomWheelDismissTap
    {
      return true
    }
    // Let a second finger transition naturally from vertical drag to pinch.
    if gestureRecognizer is UIPinchGestureRecognizer
      || otherGestureRecognizer is UIPinchGestureRecognizer
    {
      return true
    }

    // These gestures live on separate controls and may be driven by separate
    // fingers: holding the shutter records, while scrubbing the zoom rail zooms.
    let shutterAndWheel =
      (gestureRecognizer.view === shutterButton && otherGestureRecognizer.view === zoomRail)
      || (gestureRecognizer.view === zoomRail && otherGestureRecognizer.view === shutterButton)
    if shutterAndWheel {
      return true
    }

    let shutterGesture = gestureRecognizer.view === shutterButton
      && otherGestureRecognizer.view === shutterButton
    return shutterGesture
      && (gestureRecognizer is UILongPressGestureRecognizer
        || otherGestureRecognizer is UILongPressGestureRecognizer)
  }
}

// MARK: - Session delegate

extension NativeCameraViewController: NativeCameraSessionDelegate {
  func sessionDidFinishConfiguration(_ session: NativeCameraSession) {
    busyOverlay.stopAnimating()
    refreshZoomChips()
    // configureLocked resets hardware zoom — restore the UI selection so a
    // photo↔video switch does not silently jump FOV.
    let range = session.zoomFactorRange()
    let restored = min(max(currentZoomFactor, range.lowerBound), range.upperBound)
    if restored > 0.01 {
      currentZoomFactor = restored
      session.setZoomFactor(restored, animated: false)
      highlightZoomChip(closestTo: restored)
    }
    refreshFlashButton()
    refreshFlipButton(isRecording: session.isRecording)
    refreshExposureControls()
    applyVideoOrientationFromInterface()
    consumePendingCaptureAction()
  }

  func session(_ session: NativeCameraSession, didFailWithCode code: String, message: String) {
    let hadActivePhoto = activePhotoCaptureEpoch != nil
    if hadActivePhoto {
      _ = completeActivePhotoCaptureIfCurrent()
    } else {
      cancelPhotoCaptureTimeout()
    }
    busyOverlay.stopAnimating()
    shutterButton.isEnabled = true
    pendingCaptureAction = .none
    if code == "init_failed" || code == "no_rear_camera" || code == "camera_in_use"
      || code == "permission_denied"
    {
      finish(.failure(code: code, message: message))
      return
    }
    // Timeout already unlocked UI — ignore a late ISP/encode failure for that shot.
    if !hadActivePhoto, code == "capture_failed" || code == "insufficient_storage" {
      NSLog("\(Self.logPrefix) ignoring late photo failure code=\(code)")
      return
    }
    presentErrorAlert(message: message)
  }

  func session(_ session: NativeCameraSession, didUpdateZoomFactor factor: CGFloat) {
    currentZoomFactor = factor
    highlightZoomChip(closestTo: factor)
    updateZoomWheel(currentDeviceFactor: factor)
  }

  func session(_ session: NativeCameraSession, didChangeRecording isRecording: Bool) {
    updateShutterAppearance(recording: isRecording)
    updateHint(recording: isRecording)
    modeControl.isEnabled = !isRecording
    refreshFlipButton(isRecording: isRecording)
    if isRecording {
      startRecordingTimer()
    } else {
      stopRecordingTimer()
    }
  }

  func session(
    _ session: NativeCameraSession,
    didCapturePhotoAt url: URL,
    metadata: [String: Any]
  ) {
    handleSuccessfulCapture(url: url, metadata: metadata, isPhoto: true)
  }

  func session(
    _ session: NativeCameraSession,
    didFinishRecordingAt url: URL,
    metadata: [String: Any]
  ) {
    handleSuccessfulCapture(url: url, metadata: metadata, isPhoto: false)
  }

  func session(_ session: NativeCameraSession, recordingDidFail code: String, message: String) {
    shutterLongPressActive = false
    stopRecordingTimer()
    updateShutterAppearance(recording: false)
    updateHint(recording: false)
    returnToPhotoModeIfAllowed()
    presentErrorAlert(message: message)
  }

  func sessionWasInterrupted(_ session: NativeCameraSession, reason: String) {
    if reason == "camera_in_use" {
      presentErrorAlert(message: "Camera is in use by another application.")
    }
  }

  func sessionInterruptionEnded(_ session: NativeCameraSession) {
    // Session restarts itself.
  }
}
