import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

bool _tzInitialized = false;
tz.Location? _sfLoc;

void _ensureInitialized() {
  if (_tzInitialized) return;
  tz_data.initializeTimeZones();
  _sfLoc = tz.getLocation('America/Los_Angeles');
  _tzInitialized = true;
}

/// Returns current San Francisco (Pacific) wall-clock time as a plain,
/// non-UTC DateTime. DST is handled correctly by the timezone package.
DateTime sfNow() {
  _ensureInitialized();
  final sf = tz.TZDateTime.now(_sfLoc!);
  return DateTime(
    sf.year,
    sf.month,
    sf.day,
    sf.hour,
    sf.minute,
    sf.second,
    sf.millisecond,
    sf.microsecond,
  );
}

/// Converts any DateTime to SF (Pacific) wall-clock fields as a plain,
/// non-UTC DateTime. DST is handled correctly by the timezone package.
DateTime toSf(DateTime dt) {
  _ensureInitialized();
  final utc = dt.isUtc ? dt : dt.toUtc();
  final sf = tz.TZDateTime.from(utc, _sfLoc!);
  return DateTime(
    sf.year,
    sf.month,
    sf.day,
    sf.hour,
    sf.minute,
    sf.second,
    sf.millisecond,
    sf.microsecond,
  );
}
