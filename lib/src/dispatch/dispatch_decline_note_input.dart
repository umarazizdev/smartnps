import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../log_visit/log_visit_theme.dart';
import '../log_visit/notes/voice/inline_voice_note_player.dart';
import '../log_visit/notes/voice/voice_waveform_painter.dart';
import 'dispatch_decline_note_controller.dart';
import 'dispatch_scale.dart';

enum DispatchDeclineNoteMode { text, voice }

class DispatchDeclineNoteInput extends StatefulWidget {
  const DispatchDeclineNoteInput({
    super.key,
    required this.textController,
    required this.isDark,
    required this.declining,
    required this.errorText,
    required this.onChanged,
    required this.onVoicePathChanged,
  });

  final TextEditingController textController;
  final bool isDark;
  final bool declining;
  final String? errorText;
  final VoidCallback onChanged;
  final ValueChanged<String?> onVoicePathChanged;

  @override
  State<DispatchDeclineNoteInput> createState() =>
      _DispatchDeclineNoteInputState();
}

class _DispatchDeclineNoteInputState extends State<DispatchDeclineNoteInput> {
  late final String _tag;
  late final DispatchDeclineNoteController _c;

  @override
  void initState() {
    super.initState();
    _tag = 'dispatch_decline_note_${identityHashCode(this)}';
    _c = Get.put(
      DispatchDeclineNoteController(
        textController: widget.textController,
        onChanged: widget.onChanged,
        onVoicePathChanged: widget.onVoicePathChanged,
      ),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    Get.delete<DispatchDeclineNoteController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final isDark = widget.isDark;
    final accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF2856D9);
    final textColor = isDark ? const Color(0xFFF1F5FC) : const Color(0xFF102541);
    final labelColor = isDark ? const Color(0xFFA6B7CC) : const Color(0xFF52647D);
    final border = isDark ? const Color(0xFF2D415A) : const Color(0xFFDCE5F2);
    final input = isDark ? const Color(0xFF142437) : const Color(0xFFFFFFFF);

    return Obx(() {
      final error = widget.errorText ?? _c.voiceError.value;
      final mode = _c.mode.value;
      final hasVoice = _c.hasVoice;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Text note',
                  selected: mode == DispatchDeclineNoteMode.text,
                  isDark: isDark,
                  accent: accent,
                  onTap: () => unawaited(_c.setMode(DispatchDeclineNoteMode.text)),
                ),
              ),
              SizedBox(width: scale.s(8)),
              Expanded(
                child: _ModeChip(
                  icon: hasVoice ? Icons.mic_rounded : Icons.mic_none_rounded,
                  label: hasVoice ? 'Voice added' : 'Voice note',
                  selected: mode == DispatchDeclineNoteMode.voice,
                  isDark: isDark,
                  accent: accent,
                  onTap: () =>
                      unawaited(_c.setMode(DispatchDeclineNoteMode.voice)),
                ),
              ),
            ],
          ),
          SizedBox(height: scale.s(12)),
          if (mode == DispatchDeclineNoteMode.text)
            TextField(
              controller: widget.textController,
              maxLength: 500,
              maxLines: 3,
              onChanged: (_) => widget.onChanged(),
              style: TextStyle(color: textColor, fontSize: scale.sp(15)),
              decoration: InputDecoration(
                hintText: widget.declining
                    ? 'Example: I am handling another assignment and cannot leave my current site.'
                    : 'Example: I was assisting another officer and couldn’t access my phone.',
                hintStyle: TextStyle(
                  color: labelColor,
                  height: 1.4,
                  fontSize: scale.sp(13.5),
                ),
                errorText: error,
                filled: true,
                fillColor: input,
                contentPadding: EdgeInsets.all(scale.s(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(scale.cardRadius),
                  borderSide: BorderSide(color: border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(scale.cardRadius),
                  borderSide: BorderSide(color: accent, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(scale.cardRadius),
                  borderSide: const BorderSide(color: Color(0xFFDC3545)),
                ),
              ),
            )
          else
            _VoicePanel(
              isDark: isDark,
              accent: accent,
              textColor: textColor,
              labelColor: labelColor,
              border: border,
              input: input,
              recording: _c.recording.value,
              busy: _c.busy.value,
              hasVoice: hasVoice,
              voicePath: _c.voicePath.value,
              recordSeconds: _c.recordSeconds.value,
              waveLevels: List<double>.from(_c.waveLevels),
              errorText: error,
              onToggleRecord: () => unawaited(_c.toggleRecording()),
              onDelete: () => unawaited(_c.deleteVoice()),
            ),
        ],
      );
    });
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final bg = selected
        ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF3F6FB));
    final fg = selected
        ? accent
        : (isDark ? Colors.white : const Color(0xFF1F2937));
    final border = selected
        ? accent.withValues(alpha: 0.45)
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(scale.s(10)),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(scale.s(10)),
            border: Border.all(color: border),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: scale.s(10),
            vertical: scale.s(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: scale.s(16), color: fg),
              SizedBox(width: scale.s(6)),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: scale.sp(12.5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoicePanel extends StatelessWidget {
  const _VoicePanel({
    required this.isDark,
    required this.accent,
    required this.textColor,
    required this.labelColor,
    required this.border,
    required this.input,
    required this.recording,
    required this.busy,
    required this.hasVoice,
    required this.voicePath,
    required this.recordSeconds,
    required this.waveLevels,
    required this.errorText,
    required this.onToggleRecord,
    required this.onDelete,
  });

  final bool isDark;
  final Color accent;
  final Color textColor;
  final Color labelColor;
  final Color border;
  final Color input;
  final bool recording;
  final bool busy;
  final bool hasVoice;
  final String? voicePath;
  final int recordSeconds;
  final List<double> waveLevels;
  final String? errorText;
  final VoidCallback onToggleRecord;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    return Container(
      padding: EdgeInsets.all(scale.s(12)),
      decoration: BoxDecoration(
        color: input,
        borderRadius: BorderRadius.circular(scale.cardRadius),
        border: Border.all(
          color: errorText != null ? const Color(0xFFDC3545) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: scale.s(34),
                height: scale.s(34),
                decoration: BoxDecoration(
                  color: (recording ? cRed : accent).withValues(
                    alpha: isDark ? 0.18 : 0.10,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  recording ? Icons.mic_rounded : Icons.graphic_eq_rounded,
                  color: recording ? cRed : accent,
                  size: scale.s(18),
                ),
              ),
              SizedBox(width: scale.s(10)),
              Expanded(
                child: Text(
                  recording
                      ? 'Recording… ${formatMMSS(recordSeconds)}'
                      : hasVoice
                      ? 'Voice note attached'
                      : 'Tap record to add a voice note',
                  style: TextStyle(
                    color: recording ? cRed : textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: scale.sp(13),
                  ),
                ),
              ),
              if (hasVoice && !recording)
                IconButton(
                  tooltip: 'Delete voice note',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: VisitDeleteIcon(size: scale.s(20), color: cRed),
                ),
            ],
          ),
          if (recording) ...[
            SizedBox(height: scale.s(10)),
            SizedBox(
              height: scale.s(40),
              child: VoiceWaveform(
                levels: waveLevels.isNotEmpty
                    ? waveLevels
                    : List<double>.filled(8, 0.18),
                color: cOrange,
              ),
            ),
          ] else if (hasVoice && voicePath != null) ...[
            SizedBox(height: scale.s(10)),
            InlineVoiceNotePlayer(
              path: voicePath!,
              isDark: isDark,
              accent: accent,
              compact: true,
            ),
          ],
          SizedBox(height: scale.s(12)),
          SizedBox(
            height: scale.s(44),
            child: FilledButton.icon(
              onPressed: busy ? null : onToggleRecord,
              style: FilledButton.styleFrom(
                backgroundColor: recording ? cRed : accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(scale.s(12)),
                ),
              ),
              icon: Icon(
                recording ? Icons.stop_rounded : Icons.mic_rounded,
                size: scale.s(18),
              ),
              label: Text(
                recording
                    ? 'Stop recording'
                    : hasVoice
                    ? 'Re-record'
                    : 'Record voice note',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: scale.sp(13.5),
                ),
              ),
            ),
          ),
          if (errorText != null) ...[
            SizedBox(height: scale.s(8)),
            Text(
              errorText!,
              style: TextStyle(
                color: const Color(0xFFDC3545),
                fontSize: scale.sp(12.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          SizedBox(height: scale.s(4)),
          Text(
            'You can submit either a text note or a voice note.',
            style: TextStyle(color: labelColor, fontSize: scale.sp(12)),
          ),
        ],
      ),
    );
  }
}