class ApiUrls {
  ApiUrls._();

  static const baseUrl = 'https://smartnps360.com/api';

  static const gpsPingUrl = '$baseUrl/gps/ping';
  static const gpsBatchUrl = '$baseUrl/gps/batch';

  static const sanctumLoginUrl = '$baseUrl/auth/login';
  static const refreshTokenUrl = '$baseUrl/auth/refresh';
  static const heartbeatUrl = '$baseUrl/heartbeat';
  static const pushTokenUrl = '$baseUrl/push-token';
  static const permissionStatusUrl = '$baseUrl/native-app/permission-status';
  static const visitsUploadUrl = '$baseUrl/visits';
}
