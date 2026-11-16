enum NewOfficerStatus { standby, onShift, onBreak }

enum NewLiveStatusMode { idle, active, breakMode, standby }

enum NewTimerBlinkTier { none, yellow, orange, red }

enum NewArrivalStatus { pending, early, onTime, slight, late }

enum NewWarningTab { late, complaints, writeUps }

enum NewReminderTab { upcoming, all, completed }

enum NewReminderRepeat { once, daily, weekdays, weekly, monthly, custom }

enum NewCalendarView { today, tomorrow, week, month, year }

enum NewLogFilter {
  all,
  today,
  yesterday,
  week,
  month,
  range,
  officer,
  attention,
  incident,
}

class NewShortcutItem {
  const NewShortcutItem({
    required this.id,
    required this.title,
    required this.iconKey,
    required this.colorKey,
    this.enabled = true,
    this.hidden = false,
    this.badge,
  });

  final String id;
  final String title;
  final String iconKey;
  final String colorKey;
  final bool enabled;
  final bool hidden;
  final String? badge;
}

class NewStatItem {
  const NewStatItem({
    required this.title,
    required this.value,
    required this.meta,
    required this.iconKey,
    this.isWarning = false,
  });

  final String title;
  final String value;
  final String meta;
  final String iconKey;
  final bool isWarning;
}

class NewWarningItem {
  const NewWarningItem({
    required this.id,
    required this.title,
    required this.time,
    required this.detail,
    this.unread = false,
    this.acknowledged = false,
  });

  final String id;
  final String title;
  final String time;
  final String detail;
  final bool unread;
  final bool acknowledged;

  NewWarningItem copyWith({bool? unread, bool? acknowledged}) {
    return NewWarningItem(
      id: id,
      title: title,
      time: time,
      detail: detail,
      unread: unread ?? this.unread,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}

class NewComplaintItem {
  const NewComplaintItem({
    required this.id,
    required this.title,
    required this.site,
    required this.severity,
    required this.filedBy,
    required this.filedAt,
    required this.incidentDate,
    required this.detail,
    required this.expectedAction,
    this.unread = false,
    this.acknowledged = false,
    this.note = '',
  });

  final String id;
  final String title;
  final String site;
  final String severity;
  final String filedBy;
  final String filedAt;
  final String incidentDate;
  final String detail;
  final String expectedAction;
  final bool unread;
  final bool acknowledged;
  final String note;

  NewComplaintItem copyWith({bool? unread, bool? acknowledged, String? note}) {
    return NewComplaintItem(
      id: id,
      title: title,
      site: site,
      severity: severity,
      filedBy: filedBy,
      filedAt: filedAt,
      incidentDate: incidentDate,
      detail: detail,
      expectedAction: expectedAction,
      unread: unread ?? this.unread,
      acknowledged: acknowledged ?? this.acknowledged,
      note: note ?? this.note,
    );
  }
}

class NewReminderItem {
  const NewReminderItem({
    required this.id,
    required this.title,
    required this.dateText,
    required this.timeText,
    required this.repeat,
    this.note = '',
    this.completed = false,
    this.fromManagement = false,
    this.preAlarmMinutes = 0,
    this.sound = 'default',
    this.autoSnooze = false,
    this.critical = false,
    this.showOnCalendar = true,
  });

  final String id;
  final String title;
  final String dateText;
  final String timeText;
  final NewReminderRepeat repeat;
  final String note;
  final bool completed;
  final bool fromManagement;
  final int preAlarmMinutes;
  final String sound;
  final bool autoSnooze;
  final bool critical;
  final bool showOnCalendar;

  NewReminderItem copyWith({
    String? title,
    String? dateText,
    String? timeText,
    NewReminderRepeat? repeat,
    String? note,
    bool? completed,
    bool? fromManagement,
    int? preAlarmMinutes,
    String? sound,
    bool? autoSnooze,
    bool? critical,
    bool? showOnCalendar,
  }) {
    return NewReminderItem(
      id: id,
      title: title ?? this.title,
      dateText: dateText ?? this.dateText,
      timeText: timeText ?? this.timeText,
      repeat: repeat ?? this.repeat,
      note: note ?? this.note,
      completed: completed ?? this.completed,
      fromManagement: fromManagement ?? this.fromManagement,
      preAlarmMinutes: preAlarmMinutes ?? this.preAlarmMinutes,
      sound: sound ?? this.sound,
      autoSnooze: autoSnooze ?? this.autoSnooze,
      critical: critical ?? this.critical,
      showOnCalendar: showOnCalendar ?? this.showOnCalendar,
    );
  }
}

class NewCalendarShift {
  const NewCalendarShift({
    required this.id,
    required this.dateText,
    required this.fullDateText,
    required this.shiftName,
    required this.site,
    required this.timeRange,
    required this.role,
    required this.status,
    required this.breakMinutes,
    required this.breakPaid,
    this.firewatch = false,
    this.paidLunch = false,
  });

  final String id;
  final String dateText;
  final String fullDateText;
  final String shiftName;
  final String site;
  final String timeRange;
  final String role;
  final String status;
  final int breakMinutes;
  final bool breakPaid;
  final bool firewatch;
  final bool paidLunch;
}

class NewShiftLogEntry {
  const NewShiftLogEntry({
    required this.id,
    required this.dayText,
    required this.officerName,
    required this.timeText,
    required this.message,
    this.colorKey = 'blue',
    this.isMine = false,
    this.attention = false,
    this.incident = false,
    this.isAuto = false,
    this.autoType,
    this.attachmentName,
    this.locationText,
  });

  final String id;
  final String dayText;
  final String officerName;
  final String timeText;
  final String message;
  final String colorKey;
  final bool isMine;
  final bool attention;
  final bool incident;
  final bool isAuto;
  final String? autoType;
  final String? attachmentName;
  final String? locationText;
}

class NewChatThread {
  const NewChatThread({
    required this.id,
    required this.name,
    required this.role,
    required this.lastMessage,
    required this.timeText,
    this.unreadCount = 0,
    this.online = false,
  });

  final String id;
  final String name;
  final String role;
  final String lastMessage;
  final String timeText;
  final int unreadCount;
  final bool online;

  NewChatThread copyWith({
    String? lastMessage,
    String? timeText,
    int? unreadCount,
  }) {
    return NewChatThread(
      id: id,
      name: name,
      role: role,
      lastMessage: lastMessage ?? this.lastMessage,
      timeText: timeText ?? this.timeText,
      unreadCount: unreadCount ?? this.unreadCount,
      online: online,
    );
  }
}

class NewChatMessage {
  const NewChatMessage({
    required this.id,
    required this.threadId,
    required this.text,
    required this.timeText,
    this.mine = false,
    this.delivered = true,
    this.read = false,
    this.attachmentLabel,
    this.locationLabel,
  });

  final String id;
  final String threadId;
  final String text;
  final String timeText;
  final bool mine;
  final bool delivered;
  final bool read;
  final String? attachmentLabel;
  final String? locationLabel;
}

class NewTaskItem {
  const NewTaskItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.dueText,
    this.priority = 'Normal',
    this.completed = false,
  });

  final String id;
  final String title;
  final String detail;
  final String dueText;
  final String priority;
  final bool completed;

  NewTaskItem copyWith({bool? completed}) {
    return NewTaskItem(
      id: id,
      title: title,
      detail: detail,
      dueText: dueText,
      priority: priority,
      completed: completed ?? this.completed,
    );
  }
}

class NewNotificationItem {
  const NewNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeText,
    required this.dateText,
    required this.type,
    required this.source,
    this.site = '',
    this.shiftText = '',
    this.actionLabel = '',
    this.iconKey = 'notification',
    this.colorKey = 'blue',
    this.unread = false,
    this.critical = false,
  });

  final String id;
  final String title;
  final String body;
  final String timeText;
  final String dateText;
  final String type;
  final String source;
  final String site;
  final String shiftText;
  final String actionLabel;
  final String iconKey;
  final String colorKey;
  final bool unread;
  final bool critical;

  NewNotificationItem copyWith({bool? unread}) {
    return NewNotificationItem(
      id: id,
      title: title,
      body: body,
      timeText: timeText,
      dateText: dateText,
      type: type,
      source: source,
      site: site,
      shiftText: shiftText,
      actionLabel: actionLabel,
      iconKey: iconKey,
      colorKey: colorKey,
      unread: unread ?? this.unread,
      critical: critical,
    );
  }
}
