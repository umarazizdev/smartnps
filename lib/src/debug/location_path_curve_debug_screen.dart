import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'location_path_curve_debug_log.dart';

class LocationPathCurveDebugScreen extends StatefulWidget {
  const LocationPathCurveDebugScreen({super.key});

  @override
  State<LocationPathCurveDebugScreen> createState() =>
      _LocationPathCurveDebugScreenState();
}

class _LocationPathCurveDebugScreenState
    extends State<LocationPathCurveDebugScreen> {
  Timer? _refreshTimer;
  List<LocationPathCurveDebugEvent> _events = const [];
  LocationPathCurveDebugSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final events = await LocationPathCurveDebugLog.instance.readRecent();
    final summary = await LocationPathCurveDebugLog.instance.summarize();
    if (!mounted) return;
    setState(() {
      _events = events;
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _copyReport() async {
    final text = await LocationPathCurveDebugLog.instance.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Curve debug report copied')),
    );
  }

  Future<void> _clear() async {
    await LocationPathCurveDebugLog.instance.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final bg = isDark ? const Color(0xFF0F1724) : const Color(0xFFF4F6F9);
    final card = isDark ? const Color(AppConfig.cDarkCardColor) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF142033);
    final muted = isDark ? Colors.white70 : const Color(0xFF5B677A);
    final summary = _summary;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'GPS Curve Debug',
                      style: TextStyle(
                        color: text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy report',
                    onPressed: _copyReport,
                    icon: Icon(Icons.copy_all_outlined, color: text),
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: _clear,
                    icon: Icon(Icons.delete_outline, color: text),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Works in release. Drive a curve, then check skips / gaps. '
                'Copy report and share for analysis.',
                style: TextStyle(color: muted, fontSize: 13, height: 1.35),
              ),
            ),
            const SizedBox(height: 12),
            if (summary != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last 10 minutes',
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _chip('Queued', '${summary.queued}', text, muted),
                            _chip('Skipped', '${summary.skipped}', text, muted),
                            _chip(
                              'Ping-only',
                              '${summary.pingOnly}',
                              text,
                              muted,
                            ),
                            _chip(
                              'Corners',
                              '${summary.cornerQueued}',
                              text,
                              muted,
                            ),
                            _chip(
                              'Max gap',
                              '${summary.maxQueuedGapM.toStringAsFixed(0)}m',
                              text,
                              muted,
                            ),
                            _chip(
                              'Gaps ≥50m',
                              '${summary.gapsOver50m}',
                              text,
                              muted,
                            ),
                            _chip(
                              'Avg acc',
                              '${summary.avgQueuedAccuracyM.toStringAsFixed(0)}m',
                              text,
                              muted,
                            ),
                          ],
                        ),
                        if (summary.skipReasons.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Skip reasons: ${summary.skipReasons.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _events.isEmpty
                      ? Center(
                          child: Text(
                            'No events yet.\nClock in and drive a curve.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, height: 1.4),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          itemCount: _events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final event = _events[index];
                            final color = switch (event.outcome) {
                              'queued' => const Color(0xFF1B7F4A),
                              'ping_only' => const Color(0xFFB8860B),
                              _ => const Color(0xFFB33A3A),
                            };
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.summaryLine,
                                      style: TextStyle(
                                        color: text,
                                        fontSize: 12.5,
                                        height: 1.35,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'lat=${event.lat.toStringAsFixed(5)} '
                                      'lng=${event.lng.toStringAsFixed(5)} '
                                      'trigger=${event.keepTrigger.isEmpty ? '-' : event.keepTrigger}'
                                      '${event.headingDeltaDeg == null ? '' : ' Δh=${event.headingDeltaDeg!.toStringAsFixed(0)}°'}',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color text, Color muted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
