import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_api_responses_controller.dart';
import 'debug_env_theme.dart';
import 'session_debug_logger.dart';

class DebugEnvApiResponsesScreen extends StatelessWidget {
  const DebugEnvApiResponsesScreen({super.key});

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
          'API response logging',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: GetX<DebugEnvApiResponsesController>(
        init: DebugEnvApiResponsesController(),
        global: false,
        builder: (controller) {
          controller.sessionRevision.value;
          controller.selectedTargets.map((t) => t.id).join(',');
          controller.selectedDuration.value;
          controller.sessionBusy.value;
          controller.detailExpanded.value;
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottomInset),
            children: [
              _captureCard(colors, controller),
            ],
          );
        },
      ),
    );
  }

  Widget _captureCard(
    DebugEnvColors colors,
    DebugEnvApiResponsesController controller,
  ) {
    final logger = controller.logger;
    final running = logger.isRunning;
    final remaining = logger.remaining;
    final selectedTargets = controller.selectedTargets;
    final selectedDuration = controller.selectedDuration.value;
    final sessionBusy = controller.sessionBusy.value;
    final entries = logger.entries;

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
          const SizedBox(height: 6),
          Text(
            'Records full response bodies for the APIs you select. '
            'Use this to inspect 2xx payloads the app rejects.',
            style: TextStyle(
              color: colors.subtitle,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'APIs to capture',
            style: TextStyle(
              color: colors.label,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _ApiTargetsPicker(
            colors: colors,
            selected: selectedTargets,
            enabled: !running,
            onToggle: controller.toggleTarget,
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
                      '${logger.targetsLabel}'
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
                    onPressed: sessionBusy || selectedTargets.isEmpty
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
                    onPressed: sessionBusy ? null : controller.copyEntries,
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
                    onPressed: sessionBusy ? null : controller.clearEntries,
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
          _responsesPanel(
            colors,
            controller: controller,
            entries: entries,
            running: running,
          ),
        ],
      ),
    );
  }

  Widget _responsesPanel(
    DebugEnvColors colors, {
    required DebugEnvApiResponsesController controller,
    required List<String> entries,
    required bool running,
  }) {
    final expanded = controller.detailExpanded.value;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: controller.toggleDetailExpanded,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: colors.subtitle,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Responses (${entries.length})',
                      style: TextStyle(
                        color: colors.title,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        entries.isEmpty ? null : controller.copyEntries,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.title,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Copy all'),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: colors.cardBorder),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  running
                      ? 'Waiting for matching API responses…'
                      : 'No responses yet',
                  style: TextStyle(
                    color: colors.subtitle,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: colors.cardBorder),
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[entries.length - 1 - index];
                    return _responseEntry(
                      colors,
                      entry: entry,
                      onCopy: () => controller.copyEntry(entry),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _responseEntry(
    DebugEnvColors colors, {
    required String entry,
    required VoidCallback onCopy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onCopy,
            style: TextButton.styleFrom(
              foregroundColor: colors.title,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Copy'),
          ),
        ),
        SelectableText(
          entry,
          style: TextStyle(
            color: colors.title,
            fontSize: 11.5,
            height: 1.35,
            fontFamily: 'Courier',
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ApiTargetsPicker extends StatefulWidget {
  const _ApiTargetsPicker({
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
  State<_ApiTargetsPicker> createState() => _ApiTargetsPickerState();
}

class _ApiTargetsPickerState extends State<_ApiTargetsPicker> {
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
