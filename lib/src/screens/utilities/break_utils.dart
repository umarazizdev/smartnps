Map<String, int> parseBreakMinutes({
  dynamic unpaidField,
  dynamic paidField,
  dynamic note,
}) {
  int unpaidMin = 0;
  int paidMin = 0;

  if (unpaidField != null) {
    unpaidMin = (unpaidField is num)
        ? unpaidField.toInt()
        : int.tryParse(unpaidField.toString()) ?? 0;
  }
  if (paidField != null) {
    paidMin = (paidField is num)
        ? paidField.toInt()
        : int.tryParse(paidField.toString()) ?? 0;
  }

  // If explicit values not provided, infer from note (e.g. "30m paid break" or "30m unpaid")
  if ((unpaidMin + paidMin) == 0) {
    final noteRaw = note;
    if (noteRaw != null) {
      final s = noteRaw.toString().toLowerCase();
      final reg = RegExp(r"(\d+)\s*m");
      final m = reg.firstMatch(s);
      if (m != null) {
        final parsed = int.tryParse(m.group(1) ?? '') ?? 0;
        if (parsed > 0) {
          if (s.contains('paid')) {
            paidMin = parsed;
          } else if (s.contains('unpaid')) {
            unpaidMin = parsed;
          } else {
            unpaidMin = parsed;
          }
        }
      }
    }
  }

  return {'unpaid': unpaidMin, 'paid': paidMin, 'total': unpaidMin + paidMin};
}
