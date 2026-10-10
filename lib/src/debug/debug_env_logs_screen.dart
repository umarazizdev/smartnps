import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_logs_controller.dart';
import 'debug_env_theme.dart';
import 'session_debug_logger.dart';

class DebugEnvLogsScreen extends StatelessWidget {
  const DebugEnvLogsScreen({super.key});

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
      body: GetX<DebugEnvLogsController>(
        init: DebugEnvLogsController(),
        global: false,
        builder: (controller) {
          controller.sessionRevision.value;
          controller.selectedCategories.length;
          controller.selectedApiSuccessTargets
              .map((target) => target.id)
              .join(',');
          controller.selectedDuration.value;
          controller.sessionBusy.value;
          controller.killCycleBusy.value;
          controller.killCycle.value;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              _sessionDebugCard(colors, controller),
              if (controller.showKillCycleTimeline) ...[
                const SizedBox(height: 20),
                _killCycleTimelineCard(colors, controller),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _apiSuccessTargetsPicker({
    required DebugEnvColors colors,
    required Set<SessionDebugApiSuccessTarget> selected,
    required bool enabled,
    required ValueChanged<SessionDebugApiSuccessTarget> onToggle,
  }) {
    return _ApiSuccessTargetsPicker(
      key: const ValueKey('api_success_targets_picker'),
      colors: colors,
      selected: selected,
      enabled: enabled,
      onToggle: onToggle,
    );
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

  Widget _sessionDebugCard(
    DebugEnvColors colors,
    DebugEnvLogsController controller,
  ) {
    final session = controller.session;
    final running = session.isRunning;
    final remaining = session.remaining;
    final selectedCategories = controller.selectedCategories;
    final selectedApiSuccessTargets = controller.selectedApiSuccessTargets;
    final selectedDuration = controller.selectedDuration.value;
    final sessionBusy = controller.sessionBusy.value;
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
                  selected: selectedCategories.contains(category),
                  onSelected: running
                      ? null
                      : (_) => controller.toggleCategory(category),
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
                    color: selectedCategories.contains(category)
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
          if (controller.showApiSuccessTarget) ...[
            const SizedBox(height: 14),
            Text(
              'API success targets',
              style: TextStyle(
                color: colors.label,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _apiSuccessTargetsPicker(
              colors: colors,
              selected: selectedApiSuccessTargets,
              enabled: !running,
              onToggle: controller.toggleApiSuccessTarget,
            ),
          ],
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
                  selected: selectedDuration == duration,
                  onSelected: running
                      ? null
                      : (_) => controller.selectDuration(duration),
                  selectedColor: const Color(
                    AppConfig.cPrimary,
                  ).withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    color: colors.title,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  side: BorderSide(
                    color: selectedDuration == duration
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
                  ? 'Capture active · ${controller.formatRemaining(remaining)} remaining · '
                      '${session.categories.map((cat) => cat.label).join(', ')}'
                      '${session.categories.contains(SessionDebugCategory.apiSuccess) ? ' · success=${session.apiSuccessTargetsLabel}' : ''}'
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
                    onPressed: sessionBusy || selectedCategories.isEmpty
                        ? null
                        : (running
                            ? controller.stopSession
                            : controller.runSession),
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
                    child: sessionBusy
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
                    onPressed:
                        sessionBusy ? null : controller.copySessionLogs,
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
                        sessionBusy ? null : controller.clearSessionLogs,
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
          const SizedBox(height: 14),
          _sessionLogSections(colors, session: session, running: running),
        ],
      ),
    );
  }

  Widget _sessionLogSections(
    DebugEnvColors colors, {
    required SessionDebugLogger session,
    required bool running,
  }) {
    final entries = session.logs
        .map(_SessionLogEntry.parse)
        .toList(growable: false);
    final issues = entries.where((e) => e.isIssue).toList(growable: false);
    final successes =
        entries.where((e) => e.isSuccess).toList(growable: false);
    final other = entries
        .where((e) => !e.isIssue && !e.isSuccess)
        .toList(growable: false);

    if (!running && entries.isEmpty) {
      return Text(
        'No entries yet',
        style: TextStyle(
          color: colors.subtitle,
          fontSize: 12,
          height: 1.35,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logSection(
          colors,
          title: 'Issues',
          count: issues.length,
          emptyLabel: running ? 'None yet' : 'None',
          accent: colors.error,
          entries: issues.reversed,
        ),
        const SizedBox(height: 14),
        _logSection(
          colors,
          title: 'Success',
          count: successes.length,
          emptyLabel: running ? 'None yet' : 'None',
          accent: const Color(0xFF059669),
          entries: successes.reversed,
        ),
        if (other.isNotEmpty) ...[
          const SizedBox(height: 14),
          _logSection(
            colors,
            title: 'Activity',
            count: other.length,
            emptyLabel: 'None',
            accent: colors.subtitle,
            entries: other.reversed,
          ),
        ],
      ],
    );
  }

  Widget _logSection(
    DebugEnvColors colors, {
    required String title,
    required int count,
    required String emptyLabel,
    required Color accent,
    required Iterable<_SessionLogEntry> entries,
  }) {
    final items = entries.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: colors.title,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            _softTag(
              '$count',
              foreground: accent,
              background: accent.withValues(alpha: 0.1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 360),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.cardBorder),
          ),
          child: items.isEmpty
              ? Text(
                  emptyLabel,
                  style: TextStyle(
                    color: colors.subtitle,
                    fontSize: 12,
                    height: 1.35,
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in items)
                        _sessionLogLine(colors, entry),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _softTag(
    String label, {
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _sessionLogLine(DebugEnvColors colors, _SessionLogEntry entry) {
    if (!entry.isIssue && !entry.isSuccess) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          entry.detailText.isEmpty ? entry.message : entry.detailText,
          style: TextStyle(
            color: colors.subtitle,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    const success = Color(0xFF059669);
    final Color tagFg;
    final Color tagBg;
    switch (entry.severity) {
      case _SessionLogSeverity.error:
        tagFg = colors.error;
        tagBg = colors.error.withValues(alpha: 0.1);
      case _SessionLogSeverity.warning:
        tagFg = colors.warningFg;
        tagBg = colors.warningBg;
      case _SessionLogSeverity.success:
        tagFg = success;
        tagBg = success.withValues(alpha: 0.1);
      case _SessionLogSeverity.info:
        tagFg = colors.subtitle;
        tagBg = colors.cardBorder.withValues(alpha: 0.35);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _softTag(
              entry.tagLabel,
              foreground: tagFg,
              background: tagBg,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              entry.detailText,
              style: TextStyle(
                color: colors.title,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _killCycleTimelineCard(
    DebugEnvColors colors,
    DebugEnvLogsController controller,
  ) {
    final killCycle = controller.killCycle.value;
    final killCycleBusy = controller.killCycleBusy.value;
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
            'Kill-cycle timeline',
            style: TextStyle(
              color: colors.title,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Shown because Kill cycle is selected. Use this to review '
            'what happened when the app was closed or restarted.',
            style: TextStyle(
              color: colors.subtitle,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _killCycleStatusLine(colors, 'onDuty', '${killCycle.onDuty}'),
          _killCycleStatusLine(
            colors,
            'unpaidBreak',
            '${killCycle.unpaidBreak}',
          ),
          _killCycleStatusLine(
            colors,
            'slcArmed',
            '${killCycle.slcArmed}',
          ),
          _killCycleStatusLine(
            colors,
            'hasAccessToken',
            '${killCycle.hasAccessToken}',
          ),
          _killCycleStatusLine(
            colors,
            'notificationAuth',
            killCycle.notificationAuth.isEmpty
                ? '—'
                : killCycle.notificationAuth,
          ),
          _killCycleStatusLine(
            colors,
            'killed_at',
            killCycle.killedAt.isEmpty ? '—' : killCycle.killedAt,
          ),
          _killCycleStatusLine(
            colors,
            'opened_at',
            killCycle.openedAt.isEmpty ? '—' : killCycle.openedAt,
          ),
          _killCycleStatusLine(
            colors,
            'background_at',
            killCycle.backgroundAt.isEmpty ? '—' : killCycle.backgroundAt,
          ),
          _killCycleStatusLine(
            colors,
            'wake_service',
            killCycle.wakeService.isEmpty ? '—' : killCycle.wakeService,
          ),
          _killCycleStatusLine(
            colors,
            'wake_at',
            killCycle.wakeAt.isEmpty ? '—' : killCycle.wakeAt,
          ),
          _killCycleStatusLine(
            colors,
            'wake_detail',
            killCycle.wakeDetail.isEmpty ? '—' : killCycle.wakeDetail,
          ),
          _killCycleStatusLine(
            colors,
            'killed_uploaded',
            '${killCycle.killedUploaded}',
          ),
          const SizedBox(height: 12),
          Text(
            'Kill-cycle log (${killCycle.logs.length})',
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
            child: killCycle.logs.isEmpty
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
                      killCycle.logs.join('\n'),
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
                    onPressed: killCycleBusy
                        ? null
                        : controller.refreshKillCycle,
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
                    child: killCycleBusy
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
                    onPressed:
                        killCycleBusy ? null : controller.copyKillCycle,
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
                    onPressed: killCycleBusy
                        ? null
                        : controller.clearKillCycleLogs,
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
    );
  }
}

enum _SessionLogSeverity { info, success, warning, error }

class _SessionLogEntry {
  const _SessionLogEntry({
    required this.raw,
    required this.category,
    required this.message,
    required this.severity,
    required this.tagLabel,
    required this.detailText,
  });

  final String raw;
  final String category;
  final String message;
  final _SessionLogSeverity severity;
  final String tagLabel;
  final String detailText;

  bool get isIssue =>
      severity == _SessionLogSeverity.error ||
      severity == _SessionLogSeverity.warning;

  bool get isSuccess => severity == _SessionLogSeverity.success;

  static final RegExp _linePattern = RegExp(
    r'^(?<stamp>\S+)\s+\[(?<category>[^\]]+)\]\s+(?<message>.*)$',
  );

  static _SessionLogEntry parse(String raw) {
    final match = _linePattern.firstMatch(raw.trim());
    final category = (match?.namedGroup('category') ?? 'session').toLowerCase();
    final message = match?.namedGroup('message') ?? raw.trim();
    final severity = _classifySeverity(category, message);
    return _SessionLogEntry(
      raw: raw,
      category: category,
      message: message,
      severity: severity,
      tagLabel: _tagLabel(category, message, severity),
      detailText: _detailText(category, message, severity),
    );
  }

  static _SessionLogSeverity _classifySeverity(String category, String message) {
    final lower = message.toLowerCase();
    final status = _statusCode(lower);

    // Session lifecycle lines are not issues.
    if (category == 'session') return _SessionLogSeverity.info;

    // API success category is only written for successful responses.
    if (category == 'api_ok') return _SessionLogSeverity.success;

    // API category is only written for failed/error responses.
    if (category == 'api') return _SessionLogSeverity.error;

    if (category == 'uploads') {
      if (_containsAny(lower, const [
        'fail',
        'error',
        'denied',
        'reject',
        'timeout',
        'unable',
      ])) {
        return _SessionLogSeverity.error;
      }
    }

    if (_containsAny(lower, const [
      'crash',
      'exception',
      'fatal',
      'fail',
      'error',
      'denied',
      'timeout',
      'unable',
      'missing',
      'invalid',
      'reject',
      'unauthorized',
      'forbidden',
      'not granted',
      'cancelled',
      'canceled',
    ])) {
      if (_containsAny(lower, const [
        'crash',
        'exception',
        'fatal',
        'fail',
        'error',
        'denied',
        'unauthorized',
        'forbidden',
      ])) {
        return _SessionLogSeverity.error;
      }
      return _SessionLogSeverity.warning;
    }

    if (status != null && status >= 400) return _SessionLogSeverity.error;

    return _SessionLogSeverity.info;
  }

  static String _tagLabel(
    String category,
    String message,
    _SessionLogSeverity severity,
  ) {
    final status = _statusCode(message.toLowerCase());
    switch (severity) {
      case _SessionLogSeverity.success:
        return status?.toString() ?? 'OK';
      case _SessionLogSeverity.error:
        if (status != null) return '$status';
        return 'Issue';
      case _SessionLogSeverity.warning:
        return 'Warn';
      case _SessionLogSeverity.info:
        return 'Info';
    }
  }

  static String _detailText(
    String category,
    String message,
    _SessionLogSeverity severity,
  ) {
    final lower = message.toLowerCase();
    final api = _apiTarget(message);
    final data = _relatedData(message);

    if (severity == _SessionLogSeverity.info) {
      if (message.toLowerCase().startsWith('started')) return 'Capture started';
      if (message.toLowerCase().contains('auto-stopped')) {
        return 'Capture auto-stopped';
      }
      if (message.toLowerCase().contains('stopped')) return 'Capture stopped';
      return message;
    }

    if (category == 'api_ok') {
      return api ?? data ?? 'Request completed';
    }

    if (category == 'api') {
      final String issue;
      if (_containsAny(lower, const ['timeout', 'timed out'])) {
        issue = 'Timed out';
      } else if (_containsAny(lower, const ['connection', 'socket', 'network'])) {
        issue = 'Connection failed';
      } else if (_statusCode(lower) == 401 || _statusCode(lower) == 403) {
        issue = 'Sign-in failed';
      } else if (_statusCode(lower) == 404) {
        issue = 'Not found';
      } else if ((_statusCode(lower) ?? 0) >= 500) {
        issue = 'Server error';
      } else {
        issue = 'Request failed';
      }
      return _withRelated(issue, api ?? data);
    }

    if (category == 'uploads') {
      final issue = _containsAny(lower, const ['timeout', 'timed out'])
          ? 'Upload timed out'
          : 'Upload failed';
      return _withRelated(issue, api ?? data);
    }

    if (category == 'duty') {
      final String issue;
      if (_containsAny(lower, const ['location', 'gps'])) {
        issue = 'Location update failed';
      } else if (_containsAny(lower, const ['heartbeat', 'ping'])) {
        issue = 'Duty sync failed';
      } else {
        issue = 'Duty tracking issue';
      }
      return _withRelated(issue, data);
    }

    if (category == 'permissions') {
      final permission = _permissionTarget(lower);
      final issue = _containsAny(lower, const ['denied', 'not granted'])
          ? 'Permission denied'
          : 'Permission issue';
      return _withRelated(issue, permission ?? data);
    }

    if (category == 'kill') {
      final issue = _containsAny(lower, const ['fail', 'error', 'unable'])
          ? 'Restart recovery issue'
          : 'App closed unexpectedly';
      return _withRelated(issue, data);
    }

    if (_containsAny(lower, const ['timeout', 'timed out'])) {
      return _withRelated('Timed out', api ?? data);
    }
    return _withRelated('Needs attention', api ?? data);
  }

  static String _withRelated(String issue, String? related) {
    final value = related?.trim();
    if (value == null || value.isEmpty) return issue;
    return '$issue · $value';
  }

  static String? _apiTarget(String message) {
    final match = RegExp(
      r'\b(GET|POST|PUT|PATCH|DELETE)\s+(\S+)',
      caseSensitive: false,
    ).firstMatch(message);
    if (match != null) {
      final method = match.group(1)!.toUpperCase();
      final path = _shortPath(match.group(2)!);
      return '$method $path';
    }

    final pathMatch = RegExp(
      r'(/(?:api/)?[A-Za-z0-9][A-Za-z0-9_\-./]*)',
    ).firstMatch(message);
    if (pathMatch != null) {
      return _shortPath(pathMatch.group(1)!);
    }
    return null;
  }

  static String _shortPath(String rawPath) {
    var path = rawPath.split('?').first.trim();
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    if (path.length <= 40) return path;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final tail = parts.sublist(parts.length - 2).join('/');
      return '…/$tail';
    }
    return '${path.substring(0, 39)}…';
  }

  static String? _relatedData(String message) {
    final keyed = RegExp(
      r'\b(visitId|clientDraftId|draftId|patrolId|siteId|employeeId|'
      r'message|errors|source|acc)\s*[:=]\s*([^\s,;]+)',
      caseSensitive: false,
    ).allMatches(message);
    for (final match in keyed) {
      final key = match.group(1)!;
      final value = match.group(2)!.trim();
      if (value.isEmpty || value == 'null' || value == '[]') continue;
      final shortKey = switch (key.toLowerCase()) {
        'visitid' => 'visit',
        'clientdraftid' || 'draftid' => 'draft',
        'patrolid' => 'patrol',
        'siteid' => 'site',
        'employeeid' => 'employee',
        'message' => 'detail',
        'errors' => 'errors',
        'source' => 'source',
        'acc' => 'accuracy',
        _ => key,
      };
      var shortValue = value;
      if (shortValue.length > 28) {
        shortValue = '${shortValue.substring(0, 27)}…';
      }
      if (shortKey == 'detail' || shortKey == 'errors') {
        return shortValue;
      }
      return '$shortKey $shortValue';
    }
    return null;
  }

  static String? _permissionTarget(String lower) {
    if (lower.contains('location')) return 'location';
    if (lower.contains('notification')) return 'notifications';
    if (lower.contains('camera')) return 'camera';
    if (lower.contains('microphone') || lower.contains('mic')) {
      return 'microphone';
    }
    if (lower.contains('storage') || lower.contains('photo')) {
      return 'photos/storage';
    }
    return null;
  }

  static int? _statusCode(String lower) {
    final match = RegExp(r'status[=\s:]*([0-9]{3})').firstMatch(lower);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }
}

class _ApiSuccessTargetsPicker extends StatefulWidget {
  const _ApiSuccessTargetsPicker({
    super.key,
    required this.colors,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final DebugEnvColors colors;
  final Set<SessionDebugApiSuccessTarget> selected;
  final bool enabled;
  final ValueChanged<SessionDebugApiSuccessTarget> onToggle;

  @override
  State<_ApiSuccessTargetsPicker> createState() =>
      _ApiSuccessTargetsPickerState();
}

class _ApiSuccessTargetsPickerState extends State<_ApiSuccessTargetsPicker> {
  bool _expanded = false;

  List<SessionDebugApiSuccessTarget> get _selectedOrdered {
    final selected = widget.selected;
    return SessionDebugApiSuccessTarget.values
        .where(selected.contains)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final enabled = widget.enabled;
    final selectedTargets = _selectedOrdered;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: enabled
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: selectedTargets.isEmpty
                        ? Text(
                            'Tap to choose APIs',
                            style: TextStyle(
                              color: colors.subtitle,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          )
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final target in selectedTargets)
                                InputChip(
                                  label: Text(target.label),
                                  labelStyle: TextStyle(
                                    color: enabled
                                        ? colors.title
                                        : colors.subtitle,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  backgroundColor: const Color(
                                    AppConfig.cPrimary,
                                  ).withValues(alpha: 0.10),
                                  side: BorderSide(
                                    color: const Color(
                                      AppConfig.cPrimary,
                                    ).withValues(alpha: 0.35),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  deleteIcon: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: enabled
                                        ? colors.subtitle
                                        : colors.subtitle.withValues(
                                            alpha: 0.5,
                                          ),
                                  ),
                                  onDeleted: enabled &&
                                          target !=
                                              SessionDebugApiSuccessTarget.all
                                      ? () => widget.onToggle(target)
                                      : null,
                                  onPressed: enabled
                                      ? () => setState(
                                            () => _expanded = !_expanded,
                                          )
                                      : null,
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: colors.subtitle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: colors.cardBorder),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                children: [
                  for (final target in SessionDebugApiSuccessTarget.values)
                    CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(AppConfig.cPrimary),
                      value: widget.selected.contains(target),
                      onChanged:
                          enabled ? (_) => widget.onToggle(target) : null,
                      title: Text(
                        target.label,
                        style: TextStyle(
                          color: colors.title,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: target.pathSuffix.isEmpty
                          ? null
                          : Text(
                              target.pathSuffix,
                              style: TextStyle(
                                color: colors.subtitle,
                                fontSize: 11.5,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
