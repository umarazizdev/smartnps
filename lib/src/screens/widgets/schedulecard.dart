import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class ScheduleCard extends StatelessWidget {
  final String siteName;
  final String shiftTime;
  final String shiftType;
  final String timeRange;
  final String date;
  final String guards;
  final bool? untilCalledOff;
  final bool? enableMenu;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ScheduleCard({
    super.key,
    required this.siteName,
    required this.shiftTime,
    required this.shiftType,
    required this.timeRange,
    required this.date,
    required this.guards,
    required this.onEdit,
    required this.onDelete,
    this.untilCalledOff,
    this.enableMenu,
  });

  Color _statusColor() {
    switch (shiftType.toLowerCase()) {
      case 'temporary':
        return const Color(0xFFF59E0B);
      case 'permanent':
        return const Color(0xFF16A34A);
      case 'extra coverage':
        return const Color(0xFF4F46E5);
      default:
        return cPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : cWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 51 : 20),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: isDark ? cDarkTextPrimary : Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shiftTime,
                        style: textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? cDarkTextSecondary
                              : Color(0xFF6B7280),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Badge(
                      label: shiftType,
                      backgroundColor: _statusColor(),
                      textColor: Colors.white,
                    ),
                    if (untilCalledOff == true) ...[
                      const SizedBox(height: 6),
                      _Badge(
                        label: "Until Called Off",
                        backgroundColor: const Color(0xFFFFF7E0),
                        textColor: const Color(0xFFB45309),
                        borderColor: const Color(0xFFF59E0B),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            _InfoRow(
              icon: Icons.access_time,
              text: timeRange,
              textStyle: textTheme.bodyMedium!,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              text: date,
              textStyle: textTheme.bodyMedium!,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.people_alt_outlined,
              text: guards,
              textStyle: textTheme.bodyMedium!,
            ),
            if (enableMenu == true) ...[
              const SizedBox(height: 16),
              Divider(
                thickness: 1,
                color: isDark
                    ? cDarkBorderColor
                    : Colors.grey.shade300.withAlpha(153),
              ),

              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 120,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cPrimary,
                        foregroundColor: cPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: onEdit,
                      icon: Image.asset(
                        'assets/Icons/edit.png',
                        width: 18,
                        height: 18,
                        color: cWhiteText,
                      ),
                      label: Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          'Edit',
                          style: textTheme.labelLarge!.copyWith(
                            color: cWhiteText,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 6),
                  GestureDetector(
                    onTapDown: (TapDownDetails details) async {
                      final renderBox = Overlay.of(
                        context,
                      ).context.findRenderObject();
                      if (renderBox is! RenderBox) return;

                      await showMenu<String>(
                        context: context,
                        color: Colors.transparent,
                        elevation: 0,
                        position: RelativeRect.fromLTRB(
                          details.globalPosition.dx,
                          details.globalPosition.dy - 85,
                          renderBox.size.width - details.globalPosition.dx,
                          0,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        items: [
                          PopupMenuItem<String>(
                            value: 'delete',
                            padding: EdgeInsets.zero,
                            height: 0,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cRed,
                                foregroundColor: cWhiteText,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(100, 40),
                              ),

                              onPressed: () {
                                Navigator.pop(context);
                                onDelete();
                              },
                              icon: Image.asset(
                                'assets/Icons/delete.png',
                                width: 18,
                                height: 18,
                                color: cWhiteText,
                              ),
                              label: Text(
                                'Delete',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: cWhiteText),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(bottom: 2.0),
                      child: Icon(Icons.more_vert, color: cDarkText, size: 30),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle textStyle;

  const _InfoRow({
    required this.icon,
    required this.text,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? cDarkIconColor : Colors.grey.shade700,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: textStyle.copyWith(
              color: isDark ? cDarkTextPrimary : Colors.black87,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;

  const _Badge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
