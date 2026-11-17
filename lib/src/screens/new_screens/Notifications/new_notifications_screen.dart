import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../Dashboard/new_dashboard_controller.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';

class NewNotificationsScreen extends StatefulWidget {
  const NewNotificationsScreen({super.key});

  @override
  State<NewNotificationsScreen> createState() => _NotificationsState();
}

class _NotificationsState extends State<NewNotificationsScreen> {
  final filter = 'All'.obs;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NewDashboardController>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ColoredBox(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF101827)
            : const Color(0xFFF5F7FA),
        child: SafeArea(
          child: Column(
            children: [
              _Header(controller: controller),
              _Summary(controller: controller, filter: filter),
              Expanded(
                child: _List(controller: controller, filter: filter),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          NewBackButton(onPressed: () => Get.back()),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Obx(
            () => TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: NewUi.accent.withAlpha(20),
                disabledBackgroundColor: Theme.of(
                  context,
                ).dividerColor.withAlpha(15),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: controller.unreadNotifications > 0
                  ? controller.markAllNotificationsRead
                  : null,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text(
                'Mark all\nas read',
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller, required this.filter});
  final RxString filter;

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = controller.notifications.where((e) => e.unread).length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor.withAlpha(15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              _SummaryCard(
                title: 'All',
                value: '${controller.notifications.length}',
                icon: Icons.notifications_none_rounded,
                color: NewUi.accent,
                selected: filter.value == 'All',
                onTap: () => filter.value = 'All',
              ),
              const SizedBox(width: 8),
              _SummaryCard(
                title: 'Unread',
                selected: filter.value == 'Unread',
                onTap: () => filter.value = 'Unread',
                value: '$unread',
                icon: Icons.mark_email_unread_rounded,
                color: NewUi.warning,
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF2874E8) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 23),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withAlpha(42)
                        : NewUi.accent.withAlpha(22),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller, required this.filter});
  final RxString filter;

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.notifications
          .where(
            (item) => switch (filter.value) {
              'Unread' => item.unread,
              'Critical' => item.critical,
              'Management' => item.source == 'Management',
              _ => true,
            },
          )
          .toList();
      if (items.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(18),
          child: NewEmptyState(
            title: 'No notifications',
            subtitle: 'New alerts and reminders will appear here.',
            icon: Icons.notifications_none_rounded,
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 220 + (index * 35).clamp(0, 220)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - value)),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NotificationTile(
                item: item,
                onTap: () => _openDetails(context, item),
              ),
            ),
          );
        },
      );
    });
  }

  void _openDetails(BuildContext context, NewNotificationItem item) {
    Get.to(
      () => Scaffold(
        appBar: AppBar(
          title: const Text('Notification details'),
          leading: Padding(
            padding: const EdgeInsets.all(6),
            child: NewBackButton(onPressed: () => Get.back()),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    NewPill(text: item.type, color: _color(item)),
                    if (item.site.isNotEmpty)
                      NewPill(
                        text: item.site,
                        icon: Icons.location_on_rounded,
                        color: NewUi.accent,
                      ),
                    if (item.shiftText.isNotEmpty)
                      NewPill(
                        text: item.shiftText,
                        icon: Icons.schedule_rounded,
                        color: NewUi.purple,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item.body,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoLine(label: 'Source', value: item.source),
                _InfoLine(label: 'Date', value: item.dateText),
                _InfoLine(label: 'Time', value: item.timeText),
                if (item.actionLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: NewActionButton(
                      text: item.actionLabel,
                      color: _color(item),
                      onTap: () {
                        Get.back();
                        Get.back();
                        controller.handleNotificationAction(item);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _color(NewNotificationItem item) => newColor(item.colorKey);
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NewNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = newColor(item.colorKey);
    return NewGlassCard(
      padding: const EdgeInsets.all(13),
      highlightColor: item.unread || item.critical ? color : null,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withAlpha(22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: item.iconKey == 'message'
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: CustomPaint(
                          painter: _NotificationMessagePainter(color),
                        ),
                      )
                    : Icon(_icon(item.iconKey), color: color, size: 19),
              ),
              if (item.unread)
                const Positioned(
                  right: -2,
                  top: -2,
                  child: NewPulseDot(color: NewUi.warning, size: 6),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? NewUi.textMutedDark
                        : NewUi.textMutedLight,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String key) {
    switch (key) {
      case 'shift':
        return Icons.work_history_rounded;
      case 'reminder':
        return Icons.alarm_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'task':
        return Icons.task_alt_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}

class _NotificationMessagePainter extends CustomPainter {
  const _NotificationMessagePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(6, 3)
      ..lineTo(18, 3)
      ..quadraticBezierTo(21, 3, 21, 6)
      ..lineTo(21, 14)
      ..quadraticBezierTo(21, 17, 18, 17)
      ..lineTo(10, 17)
      ..lineTo(5, 21)
      ..lineTo(6, 17)
      ..quadraticBezierTo(3, 17, 3, 14)
      ..lineTo(3, 6)
      ..quadraticBezierTo(3, 3, 6, 3)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(const Offset(7, 8), const Offset(17, 8), paint);
    canvas.drawLine(const Offset(7, 12), const Offset(14, 12), paint);
  }

  @override
  bool shouldRepaint(covariant _NotificationMessagePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? NewUi.textMutedDark
                    : NewUi.textMutedLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
