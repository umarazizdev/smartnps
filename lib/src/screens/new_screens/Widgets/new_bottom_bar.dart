import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import '../new_main_controller.dart';

class NewBottomBar extends StatelessWidget {
  const NewBottomBar({super.key, required this.controller});

  final NewMainController controller;

  static const _tabs = [
    _NewTab(Icons.dashboard_rounded, 'Dashboard', 0),
    _NewTab(Icons.calendar_month_rounded, 'Calendar', 1),
    _NewTab(Icons.forum_rounded, 'Log', 2),
    _NewTab(Icons.chat_bubble_rounded, 'Messages', 3),
    _NewTab(Icons.person_rounded, 'Profile', 4),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final width = media.size.width;
    final scale = (width / 390).clamp(0.88, 1.12);
    final barHeight = (76.0 * scale).clamp(68.0, 84.0);
    final sidePad = (16.0 * scale).clamp(12.0, 20.0);
    final itemHeight = (60.0 * scale).clamp(52.0, 66.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePad,
        0,
        sidePad,
        bottomInset > 0 ? bottomInset + 6 : 10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: barHeight,
            padding: EdgeInsets.symmetric(
              horizontal: 7 * scale,
              vertical: 7 * scale,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF11162A).withAlpha(235)
                  : Colors.white.withAlpha(246),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(22)
                    : const Color(0xFFE5EAF1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 90 : 22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Obx(
              () => Row(
                children: _tabs.map((tab) {
                  final active = controller.pageIndex.value == tab.index;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(23),
                      overlayColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                      onTap: () => controller.changePage(tab.index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOutCubic,
                        height: itemHeight,
                        decoration: BoxDecoration(
                          color: active
                              ? cPrimary.withAlpha(isDark ? 38 : 18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(23),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: active ? 1.08 : 1,
                              duration: const Duration(milliseconds: 170),
                              child: Icon(
                                tab.icon,
                                color: active
                                    ? cPrimary
                                    : (isDark
                                        ? Colors.white.withAlpha(145)
                                        : const Color(0xFF8B93A3)),
                                size: active ? 24 * scale : 22 * scale,
                              ),
                            ),
                            SizedBox(height: 4 * scale),
                            Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: active
                                        ? cPrimary
                                        : (isDark
                                            ? Colors.white.withAlpha(145)
                                            : const Color(0xFF8B93A3)),
                                    fontSize: 10.5 * scale,
                                    fontWeight: active
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    height: 1,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewTab {
  const _NewTab(this.icon, this.label, this.index);

  final IconData icon;
  final String label;
  final int index;
}
