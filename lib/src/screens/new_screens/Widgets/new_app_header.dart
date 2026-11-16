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
    final size = MediaQuery.sizeOf(context);
    final scale = (size.width / 390).clamp(0.85, 1.2);
    final metrics = _HeaderMetrics(scale);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.sidePad,
          metrics.topPad,
          metrics.sidePad,
          metrics.bottomPad,
        ),
        child: SizedBox(
          height: metrics.rowHeight,
          child: Row(
            children: [
              _HeaderButton(
                asset: 'assets/images/header_menu_outline_v4.png',
                onTap: onMenuTap,
                tinted: true,
                metrics: metrics,
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.logoPad),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(metrics.logoRadius),
                  child: Image.asset(
                    'assets/images/npslogo_navy_exact.png',
                    width: metrics.logoSize,
                    height: metrics.logoSize,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: metrics.titleSize,
                      letterSpacing: -.4,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    children: const [
                      TextSpan(text: 'SmartNPS'),
                      TextSpan(
                        text: ' 360',
                        style: TextStyle(color: Color(0xFF4F8DFF)),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: metrics.actionGap),
              Obx(
                () => Tooltip(
                  message: controller.isDarkMode.value
                      ? 'Switch to light mode'
                      : 'Switch to dark mode',
                  child: _HeaderButton(
                    asset: 'assets/images/header_moon_outline_v4.png',
                    onTap: controller.toggleTheme,
                    metrics: metrics,
                  ),
                ),
              ),
              SizedBox(width: metrics.actionGap),
              Obx(
                () => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _HeaderButton(
                      asset: 'assets/images/header_bell_outline_v4.png',
                      onTap: controller.openNotifications,
                      metrics: metrics,
                    ),
                    if (controller.unreadNotifications > 0)
                      Positioned(
                        right: metrics.badgeOffset,
                        top: metrics.badgeOffset,
                        child: Container(
                          height: metrics.badgeSize,
                          constraints: BoxConstraints(
                            minWidth: metrics.badgeSize,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.badgePad,
                          ),
                          decoration: BoxDecoration(
                            color: cRed,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: metrics.badgeBorder,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${controller.unreadNotifications}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: metrics.badgeFont,
                                fontWeight: FontWeight.w700,
                                height: 1,
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
      ),
    );
  }
}

class _HeaderMetrics {
  const _HeaderMetrics(this.scale);

  final double scale;

  double get sidePad => (12 * scale).clamp(10.0, 16.0);
  double get topPad => (3 * scale).clamp(2.0, 5.0);
  double get bottomPad => (8 * scale).clamp(6.0, 10.0);
  double get rowHeight => (46 * scale).clamp(42.0, 54.0);
  double get logoSize => (46 * scale).clamp(40.0, 52.0);
  double get logoPad => (2 * scale).clamp(1.0, 3.0);
  double get logoRadius => (12 * scale).clamp(10.0, 14.0);
  double get titleSize => (15 * scale).clamp(13.5, 17.0);
  double get actionGap => (7 * scale).clamp(6.0, 9.0);
  double get buttonSize => (44 * scale).clamp(40.0, 50.0);
  double get buttonRadius => (15 * scale).clamp(13.0, 17.0);
  double get iconSize => (24 * scale).clamp(22.0, 28.0);
  double get badgeSize => (17 * scale).clamp(15.0, 19.0);
  double get badgePad => (4 * scale).clamp(3.0, 5.0);
  double get badgeFont => (9 * scale).clamp(8.0, 10.0);
  double get badgeBorder => (2 * scale).clamp(1.5, 2.5);
  double get badgeOffset => (1 * scale).clamp(1.0, 2.0);
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.asset,
    required this.onTap,
    required this.metrics,
    this.tinted = false,
  });

  final bool tinted;
  final String asset;
  final VoidCallback onTap;
  final _HeaderMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(metrics.buttonRadius),
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
          width: metrics.buttonSize,
          height: metrics.buttonSize,
          decoration: BoxDecoration(
            color: tinted
                ? Theme.of(context).colorScheme.primary.withAlpha(22)
                : Theme.of(context).colorScheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(metrics.buttonRadius),
            border: tinted
                ? null
                : Border.all(
                    color: Theme.of(context).dividerColor.withAlpha(35),
                  ),
          ),
          child: Center(
            child: Image.asset(
              asset,
              width: metrics.iconSize,
              height: metrics.iconSize,
              color: tinted
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).textTheme.bodyLarge?.color,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
