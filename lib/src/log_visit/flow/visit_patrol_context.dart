import 'dart:math';

import '../../api/api_urls.dart';
import 'visit_checkpoint.dart';
import 'visit_flow_kind.dart';
import 'visit_patrol_round.dart';

class VisitPatrolContext {
  const VisitPatrolContext({
    this.clientDraftId,
    this.regionId,
    this.siteId,
    this.regionName,
    this.siteName,
    this.scheduleId,
    this.sitePatrolWindowId,
    this.requestId,
    this.siteLatitude,
    this.siteLongitude,
    this.uploadUrl,
    this.minimumPhotos,
    this.visitType,
    this.siteCheckTimeSheetId,
    this.reportContextId,
    this.reportContextIssuedAt,
    this.timeSheetId,
    this.patrolWindows = const <VisitPatrolRound>[],
    this.checkpoints = const <VisitCheckpoint>[],
  });

  final String? clientDraftId;
  final int? regionId;
  final int? siteId;
  final String? regionName;
  final String? siteName;
  final int? scheduleId;
  final int? sitePatrolWindowId;
  final String? requestId;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? uploadUrl;
  final int? minimumPhotos;
  final String? visitType;
  final int? siteCheckTimeSheetId;
  /// Server-issued authorization for issue/incident uploads.
  final String? reportContextId;
  /// Context `issued_at`; use as immutable draft `started_at`.
  final DateTime? reportContextIssuedAt;
  /// Timesheet from report-context (or bridge), when available.
  final int? timeSheetId;
  final List<VisitPatrolRound> patrolWindows;
  final List<VisitCheckpoint> checkpoints;

  bool get hasReportContext {
    final id = reportContextId?.trim();
    return id != null && id.isNotEmpty;
  }

  bool get hasSiteOrRegionId => regionId != null || siteId != null;
  bool get hasCheckpoints => checkpoints.isNotEmpty;
  bool get hasMinimumPhotoRequirement =>
      minimumPhotos != null && minimumPhotos! > 0;
  bool get isSiteCheck => flowKind == VisitFlowKind.siteCheck;

  VisitFlowKind get flowKind => VisitFlowKind.fromVisitType(visitType);

  bool get isIssueReport => flowKind == VisitFlowKind.issueReport;

  bool get isIncidentReport => flowKind == VisitFlowKind.incidentReport;

  bool get isStructuredReport => flowKind.isStructuredReport;

  bool get isOnsitePatrol {
    final url = uploadUrl?.trim().toLowerCase() ?? '';
    if (url.isEmpty) return false;
    final onsite = ApiUrls.onsitePatrolVisitsUploadUrl.trim().toLowerCase();
    return url.contains('onsite-patrol') ||
        (onsite.isNotEmpty && url == onsite);
  }

  bool get supportsRoundTags =>
      !isOnsitePatrol &&
      !isSiteCheck &&
      !isStructuredReport &&
      patrolWindows.isNotEmpty;

  VisitPatrolRound? roundByTag(String? tag) {
    final needle = tag?.trim().toLowerCase();
    if (needle == null || needle.isEmpty) return null;
    for (final round in patrolWindows) {
      if (round.roundTag.trim().toLowerCase() == needle) return round;
    }
    return null;
  }

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

  bool isSameVisitIdentityAs(VisitPatrolContext? other) {
    if (other == null) return false;
    if (!isSameSiteAs(other)) return false;
    final thisType = visitType?.trim().toLowerCase();
    final otherType = other.visitType?.trim().toLowerCase();
    return scheduleId == other.scheduleId &&
        sitePatrolWindowId == other.sitePatrolWindowId &&
        requestId == other.requestId &&
        siteCheckTimeSheetId == other.siteCheckTimeSheetId &&
        thisType == otherType;
  }

  static String resolveClientDraftIdForMerge({
    required bool sameSite,
    required VisitPatrolContext? current,
    required VisitPatrolContext incoming,
    required VisitPatrolContext mergedVisit,
    VisitPatrolContext? targetSnapshot,
  }) {
    final currentId = current?.clientDraftId?.trim();
    final incomingId = incoming.clientDraftId?.trim();
    final snapshotId = targetSnapshot?.clientDraftId?.trim();

    // Issue/incident drafts ignore changing bridge request_id so reopen keeps
    // the same client_draft_id for the site + report type.
    if (mergedVisit.isStructuredReport) {
      if (sameSite &&
          current != null &&
          current.isStructuredReport &&
          current.flowKind == mergedVisit.flowKind &&
          currentId != null &&
          currentId.isNotEmpty) {
        return currentId;
      }
      if (snapshotId != null &&
          snapshotId.isNotEmpty &&
          targetSnapshot != null &&
          targetSnapshot.isStructuredReport &&
          targetSnapshot.flowKind == mergedVisit.flowKind &&
          targetSnapshot.isSameSiteAs(mergedVisit)) {
        return snapshotId;
      }
    }

    final sameVisit =
        sameSite &&
        (current == null || current.isSameVisitIdentityAs(mergedVisit));

    if (sameVisit) {
      if (currentId != null && currentId.isNotEmpty) return currentId;
      if (snapshotId != null && snapshotId.isNotEmpty) return snapshotId;
      if (incomingId != null && incomingId.isNotEmpty) return incomingId;
      return generateClientDraftId();
    }

    if (snapshotId != null &&
        snapshotId.isNotEmpty &&
        targetSnapshot != null &&
        targetSnapshot.isSameVisitIdentityAs(mergedVisit)) {
      return snapshotId;
    }

    if (incomingId != null &&
        incomingId.isNotEmpty &&
        (currentId == null || incomingId != currentId)) {
      return incomingId;
    }

    return generateClientDraftId();
  }

  VisitCheckpoint? checkpointById(int id) {
    for (final checkpoint in checkpoints) {
      if (checkpoint.id == id) return checkpoint;
    }
    return null;
  }

  VisitPatrolContext copyWith({
    String? clientDraftId,
    int? regionId,
    int? siteId,
    String? regionName,
    String? siteName,
    int? scheduleId,
    int? sitePatrolWindowId,
    String? requestId,
    double? siteLatitude,
    double? siteLongitude,
    String? uploadUrl,
    int? minimumPhotos,
    String? visitType,
    int? siteCheckTimeSheetId,
    String? reportContextId,
    DateTime? reportContextIssuedAt,
    int? timeSheetId,
    List<VisitPatrolRound>? patrolWindows,
    List<VisitCheckpoint>? checkpoints,
    bool clearClientDraftId = false,
    bool clearRegionId = false,
    bool clearSiteId = false,
    bool clearRegionName = false,
    bool clearSiteName = false,
    bool clearScheduleId = false,
    bool clearSitePatrolWindowId = false,
    bool clearRequestId = false,
    bool clearSiteLatitude = false,
    bool clearSiteLongitude = false,
    bool clearUploadUrl = false,
    bool clearMinimumPhotos = false,
    bool clearVisitType = false,
    bool clearSiteCheckTimeSheetId = false,
    bool clearReportContextId = false,
    bool clearReportContextIssuedAt = false,
    bool clearTimeSheetId = false,
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
      sitePatrolWindowId: clearSitePatrolWindowId
          ? null
          : (sitePatrolWindowId ?? this.sitePatrolWindowId),
      requestId: clearRequestId ? null : (requestId ?? this.requestId),
      siteLatitude: clearSiteLatitude
          ? null
          : (siteLatitude ?? this.siteLatitude),
      siteLongitude: clearSiteLongitude
          ? null
          : (siteLongitude ?? this.siteLongitude),
      uploadUrl: clearUploadUrl ? null : (uploadUrl ?? this.uploadUrl),
      minimumPhotos: clearMinimumPhotos
          ? null
          : (minimumPhotos ?? this.minimumPhotos),
      visitType: clearVisitType ? null : (visitType ?? this.visitType),
      siteCheckTimeSheetId: clearSiteCheckTimeSheetId
          ? null
          : (siteCheckTimeSheetId ?? this.siteCheckTimeSheetId),
      reportContextId: clearReportContextId
          ? null
          : (reportContextId ?? this.reportContextId),
      reportContextIssuedAt: clearReportContextIssuedAt
          ? null
          : (reportContextIssuedAt ?? this.reportContextIssuedAt),
      timeSheetId: clearTimeSheetId ? null : (timeSheetId ?? this.timeSheetId),
      patrolWindows: patrolWindows ?? this.patrolWindows,
      checkpoints: checkpoints ?? this.checkpoints,
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
      'sitePatrolWindowId': sitePatrolWindowId,
      'requestId': requestId,
      'siteLatitude': siteLatitude,
      'siteLongitude': siteLongitude,
      'uploadUrl': uploadUrl,
      if (minimumPhotos != null) 'minimumPhotos': minimumPhotos,
      if (visitType != null) 'visitType': visitType,
      if (siteCheckTimeSheetId != null)
        'siteCheckTimeSheetId': siteCheckTimeSheetId,
      if (reportContextId != null) 'reportContextId': reportContextId,
      if (reportContextIssuedAt != null)
        'reportContextIssuedAt': reportContextIssuedAt!.toUtc().toIso8601String(),
      if (timeSheetId != null) 'timeSheetId': timeSheetId,
      'patrolWindows': patrolWindows.map((e) => e.toJson()).toList(),
      'checkpoints': checkpoints.map((e) => e.toJson()).toList(),
    };
  }

  Map<String, dynamic> toUploadMetaFields({Object? officerId}) {
    return <String, dynamic>{
      if (clientDraftId != null && clientDraftId!.isNotEmpty)
        'client_draft_id': clientDraftId,
      'officer_id': ?officerId,
      if (regionId != null) 'region_id': regionId,
      if (siteId != null) 'site_id': siteId,
      if (regionName != null && regionName!.trim().isNotEmpty)
        'region_name': regionName!.trim(),
      if (siteName != null && siteName!.trim().isNotEmpty)
        'site_name': siteName!.trim(),
      if (scheduleId != null) 'schedule_id': scheduleId,
      if (sitePatrolWindowId != null)
        'site_patrol_window_id': sitePatrolWindowId,
      if (visitType != null && visitType!.trim().isNotEmpty)
        'visit_type': visitType!.trim(),
      if (siteCheckTimeSheetId != null)
        'site_check_time_sheet_id': siteCheckTimeSheetId,
      if (hasReportContext) 'report_context_id': reportContextId!.trim(),
    };
  }

  static VisitPatrolContext? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final nestedSite = _asMap(json['site']);
    final nestedRegion = _asMap(json['region']);
    final nestedPatrol = _asMap(json['patrol']);

    final clientDraftId = _string(
      json['clientDraftId'] ?? json['client_draft_id'],
    );
    final regionId = _int(
      json['regionId'] ??
          json['region_id'] ??
          nestedPatrol?['region_id'] ??
          nestedRegion?['id'],
    );
    final siteId = _int(
      json['siteId'] ??
          json['site_id'] ??
          nestedPatrol?['site_id'] ??
          nestedSite?['id'],
    );
    final regionName = _string(
      json['regionName'] ??
          json['region_name'] ??
          nestedPatrol?['region_name'] ??
          nestedRegion?['name'],
    );
    final siteName = _string(
      json['siteName'] ??
          json['site_name'] ??
          nestedPatrol?['site_name'] ??
          nestedSite?['name'],
    );
    final scheduleId = _int(
      json['scheduleId'] ?? json['schedule_id'] ?? nestedPatrol?['schedule_id'],
    );
    final sitePatrolWindowId = _int(
      json['sitePatrolWindowId'] ??
          json['site_patrol_window_id'] ??
          nestedPatrol?['site_patrol_window_id'],
    );
    final requestId = _string(json['requestId'] ?? json['request_id']);
    final siteLatitude = _double(
      json['siteLatitude'] ?? json['site_latitude'] ?? nestedSite?['latitude'],
    );
    final siteLongitude = _double(
      json['siteLongitude'] ??
          json['site_longitude'] ??
          nestedSite?['longitude'],
    );
    final uploadUrl = _string(
      json['api_upload_url'] ??
          json['upload_url'] ??
          json['uploadUrl'] ??
          json['apiUploadUrl'],
    );
    final minimumPhotos = _int(
      json['minimumPhotos'] ??
          json['minimum_photos'] ??
          nestedSite?['minimum_photos'] ??
          nestedSite?['minimumPhotos'],
    );
    final visitType = _string(json['visitType'] ?? json['visit_type']);
    final siteCheckTimeSheetId = _int(
      json['siteCheckTimeSheetId'] ??
          json['site_check_time_sheet_id'] ??
          nestedPatrol?['site_check_time_sheet_id'],
    );
    final reportContextId = _string(
      json['reportContextId'] ?? json['report_context_id'],
    );
    DateTime? reportContextIssuedAt;
    final issuedRaw =
        json['reportContextIssuedAt'] ??
        json['report_context_issued_at'] ??
        json['issued_at'] ??
        json['issuedAt'];
    if (issuedRaw is String && issuedRaw.trim().isNotEmpty) {
      reportContextIssuedAt = DateTime.tryParse(issuedRaw.trim());
    }
    final timeSheetId = _int(
      json['timeSheetId'] ??
          json['time_sheet_id'] ??
          nestedPatrol?['time_sheet_id'],
    );
    final patrolWindows = VisitPatrolRound.listFromPayload(json);
    final checkpoints = VisitCheckpoint.listFromJson(
      json['checkpoints'],
      baseUrl: uploadUrl,
    );

    if (clientDraftId == null &&
        regionId == null &&
        siteId == null &&
        regionName == null &&
        siteName == null &&
        scheduleId == null &&
        sitePatrolWindowId == null &&
        requestId == null &&
        minimumPhotos == null &&
        visitType == null &&
        siteCheckTimeSheetId == null &&
        reportContextId == null &&
        reportContextIssuedAt == null &&
        timeSheetId == null &&
        patrolWindows.isEmpty &&
        checkpoints.isEmpty) {
      return null;
    }

    return VisitPatrolContext(
      clientDraftId: clientDraftId,
      regionId: regionId,
      siteId: siteId,
      regionName: regionName,
      siteName: siteName,
      scheduleId: scheduleId,
      sitePatrolWindowId: sitePatrolWindowId,
      requestId: requestId,
      siteLatitude: siteLatitude,
      siteLongitude: siteLongitude,
      uploadUrl: uploadUrl,
      minimumPhotos: minimumPhotos,
      visitType: visitType,
      siteCheckTimeSheetId: siteCheckTimeSheetId,
      reportContextId: reportContextId,
      reportContextIssuedAt: reportContextIssuedAt,
      timeSheetId: timeSheetId,
      patrolWindows: patrolWindows,
      checkpoints: checkpoints,
    );
  }

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

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
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

  static double? _double(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }
}
