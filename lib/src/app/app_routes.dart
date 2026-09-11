import '../debug/debug_env_config.dart';

class AppRoutes {
  AppRoutes._();

  static const visitVideoPreview = '/visit-video-preview';
  static const visitVideoRecorder = '/visit-video-recorder';
  static const captureReview = '/capture-review';
  static const visitPhotoViewer = '/visit-photo-viewer';
  static const visitVideoPlayer = '/visit-video-player';
  static const visitCheckpoint = '/visit-checkpoint';

  static String get webBaseUrl => DebugEnvConfig.instance.webBaseUrl;

  static String get webLoginUrl {
    final base = webBaseUrl;
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  static String get webSignupUrl => '${webBaseUrl}officer/register';
  static String get webDashboardUrl => '${webBaseUrl}officer/dashboard';
  static String get webShiftLogUrl => '${webBaseUrl}officer/shift-log';
  static String get webTimesheetUrl => '${webBaseUrl}officer/timesheet/monthly';
  static String get webProfileUrl => '${webBaseUrl}officer/profile';
  static String get defaultPushUrl => webDashboardUrl;

  static const bottomTabWebPaths = <String>[
    '/officer/dashboard',
    '/officer/shift-log',
    '/officer/timesheet/monthly',
    '/officer/profile',
  ];

  static const bottomBarWebPaths = <String>[
    '/officer/dashboard',
    '/officer/timesheet/monthly',
    '/officer/profile',
  ];
}
