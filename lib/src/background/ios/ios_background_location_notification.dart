import '../location/location_sharing_status_notification.dart';

class IosBackgroundLocationNotification {
  IosBackgroundLocationNotification._();

  static const int notificationId =
      LocationSharingStatusNotification.sharingNotificationId;
  static const String title = LocationSharingStatusNotification.iosAppTitle;
  static const String body = LocationSharingStatusNotification.sharingBody;

  static Future<void> show() => LocationSharingStatusNotification.showSharing();

  static Future<void> dismiss() =>
      LocationSharingStatusNotification.dismissSharing();
}
