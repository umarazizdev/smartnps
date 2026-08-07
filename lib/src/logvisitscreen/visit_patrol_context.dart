import 'dart:math';

/// Site/region context for a patrol draft, usually from the JS bridge
/// `openLogVisit` payload.
class VisitPatrolContext {
  const VisitPatrolContext({
    this.clientDraftId,
    this.regionId,
    this.siteId,
    this.regionName,
    this.siteName,
    this.scheduleId,
    this.requestId,
  });

  final String? clientDraftId;
  final int? regionId;
  final int? siteId;
  final String? regionName;
  final String? siteName;
  final int? scheduleId;
  final String? requestId;

  bool get hasSiteOrRegionId => regionId != null || siteId != null;

  String? get displayPlaceName {
    final site = siteName?.trim();
    if (site != null && site.isNotEmpty) return site;
    final region = regionName?.trim();
    if (region != null && region.isNotEmpty) return region;
    return null;
  }

  String? get locationSubtitle {
    final site = siteName?.trim();
    final region = regionName?.trim();
    if (site != null &&
        site.isNotEmpty &&
        region != null &&
        region.isNotEmpty) {
      return '$site · $region';
    }
    return displayPlaceName;
  }

  bool isSameSiteAs(VisitPatrolContext? other) {
    if (other == null) return false;
    if (siteId != null && other.siteId != null) {
      return siteId == other.siteId &&
          (regionId == null ||
              other.regionId == null ||
              regionId == other.regionId);
    }
    if (regionId != null &&
        other.regionId != null &&
        siteId == null &&
        other.siteId == null) {
      return regionId == other.regionId;
    }
    return false;
  }

  VisitPatrolContext copyWith({
    String? clientDraftId,
    int? regionId,
    int? siteId,
    String? regionName,
    String? siteName,
    int? scheduleId,
    String? requestId,
    bool clearClientDraftId = false,
    bool clearRegionId = false,
    bool clearSiteId = false,
    bool clearRegionName = false,
    bool clearSiteName = false,
    bool clearScheduleId = false,
    bool clearRequestId = false,
  }) {
    return VisitPatrolContext(
      clientDraftId: clearClientDraftId
          ? null
          : (clientDraftId ?? this.clientDraftId),
      regionId: clearRegionId ? null : (regionId ?? this.regionId),
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      regionName: clearRegionName ? null : (regionName ?? this.regionName),
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      scheduleId: clearScheduleId ? null : (scheduleId ?? this.scheduleId),
      requestId: clearRequestId ? null : (requestId ?? this.requestId),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'clientDraftId': clientDraftId,
      'regionId': regionId,
      'siteId': siteId,
      'regionName': regionName,
      'siteName': siteName,
      'scheduleId': scheduleId,
      'requestId': requestId,
    };
  }

  /// Payload keys match the upload API `meta` contract.
  Map<String, dynamic> toUploadMetaFields() {
    return <String, dynamic>{
      if (clientDraftId != null && clientDraftId!.isNotEmpty)
        'client_draft_id': clientDraftId,
      if (regionId != null) 'region_id': regionId,
      if (siteId != null) 'site_id': siteId,
      if (regionName != null && regionName!.trim().isNotEmpty)
        'region_name': regionName!.trim(),
      if (siteName != null && siteName!.trim().isNotEmpty)
        'site_name': siteName!.trim(),
      if (scheduleId != null) 'schedule_id': scheduleId,
    };
  }

  static VisitPatrolContext? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final clientDraftId = _string(json['clientDraftId'] ?? json['client_draft_id']);
    final regionId = _int(json['regionId'] ?? json['region_id']);
    final siteId = _int(json['siteId'] ?? json['site_id']);
    final regionName = _string(json['regionName'] ?? json['region_name']);
    final siteName = _string(json['siteName'] ?? json['site_name']);
    final scheduleId = _int(json['scheduleId'] ?? json['schedule_id']);
    final requestId = _string(json['requestId'] ?? json['request_id']);

    if (clientDraftId == null &&
        regionId == null &&
        siteId == null &&
        regionName == null &&
        siteName == null &&
        scheduleId == null &&
        requestId == null) {
      return null;
    }

    return VisitPatrolContext(
      clientDraftId: clientDraftId,
      regionId: regionId,
      siteId: siteId,
      regionName: regionName,
      siteName: siteName,
      scheduleId: scheduleId,
      requestId: requestId,
    );
  }

  /// Builds context from the JS bridge `openLogVisit` payload.
  static VisitPatrolContext? fromBridgePayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    return fromJson(payload);
  }

  static String generateClientDraftId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String h(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-'
        '${h(4)}${h(5)}-'
        '${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-'
        '${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}
