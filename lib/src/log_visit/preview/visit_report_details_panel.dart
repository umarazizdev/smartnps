import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../flow/visit_flow_kind.dart';
import '../flow/visit_report_details.dart';
import '../flow/visit_video_flow_controller.dart';
import '../log_visit_theme.dart';

String _formatReportDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.month}/${value.day}/${value.year}, '
      '$hour:$minute $period';
}

class VisitReportDetailsPanel extends StatelessWidget {
  const VisitReportDetailsPanel({
    super.key,
    required this.flow,
    required this.isDark,
    this.compact = false,
  });

  final VisitVideoFlowController flow;
  final bool isDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final kind = flow.flowKind;
      if (!kind.isStructuredReport) return const SizedBox.shrink();
      final details = flow.reportDetails.value;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 16,
          compact ? 2 : 4,
          compact ? 14 : 16,
          compact ? 4 : 8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF121826).withValues(alpha: 0.96)
                : Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFFD8E0EA),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 14,
              compact ? 12 : 14,
              compact ? 12 : 14,
              compact ? 12 : 14,
            ),
            child: kind == VisitFlowKind.issueReport
                ? _IssueReportForm(
                    isDark: isDark,
                    compact: compact,
                    details: details,
                    onChanged: flow.updateReportDetails,
                  )
                : _IncidentReportForm(
                    isDark: isDark,
                    compact: compact,
                    details: details,
                    onChanged: flow.updateReportDetails,
                  ),
          ),
        ),
      );
    });
  }
}

class _IssueReportForm extends StatelessWidget {
  const _IssueReportForm({
    required this.isDark,
    required this.compact,
    required this.details,
    required this.onChanged,
  });

  final bool isDark;
  final bool compact;
  final VisitReportDetails details;
  final ValueChanged<VisitReportDetails> onChanged;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 10.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportFormHeader(
          isDark: isDark,
          icon: Icons.flag_rounded,
          iconColor: const Color(0xFF7C3AED),
          title: 'Report an Issue',
          subtitle: 'Security, maintenance or any other site issue',
        ),
        SizedBox(height: gap + 2),
        _LabeledField(
          isDark: isDark,
          label: 'TITLE',
          required: true,
          child: _ReportTextField(
            isDark: isDark,
            value: details.title,
            hint: 'e.g. Broken gate at south entrance',
            textInputAction: TextInputAction.next,
            onChanged: (value) => onChanged(details.copyWith(title: value)),
          ),
        ),
        SizedBox(height: gap),
        _LabeledField(
          isDark: isDark,
          label: 'CATEGORY',
          child: Column(
            children: [
              _ReportPickerField(
                isDark: isDark,
                value: details.category ??
                    VisitReportDetails.issueCategories.first,
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: () => _openCategoryPicker(
                  context: context,
                  isDark: isDark,
                  title: 'Select category',
                  options: VisitReportDetails.issueCategories,
                  selected: details.category,
                  onSelected: (value) => onChanged(
                    details.copyWith(
                      category: value,
                      categoryOther:
                          value == VisitReportDetails.issueOtherCategory
                          ? details.categoryOther
                          : '',
                    ),
                  ),
                ),
              ),
              if (details.isOtherCategory) ...[
                const SizedBox(height: 8),
                _ReportTextField(
                  isDark: isDark,
                  value: details.categoryOther,
                  hint: 'Type the issue type...',
                  textInputAction: TextInputAction.next,
                  onChanged: (value) =>
                      onChanged(details.copyWith(categoryOther: value)),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: gap),
        _LabeledField(
          isDark: isDark,
          label: 'DETAILS',
          required: true,
          child: _ReportTextField(
            isDark: isDark,
            value: details.details,
            hint: 'Describe the issue — what, where, and any action taken...',
            maxLines: compact ? 3 : 3,
            onChanged: (value) => onChanged(details.copyWith(details: value)),
          ),
        ),
        SizedBox(height: gap),
        _ReportAttentionFlags(
          isDark: isDark,
          details: details,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _IncidentReportForm extends StatelessWidget {
  const _IncidentReportForm({
    required this.isDark,
    required this.compact,
    required this.details,
    required this.onChanged,
  });

  final bool isDark;
  final bool compact;
  final VisitReportDetails details;
  final ValueChanged<VisitReportDetails> onChanged;

  Future<void> _pickDateTime(BuildContext context) async {
    final initial = details.occurredAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 1),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    onChanged(
      details.copyWith(
        occurredAt: DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 10.0 : 12.0;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final categoryField = _LabeledField(
      isDark: isDark,
      label: 'CATEGORY',
      child: _ReportPickerField(
        isDark: isDark,
        value:
            details.category ?? VisitReportDetails.incidentCategories.first,
        icon: Icons.keyboard_arrow_down_rounded,
        onTap: () => _openCategoryPicker(
          context: context,
          isDark: isDark,
          title: 'Select category',
          options: VisitReportDetails.incidentCategories,
          selected: details.category,
          onSelected: (value) => onChanged(details.copyWith(category: value)),
        ),
      ),
    );
    final dateField = _LabeledField(
      isDark: isDark,
      label: 'DATE & TIME',
      child: _ReportPickerField(
        isDark: isDark,
        value: details.occurredAt == null
            ? 'Select date & time'
            : _formatReportDateTime(details.occurredAt!),
        icon: Icons.calendar_today_outlined,
        onTap: () => _pickDateTime(context),
      ),
    );
    final locationField = _LabeledField(
      isDark: isDark,
      label: 'LOCATION',
      child: _ReportTextField(
        isDark: isDark,
        value: details.location,
        hint: 'Where did it happen?',
        textInputAction: TextInputAction.next,
        onChanged: (value) => onChanged(details.copyWith(location: value)),
      ),
    );
    final peopleField = _LabeledField(
      isDark: isDark,
      label: 'PEOPLE INVOLVED / WITNESSES',
      child: _ReportTextField(
        isDark: isDark,
        value: details.peopleInvolved,
        hint: 'Names or descriptions (optional)',
        textInputAction: TextInputAction.next,
        onChanged: (value) =>
            onChanged(details.copyWith(peopleInvolved: value)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportFormHeader(
          isDark: isDark,
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFDC2626),
          title: 'Incident Report',
          subtitle: 'Document a security or safety incident',
        ),
        SizedBox(height: gap + 2),
        _LabeledField(
          isDark: isDark,
          label: 'TITLE',
          required: true,
          child: _ReportTextField(
            isDark: isDark,
            value: details.title,
            hint: 'e.g. Break-in at the north gate',
            textInputAction: TextInputAction.next,
            onChanged: (value) => onChanged(details.copyWith(title: value)),
          ),
        ),
        SizedBox(height: gap),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: categoryField),
              const SizedBox(width: 10),
              Expanded(child: dateField),
            ],
          )
        else ...[
          categoryField,
          SizedBox(height: gap),
          dateField,
        ],
        SizedBox(height: gap),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: locationField),
              const SizedBox(width: 10),
              Expanded(child: peopleField),
            ],
          )
        else ...[
          locationField,
          SizedBox(height: gap),
          peopleField,
        ],
        SizedBox(height: gap),
        _LabeledField(
          isDark: isDark,
          label: 'DESCRIPTION',
          required: true,
          child: _ReportTextField(
            isDark: isDark,
            value: details.description,
            hint:
                'What happened — who, what, when, where, and any action taken...',
            maxLines: 3,
            onChanged: (value) =>
                onChanged(details.copyWith(description: value)),
          ),
        ),
        SizedBox(height: gap),
        _ReportAttentionFlags(
          isDark: isDark,
          details: details,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

Future<void> _openCategoryPicker({
  required BuildContext context,
  required bool isDark,
  required String title,
  required List<String> options,
  required String? selected,
  required ValueChanged<String> onSelected,
}) async {
  final chosen = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.62;
      final bottomInset = MediaQuery.viewPaddingOf(ctx).bottom;
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151E2F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFE5EAF1),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: isDark
                            ? cDarkTextPrimary
                            : const Color(0xFF0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE8EEF5),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 20 + bottomInset),
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option == selected;
                  return Material(
                    color: isSelected
                        ? (isDark
                              ? const Color(0xFF1E3A5F).withValues(alpha: 0.85)
                              : const Color(0xFFEFF6FF))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(ctx).pop(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option,
                                style: TextStyle(
                                  color: isDark
                                      ? cDarkTextPrimary
                                      : const Color(0xFF0F172A),
                                  fontSize: 14.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: isDark
                                    ? const Color(0xFF93C5FD)
                                    : cPrimary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
  if (chosen != null) onSelected(chosen);
}

class _ReportAttentionFlags extends StatelessWidget {
  const _ReportAttentionFlags({
    required this.isDark,
    required this.details,
    required this.onChanged,
  });

  final bool isDark;
  final VisitReportDetails details;
  final ValueChanged<VisitReportDetails> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ATTENTION',
          style: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.55)
                : const Color(0xFF667085),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        _AttentionFlagToggle(
          isDark: isDark,
          icon: Icons.apartment_rounded,
          label: 'Attention to property management',
          value: details.attentionToPropertyManagement,
          onChanged: (value) => onChanged(
            details.copyWith(attentionToPropertyManagement: value),
          ),
        ),
        const SizedBox(height: 8),
        _AttentionFlagToggle(
          isDark: isDark,
          icon: Icons.shield_outlined,
          label: 'Attention to NPS',
          value: details.attentionToNps,
          onChanged: (value) =>
              onChanged(details.copyWith(attentionToNps: value)),
        ),
      ],
    );
  }
}

class _AttentionFlagToggle extends StatelessWidget {
  const _AttentionFlagToggle({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final bool isDark;
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFDC2626);
    return Material(
      color: value
          ? accent.withValues(alpha: isDark ? 0.16 : 0.07)
          : (isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: value
              ? accent.withValues(alpha: isDark ? 0.40 : 0.24)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : const Color(0xFFE2E8F0)),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value
                      ? accent.withValues(alpha: isDark ? 0.28 : 0.12)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFE8EEF5)),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: value
                      ? accent
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.65)
                            : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: value
                        ? (isDark
                              ? const Color(0xFFFFE4E6)
                              : const Color(0xFF9F1239))
                        : (isDark
                              ? cDarkTextPrimary
                              : const Color(0xFF1E293B)),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              SizedBox(
                width: 42,
                height: 28,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
                  child: Switch.adaptive(
                    value: value,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeTrackColor: accent.withValues(alpha: 0.45),
                    activeThumbColor: accent,
                    onChanged: onChanged,
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

class _ReportFormHeader extends StatelessWidget {
  const _ReportFormHeader({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark
                      ? cDarkTextSecondary.withValues(alpha: 0.88)
                      : const Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.isDark,
    required this.label,
    required this.child,
    this.required = false,
  });

  final bool isDark;
  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.58)
                    : const Color(0xFF667085),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ReportTextField extends StatefulWidget {
  const _ReportTextField({
    required this.isDark,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.maxLines = 1,
    this.textInputAction,
  });

  final bool isDark;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputAction? textInputAction;

  @override
  State<_ReportTextField> createState() => _ReportTextFieldState();
}

class _ReportTextFieldState extends State<_ReportTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ReportTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFD5DEEA),
      ),
    );
    final focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(
        color: widget.isDark ? const Color(0xFF4F8DF7) : cPrimary,
        width: 1.5,
      ),
    );
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: widget.maxLines,
      minLines: widget.maxLines > 1 ? widget.maxLines : 1,
      textInputAction: widget.textInputAction,
      style: TextStyle(
        color: widget.isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      cursorColor: widget.isDark ? const Color(0xFF93C5FD) : cPrimary,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.34)
              : const Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: widget.isDark
            ? const Color(0xFF0F1522)
            : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: focused,
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _ReportPickerField extends StatelessWidget {
  const _ReportPickerField({
    required this.isDark,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final bool isDark;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? const Color(0xFF0F1522) : const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFD5DEEA),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                icon,
                size: 20,
                color: isDark ? const Color(0xFF93C5FD) : cPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
