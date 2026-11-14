import 'package:smartnps360/src/screens/utilities/sf_time.dart';

class DarModel {
  final int? id;
  final DateTime dateTime;
  final String siteName;
  final String shiftType;
  final String shift;
  final String schedule;
  final String status;
  final String? activityType;
  final String? seriousness;
  final String? description;
  final bool? policeNotified;
  final String? policeReportNumber;
  final bool? managerNotified;
  final String? managerName;
  final List<String> photos;
  final double? latitude;
  final double? longitude;

  // Detail-only / optional metadata
  final String? guardGroup;
  final String? unitNumber;
  final DateTime? createdAt;
  final String? createdBy;

  DarModel({
    this.id,
    required this.dateTime,
    required this.siteName,
    required this.shiftType,
    required this.shift,
    required this.schedule,
    required this.status,
    this.activityType,
    this.seriousness,
    this.description,
    this.policeNotified,
    this.policeReportNumber,
    this.managerNotified,
    this.managerName,
    required this.photos,
    this.latitude,
    this.longitude,
    this.guardGroup,
    this.unitNumber,
    this.createdAt,
    this.createdBy,
  });

  factory DarModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String? value) {
      try {
        return DateTime.parse(value ?? '');
      } catch (_) {
        return sfNow();
      }
    }

    bool? parseBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      if (v is num) return v == 1;
      final s = v.toString().trim().toLowerCase();
      if (s == '1' || s == 'true') return true;
      if (s == '0' || s == 'false') return false;
      return null;
    }

    // Photos
    final photos =
        (json['photos'] as List?)?.whereType<String>().toList() ?? [];

    // GPS (optional)
    final gps = json['gpsLocation'] as Map<String, dynamic>?;

    // Incident (optional)
    final incident = json['incident'] as Map<String, dynamic>?;

    // Prefer values from incident object, fallback to root keys if backend sometimes sends them there
    final policeNotifiedVal =
        incident?['policeNotified'] ??
        incident?['police_notified'] ??
        json['policeNotified'] ??
        json['police_notified'];
    final managerNotifiedVal =
        incident?['managerNotified'] ??
        incident?['manager_notified'] ??
        json['managerNotified'] ??
        json['manager_notified'];

    final policeReportNumberVal =
        incident?['policeReportNumber'] ??
        incident?['police_report_number'] ??
        json['policeReportNumber'] ??
        json['police_report_number'];
    final managerNameVal =
        incident?['managerName'] ??
        incident?['manager_name'] ??
        json['managerName'] ??
        json['manager_name'];

    return DarModel(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      dateTime: parseDate(json['dateTime']?.toString()),
      siteName: json['siteName']?.toString() ?? '',
      // Your sample response does NOT include these keys, so default to '' safely
      shiftType: json['shiftType']?.toString() ?? '',
      shift: json['shift']?.toString() ?? '',
      schedule: json['schedule']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      activityType: json['activityType']?.toString(),
      seriousness: json['seriousness']?.toString(),
      description: json['description']?.toString(),

      policeNotified: parseBool(policeNotifiedVal),
      policeReportNumber: policeReportNumberVal?.toString(),
      managerNotified: parseBool(managerNotifiedVal),
      managerName: managerNameVal?.toString(),

      photos: photos,
      latitude: (gps?['latitude'] as num?)?.toDouble(),
      longitude: (gps?['longitude'] as num?)?.toDouble(),

      guardGroup: json['guardGroup']?.toString(),
      unitNumber: json['unitNumber']?.toString(),
      createdAt: json['createdAt'] != null
          ? parseDate(json['createdAt']?.toString())
          : null,
      createdBy: json['createdBy']?.toString(),
    );
  }

  /// Helpful flag for UI
  bool get hasFullDetail =>
      description != null && description!.isNotEmpty && photos.isNotEmpty;
}
