class AppRoutes {
  AppRoutes._();

  static const visitVideoPreview = '/visit-video-preview';
  static const visitVideoRecorder = '/visit-video-recorder';
  static const captureReview = '/capture-review';
  static const visitPhotoViewer = '/visit-photo-viewer';
  static const visitVideoPlayer = '/visit-video-player';

  static const webBaseUrl = 'https://smartnps360.com/';

  static const webLoginUrl = 'https://smartnps360.com';
  static const webSignupUrl = '${webBaseUrl}officer/register';
  static const webDashboardUrl = '${webBaseUrl}officer/dashboard';
  static const webShiftLogUrl = '${webBaseUrl}officer/shift-log';
  static const webTimesheetUrl = '${webBaseUrl}officer/timesheet/monthly';
  static const webProfileUrl = '${webBaseUrl}officer/profile';
  static const defaultPushUrl = webDashboardUrl;

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
