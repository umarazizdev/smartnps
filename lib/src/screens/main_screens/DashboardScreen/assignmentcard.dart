// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/assignmentmodel.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final VoidCallback onTap;
  final VoidCallback onLogVisit;
  final VoidCallback onViewImages;

  const _AssignmentCard({
    required this.assignment,
    required this.onTap,
    required this.onLogVisit,
    required this.onViewImages,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isPending = assignment.status.toLowerCase() == 'pending';
    final TextStyle titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
    );
    final TextStyle metaStyle = TextStyle(
      fontSize: 13,
      color: isDark ? cDarkTextSecondary : const Color(0xFF374151),
    );
    final double actionWidth = 94;

    return Semantics(
      container: true,
      label:
          'Assignment ${assignment.index}, ${assignment.site}, status ${assignment.status}',
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Index badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark
                        ? cDarkInputFillColor
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${assignment.index}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? cDarkTextPrimary
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Site title
                      Text(
                        assignment.site,
                        style: titleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Meta chips (wrap to next line if needed)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Round type (icon + text)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 14,
                                color: isDark
                                    ? cDarkIconColor
                                    : const Color(0xFF6B7280),
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 140,
                                ),
                                child: Text(
                                  assignment.roundType,
                                  style: metaStyle,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),

                          // Frequency chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              assignment.frequency,
                              style: const TextStyle(
                                color: Color(0xFF0369A1),
                                fontSize: 12,
                              ),
                            ),
                          ),

                          // Rounds chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: assignment.status == 'Completed'
                                  ? const Color(0xFFEFFDF3)
                                  : const Color(0xFFFFF7EB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${assignment.completed}/${assignment.total}',
                              style: TextStyle(
                                color: assignment.status == 'Completed'
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF92400E),
                                fontSize: 12,
                              ),
                            ),
                          ),

                          // Status chip (visually distinct)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: assignment.status == 'Completed'
                                  ? const Color(0xFFE6F9EE)
                                  : const Color(0xFFFFF5E6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: assignment.status == 'Completed'
                                    ? const Color(0xFF9AE6C0)
                                    : const Color(0xFFF5D3A6),
                              ),
                            ),
                            child: Text(
                              assignment.status,
                              style: TextStyle(
                                color: assignment.status == 'Completed'
                                    ? const Color(0xFF027A3C)
                                    : const Color(0xFFB76E00),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Actions column (stacked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isPending)
                      SizedBox(
                        width: actionWidth,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: onLogVisit,
                          icon: const Icon(
                            Icons.gps_fixed,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Log Visit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    if (isPending) const SizedBox(height: 8),

                    SizedBox(
                      width: actionWidth,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: onViewImages,
                        icon: Icon(
                          Icons.image_outlined,
                          size: 16,
                          color: isDark
                              ? cDarkTextPrimary
                              : const Color(0xFF0F172A),
                        ),
                        label: Text(
                          'View Images',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? cDarkTextPrimary
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
