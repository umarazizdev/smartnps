import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../flow/visit_video_flow_controller.dart';
import 'visit_media_notes_sheet.dart';
import 'voice/inline_voice_note_player.dart';

class VisitBatchNotesPanel extends StatelessWidget {
  const VisitBatchNotesPanel({
    super.key,
    required this.flow,
    required this.isDark,
  });

  final VisitVideoFlowController flow;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const attentionRed = Color(0xFFDC2626);
    final titleColor = attentionRed;
    final border = attentionRed.withValues(alpha: isDark ? 0.42 : 0.28);
    final cardBg = attentionRed.withValues(alpha: isDark ? 0.16 : 0.08);
    final accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF4F46E5);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF374151);

    return Obx(() {
      final note = flow.batchNote.value;
      final enabled = note.enabled;

      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(10, 4, 6, enabled ? 8 : 4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Attention needed',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.62,
                    alignment: Alignment.centerRight,
                    child: Switch.adaptive(
                      value: enabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeTrackColor: attentionRed.withValues(alpha: 0.45),
                      activeThumbColor: attentionRed,
                      onChanged: (value) {
                        unawaited(flow.setBatchNotesEnabled(value));
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (enabled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _NoteActionButton(
                      icon: Icons.sticky_note_2_outlined,
                      label: note.hasTextNote ? 'Edit text' : 'Text note',
                      active: note.hasTextNote,
                      isDark: isDark,
                      accent: accent,
                      onTap: () => openVisitBatchNotesSheet(
                        context: context,
                        kind: VisitMediaNoteKind.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _NoteActionButton(
                      icon: Icons.mic_none_rounded,
                      label: note.hasVoiceNote ? 'Edit voice' : 'Voice note',
                      active: note.hasVoiceNote,
                      isDark: isDark,
                      accent: accent,
                      onTap: () => openVisitBatchNotesSheet(
                        context: context,
                        kind: VisitMediaNoteKind.voice,
                      ),
                    ),
                  ),
                ],
              ),
              if (note.hasTextNote) ...[
                const SizedBox(height: 6),
                _SavedTextNote(
                  text: note.textNote.trim(),
                  isDark: isDark,
                  bodyColor: bodyColor,
                  accent: accent,
                ),
              ] else if (note.hasVoiceNote) ...[
                const SizedBox(height: 6),
                _SavedVoiceNote(
                  path: note.voiceNotePath!,
                  isDark: isDark,
                  accent: accent,
                ),
              ],
            ],
          ],
        ),
      );
    });
  }
}

class _SavedTextNote extends StatelessWidget {
  const _SavedTextNote({
    required this.text,
    required this.isDark,
    required this.bodyColor,
    required this.accent,
  });

  final String text;
  final bool isDark;
  final Color bodyColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.sticky_note_2_outlined, size: 14, color: accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: bodyColor,
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedVoiceNote extends StatelessWidget {
  const _SavedVoiceNote({
    required this.path,
    required this.isDark,
    required this.accent,
  });

  final String path;
  final bool isDark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: InlineVoiceNotePlayer(
        path: path,
        isDark: isDark,
        accent: accent,
        compact: true,
      ),
    );
  }
}

class _NoteActionButton extends StatelessWidget {
  const _NoteActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.9));
    final fg = active
        ? accent
        : (isDark ? Colors.white : const Color(0xFF1F2937));
    final border = active
        ? accent.withValues(alpha: 0.45)
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
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
