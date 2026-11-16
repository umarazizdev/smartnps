import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import '../Dashboard/new_dashboard_controller.dart';

class NewAppHeader extends StatelessWidget {
  const NewAppHeader({super.key, required this.onMenuTap});

  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NewDashboardController>();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 3),
        child: Row(
          children: [
            _HeaderButton(icon: Icons.menu_rounded, onTap: onMenuTap),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/npslogo.png',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  children: const [
                    TextSpan(text: 'SmartNPS'),
                    TextSpan(
                      text: '360',
                      style: TextStyle(color: Color(0xFF4F8DFF)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Obx(
              () => _HeaderButton(
                icon: controller.isDarkMode.value
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                onTap: controller.toggleTheme,
              ),
            ),
            const SizedBox(width: 6),
            Obx(
              () => Stack(
                clipBehavior: Clip.none,
                children: [
                  _HeaderButton(
                    icon: Icons.notifications_rounded,
                    onTap: controller.openNotifications,
                  ),
                  if (controller.unreadNotifications > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        height: 17,
                        constraints: const BoxConstraints(minWidth: 17),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: cRed,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${controller.unreadNotifications}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return const Color(0xFF4F8DFF).withAlpha(28);
        }
        if (states.contains(WidgetState.focused)) {
          return const Color(0xFF4F8DFF).withAlpha(20);
        }
        return null;
      }),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(20)
                : const Color(0xFFE5EAF1),
          ),
        ),
        child: Icon(
          icon,
          size: 19,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}
