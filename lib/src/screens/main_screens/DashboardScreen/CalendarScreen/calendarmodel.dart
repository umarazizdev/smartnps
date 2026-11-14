class CalendarMonthResponse {
  final String month;
  final DateRange range;
  final List<CalendarDay> data;

  CalendarMonthResponse({
    required this.month,
    required this.range,
    required this.data,
  });

  factory CalendarMonthResponse.fromJson(Map<String, dynamic> json) {
    return CalendarMonthResponse(
      month: json['month'] as String,
      range: DateRange.fromJson(json['range'] as Map<String, dynamic>),
      data: (json['data'] as List)
          .map((item) => CalendarDay.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DateRange {
  final String start;
  final String end;

  DateRange({required this.start, required this.end});

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(
      start: json['start'] as String,
      end: json['end'] as String,
    );
  }
}

class CalendarDay {
  final String date;
  final int count;
  final List<ShiftDay> shifts;

  CalendarDay({required this.date, required this.count, required this.shifts});

  factory CalendarDay.fromJson(Map<String, dynamic> json) {
    return CalendarDay(
      date: json['date'] as String,
      count: json['count'] as int,
      shifts: (json['shifts'] as List)
          .map((item) => ShiftDay.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ShiftDay {
  final int occurrenceId;
  final int seriesId;
  final int assignmentId;
  final String date;
  final String? workStatus;
  final String status;
  final String rawStatus;
  final String title;
  final String timeRange;
  final String startDateTime;
  final String endDateTime;
  final int unpaidBreakMinutes;
  final int paidBreakMinutes;
  final String? note;
  final int siteId;
  final String siteName;

  ShiftDay({
    required this.occurrenceId,
    required this.seriesId,
    required this.assignmentId,
    required this.date,
    this.workStatus,
    required this.status,
    required this.rawStatus,
    required this.title,
    required this.timeRange,
    required this.startDateTime,
    required this.endDateTime,
    required this.unpaidBreakMinutes,
    required this.paidBreakMinutes,
    this.note,
    required this.siteId,
    required this.siteName,
  });

  factory ShiftDay.fromJson(Map<String, dynamic> json) {
    return ShiftDay(
      seriesId: json['seriesId'] as int,
      occurrenceId: json['occurrenceId'] as int,
      assignmentId: json['assignmentId'] as int,
      date: json['date'] as String,
      workStatus: (json['work_status'] ?? json['workStatus']) as String?,
      status: json['status'] as String,
      rawStatus: json['rawStatus'] as String,
      title: json['title'] as String,
      timeRange: json['timeRange'] as String,
      startDateTime: json['startDateTime'] as String,
      endDateTime: json['endDateTime'] as String,
      unpaidBreakMinutes: (json['unpaidBreakMinutes'] as num?)?.toInt() ?? 0,
      paidBreakMinutes: (json['paidBreakMinutes'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
      siteId: json['siteId'] as int,
      siteName: json['siteName'] as String,
    );
  }
}
