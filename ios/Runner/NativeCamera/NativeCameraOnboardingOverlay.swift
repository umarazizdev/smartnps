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
    holeStroke.strokeColor = UIColor(
      red: 228 / 255,
      green: 142 / 255,
      blue: 21 / 255,
      alpha: 1
    ).cgColor
    holeStroke.lineWidth = 2.5
    layer.addSublayer(holeStroke)

    arrowLayer.fillColor = UIColor.white.cgColor
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
    let holeCx = holeRect.midX
    let holeCy = holeRect.midY

    let preferred: String = {
      switch preferredArrow.lowercased() {
      case "left", "right", "up", "down":
        return preferredArrow.lowercased()
      default:
        return holeCx > bounds.width * 0.55 ? "left" : "right"
      }
    }()

    var cardOrigin = CGPoint.zero
    switch preferred {
    case "left":
      cardOrigin.x = max(margin, holeRect.minX - cardSize.width - 28)
      cardOrigin.y = min(
        max(margin, holeCy - cardSize.height / 2),
        max(margin, bounds.height - cardSize.height - margin)
      )
    case "right":
      cardOrigin.x = min(
        max(margin, holeRect.maxX + 28),
        max(margin, bounds.width - cardSize.width - margin)
      )
      cardOrigin.y = min(
        max(margin, holeCy - cardSize.height / 2),
        max(margin, bounds.height - cardSize.height - margin)
      )
    case "up":
      cardOrigin.x = min(
        max(margin, holeCx - cardSize.width / 2),
        max(margin, bounds.width - cardSize.width - margin)
      )
      cardOrigin.y = max(margin, holeRect.minY - cardSize.height - 28)
    default:
      cardOrigin.x = min(
        max(margin, holeCx - cardSize.width / 2),
        max(margin, bounds.width - cardSize.width - margin)
      )
      cardOrigin.y = min(
        max(margin, holeRect.maxY + 28),
        max(margin, bounds.height - cardSize.height - margin)
      )
    }
    cardLeadingConstraint?.constant = cardOrigin.x
    cardTopConstraint?.constant = cardOrigin.y
    rebuildMask(preferred: preferred)
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

    arrowPath = UIBezierPath()
    let tipSize: CGFloat = 12
    switch preferred {
    case "left":
      let tip = CGPoint(x: holeRect.minX - 4, y: holeRect.midY)
      let baseX = card.frame.maxX
      let baseY = min(max(card.frame.midY, card.frame.minY + tipSize), card.frame.maxY - tipSize)
      arrowPath.move(to: tip)
      arrowPath.addLine(to: CGPoint(x: baseX, y: baseY - tipSize))
      arrowPath.addLine(to: CGPoint(x: baseX, y: baseY + tipSize))
      arrowPath.close()
    case "right":
      let tip = CGPoint(x: holeRect.maxX + 4, y: holeRect.midY)
      let baseX = card.frame.minX
      let baseY = min(max(card.frame.midY, card.frame.minY + tipSize), card.frame.maxY - tipSize)
      arrowPath.move(to: tip)
      arrowPath.addLine(to: CGPoint(x: baseX, y: baseY - tipSize))
      arrowPath.addLine(to: CGPoint(x: baseX, y: baseY + tipSize))
      arrowPath.close()
    case "up":
      let tip = CGPoint(x: holeRect.midX, y: holeRect.minY - 4)
      let baseY = card.frame.maxY
      let baseX = min(max(card.frame.midX, card.frame.minX + tipSize), card.frame.maxX - tipSize)
      arrowPath.move(to: tip)
      arrowPath.addLine(to: CGPoint(x: baseX - tipSize, y: baseY))
      arrowPath.addLine(to: CGPoint(x: baseX + tipSize, y: baseY))
      arrowPath.close()
    default:
      let tip = CGPoint(x: holeRect.midX, y: holeRect.maxY + 4)
      let baseY = card.frame.minY
      let baseX = min(max(card.frame.midX, card.frame.minX + tipSize), card.frame.maxX - tipSize)
      arrowPath.move(to: tip)
      arrowPath.addLine(to: CGPoint(x: baseX - tipSize, y: baseY))
      arrowPath.addLine(to: CGPoint(x: baseX + tipSize, y: baseY))
      arrowPath.close()
    }
    arrowLayer.path = arrowPath.cgPath
    arrowLayer.frame = bounds
  }
}
