import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/api/visit_upload_api.dart';
import 'package:smartnps360/src/log_visit/flow/visit_flow_kind.dart';

void main() {
  group('VisitUploadResult.parseHttp', () {
    test('accepts live log-visit patrol /api/visits 200 response', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 200,
        flowKind: VisitFlowKind.patrol,
        data: {
          'success': true,
          'message': 'Visit report uploaded successfully',
          'visit_id': 159906,
          'client_draft_id': '42f207ae-801f-476d-8de5-c33a039da2bd',
          'items_saved': 2,
        },
      );

      expect(result.success, isTrue);
      expect(result.visitId, 159906);
      expect(result.itemsSaved, 2);
      expect(result.clientDraftId, '42f207ae-801f-476d-8de5-c33a039da2bd');
      expect(result.statusCode, 200);
      expect(result.displayMessage, 'Visit report uploaded successfully');
    });

    test('accepts live onsite-patrol /api/onsite-patrol/visits 200 response', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 200,
        flowKind: VisitFlowKind.siteCheck,
        data: {
          'success': true,
          'message': 'Visit report uploaded successfully',
          'visit_id': 1836,
          'client_draft_id': '865b056b-472d-42f4-8628-4325e1c97cb5',
          'items_saved': 1,
        },
      );

      expect(result.success, isTrue);
      expect(result.visitId, 1836);
      expect(result.itemsSaved, 1);
      expect(result.displayMessage, 'Visit report uploaded successfully');
    });

    test('accepts live incident-reports 201 with itemsSaved=0', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 201,
        flowKind: VisitFlowKind.incidentReport,
        data: {
          'success': true,
          'message': 'Patrol round report uploaded successfully',
          'visit_id': 8,
          'client_draft_id': 'dbd4bb91-e73b-4be0-bad3-5f430ebd4f1a',
          'items_saved': 0,
        },
      );

      expect(result.success, isTrue);
      expect(result.visitId, 8);
      expect(result.itemsSaved, 0);
      expect(result.message, 'Patrol round report uploaded successfully');
      expect(result.displayMessage, 'Incident report uploaded successfully');
    });

    test('accepts live issue-reports 201 with itemsSaved=0', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 201,
        flowKind: VisitFlowKind.issueReport,
        data: {
          'success': true,
          'message': 'Issue report saved.',
          'visit_id': 7,
          'client_draft_id': '91eafe12-aaaa-bbbb-cccc-ddddeeeeffff',
          'items_saved': 0,
        },
      );

      expect(result.success, isTrue);
      expect(result.visitId, 7);
      expect(result.itemsSaved, 0);
      expect(result.displayMessage, 'Issue report uploaded successfully');
    });

    test('accepts camelCase visitId / itemsSaved keys', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 201,
        flowKind: VisitFlowKind.patrol,
        data: {
          'success': true,
          'visitId': 42,
          'itemsSaved': 3,
        },
      );

      expect(result.success, isTrue);
      expect(result.visitId, 42);
      expect(result.itemsSaved, 3);
    });

    test('rejects 2xx with success true but missing visit_id', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 200,
        data: {
          'success': true,
          'message': 'OK',
        },
      );

      expect(result.success, isFalse);
      expect(result.visitId, isNull);
      expect(result.message, 'OK');
    });

    test('rejects empty/HTML 2xx body that previously looked successful', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 200,
        data: '<html>gateway timeout page</html>',
      );

      expect(result.success, isFalse);
      expect(result.visitId, isNull);
      expect(result.message, 'Upload response missing visit_id.');
    });

    test('rejects success:false even when visit_id is present', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 200,
        data: {
          'success': false,
          'message': 'Validation failed',
          'visit_id': 9,
        },
      );

      expect(result.success, isFalse);
      expect(result.visitId, 9);
      expect(result.message, 'Validation failed');
    });

    test('parses JSON string bodies', () {
      final result = VisitUploadResult.parseHttp(
        statusCode: 201,
        flowKind: VisitFlowKind.patrol,
        data:
            '{"success":true,"visit_id":11,"client_draft_id":"d1","items_saved":2}',
      );

      expect(result.success, isTrue);
      expect(result.visitId, 11);
      expect(result.itemsSaved, 2);
      expect(result.displayMessage, 'Visit report uploaded successfully');
    });
  });
}
