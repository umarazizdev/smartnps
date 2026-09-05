import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/background/duty/duty_heartbeat_client.dart';

void main() {
  group('DutyHeartbeatClient.parseDutyStatus', () {
    test('parses plain and nested duty values', () {
      expect(DutyHeartbeatClient.parseDutyStatus('on_duty'), 'on_duty');
      expect(DutyHeartbeatClient.parseDutyStatus('OFF-DUTY'), 'off_duty');
      expect(
        DutyHeartbeatClient.parseDutyStatus({'status': 'onDuty'}),
        'on_duty',
      );
      expect(
        DutyHeartbeatClient.parseDutyStatus({
          'data': {'duty_status': 'off_duty'},
        }),
        'off_duty',
      );
    });

    test('returns null for unknown payloads', () {
      expect(DutyHeartbeatClient.parseDutyStatus(null), isNull);
      expect(DutyHeartbeatClient.parseDutyStatus({'ok': true}), isNull);
    });
  });

  group('DutyHeartbeatClient.parseHeartbeat break gating', () {
    test('keeps tracking on paid break', () {
      final payload = DutyHeartbeatClient.parseHeartbeat({
        'status': 'on-duty',
        'working_status': 'on_break',
        'break_type': 'paid',
        'allowed_break_minutes': 45,
      });
      expect(payload?.isOnDuty, isTrue);
      expect(payload?.isOnBreak, isTrue);
      expect(payload?.isUnpaidBreak, isFalse);
      expect(payload?.allowsLocationTracking, isTrue);
      expect(payload?.breakMinutesOrDefault, 45);
    });

    test('pauses tracking on unpaid break', () {
      final payload = DutyHeartbeatClient.parseHeartbeat({
        'status': 'on-duty',
        'working_status': 'on_break',
        'break_type': 'unpaid',
        'allowed_break_minutes': 30,
      });
      expect(payload?.isOnDuty, isTrue);
      expect(payload?.isUnpaidBreak, isTrue);
      expect(payload?.allowsLocationTracking, isFalse);
    });

    test('uses break_paid false from JS bridge payload', () {
      final payload = DutyHeartbeatClient.parseAttendanceBridgePayload({
        'status': 'on_duty',
        'working_status': 'on_break',
        'break_type': 'unpaid',
        'allowed_break_minutes': 45,
        'break_paid': false,
      });
      expect(payload?.isUnpaidBreak, isTrue);
      expect(payload?.allowsLocationTracking, isFalse);
      expect(payload?.breakMinutesOrDefault, 45);
    });

    test('allows tracking while working', () {
      final payload = DutyHeartbeatClient.parseHeartbeat({
        'status': 'on-duty',
        'working_status': 'working',
        'break_type': 'unpaid',
        'allowed_break_minutes': 45,
      });
      expect(payload?.isOnBreak, isFalse);
      expect(payload?.isUnpaidBreak, isFalse);
      expect(payload?.allowsLocationTracking, isTrue);
    });
  });
}
