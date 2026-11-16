import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../Dashboard/new_dashboard_controller.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';

class NewNotificationsScreen extends StatelessWidget {
  const NewNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NewDashboardController>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NewAnimatedShell(
        child: SafeArea(
          child: Column(
            children: [
              _Header(controller: controller),
              _Summary(controller: controller),
              Expanded(child: _List(controller: controller)),
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
          IconButton(onPressed: Get.back, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.7)),
                const SizedBox(height: 2),
                Obx(() => Text('${controller.unreadNotifications} unread alerts', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
          TextButton(onPressed: controller.markAllNotificationsRead, child: const Text('Mark read')),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = controller.notifications.where((e) => e.unread).length;
      final critical = controller.notifications.where((e) => e.critical).length;
      final management = controller.notifications.where((e) => e.source == 'Management').length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
        child: Row(
          children: [
            _SummaryCard(title: 'Unread', value: '$unread', icon: Icons.mark_email_unread_rounded, color: NewUi.warning),
            const SizedBox(width: 8),
            _SummaryCard(title: 'Critical', value: '$critical', icon: Icons.priority_high_rounded, color: NewUi.danger),
            const SizedBox(width: 8),
            _SummaryCard(title: 'Mgmt', value: '$management', icon: Icons.admin_panel_settings_rounded, color: NewUi.purple),
          ],
        ),
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: NewGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        highlightColor: color,
        child: Row(
          children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withAlpha(22), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 15, color: color)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1)),
                const SizedBox(height: 2),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontSize: 10, fontWeight: FontWeight.w800)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final NewDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.notifications.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(18),
          child: NewEmptyState(title: 'No notifications', subtitle: 'New alerts and reminders will appear here.', icon: Icons.notifications_none_rounded),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 130),
        itemCount: controller.notifications.length,
        itemBuilder: (context, index) {
          final item = controller.notifications[index];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 220 + (index * 35).clamp(0, 220)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 16 * (1 - value)), child: child)),
            child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _NotificationTile(item: item, onTap: () => _openDetails(context, item))),
          );
        },
      );
    });
  }

  void _openDetails(BuildContext context, NewNotificationItem item) {
    Get.bottomSheet(
      SafeArea(
        child: NewGlassCard(
          margin: const EdgeInsets.all(14),
          highlightColor: _color(item),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Expanded(child: Text(item.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))), IconButton(onPressed: Get.back, icon: const Icon(Icons.close_rounded))]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                NewPill(text: item.type, color: _color(item)),
                if (item.site.isNotEmpty) NewPill(text: item.site, icon: Icons.location_on_rounded, color: NewUi.accent),
                if (item.shiftText.isNotEmpty) NewPill(text: item.shiftText, icon: Icons.schedule_rounded, color: NewUi.purple),
              ]),
              const SizedBox(height: 12),
              Text(item.body, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.45)),
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(gradient: NewUi.accentGradient(color), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: color.withAlpha(55), blurRadius: 12)]),
                child: Icon(_icon(item.iconKey), color: Colors.white, size: 20),
              ),
              if (item.unread) const Positioned(right: -2, top: -2, child: NewPulseDot(color: NewUi.warning, size: 6)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(item.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.1))), Text(item.timeText, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w800))]),
                const SizedBox(height: 4),
                Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  NewPill(text: item.type, color: color),
                  if (item.source.isNotEmpty) NewPill(text: item.source, icon: Icons.person_rounded, color: NewUi.purple),
                  if (item.site.isNotEmpty) NewPill(text: item.site, icon: Icons.location_on_rounded, color: NewUi.accent),
                  if (item.critical) const NewPill(text: 'Critical', icon: Icons.priority_high_rounded, color: NewUi.danger),
                ]),
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w900)), const Spacer(), Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w700)))]),
    );
  }
}
