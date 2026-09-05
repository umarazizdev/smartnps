import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Release-safe ring log of path decisions for real-road curve testing.
class LocationPathCurveDebugEvent {
  const LocationPathCurveDebugEvent({
    required this.atMs,
    required this.outcome,
    required this.reason,
    required this.mode,
    required this.accuracyM,
    required this.speedKmh,
    required this.distFromLastM,
    required this.needM,
    required this.headingDeltaDeg,
    required this.isCorner,
    required this.lat,
    required this.lng,
    required this.nativeMotion,
    required this.fusedMotion,
    required this.keepTrigger,
  });

  final int atMs;
  final String outcome; // queued | skipped | ping_only
  final String reason;
  final String mode;
  final double accuracyM;
  final double? speedKmh;
  final double? distFromLastM;
  final double? needM;
  final double? headingDeltaDeg;
  final bool isCorner;
  final double lat;
  final double lng;
  final String nativeMotion;
  final String fusedMotion;
  final String keepTrigger;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true);

  Map<String, dynamic> toJson() => {
        'atMs': atMs,
        'outcome': outcome,
        'reason': reason,
        'mode': mode,
        'accuracyM': accuracyM,
        'speedKmh': speedKmh,
        'distFromLastM': distFromLastM,
        'needM': needM,
        'headingDeltaDeg': headingDeltaDeg,
        'isCorner': isCorner,
        'lat': lat,
        'lng': lng,
        'nativeMotion': nativeMotion,
        'fusedMotion': fusedMotion,
        'keepTrigger': keepTrigger,
      };

  factory LocationPathCurveDebugEvent.fromJson(Map<String, dynamic> json) {
    return LocationPathCurveDebugEvent(
      atMs: (json['atMs'] as num?)?.toInt() ?? 0,
      outcome: json['outcome']?.toString() ?? 'unknown',
      reason: json['reason']?.toString() ?? '',
      mode: json['mode']?.toString() ?? '',
      accuracyM: (json['accuracyM'] as num?)?.toDouble() ?? 0,
      speedKmh: (json['speedKmh'] as num?)?.toDouble(),
      distFromLastM: (json['distFromLastM'] as num?)?.toDouble(),
      needM: (json['needM'] as num?)?.toDouble(),
      headingDeltaDeg: (json['headingDeltaDeg'] as num?)?.toDouble(),
      isCorner: json['isCorner'] == true,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      nativeMotion: json['nativeMotion']?.toString() ?? '',
      fusedMotion: json['fusedMotion']?.toString() ?? '',
      keepTrigger: json['keepTrigger']?.toString() ?? '',
    );
  }

  String get summaryLine {
    final t = at.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final dist = distFromLastM == null
        ? '-'
        : '${distFromLastM!.toStringAsFixed(0)}m';
    final need = needM == null ? '-' : '${needM!.toStringAsFixed(0)}m';
    final speed =
        speedKmh == null ? '-' : '${speedKmh!.toStringAsFixed(0)}km/h';
    final corner = isCorner ? ' corner' : '';
    return '$hh:$mm:$ss ${outcome.toUpperCase()} $reason '
        'mode=$mode acc=${accuracyM.toStringAsFixed(0)}m '
        'dist=$dist need=$need speed=$speed$corner '
        'motion=$nativeMotion/$fusedMotion';
  }
}

class LocationPathCurveDebugSummary {
  const LocationPathCurveDebugSummary({
    required this.total,
    required this.queued,
    required this.skipped,
    required this.pingOnly,
    required this.skipReasons,
    required this.maxQueuedGapM,
    required this.avgQueuedAccuracyM,
    required this.cornerQueued,
    required this.gapsOver50m,
  });

  final int total;
  final int queued;
  final int skipped;
  final int pingOnly;
  final Map<String, int> skipReasons;
  final double maxQueuedGapM;
  final double avgQueuedAccuracyM;
  final int cornerQueued;
  final int gapsOver50m;
}

class LocationPathCurveDebugLog {
  LocationPathCurveDebugLog._();

  static final LocationPathCurveDebugLog instance = LocationPathCurveDebugLog._();

  static const int maxEvents = 300;
  static const String _fileName = 'gps_curve_debug.jsonl';

  File? _file;
  Future<void> _writeChain = Future<void>.value();

  Future<File> _ensureFile() async {
    final existing = _file;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _file = file;
    return file;
  }

  void record({
    required String outcome,
    required String reason,
    required String mode,
    required double accuracyM,
    required double lat,
    required double lng,
    double? speedKmh,
    double? distFromLastM,
    double? needM,
    double? headingDeltaDeg,
    bool isCorner = false,
    String nativeMotion = '',
    String fusedMotion = '',
    String keepTrigger = '',
  }) {
    final event = LocationPathCurveDebugEvent(
      atMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      outcome: outcome,
      reason: reason,
      mode: mode,
      accuracyM: accuracyM,
      speedKmh: speedKmh,
      distFromLastM: distFromLastM,
      needM: needM,
      headingDeltaDeg: headingDeltaDeg,
      isCorner: isCorner,
      lat: lat,
      lng: lng,
      nativeMotion: nativeMotion,
      fusedMotion: fusedMotion,
      keepTrigger: keepTrigger,
    );
    _writeChain = _writeChain.then((_) => _append(event)).catchError((_) {});
  }

  Future<void> _append(LocationPathCurveDebugEvent event) async {
    final file = await _ensureFile();
    await file.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    await _trimIfNeeded(file);
  }

  Future<void> _trimIfNeeded(File file) async {
    final lines = await file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length <= maxEvents) return;
    final keep = lines.sublist(lines.length - maxEvents);
    await file.writeAsString('${keep.join('\n')}\n', flush: true);
  }

  Future<List<LocationPathCurveDebugEvent>> readRecent({int limit = 120}) async {
    try {
      final file = await _ensureFile();
      if (!await file.exists()) return const [];
      final lines = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final start = lines.length > limit ? lines.length - limit : 0;
      final events = <LocationPathCurveDebugEvent>[];
      for (final line in lines.sublist(start)) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) {
            events.add(LocationPathCurveDebugEvent.fromJson(decoded));
          } else if (decoded is Map) {
            events.add(
              LocationPathCurveDebugEvent.fromJson(
                Map<String, dynamic>.from(decoded),
              ),
            );
          }
        } catch (_) {}
      }
      return events.reversed.toList();
    } catch (_) {
      return const [];
    }
  }

  Future<LocationPathCurveDebugSummary> summarize({
    Duration window = const Duration(minutes: 10),
  }) async {
    final events = await readRecent(limit: maxEvents);
    final cutoff = DateTime.now().toUtc().subtract(window);
    final recent = events.where((e) => !e.at.isBefore(cutoff)).toList();

    var queued = 0;
    var skipped = 0;
    var pingOnly = 0;
    var cornerQueued = 0;
    var accuracySum = 0.0;
    var accuracyCount = 0;
    var maxGap = 0.0;
    var gapsOver50 = 0;
    final reasons = <String, int>{};

    for (final event in recent) {
      if (event.outcome == 'queued') {
        queued++;
        if (event.isCorner) cornerQueued++;
        accuracySum += event.accuracyM;
        accuracyCount++;
        final gap = event.distFromLastM ?? 0;
        if (gap > maxGap) maxGap = gap;
        if (gap >= 50) gapsOver50++;
      } else if (event.outcome == 'ping_only') {
        pingOnly++;
        reasons[event.reason] = (reasons[event.reason] ?? 0) + 1;
      } else {
        skipped++;
        reasons[event.reason] = (reasons[event.reason] ?? 0) + 1;
      }
    }

    return LocationPathCurveDebugSummary(
      total: recent.length,
      queued: queued,
      skipped: skipped,
      pingOnly: pingOnly,
      skipReasons: reasons,
      maxQueuedGapM: maxGap,
      avgQueuedAccuracyM: accuracyCount == 0 ? 0 : accuracySum / accuracyCount,
      cornerQueued: cornerQueued,
      gapsOver50m: gapsOver50,
    );
  }

  Future<String> exportText({int limit = 80}) async {
    final events = await readRecent(limit: limit);
    final summary = await summarize();
    final buf = StringBuffer()
      ..writeln('SmartNPS360 GPS curve debug')
      ..writeln('window=10m events=${summary.total}')
      ..writeln(
        'queued=${summary.queued} skipped=${summary.skipped} '
        'pingOnly=${summary.pingOnly} corners=${summary.cornerQueued}',
      )
      ..writeln(
        'maxGap=${summary.maxQueuedGapM.toStringAsFixed(0)}m '
        'gaps>=50m=${summary.gapsOver50m} '
        'avgAcc=${summary.avgQueuedAccuracyM.toStringAsFixed(1)}m',
      )
      ..writeln('skipReasons=${summary.skipReasons}')
      ..writeln('---');
    for (final event in events) {
      buf.writeln(event.summaryLine);
    }
    return buf.toString();
  }

  Future<void> clear() async {
    final file = await _ensureFile();
    await file.writeAsString('', flush: true);
  }
}
