import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_context.dart';
import 'package:smartnps360/src/log_visit/flow/visit_patrol_round.dart';

void main() {
  group('VisitPatrolRound.listFromPayload', () {
    test('parses patrol_windows round tags from bridge payload', () {
      final rounds = VisitPatrolRound.listFromPayload({
        'round_tag': 'Interior Rounds',
        'rounds_required': 4,
        'site_patrol_window_id': 287,
        'patrol_windows': [
          {
            'site_patrol_window_id': 287,
            'round_tag': 'Interior Rounds',
            'rounds_required': 4,
            'time_start': '09:00:00',
            'time_end': '21:00:00',
          },
          {
            'site_patrol_window_id': 288,
            'round_tag': 'Exterior',
            'rounds_required': 2,
            'time_start': '09:00:00',
            'time_end': '21:00:00',
          },
        ],
      });

      expect(rounds, hasLength(2));
      expect(rounds[0].roundTag, 'Interior Rounds');
      expect(rounds[0].sitePatrolWindowId, 287);
      expect(rounds[0].roundsRequired, 4);
      expect(rounds[1].roundTag, 'Exterior');
      expect(rounds[1].sitePatrolWindowId, 288);
    });

    test('falls back to root round_tag when windows missing', () {
      final rounds = VisitPatrolRound.listFromPayload({
        'round_tag': 'Night Watch',
        'site_patrol_window_id': 99,
        'rounds_required': 1,
      });
      expect(rounds, hasLength(1));
      expect(rounds.single.roundTag, 'Night Watch');
      expect(rounds.single.sitePatrolWindowId, 99);
    });
  });

  test('VisitPatrolRoundColors assigns a different color per tag', () {
    final tags = [
      'Interior Rounds',
      'Exterior',
      'Parking',
      'Rooftop',
    ];
    final palette = VisitPatrolRoundColors.mapForTags(tags);
    expect(palette, hasLength(4));
    final colors = tags.map((t) => palette[t.toLowerCase()]).toSet();
    expect(colors, hasLength(4));
    expect(
      VisitPatrolRoundColors.forTag('Exterior', amongTags: tags),
      isNot(VisitPatrolRoundColors.forTag('Interior Rounds', amongTags: tags)),
    );
  });

  test('VisitPatrolContext enables round tags only with windows', () {
    final withWindows = VisitPatrolContext.fromJson({
      'region_id': 42,
      'site_id': 659,
      'uploadUrl': 'https://smartnps360.com/api/visits',
      'patrol_windows': [
        {'round_tag': 'Interior Rounds', 'site_patrol_window_id': 287},
        {'round_tag': 'Exterior', 'site_patrol_window_id': 288},
      ],
    });
    expect(withWindows?.supportsRoundTags, isTrue);
    expect(withWindows?.patrolWindows, hasLength(2));

    final withoutWindows = VisitPatrolContext.fromJson({
      'region_id': 42,
      'site_id': 659,
      'uploadUrl': 'https://smartnps360.com/api/visits',
    });
    expect(withoutWindows?.supportsRoundTags, isFalse);

    final onsite = VisitPatrolContext.fromJson({
      'region_id': 42,
      'site_id': 659,
      'uploadUrl': 'https://smartnps360.com/api/onsite-patrol/visits',
      'patrol_windows': [
        {'round_tag': 'Interior Rounds'},
      ],
    });
    expect(onsite?.supportsRoundTags, isFalse);
  });
}
