import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/background/location/location_sharing_status_notification.dart';

void main() {
  group('LocationSharingNotificationPolicy.shouldRepostSharing', () {
    test('posts when tracking is active and never marked shown', () {
      expect(
        LocationSharingNotificationPolicy.shouldRepostSharing(
          trackingActive: true,
          markedShown: false,
          deliveredInNotificationCenter: false,
        ),
        isTrue,
      );
    });

    test('reposts when marked shown but missing from Notification Center', () {
      expect(
        LocationSharingNotificationPolicy.shouldRepostSharing(
          trackingActive: true,
          markedShown: true,
          deliveredInNotificationCenter: false,
        ),
        isTrue,
      );
    });

    test('skips when already delivered while tracking', () {
      expect(
        LocationSharingNotificationPolicy.shouldRepostSharing(
          trackingActive: true,
          markedShown: true,
          deliveredInNotificationCenter: true,
        ),
        isFalse,
      );
    });

    test('never posts when tracking is inactive', () {
      expect(
        LocationSharingNotificationPolicy.shouldRepostSharing(
          trackingActive: false,
          markedShown: false,
          deliveredInNotificationCenter: false,
        ),
        isFalse,
      );
      expect(
        LocationSharingNotificationPolicy.shouldRepostSharing(
          trackingActive: false,
          markedShown: true,
          deliveredInNotificationCenter: false,
        ),
        isFalse,
      );
    });
  });
}
