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
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: Row(
          children: [
            _HeaderButton(icon: Icons.menu_rounded, onTap: onMenuTap),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF4F8DFF), Color(0xFF7CC4FF)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: const Color(0xFF4F8DFF).withAlpha(70), blurRadius: 14)],
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).textTheme.bodyLarge?.color),
                            children: const [TextSpan(text: 'SmartNPS'), TextSpan(text: '360', style: TextStyle(color: Color(0xFF4F8DFF)))],
                          ),
                        ),
                        Row(
                          children: [
                            Container(width: 5, height: 5, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text('v3.0 · System Online', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cDarkGreyclr, fontWeight: FontWeight.w700, fontSize: 9)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Obx(() => _HeaderButton(icon: controller.isDarkMode.value ? Icons.light_mode_rounded : Icons.dark_mode_rounded, onTap: controller.toggleTheme)),
            const SizedBox(width: 7),
            Obx(
              () => Stack(
                clipBehavior: Clip.none,
                children: [
                  _HeaderButton(icon: Icons.notifications_rounded, onTap: controller.openNotifications),
                  if (controller.unreadNotifications > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        height: 17,
                        constraints: const BoxConstraints(minWidth: 17),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: cRed, borderRadius: BorderRadius.circular(99), border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2)),
                        child: Center(child: Text('${controller.unreadNotifications}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
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
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFE5EAF1)),
        ),
        child: Icon(icon, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color),
      ),
    );
  }
}
