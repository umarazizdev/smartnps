import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';

class NewConfirmDialog extends StatelessWidget {
  const NewConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.onConfirm,
    this.danger = false,
  });

  final String title;
  final String body;
  final VoidCallback onConfirm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? NewUi.danger : NewUi.accent;
    return _DialogShell(
      icon: danger ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
      iconColor: color,
      title: title,
      subtitle: 'Action requires confirmation',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: NewActionButton(
                  text: 'Cancel',
                  primary: false,
                  color: color,
                  onTap: Get.back,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NewActionButton(
                  text: 'Confirm',
                  color: color,
                  onTap: () {
                    Get.back();
                    onConfirm();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NewInfoDialog extends StatelessWidget {
  const NewInfoDialog({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline_rounded,
    this.color = NewUi.accent,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: 'Section preview',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.45),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: NewActionButton(
              text: 'Close',
              color: color,
              onTap: Get.back,
            ),
          ),
        ],
      ),
    );
  }
}

class NewWarningsDialog extends StatelessWidget {
  const NewWarningsDialog({super.key, required this.controller});

  final dynamic controller;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.warning_amber_rounded,
      iconColor: NewUi.danger,
      title: 'Officer Warnings',
      subtitle: 'Review your record',
      child: Obx(() {
        final items = controller.warningTab.value == NewWarningTab.late
            ? controller.lateItems
            : controller.warningTab.value == NewWarningTab.writeUps
            ? controller.writeUps
            : const <NewWarningItem>[];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SegmentTabs<NewWarningTab>(
              selected: controller.warningTab.value,
              items: const {
                NewWarningTab.late: 'Late Counts',
                NewWarningTab.complaints: 'Complaints',
                NewWarningTab.writeUps: 'Write Ups',
              },
              onTap: controller.setWarningTab,
            ),
            const SizedBox(height: 12),
            if (controller.warningTab.value == NewWarningTab.complaints)
              ...controller.complaints.map<Widget>(
                (e) => _ListCard(
                  title: e.title,
                  subtitle: '${e.site} · ${e.severity}\n${e.filedAt}',
                  color: e.unread ? NewUi.danger : NewUi.accent,
                  trailing: e.unread
                      ? 'NEW'
                      : e.acknowledged
                      ? 'ACK'
                      : null,
                  onTap: () => controller.openComplaint(e),
                ),
              )
            else
              ...items.map<Widget>(
                (e) => _ListCard(
                  title: e.title,
                  subtitle: '${e.time}\n${e.detail}',
                  color: e.unread ? NewUi.danger : NewUi.warning,
                  trailing: e.unread
                      ? 'NEW'
                      : e.acknowledged
                      ? 'ACK'
                      : null,
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NewActionButton(text: 'Close', onTap: Get.back),
            ),
          ],
        );
      }),
    );
  }
}

class NewComplaintDialog extends StatelessWidget {
  const NewComplaintDialog({
    super.key,
    required this.controller,
    required this.complaint,
  });

  final dynamic controller;
  final NewComplaintItem complaint;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.chat_bubble_outline_rounded,
      iconColor: NewUi.danger,
      title: complaint.title,
      subtitle: 'Filed by management',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              NewPill(
                text: complaint.site,
                icon: Icons.location_on_rounded,
                color: NewUi.accent,
              ),
              NewPill(
                text: complaint.severity,
                icon: Icons.priority_high_rounded,
                color: NewUi.danger,
              ),
              NewPill(
                text: complaint.filedAt,
                icon: Icons.schedule_rounded,
                color: NewUi.purple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _NoteBox(
            title: 'Complaint Details',
            body: complaint.detail,
            color: NewUi.danger,
          ),
          const SizedBox(height: 10),
          _NoteBox(
            title: 'Expected Action',
            body: complaint.expectedAction,
            color: NewUi.warning,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller.complaintNoteCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Officer Response',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: NewActionButton(
                  text: 'Close',
                  primary: false,
                  onTap: Get.back,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NewActionButton(
                  text: 'Submit',
                  color: NewUi.danger,
                  onTap: () => controller.acknowledgeComplaint(complaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NewNotificationsDialog extends StatelessWidget {
  const NewNotificationsDialog({super.key, required this.controller});

  final dynamic controller;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.notifications_rounded,
      iconColor: NewUi.warning,
      title: 'Notifications',
      subtitle: 'All alerts and reminders',
      child: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...controller.notifications.map<Widget>(
              (e) => _ListCard(
                title: e.title,
                subtitle: '${e.body}\n${e.timeText}',
                color: e.unread ? NewUi.warning : NewUi.accent,
                trailing: e.unread ? 'NEW' : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: NewActionButton(
                    text: 'Mark read',
                    primary: false,
                    color: NewUi.warning,
                    onTap: controller.markAllNotificationsRead,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NewActionButton(
                    text: 'Clear',
                    primary: false,
                    color: NewUi.danger,
                    onTap: controller.clearNotifications,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NewActionButton(
                text: 'Close',
                color: NewUi.warning,
                onTap: Get.back,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NewRemindersDialog extends StatelessWidget {
  const NewRemindersDialog({super.key, required this.controller});

  final dynamic controller;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.alarm_rounded,
      iconColor: NewUi.warning,
      title: 'Reminders',
      subtitle: 'Personal reminders',
      child: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SegmentTabs<NewReminderTab>(
              selected: controller.reminderTab.value,
              items: const {
                NewReminderTab.upcoming: 'Upcoming',
                NewReminderTab.all: 'All',
                NewReminderTab.completed: 'Completed',
              },
              onTap: controller.setReminderTab,
            ),
            const SizedBox(height: 12),
            ...controller.filteredReminders.map<Widget>(
              (e) => _ListCard(
                title: e.title,
                subtitle: '${e.dateText} · ${e.timeText}\n${e.repeat.name}',
                color: e.completed
                    ? NewUi.success
                    : e.fromManagement
                    ? NewUi.purple
                    : NewUi.warning,
                trailing: e.completed
                    ? 'DONE'
                    : e.fromManagement
                    ? 'MGMT'
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: NewActionButton(
                    text: 'New Reminder',
                    color: NewUi.warning,
                    icon: Icons.add_rounded,
                    onTap: controller.openReminderEditor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NewActionButton(
                    text: 'Close',
                    primary: false,
                    color: NewUi.warning,
                    onTap: Get.back,
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

class NewReminderEditorDialog extends StatelessWidget {
  const NewReminderEditorDialog({super.key, required this.controller});

  final dynamic controller;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.alarm_add_rounded,
      iconColor: NewUi.warning,
      title: 'New Reminder',
      subtitle: 'Set up your reminder',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller.reminderTitleCtrl,
            decoration: _input('Title'),
          ),
          const SizedBox(height: 10),
          Obx(
            () => DropdownButtonFormField<NewReminderRepeat>(
              initialValue: controller.selectedReminderRepeat.value,
              decoration: _input('Repeat'),
              items: NewReminderRepeat.values
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) controller.setReminderRepeat(v);
              },
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller.reminderNoteCtrl,
            maxLines: 3,
            decoration: _input('Note'),
          ),
          Obx(
            () => _SwitchRow(
              title: 'Auto Snooze',
              subtitle: 'Re-alert every 5 minutes if not dismissed',
              value: controller.reminderAutoSnooze.value,
              onChanged: controller.toggleReminderAutoSnooze,
            ),
          ),
          Obx(
            () => _SwitchRow(
              title: 'Critical Alert',
              subtitle: 'Bypasses Do Not Disturb and silent mode',
              value: controller.reminderCritical.value,
              onChanged: controller.toggleReminderCritical,
            ),
          ),
          Obx(
            () => _SwitchRow(
              title: 'Show on Calendar',
              subtitle: 'Display reminder in Calendar tab',
              value: controller.reminderShowCalendar.value,
              onChanged: controller.toggleReminderCalendar,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NewActionButton(
                  text: 'Cancel',
                  primary: false,
                  color: NewUi.warning,
                  onTap: Get.back,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NewActionButton(
                  text: 'Save Reminder',
                  color: NewUi.warning,
                  onTap: controller.saveReminder,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NewEditProfileDialog extends StatelessWidget {
  const NewEditProfileDialog({super.key, required this.controller});

  final dynamic controller;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.person_rounded,
      iconColor: NewUi.accent,
      title: 'Edit Profile',
      subtitle: 'Update your photo and details',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              gradient: NewUi.accentGradient(NewUi.accent),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: NewUi.accent.withAlpha(70), blurRadius: 20),
              ],
            ),
            child: Center(
              child: Text(
                controller.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NewActionButton(
                  text: 'Take Photo',
                  icon: Icons.photo_camera_rounded,
                  onTap: () => controller.showInfoText(
                    'Photo',
                    'Camera UI placeholder is ready.',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NewActionButton(
                  text: 'Choose',
                  primary: false,
                  icon: Icons.photo_library_rounded,
                  onTap: () => controller.showInfoText(
                    'Photo',
                    'Gallery UI placeholder is ready.',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller.profileNameCtrl,
            decoration: _input('Full Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller.profilePhoneCtrl,
            decoration: _input('Phone'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller.profileEmailCtrl,
            decoration: _input('Email'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: NewActionButton(
                  text: 'Cancel',
                  primary: false,
                  onTap: Get.back,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NewActionButton(
                  text: 'Save',
                  onTap: controller.saveProfile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NewTasksDialog extends StatelessWidget {
  const NewTasksDialog({super.key, required this.controller});

  final dynamic controller;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: Icons.task_alt_rounded,
      iconColor: NewUi.accent,
      title: 'Assigned Tasks',
      subtitle: 'Pending and completed',
      child: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SegmentTabs<bool>(
              selected: controller.taskOpenTab.value,
              items: const {true: 'Open', false: 'Done'},
              onTap: (v) => controller.taskOpenTab.value = v,
            ),
            const SizedBox(height: 12),
            ...controller.filteredTasks.map<Widget>(
              (e) => _ListCard(
                title: e.title,
                subtitle: '${e.dueText}\n${e.detail}',
                color: e.completed
                    ? NewUi.success
                    : e.priority == 'High'
                    ? NewUi.danger
                    : NewUi.accent,
                trailing: e.completed ? 'DONE' : e.priority,
                onTap: e.completed ? null : () => controller.completeTask(e),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: NewActionButton(text: 'Close', onTap: Get.back),
            ),
          ],
        ),
      ),
    );
  }
}

class NewActionFlowDialog extends StatelessWidget {
  const NewActionFlowDialog({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: 'UI flow ready',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NoteBox(title: title, body: body, color: color),
          const SizedBox(height: 12),
          NewGlassCard(
            padding: const EdgeInsets.all(12),
            highlightColor: color,
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: color),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Backend API can be connected later without changing this UI structure.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: NewActionButton(
              text: 'Close',
              color: color,
              onTap: Get.back,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? const Color(0xFFF5F7FB) : const Color(0xFF172033);
    final bodyColor = dark ? const Color(0xFFAEBBCB) : const Color(0xFF667085);
    return Dialog(
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 720),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                border: Border.all(
                  color: dark
                      ? const Color(0xFF40526A)
                      : const Color(0xFFC9D8EA),
                  width: 1.2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? const [
                          Color(0xFF1B2738),
                          Color(0xFF172233),
                          Color(0xFF121D2D),
                        ]
                      : const [
                          Color(0xFFFFFFFF),
                          Color(0xFFF9FBFE),
                          Color(0xFFF1F5FA),
                        ],
                  stops: const [0, .52, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(dark ? 70 : 24),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: iconColor.withAlpha(dark ? 34 : 18),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: iconColor.withAlpha(dark ? 92 : 66),
                          ),
                        ),
                        child: Icon(icon, color: iconColor, size: 30),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    child,
                  ],
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: Get.back,
                  customBorder: const CircleBorder(),
                  child: Ink(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dark
                          ? Colors.white.withAlpha(12)
                          : const Color(0xFFF0F4F9),
                      border: Border.all(
                        color: dark
                            ? Colors.white.withAlpha(24)
                            : const Color(0xFFDCE4EE),
                      ),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: bodyColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentTabs<T> extends StatelessWidget {
  const _SegmentTabs({
    required this.selected,
    required this.items,
    required this.onTap,
  });

  final T selected;
  final Map<T, String> items;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items.entries.map((entry) {
        final active = selected == entry.key;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onTap(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? NewUi.accent.withAlpha(
                          Theme.of(context).brightness == Brightness.dark
                              ? 34
                              : 17,
                        )
                      : Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withAlpha(8)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active
                        ? NewUi.accent.withAlpha(65)
                        : Theme.of(context).dividerColor.withAlpha(70),
                  ),
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active
                        ? NewUi.accent
                        : Theme.of(context).textTheme.bodyMedium?.color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.subtitle,
    required this.color,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NewGlassCard(
        padding: const EdgeInsets.all(12),
        highlightColor: color,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: NewUi.accentGradient(color),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.circle, size: 8, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? NewUi.textMutedDark
                          : NewUi.textMutedLight,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) NewPill(text: trailing!, color: color),
          ],
        ),
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  const _NoteBox({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withAlpha(10)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(80)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        activeThumbColor: NewUi.accent,
      ),
    );
  }
}

InputDecoration _input(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );
}
