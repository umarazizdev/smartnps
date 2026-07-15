import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/push/officer_announcement_push.dart';

void main() {
  const validUuid = '123e4567-e89b-12d3-a456-426614174000';

  group('OfficerAnnouncementPush.tryParse', () {
    test('parses type = officer_announcement', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': validUuid,
      });
      expect(push, isNotNull);
      expect(push!.recipientPublicId, validUuid);
    });

    test('parses notification_type = officer_announcement', () {
      final push = OfficerAnnouncementPush.tryParse({
        'notification_type': 'officer_announcement',
        'recipient_public_id': validUuid,
      });
      expect(push, isNotNull);
      expect(push!.recipientPublicId, validUuid);
    });

    test('rejects missing recipient_public_id', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
      });
      expect(push, isNull);
    });

    test('rejects empty recipient_public_id', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': '   ',
      });
      expect(push, isNull);
    });

    test('rejects malformed UUID', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': 'not-a-uuid',
      });
      expect(push, isNull);
    });

    test('accepts a valid UUID', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': validUuid,
      });
      expect(push, isNotNull);
      expect(OfficerAnnouncementPush.isUuid(push!.recipientPublicId), isTrue);
    });

    test('parses an allowed destination URL', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': validUuid,
        'url': 'https://smartnps360.com/officer/dashboard',
      });
      expect(push, isNotNull);
      expect(
        push!.destinationUrl.toString(),
        'https://smartnps360.com/officer/dashboard',
      );
    });

    test('rejects an untrusted destination URL', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': validUuid,
        'url': 'https://evil.example/phish',
      });
      expect(push, isNotNull);
      expect(push!.destinationUrl, isNull);
    });

    test('ignores unrelated push types', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'shift_reminder',
        'notification_type': 'duty_alert',
        'recipient_public_id': validUuid,
        'url': 'https://smartnps360.com/officer/dashboard',
      });
      expect(push, isNull);
    });

    test('ignores title and body fields for parsing result', () {
      final push = OfficerAnnouncementPush.tryParse({
        'type': 'officer_announcement',
        'recipient_public_id': validUuid,
        'title': 'Secret title',
        'body': 'Secret body',
        'message': 'Secret message',
      });
      expect(push, isNotNull);
      // Model has no title/body fields; only recipient + optional URL.
      expect(push!.recipientPublicId, validUuid);
      expect(push.destinationUrl, isNull);
    });
  });

  group('OfficerAnnouncementPush redaction', () {
    test('redacts recipient UUID for debug logs', () {
      expect(
        OfficerAnnouncementPush.redactRecipientPublicId(validUuid),
        '123e4567…4000',
      );
    });
  });
}
