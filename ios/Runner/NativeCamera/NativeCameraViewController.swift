import AVFoundation
import UIKit

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
  }

  enum Outcome {
    case success([String: Any])
    case canceled
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
  private let controlsOverlay = UIView()
  private let closeButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .system)
  private let flipButton = UIButton(type: .system)
  private let shutterButton = UIButton(type: .custom)
  private let modeControl = UISegmentedControl(items: ["Photo", "Video"])
  private let recordingBadge = UIView()
  private let recordingDot = UIView()
  private let timerLabel = UILabel()
  private let zoomRail = UIView()
  private let zoomStack = UIStackView()
  private let shutterRail = UIView()
  private let exposureStack = UIStackView()
  private let exposureUpButton = UIButton(type: .system)
  private let exposureDownButton = UIButton(type: .system)
  private let exposureValueLabel = UILabel()
  private let hintLabel = UILabel()
  private let focusIndicator = UIView()
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
  private var pendingCaptureAction: PendingCaptureAction = .none
  private var shutterLongPressActive = false
  /// EV step in stops, matching the Android exposure control granularity.
  private let exposureStep: Float = 0.5

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
        self.refreshFlashButton()
        self.refreshFlipButton()
        self.refreshExposureControls()
        NSLog("\(Self.logPrefix) CAMERA_READY +\(ms())ms")
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    cameraSession.previewLayer.frame = previewContainer.bounds
    applyVideoOrientationFromInterface()
    syncPortraitBlock()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    cameraSession.startRunning()
    syncPortraitBlock()
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

    controlsOverlay.translatesAutoresizingMaskIntoConstraints = false
    controlsOverlay.backgroundColor = .clear
    view.addSubview(controlsOverlay)

    NSLayoutConstraint.activate([
      previewContainer.topAnchor.constraint(equalTo: view.topAnchor),
      previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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

    focusIndicator.frame = CGRect(x: 0, y: 0, width: 72, height: 72)
    focusIndicator.layer.borderColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1).cgColor
    focusIndicator.layer.borderWidth = 1.5
    focusIndicator.layer.cornerRadius = 8
    focusIndicator.alpha = 0
    focusIndicator.isUserInteractionEnabled = false
    previewContainer.addSubview(focusIndicator)

    busyOverlay.translatesAutoresizingMaskIntoConstraints = false
    busyOverlay.color = .white
    busyOverlay.hidesWhenStopped = true

    controlsOverlay.addSubview(closeButton)
    controlsOverlay.addSubview(recordingBadge)
    controlsOverlay.addSubview(zoomRail)
    controlsOverlay.addSubview(shutterRail)
    controlsOverlay.addSubview(modeControl)
    controlsOverlay.addSubview(busyOverlay)
    buildPortraitBlockOverlay()
    controlsOverlay.addSubview(portraitBlockOverlay)
    // Keep Close above the portrait scrim so it stays tappable.
    controlsOverlay.bringSubviewToFront(closeButton)

    let guide = controlsOverlay.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
      closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 18),
      closeButton.widthAnchor.constraint(equalToConstant: 42),
      closeButton.heightAnchor.constraint(equalToConstant: 42),

      recordingBadge.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      recordingBadge.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

      // Extra trailing inset so hint text never clips on notched devices.
      shutterRail.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -28),
      shutterRail.topAnchor.constraint(equalTo: guide.topAnchor),
      shutterRail.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
      shutterRail.widthAnchor.constraint(equalToConstant: 96),

      zoomRail.trailingAnchor.constraint(equalTo: shutterRail.leadingAnchor, constant: -14),
      zoomRail.centerYAnchor.constraint(equalTo: guide.centerYAnchor),

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
    guard configuration.landscapeOnly else {
      isPortraitBlocked = false
      portraitBlockOverlay.isHidden = true
      zoomRail.alpha = 1
      shutterRail.alpha = 1
      zoomRail.isUserInteractionEnabled = true
      shutterRail.isUserInteractionEnabled = true
      stopRotateHintAnimation()
      return
    }
    let boundsSize = size ?? view.bounds.size
    let portrait = boundsSize.height >= boundsSize.width
    isPortraitBlocked = portrait
    portraitBlockOverlay.isHidden = !portrait
    // Keep live preview under the dialog; only hide capture chrome.
    zoomRail.alpha = portrait ? 0 : 1
    shutterRail.alpha = portrait ? 0 : 1
    zoomRail.isUserInteractionEnabled = !portrait
    shutterRail.isUserInteractionEnabled = !portrait
    if portrait {
      startRotateHintAnimation()
      // Portrait live preview behind the dialog must stay upright.
      applyVideoOrientationFromInterface()
    } else {
      stopRotateHintAnimation()
      applyVideoOrientationFromInterface()
    }
    if portrait, cameraSession.isRecording {
      cameraSession.toggleRecording()
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

    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.accessibilityLabel = "Capture"
    shutterButton.layer.cornerRadius = 36
    shutterButton.clipsToBounds = true
    updateShutterAppearance(recording: false)

    hintLabel.translatesAutoresizingMaskIntoConstraints = false
    hintLabel.numberOfLines = 2
    hintLabel.textAlignment = .center
    hintLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    hintLabel.adjustsFontSizeToFitWidth = true
    hintLabel.minimumScaleFactor = 0.85
    hintLabel.lineBreakMode = .byWordWrapping
    updateHint(recording: false)

    buildExposureControls()

    shutterRail.addSubview(flashButton)
    shutterRail.addSubview(flipButton)
    shutterRail.addSubview(hintLabel)
    shutterRail.addSubview(shutterButton)
    shutterRail.addSubview(exposureStack)

    // Sits under the shutter, pinned to the bottom of the rail. The clearance
    // constraint yields first on short screens so nothing is ever clipped.
    let exposureClearance = exposureStack.topAnchor.constraint(
      greaterThanOrEqualTo: shutterButton.bottomAnchor,
      constant: 8
    )
    exposureClearance.priority = .defaultHigh
    NSLayoutConstraint.activate([
      exposureStack.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      exposureStack.bottomAnchor.constraint(
        equalTo: shutterRail.safeAreaLayoutGuide.bottomAnchor,
        constant: -10
      ),
      exposureClearance,
    ])

    NSLayoutConstraint.activate([
      flashButton.topAnchor.constraint(equalTo: shutterRail.safeAreaLayoutGuide.topAnchor, constant: 8),
      flashButton.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      flashButton.widthAnchor.constraint(equalToConstant: 42),
      flashButton.heightAnchor.constraint(equalToConstant: 42),

      flipButton.topAnchor.constraint(equalTo: flashButton.bottomAnchor, constant: 10),
      flipButton.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      flipButton.widthAnchor.constraint(equalToConstant: 42),
      flipButton.heightAnchor.constraint(equalToConstant: 42),

      shutterButton.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      shutterButton.centerYAnchor.constraint(equalTo: shutterRail.centerYAnchor),
      shutterButton.widthAnchor.constraint(equalToConstant: 72),
      shutterButton.heightAnchor.constraint(equalToConstant: 72),

      hintLabel.centerXAnchor.constraint(equalTo: shutterRail.centerXAnchor),
      hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: shutterRail.leadingAnchor, constant: 2),
      hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: shutterRail.trailingAnchor, constant: -2),
      hintLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -4),
    ])
  }

  /// Glass +/- EV control. Shown only when the active device reports a usable
  /// exposure target bias range.
  private func buildExposureControls() {
    styleGlassCircleButton(
      exposureUpButton,
      systemName: "plus",
      accessibility: "Increase exposure"
    )
    styleGlassCircleButton(
      exposureDownButton,
      systemName: "minus",
      accessibility: "Decrease exposure"
    )
    exposureUpButton.addTarget(self, action: #selector(exposureUpTapped), for: .touchUpInside)
    exposureDownButton.addTarget(self, action: #selector(exposureDownTapped), for: .touchUpInside)

    exposureValueLabel.translatesAutoresizingMaskIntoConstraints = false
    exposureValueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
    exposureValueLabel.textAlignment = .center
    exposureValueLabel.textColor = .white
    exposureValueLabel.accessibilityLabel = "Exposure compensation"
    exposureValueLabel.layer.shadowColor = UIColor.black.cgColor
    exposureValueLabel.layer.shadowOpacity = 0.6
    exposureValueLabel.layer.shadowRadius = 4
    exposureValueLabel.layer.shadowOffset = CGSize(width: 0, height: 1)

    exposureStack.translatesAutoresizingMaskIntoConstraints = false
    exposureStack.axis = .vertical
    exposureStack.spacing = 4
    exposureStack.alignment = .center
    exposureStack.isHidden = true
    exposureStack.addArrangedSubview(exposureUpButton)
    exposureStack.addArrangedSubview(exposureValueLabel)
    exposureStack.addArrangedSubview(exposureDownButton)

    NSLayoutConstraint.activate([
      exposureUpButton.widthAnchor.constraint(equalToConstant: 34),
      exposureUpButton.heightAnchor.constraint(equalToConstant: 34),
      exposureDownButton.widthAnchor.constraint(equalToConstant: 34),
      exposureDownButton.heightAnchor.constraint(equalToConstant: 34),
      exposureValueLabel.widthAnchor.constraint(equalToConstant: 40),
    ])
    exposureUpButton.layer.cornerRadius = 17
    exposureDownButton.layer.cornerRadius = 17
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
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
    previewContainer.addGestureRecognizer(tap)

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    previewContainer.addGestureRecognizer(pinch)

    let shutterTap = UITapGestureRecognizer(target: self, action: #selector(shutterTapped))
    let shutterLongPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(shutterLongPressed(_:))
    )
    shutterLongPress.minimumPressDuration = 0.35
    shutterTap.require(toFail: shutterLongPress)
    shutterButton.addGestureRecognizer(shutterLongPress)
    shutterButton.addGestureRecognizer(shutterTap)
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
    if cameraSession.isRecording {
      cameraSession.toggleRecording()
    }
    finish(.canceled)
  }

  @objc private func flashTapped() {
    let mode = cameraSession.cycleFlashMode()
    refreshFlashButton(mode: mode)
  }

  @objc private func exposureUpTapped() {
    adjustExposure(by: exposureStep)
  }

  @objc private func exposureDownTapped() {
    adjustExposure(by: -exposureStep)
  }

  private func adjustExposure(by delta: Float) {
    guard cameraSession.supportsExposureCompensation else { return }
    let applied = cameraSession.setExposureTargetBias(
      cameraSession.exposureTargetBias + delta
    )
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
    guard !cameraSession.isRecording else { return }
    let index = sender.tag
    guard index >= 0, index < cameraSession.zoomChips.count else { return }
    let chip = cameraSession.zoomChips[index]
    currentZoomFactor = chip.deviceFactor
    cameraSession.setZoomFactor(chip.deviceFactor, animated: true)
    highlightZoomChip(closestTo: chip.deviceFactor)
  }

  @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
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
    cameraSession.capturePhoto()
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
    highlightZoomChip(closestTo: currentZoomFactor)
  }

  private func highlightZoomChip(closestTo deviceFactor: CGFloat) {
    let display = cameraSession.displayZoomFactor(forDeviceZoom: deviceFactor)
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
      button.backgroundColor = selected ? Chrome.zoomChipSelected : Chrome.zoomChip
      button.setTitleColor(selected ? Chrome.zoomSelectedText : .white, for: .normal)
      button.titleLabel?.font = .systemFont(
        ofSize: selected ? 11 : 10,
        weight: .semibold
      )
    }
  }

  private func refreshFlashButton(mode: NativeCameraFlashMode? = nil) {
    let flashMode = mode ?? cameraSession.flashMode
    let supported = cameraSession.supportsFlashOrTorch
    flashButton.isHidden = !supported
    guard supported else { return }

    let name: String
    let tint: UIColor
    if isVideoMode {
      name = flashMode == .on ? "flashlight.on.fill" : "flashlight.off.fill"
      tint = flashMode == .on ? Chrome.zoomSelectedText : .white
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
    }
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    flashButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
    flashButton.tintColor = tint
    flashButton.accessibilityValue = flashMode.title
  }

  private func refreshExposureControls(bias: Float? = nil) {
    let supported = cameraSession.supportsExposureCompensation
    exposureStack.isHidden = !supported
    guard supported else { return }

    let value = bias ?? cameraSession.exposureTargetBias
    let rounded = (value * 10).rounded() / 10
    if abs(rounded) < 0.05 {
      exposureValueLabel.text = "0 EV"
      exposureValueLabel.textColor = UIColor(white: 1, alpha: 0.92)
    } else {
      exposureValueLabel.text = String(format: "%+.1f", rounded)
      exposureValueLabel.textColor = Chrome.zoomSelectedText
    }
    exposureValueLabel.accessibilityValue = exposureValueLabel.text

    exposureUpButton.isEnabled = value < cameraSession.maxExposureTargetBias - 0.01
    exposureDownButton.isEnabled = value > cameraSession.minExposureTargetBias + 0.01
    exposureUpButton.alpha = exposureUpButton.isEnabled ? 1 : 0.4
    exposureDownButton.alpha = exposureDownButton.isEnabled ? 1 : 0.4
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
      hintLabel.text = "Slide up/down\nto zoom"
      hintLabel.textColor = Chrome.orange
    } else {
      hintLabel.text = "Tap photo\nHold video"
      hintLabel.textColor = UIColor(white: 1, alpha: 0.92)
    }
    hintLabel.layer.shadowColor = UIColor.black.cgColor
    hintLabel.layer.shadowOpacity = 0.6
    hintLabel.layer.shadowRadius = 4
    hintLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
  }

  private func showFocusIndicator(at point: CGPoint) {
    focusIndicator.center = point
    focusIndicator.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
    focusIndicator.alpha = 1
    UIView.animate(
      withDuration: 0.22,
      animations: {
        self.focusIndicator.transform = .identity
      },
      completion: { _ in
        UIView.animate(
          withDuration: 0.35,
          delay: 0.65,
          options: [],
          animations: { self.focusIndicator.alpha = 0 }
        )
      }
    )
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
    stopRecordingTimer()
    cameraSession.stopRunning()
    let callback = onFinish
    onFinish = nil
    dismiss(animated: true) {
      callback?(outcome)
    }
  }

  private func handleSuccessfulCapture(url: URL, metadata: [String: Any], isPhoto: Bool) {
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
    finish(.success(payload))
  }
}

// MARK: - Session delegate

extension NativeCameraViewController: NativeCameraSessionDelegate {
  func sessionDidFinishConfiguration(_ session: NativeCameraSession) {
    busyOverlay.stopAnimating()
    refreshZoomChips()
    refreshFlashButton()
    refreshFlipButton(isRecording: session.isRecording)
    refreshExposureControls()
    applyVideoOrientationFromInterface()
    consumePendingCaptureAction()
  }

  func session(_ session: NativeCameraSession, didFailWithCode code: String, message: String) {
    busyOverlay.stopAnimating()
    shutterButton.isEnabled = true
    pendingCaptureAction = .none
    if code == "init_failed" || code == "no_rear_camera" || code == "camera_in_use"
      || code == "permission_denied"
    {
      finish(.failure(code: code, message: message))
      return
    }
    presentErrorAlert(message: message)
  }

  func session(_ session: NativeCameraSession, didUpdateZoomFactor factor: CGFloat) {
    currentZoomFactor = factor
    highlightZoomChip(closestTo: factor)
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
