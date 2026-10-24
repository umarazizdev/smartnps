import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/api/visit_upload_api.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';

void main() {
  group('VisitPatrolContext.resolveClientDraftIdForMerge', () {
    const current = VisitPatrolContext(
      clientDraftId: 'draft-current',
      regionId: 7,
      siteId: 11,
      scheduleId: 100,
      sitePatrolWindowId: 1,
    );

    test('keeps current id when reopening same site and visit identity', () {
      const incoming = VisitPatrolContext(
        regionId: 7,
        siteId: 11,
        scheduleId: 100,
        sitePatrolWindowId: 1,
      );
      final id = VisitPatrolContext.resolveClientDraftIdForMerge(
        sameSite: true,
        current: current,
        incoming: incoming,
        mergedVisit: current,
      );
      expect(id, 'draft-current');
    });

    test('does not reuse current id when switching sites', () {
      const incoming = VisitPatrolContext(
        clientDraftId: 'draft-incoming-b',
        regionId: 7,
        siteId: 99,
        scheduleId: 200,
      );
      const merged = VisitPatrolContext(
        regionId: 7,
        siteId: 99,
        scheduleId: 200,
      );
      final id = VisitPatrolContext.resolveClientDraftIdForMerge(
        sameSite: false,
        current: current,
        incoming: incoming,
        mergedVisit: merged,
      );
      expect(id, 'draft-incoming-b');
      expect(id, isNot('draft-current'));
    });

    test('generates new id when site changes and incoming reuses current id', () {
      const incoming = VisitPatrolContext(
        clientDraftId: 'draft-current',
        regionId: 7,
        siteId: 99,
      );
      const merged = VisitPatrolContext(regionId: 7, siteId: 99);
      final id = VisitPatrolContext.resolveClientDraftIdForMerge(
        sameSite: false,
        current: current,
        incoming: incoming,
        mergedVisit: merged,
      );
      expect(id, isNot('draft-current'));
      expect(id, isNotEmpty);
    });

    test('rotates when same site but schedule / window identity changes', () {
      const incoming = VisitPatrolContext(
        regionId: 7,
        siteId: 11,
        scheduleId: 999,
        sitePatrolWindowId: 2,
      );
      const merged = VisitPatrolContext(
        regionId: 7,
        siteId: 11,
        scheduleId: 999,
        sitePatrolWindowId: 2,
      );
      final id = VisitPatrolContext.resolveClientDraftIdForMerge(
        sameSite: true,
        current: current,
        incoming: incoming,
        mergedVisit: merged,
      );
      expect(id, isNot('draft-current'));
    });

    test('keeps target snapshot id when resuming matching pending draft', () {
      const snapshot = VisitPatrolContext(
        clientDraftId: 'draft-snapshot-b',
        regionId: 7,
        siteId: 99,
        scheduleId: 200,
      );
      const incoming = VisitPatrolContext(
        regionId: 7,
        siteId: 99,
        scheduleId: 200,
      );
      final id = VisitPatrolContext.resolveClientDraftIdForMerge(
        sameSite: false,
        current: current,
        incoming: incoming,
        mergedVisit: snapshot,
        targetSnapshot: snapshot,
      );
      expect(id, 'draft-snapshot-b');
    });
  });

  group('VisitUploadResult.isClientDraftReuseError', () {
    test('detects structured client_draft_id validation error', () {
      const result = VisitUploadResult(
        success: false,
        message: 'Validation failed',
        errors: {
          'client_draft_id': [
            'This draft was already used for a different visit.',
          ],
        },
      );
      expect(result.isClientDraftReuseError, isTrue);
    });

    test('is false for unrelated validation errors', () {
      const result = VisitUploadResult(
        success: false,
        message: 'Validation failed',
        errors: {
          'site_id': ['The selected site is invalid.'],
        },
      );
      expect(result.isClientDraftReuseError, isFalse);
    });
  });

  group('VisitPatrolContext.isSameVisitIdentityAs', () {
    test('same site different schedule is not same visit identity', () {
      const a = VisitPatrolContext(
        regionId: 1,
        siteId: 2,
        scheduleId: 10,
      );
      const b = VisitPatrolContext(
        regionId: 1,
        siteId: 2,
        scheduleId: 11,
      );
      expect(a.isSameSiteAs(b), isTrue);
      expect(a.isSameVisitIdentityAs(b), isFalse);
    });
  });
}
