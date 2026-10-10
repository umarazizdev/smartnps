import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/log_visit/flow/visit_flow_kind.dart';
import 'package:smartnps360/src/log_visit/flow/visit_media_draft_store.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';
import 'package:smartnps360/src/log_visit/flow/visit_report_details.dart';
import 'package:smartnps360/src/log_visit/flow/visit_video_flow_controller.dart';

void main() {
  group('VisitFlowKind', () {
    test('parses issue and incident visit types', () {
      expect(
        VisitFlowKind.fromVisitType('issue_report'),
        VisitFlowKind.issueReport,
      );
      expect(
        VisitFlowKind.fromVisitType('incident_report'),
        VisitFlowKind.incidentReport,
      );
      expect(
        VisitFlowKind.fromVisitType('site_check'),
        VisitFlowKind.siteCheck,
      );
    });
  });

  group('VisitDraftKey', () {
    test('isolates issue and incident drafts from patrol', () {
      const patrol = VisitDraftKey(regionId: 1, siteId: 2);
      const issue = VisitDraftKey(
        regionId: 1,
        siteId: 2,
        flowKind: VisitFlowKind.issueReport,
      );
      const incident = VisitDraftKey(
        regionId: 1,
        siteId: 2,
        flowKind: VisitFlowKind.incidentReport,
      );

      expect(patrol.folderName, 'r1_s2');
      expect(issue.folderName, 'r1_s2_issue');
      expect(incident.folderName, 'r1_s2_incident');
      expect(patrol == issue, isFalse);
      expect(VisitDraftKey.tryParse('r1_s2_issue'), issue);
      expect(VisitDraftKey.tryParse('r1_s2_incident'), incident);
      expect(VisitDraftKey.tryParse('r1_s2'), patrol);
    });

    test('fromContext uses structured report suffixes', () {
      const issueContext = VisitPatrolContext(
        regionId: 3,
        siteId: 9,
        visitType: VisitFlowKind.issueReportVisitType,
      );
      final key = VisitDraftKey.fromContext(issueContext);
      expect(key.folderName, 'r3_s9_issue');
      expect(key.flowKind, VisitFlowKind.issueReport);
    });

    test('patrol and structured drafts on same site stay distinct', () {
      const patrolCtx = VisitPatrolContext(regionId: 1, siteId: 2);
      const issueCtx = VisitPatrolContext(
        regionId: 1,
        siteId: 2,
        visitType: VisitFlowKind.issueReportVisitType,
      );
      const incidentCtx = VisitPatrolContext(
        regionId: 1,
        siteId: 2,
        visitType: VisitFlowKind.incidentReportVisitType,
      );

      final patrolKey = VisitDraftKey.fromContext(patrolCtx);
      final issueKey = VisitDraftKey.fromContext(issueCtx);
      final incidentKey = VisitDraftKey.fromContext(incidentCtx);

      expect(patrolKey, isNot(issueKey));
      expect(patrolKey, isNot(incidentKey));
      expect(issueKey, isNot(incidentKey));
      expect(
        {
          patrolKey.folderName,
          issueKey.folderName,
          incidentKey.folderName,
        }.length,
        3,
      );
    });
  });

  group('VisitReportDetails', () {
    test('requires title and details for issue reports', () {
      const incomplete = VisitReportDetails(category: 'Suspicious Activity');
      expect(incomplete.isCompleteFor(VisitFlowKind.issueReport), isFalse);

      const complete = VisitReportDetails(
        title: 'Broken gate',
        category: 'Suspicious Activity',
        details: 'South entrance gate will not latch.',
      );
      expect(complete.isCompleteFor(VisitFlowKind.issueReport), isTrue);
    });

    test('requires custom type when category is Other', () {
      const details = VisitReportDetails(
        title: 'Odd case',
        category: 'Other',
        details: 'Something else',
      );
      expect(details.isCompleteFor(VisitFlowKind.issueReport), isFalse);

      const withCustom = VisitReportDetails(
        title: 'Odd case',
        category: 'Other',
        categoryOther: 'Custom issue',
        details: 'Something else',
      );
      expect(withCustom.isCompleteFor(VisitFlowKind.issueReport), isTrue);
      expect(withCustom.resolvedCategory, 'Custom issue');
    });

    test('builds flat upload meta for issue and incident', () {
      const issue = VisitReportDetails(
        title: 'Broken gate',
        category: 'Maintenance Issue',
        details: 'Needs repair',
        attentionToPropertyManagement: true,
        attentionToNps: false,
      );
      final issueMeta = issue.toUploadMeta(VisitFlowKind.issueReport);
      expect(issueMeta.containsKey('issue_report'), isFalse);
      expect(issueMeta['title'], 'Broken gate');
      expect(issueMeta['category'], 'Maintenance Issue');
      expect(issueMeta['details'], 'Needs repair');
      expect(issueMeta['attention_to_property_management'], 'yes');
      expect(issueMeta['attention_to_nps'], 'no');

      final occurred = DateTime.utc(2026, 10, 10, 1, 40);
      final incident = VisitReportDetails(
        title: 'Break-in',
        category: 'Security',
        description: 'North gate forced open',
        occurredAt: occurred,
        location: 'North gate',
        peopleInvolved: 'Two unknown males',
        attentionToNps: true,
      );
      final incidentMeta = incident.toUploadMeta(VisitFlowKind.incidentReport);
      expect(incidentMeta.containsKey('incident_report'), isFalse);
      expect(incidentMeta['title'], 'Break-in');
      expect(incidentMeta['location'], 'North gate');
      expect(incidentMeta['occurred_at'], occurred.toIso8601String());
      expect(incidentMeta['attention_to_property_management'], 'no');
      expect(incidentMeta['attention_to_nps'], 'yes');
    });
  });

  group('VisitPatrolContext draft id merge', () {
    test('keeps issue draft id across new bridge request_id', () {
      const snapshot = VisitPatrolContext(
        clientDraftId: 'kept-draft-id',
        regionId: 42,
        siteId: 659,
        visitType: VisitFlowKind.issueReportVisitType,
        requestId: 'old-request',
      );
      const incoming = VisitPatrolContext(
        regionId: 42,
        siteId: 659,
        visitType: VisitFlowKind.issueReportVisitType,
        requestId: 'new-request',
      );
      final id = VisitPatrolContext.resolveClientDraftIdForMerge(
        sameSite: false,
        current: null,
        incoming: incoming,
        mergedVisit: incoming,
        targetSnapshot: snapshot,
      );
      expect(id, 'kept-draft-id');
    });
  });

  group('VisitUploadMeta structured reports', () {
    test('flattens fields and omits patrol-only keys', () {
      final issued = DateTime.utc(2026, 10, 10, 8);
      final context = VisitPatrolContext(
        regionId: 42,
        siteId: 659,
        regionName: 'East Bay',
        siteName: "hamid's house",
        visitType: VisitFlowKind.issueReportVisitType,
        uploadUrl: 'https://smartnps360.com/api/issue-reports',
        scheduleId: 99,
        sitePatrolWindowId: 12,
        reportContextId: '1e4aa9e4-a2cc-44c4-8ef6-c36ba2b55f10',
        reportContextIssuedAt: issued,
      );
      const details = VisitReportDetails(
        title: 'Damaged entrance lock',
        category: 'Door / Gate / Lock Issue',
        details: 'East entrance lock damaged.',
        attentionToPropertyManagement: true,
      );
      final started = DateTime.utc(2026, 10, 10, 8);
      final submitted = DateTime.utc(2026, 10, 10, 8, 12);
      final meta = VisitUploadMeta.build(
        mediaItems: const [],
        context: context,
        startedAt: started,
        batchNote: const VisitBatchNote(enabled: true, textNote: 'batch'),
        generalNote: const VisitBatchNote(enabled: true, textNote: 'general'),
        reportDetails: details,
        clientDraftId: 'draft-42',
        submittedAt: submitted,
        officerId: '103',
      );

      expect(meta['client_draft_id'], 'draft-42');
      expect(meta['visit_type'], 'issue_report');
      expect(meta['site_id'], 659);
      expect(meta['region_id'], 42);
      expect(
        meta['report_context_id'],
        '1e4aa9e4-a2cc-44c4-8ef6-c36ba2b55f10',
      );
      expect(meta['title'], 'Damaged entrance lock');
      expect(meta['category'], 'Door / Gate / Lock Issue');
      expect(meta['details'], 'East entrance lock damaged.');
      expect(meta['attention_to_property_management'], 'yes');
      expect(meta['items'], isEmpty);
      expect(meta.containsKey('issue_report'), isFalse);
      expect(meta.containsKey('attention_needed'), isFalse);
      expect(meta.containsKey('general_note'), isFalse);
      expect(meta.containsKey('schedule_id'), isFalse);
      expect(meta.containsKey('site_patrol_window_id'), isFalse);
      expect(meta['started_at'], issued.toIso8601String());
      expect(meta['submitted_at'], submitted.toIso8601String());
    });
  });
}
