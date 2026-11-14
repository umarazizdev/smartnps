import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';
import 'new_shift_log_controller.dart';

class NewShiftLogScreen extends StatelessWidget {
  const NewShiftLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewShiftLogController());
    return NewAnimatedShell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Shift Log', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.7))),
                    const NewPill(text: 'BayCrest', pulse: true, color: NewUi.success),
                  ],
                ),
                const SizedBox(height: 7),
                Text('Active Site · 4 officers', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          _Controls(controller: controller),
          Expanded(child: _LogList(controller: controller)),
          _Composer(controller: controller),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withAlpha(70)))),
      child: Column(
        children: [
          _SearchBox(controller: controller),
          const SizedBox(height: 8),
          _Filters(controller: controller),
          _MonthNav(controller: controller),
          _OfficerStrip(controller: controller),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(90)),
      ),
      child: TextField(
        onChanged: controller.updateSearch,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Search shift log...',
          hintStyle: TextStyle(fontSize: 13, color: isDark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w600),
          prefixIcon: Icon(Icons.search_rounded, size: 17, color: isDark ? NewUi.textMutedDark : NewUi.textMutedLight),
          suffixIcon: Obx(() => controller.searchText.value.isEmpty ? const SizedBox.shrink() : IconButton(onPressed: controller.clearSearch, icon: const Icon(Icons.close_rounded, size: 17))),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: NewLogFilter.values.map((filter) {
            final active = controller.selectedFilter.value == filter;
            final color = filter == NewLogFilter.attention ? NewUi.warning : filter == NewLogFilter.incident ? NewUi.danger : NewUi.accent;
            return Padding(
              padding: const EdgeInsets.only(right: 5),
              child: GestureDetector(
                onTap: () => controller.changeFilter(filter),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: active ? NewUi.accentGradient(color) : null,
                    color: active ? null : Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: active ? Colors.transparent : Theme.of(context).dividerColor.withAlpha(90)),
                    boxShadow: active ? [BoxShadow(color: color.withAlpha(40), blurRadius: 10, offset: const Offset(0, 3))] : null,
                  ),
                  child: Center(child: Text(_label(filter), style: TextStyle(color: active ? Colors.white : Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontSize: 11.5, fontWeight: FontWeight.w900))),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _label(NewLogFilter filter) {
    switch (filter) {
      case NewLogFilter.all:
        return 'All';
      case NewLogFilter.today:
        return 'Today';
      case NewLogFilter.yesterday:
        return 'Yesterday';
      case NewLogFilter.week:
        return 'This Week';
      case NewLogFilter.month:
        return 'This Month';
      case NewLogFilter.range:
        return 'Date Range';
      case NewLogFilter.officer:
        return 'By Officer';
      case NewLogFilter.attention:
        return 'Attention';
      case NewLogFilter.incident:
        return 'Incident';
    }
  }
}

class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedCrossFade(
        duration: const Duration(milliseconds: 180),
        crossFadeState: controller.selectedFilter.value == NewLogFilter.month || controller.selectedFilter.value == NewLogFilter.range ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: const SizedBox.shrink(),
        secondChild: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Theme.of(context).dividerColor.withAlpha(90)),
          ),
          child: Row(
            children: [
              _MiniIconButton(icon: Icons.chevron_left_rounded, onTap: () => controller.changeMonth(false)),
              Expanded(child: Text(controller.selectedMonth.value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
              _MiniIconButton(icon: Icons.chevron_right_rounded, onTap: () => controller.changeMonth(true)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfficerStrip extends StatelessWidget {
  const _OfficerStrip({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedCrossFade(
        duration: const Duration(milliseconds: 180),
        crossFadeState: controller.selectedFilter.value == NewLogFilter.officer ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: const SizedBox.shrink(),
        secondChild: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: controller.officers.map((officer) {
              final active = controller.selectedOfficer.value == officer;
              return Padding(
                padding: const EdgeInsets.only(right: 5),
                child: GestureDetector(
                  onTap: () => controller.setOfficer(officer),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: active ? Theme.of(context).dividerColor.withAlpha(80) : Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Theme.of(context).dividerColor.withAlpha(active ? 140 : 90)),
                    ),
                    child: Row(
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: _officerColor(officer), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(officer, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: active ? Theme.of(context).textTheme.bodyMedium?.color : Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Color _officerColor(String officer) {
    switch (officer) {
      case 'Sarah Chen':
        return NewUi.warning;
      case 'Dispatch':
        return NewUi.purple;
      case 'Michael Rivera':
        return NewUi.teal;
      case 'Hamid Khan':
        return NewUi.accent;
      default:
        return NewUi.textMutedLight;
    }
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final logs = controller.filteredLogs;
      if (logs.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(18),
          child: NewEmptyState(title: 'No logs found', subtitle: 'Try changing your filter or search.', icon: Icons.forum_outlined),
        );
      }

      String? lastDay;
      final children = <Widget>[];
      for (int i = 0; i < logs.length; i++) {
        final log = logs[i];
        if (lastDay != log.dayText) {
          children.add(_DayDivider(text: log.dayText));
          lastDay = log.dayText;
        }
        children.add(_LogRow(entry: log));
        if (log.isAuto && log.autoType == 'on-break') {
          children.add(const _ShiftEnd(text: 'Break started — timer paused'));
        }
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        children: children,
      );
    });
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.symmetric(vertical: 7),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9),
        border: Border.symmetric(horizontal: BorderSide(color: Theme.of(context).dividerColor.withAlpha(70))),
      ),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight)),
    );
  }
}

class _ShiftEnd extends StatelessWidget {
  const _ShiftEnd({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: const EdgeInsets.symmetric(vertical: 6),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(8) : const Color(0xFFF8FAFC),
        border: Border.symmetric(horizontal: BorderSide(color: Theme.of(context).dividerColor.withAlpha(55))),
      ),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight)),
    );
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({required this.entry});

  final NewShiftLogEntry entry;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    if (widget.entry.attention || widget.entry.incident) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final rowColor = entry.incident ? NewUi.danger : entry.attention ? NewUi.warning : _color(entry.colorKey);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final pulseAlpha = ((entry.attention || entry.incident) ? (18 + (_pulse.value * 24)) : 0).round();
        return Container(
          padding: EdgeInsets.fromLTRB(entry.isAuto ? 12 : 13, entry.isAuto ? 5 : 9, 13, entry.isAuto ? 5 : 9),
          decoration: BoxDecoration(
            color: entry.isAuto ? Colors.transparent : rowColor.withAlpha(pulseAlpha),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withAlpha(70)), left: BorderSide(color: rowColor, width: entry.isAuto ? 2 : 3)),
          ),
          child: Stack(
            children: [
              child!,
              if (entry.attention || entry.incident)
                Positioned(
                  top: 5,
                  right: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rowColor,
                      boxShadow: [BoxShadow(color: rowColor.withAlpha(((1 - _pulse.value) * 170).round()), spreadRadius: 8 * _pulse.value, blurRadius: 8)],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: entry.isAuto ? 11 : 13, height: 1.45),
              children: [
                TextSpan(text: '${entry.timeText}  ', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, color: entry.attention || entry.incident ? rowColor : Theme.of(context).textTheme.bodyLarge?.color)),
                if (entry.attention) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: _Tag(text: 'ATTENTION', color: NewUi.warning, icon: Icons.warning_amber_rounded)),
                if (entry.incident) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: _Tag(text: 'INCIDENT', color: NewUi.danger, icon: Icons.report_rounded)),
                TextSpan(text: entry.message, style: TextStyle(fontWeight: entry.isAuto ? FontWeight.w900 : FontWeight.w600, fontStyle: entry.isAuto ? FontStyle.italic : FontStyle.normal, color: entry.isAuto ? rowColor : null, letterSpacing: entry.isAuto ? .7 : 0)),
                TextSpan(text: '  ${entry.officerName}', style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w800, color: _officerColor(entry.officerName))),
              ],
            ),
          ),
          if (!entry.isAuto && (entry.attachmentName != null || entry.locationText != null))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Wrap(
                spacing: 11,
                runSpacing: 4,
                children: [
                  if (entry.attachmentName != null) _Meta(icon: Icons.attach_file_rounded, text: entry.attachmentName!),
                  if (entry.locationText != null)
                    GestureDetector(
                      onTap: () => _openMap(context, entry.locationText!),
                      child: _Meta(icon: Icons.location_on_rounded, text: entry.locationText!),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openMap(BuildContext context, String location) {
    Get.dialog(Dialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: Colors.transparent,
      child: NewGlassCard(
        padding: EdgeInsets.zero,
        highlightColor: NewUi.accent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(color: NewUi.accent.withAlpha(18), borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
              child: const Icon(Icons.map_rounded, size: 54, color: NewUi.accent),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [Expanded(child: Text(location, style: const TextStyle(fontWeight: FontWeight.w900))), TextButton(onPressed: Get.back, child: const Text('Close'))]),
            ),
          ],
        ),
      ),
    ));
  }

  Color _color(String key) {
    switch (key) {
      case 'purple':
        return NewUi.purple;
      case 'teal':
        return NewUi.teal;
      case 'amber':
        return NewUi.warning;
      default:
        return NewUi.accent;
    }
  }

  Color _officerColor(String name) {
    switch (name) {
      case 'Sarah Chen':
        return NewUi.purple;
      case 'Dispatch':
        return NewUi.warning;
      case 'Michael Rivera':
        return NewUi.teal;
      default:
        return NewUi.accent2;
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withAlpha(70))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 9, color: color), const SizedBox(width: 3), Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .8))]),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 11, color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight), const SizedBox(width: 4), Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight))]);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 104),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? NewUi.bgDark.withAlpha(230) : Colors.white.withAlpha(235),
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withAlpha(80))),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (controller.emojiOpen.value) Positioned(left: 0, right: 0, bottom: 92, child: _EmojiPicker(controller: controller)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: controller.attachName.value == null ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: const SizedBox.shrink(),
                  secondChild: _AttachBanner(controller: controller),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  decoration: BoxDecoration(
                    color: controller.incidentMode.value ? NewUi.danger.withAlpha(16) : controller.attentionMode.value ? NewUi.warning.withAlpha(16) : Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(12) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: controller.incidentMode.value ? NewUi.danger : controller.attentionMode.value ? NewUi.warning : Theme.of(context).dividerColor.withAlpha(90)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: controller.inputCtrl,
                        minLines: 2,
                        maxLines: 5,
                        decoration: InputDecoration.collapsed(hintText: 'Write a message...', hintStyle: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w600)),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _PillIcon(icon: Icons.attach_file_rounded, active: controller.attachName.value != null, color: NewUi.accent, onTap: controller.mockAttach),
                          _PillIcon(icon: Icons.emoji_emotions_outlined, active: controller.emojiOpen.value, color: NewUi.warning, onTap: controller.toggleEmoji),
                          _PillIcon(icon: Icons.warning_amber_rounded, active: controller.attentionMode.value, color: NewUi.warning, onTap: controller.toggleAttention),
                          _PillIcon(icon: Icons.report_rounded, active: controller.incidentMode.value, color: NewUi.danger, onTap: controller.toggleIncident),
                          const Spacer(),
                          GestureDetector(
                            onTap: controller.sendLog,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: controller.incidentMode.value ? NewUi.accentGradient(NewUi.danger) : controller.attentionMode.value ? NewUi.accentGradient(NewUi.warning) : NewUi.accentGradient(NewUi.accent),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: (controller.incidentMode.value ? NewUi.danger : controller.attentionMode.value ? NewUi.warning : NewUi.accent).withAlpha(60), blurRadius: 12)],
                              ),
                              child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    return NewGlassCard(
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: controller.emojis.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 3, mainAxisSpacing: 3),
        itemBuilder: (context, index) => InkWell(
          onTap: () => controller.insertEmoji(controller.emojis[index]),
          borderRadius: BorderRadius.circular(7),
          child: Center(child: Text(controller.emojis[index], style: const TextStyle(fontSize: 19))),
        ),
      ),
    );
  }
}

class _AttachBanner extends StatelessWidget {
  const _AttachBanner({required this.controller});

  final NewShiftLogController controller;

  @override
  Widget build(BuildContext context) {
    final name = controller.attachName.value ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: NewUi.accent.withAlpha(18), borderRadius: BorderRadius.circular(11), border: Border.all(color: NewUi.accent.withAlpha(60))),
      child: Row(children: [Expanded(child: Text(name, style: const TextStyle(color: NewUi.accent2, fontSize: 11.5, fontWeight: FontWeight.w900))), TextButton(onPressed: controller.removeAttach, child: const Text('Remove'))]),
    );
  }
}

class _PillIcon extends StatelessWidget {
  const _PillIcon({required this.icon, required this.active, required this.color, required this.onTap});

  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: active ? color.withAlpha(28) : Colors.transparent, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: active ? color : Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(width: 28, height: 28, decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 18, color: NewUi.accent2)),
    );
  }
}
