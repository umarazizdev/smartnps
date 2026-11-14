class ApiURL {
  // base
  static const baseUrl = 'https://development.smartnps360.com/api/';
  // auth
  static const login = 'auth/login';
  static const register = 'auth/register';
  static const registerValidateStep1 = 'auth/register/validate-step-1';
  static const registerValidateStep2 = 'auth/register/validate-step-2';
  static const forgotPassword = 'auth/forgot-password';
  static const logout = 'auth/logout';

  //user
  static const profile = 'users/profile';
  static const updateProfile = 'users/profile';

  // Dashboard / Assignments / Schedules
  static const assignments = 'scheduledPatrols';
  static const schedulesMonthly = 'schedules/monthly';
  static const schedulesResolve = 'schedules/resolve';
  static const logVisit = 'visits/log';

  // Locations & shifts
  static const regions = 'locations/regions';
  static const shifts = 'shifts';

  // Time Tracker
  static const timeTrackerClockIn = 'time-tracker/clock-in';
  static const timeTrackerBreakStart = 'time-tracker/{sessionId}/break-start';
  static const timeTrackerBreakEnd = 'time-tracker/{sessionId}/break-end';
  static const timeTrackerClockOut = 'time-tracker/{sessionId}/clock-out';
  static const timeTrackerCurrentSession = 'current-status';

  // DAR (Daily Activity Report)
  static const createDar = 'dars/create';
  static const getDars = 'dars';
  static const searchDars = 'dars/search';
  static const getDarDetail = 'dars/{darId}';

  // Dropdowns / lookups
  static const activityTypes = 'activity-types';
  static const sites = 'sites';

  // Timesheets
  static const timesheetsMonthly = 'timesheets/monthly';
  static const timesheetByDate = 'timesheets/{date}';

  // Settings
  static const settings = 'settings';
}
