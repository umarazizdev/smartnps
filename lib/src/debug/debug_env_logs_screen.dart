import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_theme.dart';
import 'kill_cycle_debug_service.dart';
import 'session_debug_logger.dart';

/// Timed diagnostic capture and kill-cycle timeline viewer.
class DebugEnvLogsScreen extends StatefulWidget {
  const DebugEnvLogsScreen({super.key});

  @override
  State<DebugEnvLogsScreen> createState() => _DebugEnvLogsScreenState();
}

class _DebugEnvLogsScreenState extends State<DebugEnvLogsScreen> {
  bool _killCycleBusy = false;
  bool _sessionBusy = false;
  KillCycleDebugSnapshot _killCycle = const KillCycleDebugSnapshot.empty();
  final Set<SessionDebugCategory> _selectedCategories = {
    SessionDebugCategory.apiErrors,
  };
  SessionDebugDuration _selectedDuration = SessionDebugDuration.fiveMinutes;
  Timer? _sessionTicker;

  SessionDebugLogger get _session => SessionDebugLogger.instance;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    unawaited(_refreshKillCycle());
    unawaited(_loadSession());
  }

  Future<void> _loadSession() async {
    await _session.ensureReady();
    if (!mounted) return;
    if (_session.categories.isNotEmpty) {
      setState(() {
        _selectedCategories
          ..clear()
          ..addAll(_session.categories);
      });
    }
    _syncSessionTicker();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    _syncSessionTicker();
  }

  void _syncSessionTicker() {
    if (_session.isRunning) {
      _sessionTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!_session.isRunning) {
          _sessionTicker?.cancel();
          _sessionTicker = null;
        }
      });
    } else {
      _sessionTicker?.cancel();
      _sessionTicker = null;
    }
  }

  Future<void> _refreshKillCycle() async {
    setState(() => _killCycleBusy = true);
    try {
      final snapshot = await KillCycleDebugService.loadSnapshot();
      if (!mounted) return;
      setState(() => _killCycle = snapshot);
    } finally {
      if (mounted) setState(() => _killCycleBusy = false);
    }
  }

  Future<void> _clearKillCycleLogs() async {
    setState(() => _killCycleBusy = true);
    try {
      await KillCycleDebugService.clearLogs();
      final snapshot = await KillCycleDebugService.loadSnapshot();
      if (!mounted) return;
      setState(() => _killCycle = snapshot);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kill-cycle logs cleared')),
      );
    } finally {
      if (mounted) setState(() => _killCycleBusy = false);
    }
  }

  Future<void> _copyKillCycle() async {
    await Clipboard.setData(ClipboardData(text: _killCycle.toCopyText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kill-cycle snapshot copied')),
    );
  }

  Future<void> _runSession() async {
    if (_sessionBusy || _selectedCategories.isEmpty) return;
    setState(() => _sessionBusy = true);
    try {
      await _session.start(
        categories: Set<SessionDebugCategory>.from(_selectedCategories),
        duration: _selectedDuration.duration,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Capture started for ${_selectedDuration.label}. '
            'Stops automatically when the timer ends.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sessionBusy = false);
    }
  }

  Future<void> _stopSession() async {
    if (_sessionBusy) return;
    setState(() => _sessionBusy = true);
    try {
      await _session.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture stopped')),
      );
    } finally {
      if (mounted) setState(() => _sessionBusy = false);
    }
  }

  Future<void> _clearSessionLogs() async {
    setState(() => _sessionBusy = true);
    try {
      await _session.clearLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session logs cleared')),
      );
    } finally {
      if (mounted) setState(() => _sessionBusy = false);
    }
  }

  Future<void> _copySessionLogs() async {
    await Clipboard.setData(ClipboardData(text: _session.toCopyText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session logs copied')),
    );
  }

  void _toggleCategory(SessionDebugCategory category) {
    if (_session.isRunning) return;
    setState(() {
      if (_selectedCategories.contains(category)) {
        if (_selectedCategories.length == 1) return;
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _sessionTicker?.cancel();
    super.dispose();
  }

  Widget _killCycleStatusLine(
    DebugEnvColors colors,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                color: colors.subtitle,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colors.title,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRemaining(Duration remaining) {
    final total = remaining.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _sessionDebugCard(DebugEnvColors colors) {
    final running = _session.isRunning;
    final remaining = _session.remaining;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capture session',
            style: TextStyle(
              color: colors.title,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Categories',
            style: TextStyle(
              color: colors.label,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in SessionDebugCategory.values)
                FilterChip(
                  label: Text(category.label),
                  selected: _selectedCategories.contains(category),
                  onSelected: running
                      ? null
                      : (_) => _toggleCategory(category),
                  selectedColor: const Color(
                    AppConfig.cPrimary,
                  ).withValues(alpha: 0.18),
                  checkmarkColor: const Color(AppConfig.cPrimary),
                  labelStyle: TextStyle(
                    color: colors.title,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  side: BorderSide(
                    color: _selectedCategories.contains(category)
                        ? const Color(AppConfig.cPrimary)
                        : colors.cardBorder,
                  ),
                  backgroundColor: colors.background,
                  showCheckmark: true,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Duration',
            style: TextStyle(
              color: colors.label,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final duration in SessionDebugDuration.values)
                ChoiceChip(
                  label: Text(duration.label),
                  selected: _selectedDuration == duration,
                  onSelected: running
                      ? null
                      : (_) => setState(() => _selectedDuration = duration),
                  selectedColor: const Color(
                    AppConfig.cPrimary,
                  ).withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    color: colors.title,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  side: BorderSide(
                    color: _selectedDuration == duration
                        ? const Color(AppConfig.cPrimary)
                        : colors.cardBorder,
                  ),
                  backgroundColor: colors.background,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: running ? colors.warningBg : colors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: running ? colors.warningBorder : colors.cardBorder,
              ),
            ),
            child: Text(
              running
                  ? 'Capture active · ${_formatRemaining(remaining)} remaining · '
                      '${_session.categories.map((c) => c.label).join(', ')}'
                  : 'Capture inactive · press Run to begin',
              style: TextStyle(
                color: running ? colors.warningFg : colors.subtitle,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: _sessionBusy || _selectedCategories.isEmpty
                        ? null
                        : (running ? _stopSession : _runSession),
                    style: FilledButton.styleFrom(
                      backgroundColor: running
                          ? colors.error
                          : const Color(AppConfig.cPrimary),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: _sessionBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(running ? 'Stop' : 'Run'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _sessionBusy ? null : _copySessionLogs,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.title,
                      side: BorderSide(color: colors.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Copy'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _sessionBusy ? null : _clearSessionLogs,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Session log (${_session.logs.length})',
            style: TextStyle(
              color: colors.title,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.cardBorder),
            ),
            child: _session.logs.isEmpty
                ? Text(
                    'No entries yet',
                    style: TextStyle(
                      color: colors.subtitle,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      _session.logs.join('\n'),
                      style: TextStyle(
                        color: colors.title,
                        fontSize: 11.5,
                        height: 1.35,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = DebugEnvColors.of(isDark);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(AppConfig.cPrimary),
        foregroundColor: Colors.white,
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Diagnostic logging',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          _sessionDebugCard(colors),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kill-cycle timeline',
                  style: TextStyle(
                    color: colors.title,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _killCycleStatusLine(colors, 'onDuty', '${_killCycle.onDuty}'),
                _killCycleStatusLine(
                  colors,
                  'unpaidBreak',
                  '${_killCycle.unpaidBreak}',
                ),
                _killCycleStatusLine(
                  colors,
                  'slcArmed',
                  '${_killCycle.slcArmed}',
                ),
                _killCycleStatusLine(
                  colors,
                  'hasAccessToken',
                  '${_killCycle.hasAccessToken}',
                ),
                _killCycleStatusLine(
                  colors,
                  'notificationAuth',
                  _killCycle.notificationAuth.isEmpty
                      ? '—'
                      : _killCycle.notificationAuth,
                ),
                _killCycleStatusLine(
                  colors,
                  'killed_at',
                  _killCycle.killedAt.isEmpty ? '—' : _killCycle.killedAt,
                ),
                _killCycleStatusLine(
                  colors,
                  'opened_at',
                  _killCycle.openedAt.isEmpty ? '—' : _killCycle.openedAt,
                ),
                _killCycleStatusLine(
                  colors,
                  'background_at',
                  _killCycle.backgroundAt.isEmpty
                      ? '—'
                      : _killCycle.backgroundAt,
                ),
                _killCycleStatusLine(
                  colors,
                  'wake_service',
                  _killCycle.wakeService.isEmpty
                      ? '—'
                      : _killCycle.wakeService,
                ),
                _killCycleStatusLine(
                  colors,
                  'wake_at',
                  _killCycle.wakeAt.isEmpty ? '—' : _killCycle.wakeAt,
                ),
                _killCycleStatusLine(
                  colors,
                  'wake_detail',
                  _killCycle.wakeDetail.isEmpty ? '—' : _killCycle.wakeDetail,
                ),
                _killCycleStatusLine(
                  colors,
                  'killed_uploaded',
                  '${_killCycle.killedUploaded}',
                ),
                const SizedBox(height: 12),
                Text(
                  'Kill-cycle log (${_killCycle.logs.length})',
                  style: TextStyle(
                    color: colors.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: _killCycle.logs.isEmpty
                      ? Text(
                          'No entries yet',
                          style: TextStyle(
                            color: colors.subtitle,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        )
                      : SingleChildScrollView(
                          child: SelectableText(
                            _killCycle.logs.join('\n'),
                            style: TextStyle(
                              color: colors.title,
                              fontSize: 11.5,
                              height: 1.35,
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed:
                              _killCycleBusy ? null : _refreshKillCycle,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(AppConfig.cPrimary),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: _killCycleBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Refresh'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _killCycleBusy ? null : _copyKillCycle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.title,
                            side: BorderSide(color: colors.cardBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Copy'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed:
                              _killCycleBusy ? null : _clearKillCycleLogs,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.error,
                            side: BorderSide(color: colors.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Clear'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
