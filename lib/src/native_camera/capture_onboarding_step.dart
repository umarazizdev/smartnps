

class CaptureOnboardingStep {
  const CaptureOnboardingStep({
    required this.targetId,
    required this.title,
    required this.body,
    this.arrow = CaptureOnboardingArrow.auto,
  });

  final String targetId;

  final String title;
  final String body;

  final CaptureOnboardingArrow arrow;

  Map<String, Object?> toWire() => <String, Object?>{
        'id': targetId,
        'title': title,
        'body': body,
        'arrow': arrow.wireName,
      };

  static CaptureOnboardingStep? tryFromWire(Map<Object?, Object?> raw) {
    final id = (raw['id'] as String?)?.trim();
    final title = (raw['title'] as String?)?.trim();
    final body = (raw['body'] as String?)?.trim();
    if (id == null || id.isEmpty || title == null || title.isEmpty) {
      return null;
    }
    if (body == null || body.isEmpty) return null;
    return CaptureOnboardingStep(
      targetId: id,
      title: title,
      body: body,
      arrow: CaptureOnboardingArrow.fromWire(raw['arrow'] as String?),
    );
  }
}

enum CaptureOnboardingArrow {
  auto,
  left,
  right,
  up,
  down;

  String get wireName => name;

  static CaptureOnboardingArrow fromWire(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'left':
        return CaptureOnboardingArrow.left;
      case 'right':
        return CaptureOnboardingArrow.right;
      case 'up':
        return CaptureOnboardingArrow.up;
      case 'down':
        return CaptureOnboardingArrow.down;
      default:
        return CaptureOnboardingArrow.auto;
    }
  }
}
