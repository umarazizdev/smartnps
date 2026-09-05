import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_navigator.dart';
import '../../widgets/dialogs/glass_action_dialog.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';
import 'visit_media_notes_controller.dart';
import 'voice/voice_waveform_painter.dart';

export 'visit_media_notes_controller.dart'
    show VisitMediaNoteKind, VisitBatchNoteScope;

Future<void> openVisitMediaNotesSheet({
  required BuildContext context,
  required VisitMediaItem item,
  VisitMediaNoteKind kind = VisitMediaNoteKind.text,
}) async {
  final alert = item.attentionNeeded;
  await _openNotesDialog(
    context: context,
    kind: kind,
    tag: 'notes-${item.path}',
    item: item,
    batchMode: false,
    hasTextNote: item.hasTextNote,
    hasVoiceNote: item.hasVoiceNote,
    title: kind == VisitMediaNoteKind.text
        ? (alert
              ? 'Attention Text Note'
              : (item.isPhoto ? 'Photo Text Note' : 'Video Text Note'))
        : (alert
              ? 'Attention Voice Note'
              : (item.isPhoto ? 'Photo Voice Note' : 'Video Voice Note')),
    subtitle: kind == VisitMediaNoteKind.text
        ? (alert
              ? 'Add a text note for this attention-needed ${item.isPhoto ? 'photo' : 'video'}.'
              : 'Add a text note for this ${item.isPhoto ? 'photo' : 'video'}.')
        : (alert
              ? 'Record a voice note for this attention-needed ${item.isPhoto ? 'photo' : 'video'}.'
              : 'Record a voice note for this ${item.isPhoto ? 'photo' : 'video'}.'),
    textHint: alert
        ? 'Describe what needs attention...'
        : 'Type your note for this ${item.isPhoto ? 'photo' : 'video'}...',
    forceAlertAccent: alert,
  );
}

Future<void> openVisitBatchNotesSheet({
  required BuildContext context,
  VisitMediaNoteKind kind = VisitMediaNoteKind.text,
  VisitBatchNoteScope scope = VisitBatchNoteScope.attentionNeeded,
}) async {
  final flow = Get.isRegistered<VisitVideoFlowController>()
      ? Get.find<VisitVideoFlowController>()
      : null;
  final isGeneral = scope == VisitBatchNoteScope.generalNote;
  final note = isGeneral
      ? (flow?.generalNote.value ?? const VisitBatchNote())
      : (flow?.batchNote.value ?? const VisitBatchNote());
  final label = isGeneral ? 'General' : 'Attention Needed';
  await _openNotesDialog(
    context: context,
    kind: kind,
    tag: isGeneral ? 'notes-general' : 'notes-batch',
    item: null,
    batchMode: true,
    batchScope: scope,
    hasTextNote: note.hasTextNote,
    hasVoiceNote: note.hasVoiceNote,
    title: kind == VisitMediaNoteKind.text
        ? '$label Text Note'
        : '$label Voice Note',
    subtitle: kind == VisitMediaNoteKind.text
        ? 'Add a ${isGeneral ? 'general' : 'attention needed'} text note.'
        : 'Record a ${isGeneral ? 'general' : 'attention needed'} voice note.',
    textHint: isGeneral
        ? 'Type your general note...'
        : 'Type your attention needed note...',
  );
}

Future<void> _openNotesDialog({
  required BuildContext context,
  required VisitMediaNoteKind kind,
  required String tag,
  required VisitMediaItem? item,
  required bool batchMode,
  VisitBatchNoteScope batchScope = VisitBatchNoteScope.attentionNeeded,
  required bool hasTextNote,
  required bool hasVoiceNote,
  required String title,
  required String subtitle,
  required String textHint,
  bool forceAlertAccent = false,
}) async {
  if (Get.isRegistered<VisitMediaNotesController>(tag: tag)) {
    Get.delete<VisitMediaNotesController>(tag: tag, force: true);
  }

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final useAlertAccent = forceAlertAccent ||
      (batchMode && batchScope == VisitBatchNoteScope.attentionNeeded);
  final accentColor = useAlertAccent
      ? const Color(0xFFDC2626)
      : (isDark ? const Color(0xFF93C5FD) : const Color(0xFF4F46E5));
  var didSave = false;

  BuildContext safeDialogContext() {
    final navContext = AppNavigator.key.currentContext;
    if (navContext != null && navContext.mounted) return navContext;
    return context;
  }

  Future<bool> confirmAction({
    required String title,
    required String message,
    String primaryLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final ctx = safeDialogContext();
    if (!ctx.mounted) return false;

    final result = await GlassActionDialog.show(
      context: ctx,
      icon: destructive
          ? Icons.warning_amber_rounded
          : Icons.help_outline_rounded,
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      secondaryLabel: 'Cancel',
      iconColor: destructive ? const Color(0xFFE53935) : accentColor,
      variant: destructive
          ? GlassActionDialogVariant.error
          : GlassActionDialogVariant.normal,
      barrierDismissible: true,
      useRootNavigator: true,
    );
    return result == true;
  }

  var replacingOther = false;
  if (kind == VisitMediaNoteKind.text && hasVoiceNote) {
    final ok = await confirmAction(
      title: 'Replace voice note?',
      message:
          'Switching to a text note will remove the current voice note. Continue?',
      primaryLabel: 'Replace',
      destructive: true,
    );
    if (!ok) return;
    replacingOther = true;
  } else if (kind == VisitMediaNoteKind.voice && hasTextNote) {
    final ok = await confirmAction(
      title: 'Replace text note?',
      message:
          'Recording a voice note will remove the current text note. Continue?',
      primaryLabel: 'Replace',
      destructive: true,
    );
    if (!ok) return;
    replacingOther = true;
  }

  final controller = Get.put(
    VisitMediaNotesController(
      mediaPath: item?.path ?? '',
      kind: kind,
      replacingOther: replacingOther,
      batchMode: batchMode,
      batchScope: batchScope,
    ),
    tag: tag,
  );
  controller.confirm = confirmAction;

  try {
    final dialogContext = safeDialogContext();
    if (!dialogContext.mounted) return;

    final isText = kind == VisitMediaNoteKind.text;
    final media = MediaQuery.of(dialogContext);
    final isLandscape = media.orientation == Orientation.landscape;
    final result = await GlassActionDialog.show(
      context: dialogContext,
      icon: isText ? Icons.sticky_note_2_rounded : Icons.mic_rounded,
      title: title,
      iconColor: accentColor,
      primaryLabel: 'Save',
      barrierDismissible: true,
      showCloseButton: true,
      compact: isLandscape,
      messageMaxHeightFactor: isLandscape ? 0.92 : 0.58,
      insetPadding: isLandscape
          ? EdgeInsets.symmetric(
              horizontal: (media.size.width * 0.18).clamp(24.0, 80.0),
              vertical: 8,
            )
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      maxWidth: isLandscape ? 460 : null,
      useRootNavigator: true,
      onPrimaryPressed: () async {
        if (controller.isClosed) return false;
        if (controller.isRecording.value) {
          await controller.stopRecording();
        }
        if (controller.isClosed) return false;
        if (controller.isPlaying.value) {
          await controller.togglePlayback();
        }
        if (controller.isClosed) return false;

        if (!controller.hasChanges.value) {
          return true;
        }

        await controller.commitDraft();
        if (controller.isClosed) return false;
        if (controller.hasChanges.value) {
          controller.errorMessage.value = isText
              ? 'Enter a text note to replace the voice note.'
              : 'Record a voice note to replace the text note.';
          return false;
        }
        didSave = true;
        return true;
      },
      content: _VisitMediaNotesContent(
        item: item,
        controller: controller,
        isDark: isDark,
        kind: kind,
        subtitle: subtitle,
        textHint: textHint,
        accent: accentColor,
      ),
    );
    if (result == true) {
      didSave = true;
    }
  } finally {
    if (!controller.isClosed) {
      if (controller.isRecording.value) {
        await controller.stopRecording();
      }
      if (!didSave) {
        controller.discardDraft();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<VisitMediaNotesController>(tag: tag)) {
        Get.delete<VisitMediaNotesController>(tag: tag);
      }
    });
  }
}

class _VisitMediaNotesContent extends StatelessWidget {
  const _VisitMediaNotesContent({
    required this.item,
    required this.controller,
    required this.isDark,
    required this.kind,
    required this.subtitle,
    required this.textHint,
    required this.accent,
  });

  final VisitMediaItem? item;
  final VisitMediaNotesController controller;
  final bool isDark;
  final VisitMediaNoteKind kind;
  final String subtitle;
  final String textHint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final labelColor = isDark ? cDarkTextSecondary : const Color(0xFF667085);
    final fieldFill = isDark
        ? cDarkInputFillColor
        : Colors.white.withValues(alpha: 0.72);
    final fieldBorder = isDark ? cDarkBorderColor : const Color(0xFFD0D5DD);
    final cardFill = isDark
        ? cDarkCardColor.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.72);
    final textColor = isDark ? cDarkTextPrimary : const Color(0xFF20283A);
    final isText = kind == VisitMediaNoteKind.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          subtitle,
          textAlign: isLandscape ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: isLandscape ? 12 : 13.5,
            height: 1.3,
            color: labelColor,
          ),
        ),
        SizedBox(height: isLandscape ? 8 : 14),
        if (isText)
          _TextNoteSection(
            controller: controller,
            labelColor: labelColor,
            fieldFill: fieldFill,
            fieldBorder: fieldBorder,
            textColor: textColor,
            accent: accent,
            hintText: textHint,
            isLandscape: isLandscape,
          )
        else
          _VoiceNoteSection(
            controller: controller,
            isDark: isDark,
            fieldBorder: fieldBorder,
            cardFill: cardFill,
            textColor: textColor,
            accent: accent,
            isLandscape: isLandscape,
          ),
      ],
    );
  }
}

class _TextNoteSection extends StatelessWidget {
  const _TextNoteSection({
    required this.controller,
    required this.labelColor,
    required this.fieldFill,
    required this.fieldBorder,
    required this.textColor,
    required this.accent,
    required this.hintText,
    this.isLandscape = false,
  });

  final VisitMediaNotesController controller;
  final Color labelColor;
  final Color fieldFill;
  final Color fieldBorder;
  final Color textColor;
  final Color accent;
  final String hintText;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final lines = isLandscape ? 2 : 5;
    return TextField(
      controller: controller.textController,
      maxLines: lines,
      minLines: lines,
      textInputAction: TextInputAction.newline,
      onChanged: (value) => controller.onTextChanged(value),
      style: TextStyle(color: textColor, fontSize: isLandscape ? 13.5 : 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: labelColor.withValues(alpha: 0.85),
          fontSize: isLandscape ? 13.5 : 14,
        ),
        filled: true,
        fillColor: fieldFill,
        contentPadding: EdgeInsets.all(isLandscape ? 10 : 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isLandscape ? 14 : 16),
          borderSide: BorderSide(color: fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isLandscape ? 14 : 16),
          borderSide: BorderSide(color: fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isLandscape ? 14 : 16),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
    );
  }
}

class _VoiceNoteSection extends StatelessWidget {
  const _VoiceNoteSection({
    required this.controller,
    required this.isDark,
    required this.fieldBorder,
    required this.cardFill,
    required this.textColor,
    required this.accent,
    this.isLandscape = false,
  });

  final VisitMediaNotesController controller;
  final bool isDark;
  final Color fieldBorder;
  final Color cardFill;
  final Color textColor;
  final Color accent;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isClosed) {
        return const SizedBox.shrink();
      }
      final recording = controller.isRecording.value;
      final hasVoice = controller.voiceNotePath.value != null;
      final playing = controller.isPlaying.value;
      final seconds = controller.recordSeconds.value;
      final error = controller.errorMessage.value;
      final buttonHeight = isLandscape ? 38.0 : 44.0;
      final waveHeight = isLandscape ? 30.0 : 44.0;

      final controls = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recording || hasVoice) ...[
            Row(
              children: [
                Container(
                  width: isLandscape ? 28 : 32,
                  height: isLandscape ? 28 : 32,
                  decoration: BoxDecoration(
                    color: (recording ? cRed : accent).withValues(
                      alpha: isDark ? 0.18 : 0.10,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    recording ? Icons.mic_rounded : Icons.graphic_eq_rounded,
                    color: recording ? cRed : accent,
                    size: isLandscape ? 16 : 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    recording
                        ? 'Recording... ${formatMMSS(seconds)}'
                        : 'Voice note attached',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: isLandscape ? 12.5 : 13,
                      color: recording ? cRed : textColor,
                    ),
                  ),
                ),
                if (hasVoice && !recording)
                  IconButton(
                    tooltip: 'Delete voice note',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.deleteVoiceNote,
                    icon: VisitDeleteIcon(
                      size: isLandscape ? 18 : 20,
                      color: cRed,
                    ),
                  ),
              ],
            ),
            SizedBox(height: isLandscape ? 6 : 12),
            SizedBox(
              height: waveHeight,
              child: Obx(() {
                final levels = controller.waveLevels.isNotEmpty
                    ? List<double>.from(controller.waveLevels)
                    : List<double>.from(controller.displayWaveLevels);
                final progress = recording
                    ? null
                    : (playing || controller.playbackProgress.value > 0.001)
                    ? controller.playbackProgress.value
                    : null;
                final wave = VoiceWaveform(
                  levels: levels,
                  color: recording
                      ? cOrange
                      : accent.withValues(alpha: playing ? 1 : 0.86),
                  progress: progress,
                );

                if (recording) return wave;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    void seekAt(double dx) {
                      final width = constraints.maxWidth;
                      if (width <= 0) return;
                      controller.seekPlayback((dx / width).clamp(0.0, 1.0));
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          seekAt(details.localPosition.dx),
                      onHorizontalDragStart: (details) =>
                          seekAt(details.localPosition.dx),
                      onHorizontalDragUpdate: (details) =>
                          seekAt(details.localPosition.dx),
                      child: wave,
                    );
                  },
                );
              }),
            ),
            SizedBox(height: isLandscape ? 6 : 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.isBusy.value
                      ? null
                      : controller.toggleRecording,
                  style: FilledButton.styleFrom(
                    backgroundColor: recording ? cRed : accent,
                    foregroundColor: Colors.white,
                    minimumSize: Size.fromHeight(buttonHeight),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: Icon(
                    recording
                        ? Icons.stop_rounded
                        : hasVoice
                        ? Icons.refresh_rounded
                        : Icons.mic_rounded,
                    size: 20,
                  ),
                  label: Text(
                    recording
                        ? 'Stop'
                        : hasVoice
                        ? 'Retake'
                        : 'Record',
                  ),
                ),
              ),
              if (hasVoice && !recording) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.togglePlayback,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      minimumSize: Size.fromHeight(buttonHeight),
                      side: BorderSide(color: fieldBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: Icon(
                      playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 20,
                    ),
                    label: Text(playing ? 'Pause' : 'Play'),
                  ),
                ),
              ],
            ],
          ),
          if (error != null) ...[
            SizedBox(height: isLandscape ? 6 : 10),
            Text(
              error,
              style: const TextStyle(
                color: cRed,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      );

      if (isLandscape && !recording && !hasVoice) {
        return controls;
      }

      return Container(
        padding: EdgeInsets.all(isLandscape ? 8 : 14),
        decoration: BoxDecoration(
          color: cardFill,
          borderRadius: BorderRadius.circular(isLandscape ? 14 : 18),
          border: Border.all(
            color: recording ? cRed.withValues(alpha: 0.45) : fieldBorder,
          ),
        ),
        child: controls,
      );
    });
  }
}
