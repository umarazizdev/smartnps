// ----------------- Add in state: model + data -----------------
class Assignment {
  final int id;
  final int index;
  final String site;
  final String siteAddress;
  final String roundType;
  final String frequency; // e.g. "Daily" / "Weekly"
  final int completed;
  final int total;
  final String status; // "Completed" / "Pending" / "Upcoming"
  final String startTime;
  final String endTime;
  final int scheduleId;
  final int siteId;

  Assignment({
    required this.id,
    required this.index,
    required this.site,
    required this.siteAddress,
    required this.roundType,
    required this.frequency,
    required this.completed,
    required this.total,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.scheduleId,
    required this.siteId,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    final scheduleId = json['schedule_id'] ?? 0;
    return Assignment(
      id: json['id'] ?? scheduleId,
      index: json['index'] ?? 0,
      site: json['site'] ?? '',
      siteAddress: json['siteAddress'] ?? '',
      roundType: json['roundType'] ?? '',
      frequency: json['frequency'] ?? '',
      completed: json['completed'] ?? 0,
      total: json['total'] ?? 0,
      status: json['status'] ?? '',
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
      scheduleId: json['schedule_id'] ?? 0,
      siteId: json['site_id'] ?? 0,
    );
  }
}
