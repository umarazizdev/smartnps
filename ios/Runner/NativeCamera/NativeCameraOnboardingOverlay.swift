import UIKit

/// First-launch Capture coachmarks: dark scrim with a cutout around the active
/// control, short copy, and Next / Skip actions. Step content comes from Flutter.
final class NativeCameraOnboardingOverlay: UIView {
  struct Step {
    let id: String
    let title: String
    let body: String
    let arrow: String

    static func parse(_ raw: [[String: Any]]?) -> [Step] {
      guard let raw, !raw.isEmpty else { return [] }
      return raw.compactMap { item in
        let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = (item["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, !title.isEmpty, !body.isEmpty else { return nil }
        let arrow = (item["arrow"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          ?? "auto"
        return Step(id: id, title: title, body: body, arrow: arrow.isEmpty ? "auto" : arrow)
      }
    }
  }

  var onCompleted: (() -> Void)?
  var onFinishedUi: (() -> Void)?
  var targetResolver: ((String) -> UIView?)?
  var stepPreparer: ((String) -> Void)?

  private var steps: [Step] = []
  private var index = 0
  private var holeRect: CGRect = .null
  private var arrowPath = UIBezierPath()
  private var preferredArrow = "auto"

  private let dimLayer = CAShapeLayer()
  private let holeStroke = CAShapeLayer()
  private let connectorLayer = CAShapeLayer()
  private let arrowLayer = CAShapeLayer()

  private let card = UIView()
  private let contentStack = UIStackView()
  private let stepLabel = UILabel()
  private let titleLabel = UILabel()
  private let bodyLabel = UILabel()
  private let skipButton = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private var cardLeadingConstraint: NSLayoutConstraint?
  private var cardTopConstraint: NSLayoutConstraint?
  private var cardWidthConstraint: NSLayoutConstraint?
  private let accent = UIColor(
    red: 228 / 255,
    green: 142 / 255,
    blue: 21 / 255,
    alpha: 1
  )

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = true
    backgroundColor = .clear
    // Keep coachmarks above camera chrome if sibling z-order drifts.
    layer.zPosition = 10_000

    dimLayer.fillColor = UIColor(white: 0, alpha: 0.72).cgColor
    dimLayer.fillRule = .evenOdd
    layer.addSublayer(dimLayer)

    holeStroke.fillColor = UIColor.clear.cgColor
    holeStroke.strokeColor = accent.cgColor
    holeStroke.lineWidth = 2.5
    layer.addSublayer(holeStroke)

    connectorLayer.fillColor = UIColor.clear.cgColor
    connectorLayer.strokeColor = accent.withAlphaComponent(0.9).cgColor
    connectorLayer.lineWidth = 2.25
    connectorLayer.lineCap = .round
    layer.addSublayer(connectorLayer)

    arrowLayer.fillColor = accent.cgColor
    layer.addSublayer(arrowLayer)

    card.backgroundColor = UIColor(red: 26 / 255, green: 35 / 255, blue: 50 / 255, alpha: 0.95)
    card.layer.cornerRadius = 14
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = 0.35
    card.layer.shadowRadius = 12
    card.layer.shadowOffset = CGSize(width: 0, height: 4)
    card.isHidden = true
    // Positioned via leading/top/width; height comes from stack content.
    // Never mix frame layout with Auto Layout on this view (avoids width/height == 0 fights).
    card.translatesAutoresizingMaskIntoConstraints = false
    addSubview(card)
    // Pointer must sit above the tip card (same bug as Android z-order).
    raisePointerAboveCard()

    stepLabel.font = .systemFont(ofSize: 11, weight: .bold)
    stepLabel.textColor = UIColor(red: 148 / 255, green: 163 / 255, blue: 184 / 255, alpha: 1)

    titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
    titleLabel.textColor = UIColor(red: 241 / 255, green: 245 / 255, blue: 249 / 255, alpha: 1)
    titleLabel.numberOfLines = 2

    bodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
    bodyLabel.textColor = UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1)
    bodyLabel.numberOfLines = 0

    skipButton.setTitle("Skip", for: .normal)
    skipButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
    skipButton.setTitleColor(
      UIColor(red: 203 / 255, green: 213 / 255, blue: 225 / 255, alpha: 1),
      for: .normal
    )
    skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

    nextButton.setTitle("Next", for: .normal)
    nextButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
    nextButton.setTitleColor(
      UIColor(red: 2 / 255, green: 42 / 255, blue: 103 / 255, alpha: 1),
      for: .normal
    )
    nextButton.backgroundColor = UIColor(red: 228 / 255, green: 142 / 255, blue: 21 / 255, alpha: 1)
    nextButton.layer.cornerRadius = 8
    nextButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
    nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

    let actions = UIStackView(arrangedSubviews: [skipButton, nextButton])
    actions.axis = .horizontal
    actions.spacing = 8
    actions.alignment = .center
    actions.distribution = .fill

    contentStack.axis = .vertical
    contentStack.spacing = 6
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    [stepLabel, titleLabel, bodyLabel, actions].forEach { contentStack.addArrangedSubview($0) }
    card.addSubview(contentStack)

    let leading = card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
    let top = card.topAnchor.constraint(equalTo: topAnchor, constant: 20)
    let width = card.widthAnchor.constraint(equalToConstant: 300)
    cardLeadingConstraint = leading
    cardTopConstraint = top
    cardWidthConstraint = width

    NSLayoutConstraint.activate([
      leading,
      top,
      width,
      contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
      contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
      contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func start(steps: [Step]) {
    self.steps = steps
    index = 0
    isHidden = false
    layer.zPosition = 10_000
    superview?.bringSubviewToFront(self)
    alpha = 0
    UIView.animate(withDuration: 0.22) { self.alpha = 1 }
    DispatchQueue.main.async { [weak self] in
      self?.showCurrentStep()
    }
  }

  var isActive: Bool {
    !isHidden && !steps.isEmpty
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if !isHidden {
      layoutCurrentStep()
    }
  }

  @objc private func skipTapped() {
    finishTour(completed: true)
  }

  @objc private func nextTapped() {
    index += 1
    while index < steps.count {
      let id = steps[index].id
      stepPreparer?(id)
      if isUsable(targetResolver?(id)) { break }
      index += 1
    }
    if index >= steps.count {
      finishTour(completed: true)
      return
    }
    showCurrentStep()
  }

  private func finishTour(completed: Bool) {
    if completed {
      onCompleted?()
    }
    onFinishedUi?()
    UIView.animate(withDuration: 0.16, animations: {
      self.alpha = 0
    }, completion: { _ in
      self.isHidden = true
      self.card.isHidden = true
      self.steps = []
    })
  }

  private func isUsable(_ target: UIView?) -> Bool {
    guard let target, !target.isHidden else { return false }
    return target.bounds.width > 0 && target.bounds.height > 0
  }

  private func showCurrentStep(attempt: Int = 0) {
    while index < steps.count {
      let id = steps[index].id
      stepPreparer?(id)
      if isUsable(targetResolver?(id)) { break }
      index += 1
    }
    if index >= steps.count {
      if attempt < 6 {
        index = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
          self?.showCurrentStep(attempt: attempt + 1)
        }
        return
      }
      finishTour(completed: false)
      return
    }

    let step = steps[index]
    stepPreparer?(step.id)
    guard isUsable(targetResolver?(step.id)) else {
      if attempt < 6 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
          self?.showCurrentStep(attempt: attempt + 1)
        }
        return
      }
      index += 1
      showCurrentStep(attempt: attempt)
      return
    }

    preferredArrow = step.arrow
    stepLabel.text = "Tip \(index + 1) of \(steps.count)"
    titleLabel.text = step.title
    bodyLabel.text = step.body

    var hasMore = false
    if index + 1 < steps.count {
      for i in (index + 1)..<steps.count {
        stepPreparer?(steps[i].id)
        if isUsable(targetResolver?(steps[i].id)) {
          hasMore = true
          break
        }
      }
      stepPreparer?(step.id)
    }
    nextButton.setTitle(hasMore ? "Next" : "Done", for: .normal)
    card.isHidden = false
    layoutCurrentStep()
  }

  private func layoutCurrentStep() {
    guard index < steps.count,
          let target = targetResolver?(steps[index].id)
    else { return }

    let pad: CGFloat = 10
    let targetFrame = target.convert(target.bounds, to: self)
    holeRect = targetFrame.insetBy(dx: -pad, dy: -pad)

    let cardWidth: CGFloat = min(300, max(220, bounds.width - 40))
    cardWidthConstraint?.constant = cardWidth
    // Force a layout pass so intrinsic height reflects current copy + width.
    card.setNeedsLayout()
    layoutIfNeeded()
    let cardSize = card.systemLayoutSizeFitting(
      CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    let margin: CGFloat = 20
    let gap: CGFloat = 36
    let holeCx = holeRect.midX

    let preferred: String = {
      switch preferredArrow.lowercased() {
      case "left", "right", "up", "down":
        return preferredArrow.lowercased()
      default:
        return holeCx > bounds.width * 0.55 ? "left" : "right"
      }
    }()

    let (cardOrigin, resolved) = placeCard(
      preferred: preferred,
      cardSize: cardSize,
      margin: margin,
      gap: gap
    )
    cardLeadingConstraint?.constant = cardOrigin.x
    cardTopConstraint?.constant = cardOrigin.y
    layoutIfNeeded()
    rebuildMask(preferred: resolved)
  }

  /// Prefer catalog side, but never cover the spotlight — try alternates.
  private func placeCard(
    preferred: String,
    cardSize: CGSize,
    margin: CGFloat,
    gap: CGFloat
  ) -> (CGPoint, String) {
    let order = [preferred, "down", "up", "left", "right"]
    var seen = Set<String>()
    var bestOrigin = CGPoint(x: margin, y: margin)
    var bestDir = preferred
    var bestScore = -CGFloat.greatestFiniteMagnitude

    for dir in order where seen.insert(dir).inserted {
      let origin = cardOrigin(for: dir, cardSize: cardSize, margin: margin, gap: gap)
      let candidate = CGRect(origin: origin, size: cardSize)
      let inflatedHole = holeRect.insetBy(dx: -8, dy: -8)
      let overlaps = candidate.intersects(inflatedHole)
      var score: CGFloat = overlaps ? -1_000 : (dir == preferred ? 100 : 50)
      score += clearanceScore(candidate: candidate)
      if score > bestScore {
        bestScore = score
        bestOrigin = origin
        bestDir = dir
      }
      if !overlaps, dir == preferred { break }
    }
    return (bestOrigin, bestDir)
  }

  private func cardOrigin(
    for dir: String,
    cardSize: CGSize,
    margin: CGFloat,
    gap: CGFloat
  ) -> CGPoint {
    let holeCx = holeRect.midX
    let holeCy = holeRect.midY
    let maxX = max(margin, bounds.width - cardSize.width - margin)
    let maxY = max(margin, bounds.height - cardSize.height - margin)
    switch dir {
    case "left":
      return CGPoint(
        x: min(max(margin, holeRect.minX - cardSize.width - gap), maxX),
        y: min(max(margin, holeCy - cardSize.height / 2), maxY)
      )
    case "right":
      return CGPoint(
        x: min(max(margin, holeRect.maxX + gap), maxX),
        y: min(max(margin, holeCy - cardSize.height / 2), maxY)
      )
    case "up":
      return CGPoint(
        x: min(max(margin, holeCx - cardSize.width / 2), maxX),
        y: min(max(margin, holeRect.minY - cardSize.height - gap), maxY)
      )
    default:
      return CGPoint(
        x: min(max(margin, holeCx - cardSize.width / 2), maxX),
        y: min(max(margin, holeRect.maxY + gap), maxY)
      )
    }
  }

  private func clearanceScore(candidate: CGRect) -> CGFloat {
    let dx: CGFloat
    if candidate.maxX < holeRect.minX {
      dx = holeRect.minX - candidate.maxX
    } else if candidate.minX > holeRect.maxX {
      dx = candidate.minX - holeRect.maxX
    } else {
      dx = 0
    }
    let dy: CGFloat
    if candidate.maxY < holeRect.minY {
      dy = holeRect.minY - candidate.maxY
    } else if candidate.minY > holeRect.maxY {
      dy = candidate.minY - holeRect.maxY
    } else {
      dy = 0
    }
    return min(dx + dy, 80)
  }

  private func rebuildMask(preferred: String) {
    let path = UIBezierPath(rect: bounds)
    if !holeRect.isNull, !holeRect.isEmpty {
      path.append(UIBezierPath(roundedRect: holeRect, cornerRadius: 18))
    }
    dimLayer.path = path.cgPath
    dimLayer.frame = bounds

    if !holeRect.isNull, !holeRect.isEmpty {
      holeStroke.path = UIBezierPath(roundedRect: holeRect, cornerRadius: 18).cgPath
      holeStroke.frame = bounds
      holeStroke.isHidden = false
    } else {
      holeStroke.isHidden = true
    }

    buildPointer(preferred: preferred)
    raisePointerAboveCard()
  }

  private func buildPointer(preferred: String) {
    let caret: CGFloat = 11
    let nest: CGFloat = 1.5
    let holeCx = holeRect.midX
    let holeCy = holeRect.midY
    let cardFrame = card.frame

    let arrow = UIBezierPath()
    let connector = UIBezierPath()

    switch preferred {
    case "left":
      let baseX = cardFrame.maxX - nest
      let baseY = min(max(holeCy, cardFrame.minY + caret), cardFrame.maxY - caret)
      let tip = CGPoint(x: cardFrame.maxX + caret, y: baseY)
      arrow.move(to: tip)
      arrow.addLine(to: CGPoint(x: baseX, y: baseY - caret))
      arrow.addLine(to: CGPoint(x: baseX, y: baseY + caret))
      arrow.close()
      connector.move(to: tip)
      connector.addLine(to: CGPoint(x: holeRect.minX - 2, y: holeCy))
    case "right":
      let baseX = cardFrame.minX + nest
      let baseY = min(max(holeCy, cardFrame.minY + caret), cardFrame.maxY - caret)
      let tip = CGPoint(x: cardFrame.minX - caret, y: baseY)
      arrow.move(to: tip)
      arrow.addLine(to: CGPoint(x: baseX, y: baseY - caret))
      arrow.addLine(to: CGPoint(x: baseX, y: baseY + caret))
      arrow.close()
      connector.move(to: tip)
      connector.addLine(to: CGPoint(x: holeRect.maxX + 2, y: holeCy))
    case "up":
      let baseY = cardFrame.maxY - nest
      let baseX = min(max(holeCx, cardFrame.minX + caret), cardFrame.maxX - caret)
      let tip = CGPoint(x: baseX, y: cardFrame.maxY + caret)
      arrow.move(to: tip)
      arrow.addLine(to: CGPoint(x: baseX - caret, y: baseY))
      arrow.addLine(to: CGPoint(x: baseX + caret, y: baseY))
      arrow.close()
      connector.move(to: tip)
      connector.addLine(to: CGPoint(x: holeCx, y: holeRect.minY - 2))
    default:
      let baseY = cardFrame.minY + nest
      let baseX = min(max(holeCx, cardFrame.minX + caret), cardFrame.maxX - caret)
      let tip = CGPoint(x: baseX, y: cardFrame.minY - caret)
      arrow.move(to: tip)
      arrow.addLine(to: CGPoint(x: baseX - caret, y: baseY))
      arrow.addLine(to: CGPoint(x: baseX + caret, y: baseY))
      arrow.close()
      connector.move(to: tip)
      connector.addLine(to: CGPoint(x: holeCx, y: holeRect.maxY + 2))
    }

    arrowPath = arrow
    arrowLayer.path = arrow.cgPath
    arrowLayer.frame = bounds
    connectorLayer.path = connector.cgPath
    connectorLayer.frame = bounds
  }

  /// Keep dim/hole under content; float connector + caret above the tip card.
  private func raisePointerAboveCard() {
    dimLayer.zPosition = 0
    holeStroke.zPosition = 1
    card.layer.zPosition = 2
    connectorLayer.zPosition = 10_000
    arrowLayer.zPosition = 10_001
  }
}
