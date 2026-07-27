import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../permissions/native_permission_status_service.dart';
import '../utilities/app_config.dart';
import 'motion_activity_fusion_controller.dart';
import 'motion_activity_service.dart';
import 'vehicle_session_fusion.dart';

/// Live native motion vs GPS-fused vehicle session for field testing.
///
/// **Fused** is the source of truth (same engine as GPS uploads). Native OS
/// recognition is shown for comparison — it often lags real motion by several
/// seconds; fusion fills that gap with GPS speed.
class MotionActivityScreen extends StatefulWidget {
  const MotionActivityScreen({super.key, this.isDark = false});

  final bool isDark;

  @override
  State<MotionActivityScreen> createState() => _MotionActivityScreenState();
}

class _MotionActivityScreenState extends State<MotionActivityScreen> {
  StreamSubscription<MotionActivityUpdate>? _motionSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _ageTicker;
  final _fusion = MotionActivityFusionController.instance;

  MotionActivityUpdate? _latest;
  VehicleSessionSnapshot? _fused;
  double? _gpsSpeedKmh;
  DateTime? _lastNativeAt;
  DateTime? _lastGpsAt;
  String _statusMessage = 'Initializing…';
  bool _permissionDenied = false;
  bool _unavailable = false;
  bool _starting = false;
  bool _gpsDenied = false;
  bool _acquired = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _ageTicker?.cancel();
    unawaited(_teardown());
    super.dispose();
  }

  Future<void> _teardown() async {
    await _motionSub?.cancel();
    _motionSub = null;
    await _gpsSub?.cancel();
    _gpsSub = null;
    if (_acquired) {
      await _fusion.release();
      _acquired = false;
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _starting = true;
      _statusMessage = 'Checking sensors…';
      _permissionDenied = false;
      _unavailable = false;
      _gpsDenied = false;
    });

    // Seed from in-memory fusion if duty GPS already started it.
    final existing = _fusion.lastSnapshot;
    final existingNative = _fusion.lastNative ?? MotionActivityService.lastUpdate;
    if (existing != null || existingNative != null) {
      setState(() {
        _fused = existing;
        _latest = existingNative;
        _gpsSpeedKmh = existing?.gpsSpeedKmh ?? existing?.smoothedSpeedKmh;
        if (existingNative != null) {
          _lastNativeAt = DateTime.now();
        }
      });
    }

    final available = await MotionActivityService.isAvailable();
    if (!available) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _unavailable = true;
        _statusMessage = 'Motion activity is not available on this device.';
      });
      return;
    }

    final granted = await _ensurePermission();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _permissionDenied = true;
        _statusMessage =
            'Motion activity permission is required to detect walking, running, driving, and more.';
      });
      // Report deny / unknown to permission-status API.
      unawaited(NativePermissionStatusService.instance.syncIfChanged());
      return;
    }

    // Keep permission-status API in sync after grant / re-check.
    unawaited(NativePermissionStatusService.instance.syncIfChanged());

    if (!_acquired) {
      await _fusion.acquire();
      _acquired = true;
    }

    await _motionSub?.cancel();
    _motionSub = MotionActivityService.stream.listen((update) {
      if (!mounted) return;
      _lastNativeAt = DateTime.now();
      _applyFusion(native: update);
    });

    final running = await MotionActivityService.isRunning();
    if (!mounted) return;
    if (!running) {
      final startResult = await MotionActivityService.start();
      if (!mounted) return;
      if (startResult['ok'] != true) {
        final error = startResult['error'];
        final code = error is Map ? error['code']?.toString() : null;
        setState(() {
          _starting = false;
          _permissionDenied = code == 'permission_denied';
          _statusMessage = code == 'permission_denied'
              ? 'Motion activity permission was denied.'
              : 'Could not start motion activity recognition.';
        });
        return;
      }
    }

    // Immediate snapshot — don't wait for the next OS event.
    final snap = await MotionActivityService.queryLatest();
    if (mounted && snap != null) {
      _lastNativeAt = DateTime.now();
      _applyFusion(native: snap);
    }

    await _startGpsSpeedWatch();
    _startAgeTicker();

    if (!mounted) return;
    setState(() {
      _starting = false;
      _statusMessage = 'Live — fused is source of truth';
    });
  }

  void _startAgeTicker() {
    _ageTicker?.cancel();
    // Refresh "Xs ago" labels so staleness is obvious.
    _ageTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_lastNativeAt != null || _lastGpsAt != null) {
        setState(() {});
      }
    });
  }

  Future<void> _startGpsSpeedWatch() async {
    await _gpsSub?.cancel();
    _gpsSub = null;

    try {
      final permission = await Geolocator.checkPermission();
      var resolved = permission;
      if (permission == LocationPermission.denied) {
        resolved = await Geolocator.requestPermission();
      }
      if (resolved == LocationPermission.denied ||
          resolved == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gpsDenied = true);
        return;
      }

      // Last-known fix paints speed before the first stream event.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          final speedMps = last.speed;
          final kmh = (speedMps.isFinite && speedMps >= 0)
              ? speedMps * 3.6
              : null;
          if (kmh != null) {
            _lastGpsAt = DateTime.now();
            _applyFusion(gpsSpeedKmh: kmh);
          }
        }
      } catch (_) {}

      // High-cadence stream so fusion tracks motion before OS AR catches up.
      final LocationSettings settings;
      if (Platform.isAndroid) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(milliseconds: 800),
        );
      } else if (Platform.isIOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: false,
          showBackgroundLocationIndicator: false,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );
      }

      _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (!mounted) return;
          final speedMps = position.speed;
          final kmh = (speedMps.isFinite && speedMps >= 0)
              ? speedMps * 3.6
              : null;
          _lastGpsAt = DateTime.now();
          _applyFusion(gpsSpeedKmh: kmh);
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // Motion comparison still works without GPS.
    }
  }

  void _applyFusion({
    MotionActivityUpdate? native,
    double? gpsSpeedKmh,
  }) {
    if (native != null) {
      _latest = native;
    }
    if (gpsSpeedKmh != null) {
      _gpsSpeedKmh = gpsSpeedKmh;
    }

    final activity = _latest?.activity ?? 'unknown';
    final confidence = _latest?.confidence ?? 0;
    final snapshot = _fusion.evaluateRaw(
      nativeActivity: activity,
      nativeConfidence: confidence,
      gpsSpeedKmh: _gpsSpeedKmh,
    );

    setState(() {
      _fused = snapshot;
      _statusMessage = 'Live — fused is source of truth';
    });
  }

  Future<bool> _ensurePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.activityRecognition.status;
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) return false;
      final requested = await Permission.activityRecognition.request();
      return requested.isGranted;
    }

    if (Platform.isIOS) {
      var native = await MotionActivityService.checkPermission();
      if (native == 'granted') return true;
      if (native == 'denied' || native == 'restricted') return false;
      native = await MotionActivityService.requestPermission();
      return native == 'granted' || native == 'notDetermined';
    }

    return false;
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  String _ageLabel(DateTime? at) {
    if (at == null) return '—';
    final s = DateTime.now().difference(at).inSeconds;
    if (s <= 0) return 'now';
    if (s < 60) return '${s}s ago';
    return '${(s / 60).floor()}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark
        ? const Color(0xFF0F1724)
        : const Color(AppConfig.cSurface);
    final fg = isDark ? Colors.white : const Color(AppConfig.cPrimary);
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF5B6575);

    final nativeActivity = _latest?.activity ?? 'unknown';
    final confidence = _latest?.confidence ?? 0;
    final fusedState = _fused?.fusedState ?? nativeActivity;
    final sessionActive = _fused?.active ?? false;
    final provisional = _fused?.provisional ?? false;
    final reason = _fused?.reason ?? '—';
    final smooth = _fused?.smoothedSpeedKmh;
    final apiLabel = _fused?.apiMotionActivity ?? '—';

    final speedText = _gpsDenied
        ? 'GPS permission denied'
        : _gpsSpeedKmh == null
            ? 'GPS speed —'
            : 'GPS ${_gpsSpeedKmh!.toStringAsFixed(1)} km/h'
                '${smooth == null ? '' : ' · smooth ${smooth.toStringAsFixed(1)}'}';

    return ColoredBox(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Motion Activity',
                  style: TextStyle(
                    color: fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Fused status is what GPS uploads use. Native OS often lags — GPS fills the gap.',
                  style: TextStyle(color: muted, fontSize: 14, height: 1.35),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  speedText,
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'API $apiLabel · '
                  'Native ${_ageLabel(_lastNativeAt)} · GPS ${_ageLabel(_lastGpsAt)}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              Expanded(
                child: Center(
                  child: _permissionDenied || _unavailable
                      ? _PermissionState(
                          message: _statusMessage,
                          showSettings: _permissionDenied,
                          onRetry: _bootstrap,
                          onOpenSettings: _openSettings,
                          isDark: isDark,
                        )
                      : _starting && _latest == null && _fused == null
                      ? Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Primary: fused (source of truth)
                            _HeroStatus(
                              activity: fusedState,
                              apiLabel: apiLabel,
                              subtitle: sessionActive
                                  ? (provisional
                                      ? 'Vehicle session · provisional GPS'
                                      : 'Vehicle session active')
                                  : (provisional
                                      ? 'GPS fill-in (waiting on OS)'
                                      : 'Live fused status'),
                              detail: reason,
                              isDark: isDark,
                              visual: _visualFor(fusedState),
                            ),
                            const SizedBox(height: 28),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _ResultColumn(
                                    title: 'Native',
                                    subtitle: 'OS only (often delayed)',
                                    activity: nativeActivity,
                                    detail: 'Confidence  $confidence%',
                                    confidence: confidence,
                                    isDark: isDark,
                                    visual: _visualFor(nativeActivity),
                                    showConfidenceBar: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ResultColumn(
                                    title: 'Session',
                                    subtitle: sessionActive
                                        ? (provisional
                                            ? 'ON · provisional'
                                            : 'ON')
                                        : 'OFF',
                                    activity: fusedState,
                                    detail: reason,
                                    confidence: confidence,
                                    isDark: isDark,
                                    visual: _visualFor(fusedState),
                                    emphasize: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _LegendChip(
                              isDark: isDark,
                              sessionActive: sessionActive,
                              provisional: provisional,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ActivityVisual _visualFor(String activity) {
    switch (activity) {
      case 'walking':
        return const _ActivityVisual(Icons.directions_walk, Color(0xFF1B7F5A));
      case 'running':
        return const _ActivityVisual(Icons.directions_run, Color(0xFFC45C26));
      case 'driving':
        return const _ActivityVisual(
          Icons.directions_car_filled,
          Color(0xFF022A67),
        );
      case 'driving_stopped':
        return const _ActivityVisual(
          Icons.traffic,
          Color(0xFF334155),
        );
      case 'cycling':
        return const _ActivityVisual(Icons.directions_bike, Color(0xFF0E7490));
      case 'stationary':
        return const _ActivityVisual(
          Icons.accessibility_new,
          Color(0xFF6B7280),
        );
      default:
        return const _ActivityVisual(Icons.sensors, Color(0xFF64748B));
    }
  }
}

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({
    required this.activity,
    required this.apiLabel,
    required this.subtitle,
    required this.detail,
    required this.isDark,
    required this.visual,
  });

  final String activity;
  final String apiLabel;
  final String subtitle;
  final String detail;
  final bool isDark;
  final _ActivityVisual visual;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : const Color(AppConfig.cPrimary);
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF5B6575);
    final label = activity.contains('_')
        ? activity.split('_').map(_titleCase).join(' ')
        : _titleCase(activity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FUSED',
          style: TextStyle(
            color: visual.color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: visual.color.withValues(alpha: isDark ? 0.24 : 0.14),
            border: Border.all(
              color: visual.color.withValues(alpha: 0.75),
              width: 3,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: Icon(
              visual.icon,
              key: ValueKey('${activity}_${visual.icon.codePoint}'),
              size: 56,
              color: visual.color,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: Text(
            label,
            key: ValueKey(label),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'API · $apiLabel',
          style: TextStyle(
            color: visual.color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.25),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.isDark,
    required this.sessionActive,
    required this.provisional,
  });

  final bool isDark;
  final bool sessionActive;
  final bool provisional;

  @override
  Widget build(BuildContext context) {
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF5B6575);
    final text = sessionActive
        ? 'In traffic / stopped car → stays driving; leave-car ~1–2s'
        : provisional
            ? 'Waiting on OS motion — GPS fills the gap instantly'
            : 'Walking / stationary follow native; GPS if OS is quiet';

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: muted, fontSize: 12, height: 1.35),
    );
  }
}

class _ResultColumn extends StatelessWidget {
  const _ResultColumn({
    required this.title,
    required this.subtitle,
    required this.activity,
    required this.detail,
    required this.confidence,
    required this.isDark,
    required this.visual,
    this.emphasize = false,
    this.showConfidenceBar = false,
  });

  final String title;
  final String subtitle;
  final String activity;
  final String detail;
  final int confidence;
  final bool isDark;
  final _ActivityVisual visual;
  final bool emphasize;
  final bool showConfidenceBar;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : const Color(AppConfig.cPrimary);
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF5B6575);
    final label = activity.contains('_')
        ? activity.split('_').map(_titleCase).join(' ')
        : _titleCase(activity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11, height: 1.25),
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: emphasize ? 88 : 80,
          height: emphasize ? 88 : 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: visual.color.withValues(alpha: isDark ? 0.22 : 0.12),
            border: Border.all(
              color: visual.color.withValues(alpha: emphasize ? 0.7 : 0.45),
              width: emphasize ? 2.5 : 2,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: Icon(
              visual.icon,
              key: ValueKey('${activity}_${visual.icon.codePoint}'),
              size: emphasize ? 38 : 34,
              color: visual.color,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: Text(
            label,
            key: ValueKey(label),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (showConfidenceBar) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (confidence.clamp(0, 100)) / 100.0,
                minHeight: 5,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE4E8EF),
                color: visual.color,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _ActivityVisual {
  const _ActivityVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

class _PermissionState extends StatelessWidget {
  const _PermissionState({
    required this.message,
    required this.showSettings,
    required this.onRetry,
    required this.onOpenSettings,
    required this.isDark,
  });

  final String message;
  final bool showSettings;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : const Color(AppConfig.cPrimary);
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF5B6575);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors_off, size: 56, color: muted),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(AppConfig.cPrimary),
              foregroundColor: Colors.white,
            ),
            child: const Text('Try again'),
          ),
          if (showSettings) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onOpenSettings,
              child: Text(
                'Open Settings',
                style: TextStyle(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
