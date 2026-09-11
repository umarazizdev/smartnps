

class DutyLocationUploadGate {
  DateTime? _lastQueuedAt;

  void reset() {
    _lastQueuedAt = null;
  }

  bool tryAccept(Duration minInterval) {
    final now = DateTime.now();
    final last = _lastQueuedAt;
    if (last != null && now.difference(last) < minInterval) {
      return false;
    }
    _lastQueuedAt = now;
    return true;
  }

  Duration? timeSinceLastQueued() {
    final last = _lastQueuedAt;
    if (last == null) return null;
    return DateTime.now().difference(last);
  }
}
