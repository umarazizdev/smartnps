# bloc

A new Flutter project.

## Push notifications (Firebase Cloud Messaging)

Dependencies used:
- `firebase_core`
- `firebase_messaging`
- `flutter_local_notifications` (shows notifications while app is foreground)

Android:
- `android/app/google-services.json` present
- `android/app/build.gradle.kts` applies `com.google.gms.google-services`
- Android 13+: user must grant notification permission

iOS:
- `ios/Runner/GoogleService-Info.plist` present
- In Xcode (`ios/Runner.xcworkspace`):
  - Add capability: **Push Notifications**
  - Add capability: **Background Modes** → enable **Remote notifications**
  - Configure APNs key/cert in Firebase console for your iOS bundle id

Code entry:
- Init in `lib/main.dart`
- Service in `lib/src/push/push_notification_service.dart`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
