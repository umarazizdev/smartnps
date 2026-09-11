import '../debug/debug_env_config.dart';

class ApiUrls {
  ApiUrls._();

  static String get baseUrl => DebugEnvConfig.instance.apiBaseUrl;

  static String get gpsPingUrl => '$baseUrl/gps/ping';
  static String get gpsBatchUrl => '$baseUrl/gps/batch';

  static String get sanctumLoginUrl => '$baseUrl/auth/login';
  static String get refreshTokenUrl => '$baseUrl/auth/refresh';
  static String get heartbeatUrl => '$baseUrl/heartbeat';
  static String get pushTokenUrl => '$baseUrl/push-token';
  static String get permissionStatusUrl => '$baseUrl/native-app/permission-status';
  static String get visitsUploadUrl => '$baseUrl/visits';
}
