import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' as getx;

import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/controllers/auth_controller.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:smartnps360/src/screens/main_screens/auth_screen.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/services/notification_manager.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import '../data/api.url.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class ApiService {
  final Dio _dio = Dio();
  bool _isLoggingOut = false;

  ApiService() {
    _dio.options.baseUrl = ApiURL.baseUrl;

    // Log interceptor
    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
      ),
    );

    // 401 Unauthorized interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          // Usually 401 won't reach onResponse unless validateStatus allows it.
          if (response.statusCode == 401) {
            _log('401 Unauthorized (onResponse)', tag: 'API');
            if (_hasValidSession &&
                !NativeAuthSession.instance.isLocalSessionSync) {
              _performLogout();
            } else {
              box.remove('sessionExpired');
            }
          }
          handler.next(response);
        },
        onError: (DioException error, handler) {
          if (error.response?.statusCode == 401) {
            _log('401 Unauthorized (onError)', tag: 'API', error: error);

            if (_hasValidSession &&
                !NativeAuthSession.instance.isLocalSessionSync) {
              _performLogout();
            } else {
              box.remove('sessionExpired');
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  bool get _hasValidSession {
    return NativeAuthSession.instance.hasValidSessionSync;
  }

  String? get _tokenOrNull {
    return NativeAuthSession.instance.accessTokenSync;
  }

  Map<String, dynamic> _jsonHeaders({required bool requiresAuth}) {
    final token = _authBearerToken;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'User-Agent': 'SmartNPS360-Android/1.0',
      'X-Requested-With': 'XMLHttpRequest',
      if (requiresAuth && token != null) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _multipartHeaders({required bool requiresAuth}) {
    final token = _authBearerToken;
    return {
      'Accept': 'application/json',
      'User-Agent': 'SmartNPS360-Android/1.0',
      'X-Requested-With': 'XMLHttpRequest',
      if (requiresAuth && token != null) 'Authorization': 'Bearer $token',
    };
  }

  String? get _authBearerToken {
    if (NativeAuthSession.instance.isLocalSessionSync) return null;
    return _tokenOrNull;
  }

  /// If requiresAuth=true but there is no valid session, fail with a clear message.
  /// (Don't use Dio cancel type — that looks like the user pressed "cancel".)
  void _ensureAuthIfRequired(bool requiresAuth, String endpoint) {
    if (requiresAuth && !_hasValidSession) {
      _log('Blocked auth request (no session): $endpoint', tag: 'API');
      throw StateError('Not logged in. Please login again.');
    }
  }

  // POST request
  Future<Response<dynamic>> postData(
    String endpoint,
    Map<String, dynamic> data, {
    bool requiresAuth = true,
  }) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _jsonHeaders(requiresAuth: requiresAuth);
      final response = await _dio.post(endpoint, data: data);
      return response;
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    } catch (e) {
      throw Exception('Failed to post data: $e');
    }
  }

  // GET request
  Future<dynamic> getData(String endpoint, {bool requiresAuth = true}) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _jsonHeaders(requiresAuth: requiresAuth);
      final response = await _dio.get(endpoint);
      return _parseResponse(response.data);
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    } catch (e) {
      throw Exception('Failed to get data: $e');
    }
  }

  /// Parse response data (handle String JSON or Map)
  dynamic _parseResponse(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (e) {
        _log('Failed to parse JSON response', tag: 'API', error: e);
        return data; // Return original if parsing fails
      }
    }
    return data; // Already parsed or not a string
  }

  // PUT request
  Future<Response<dynamic>> putData(
    String endpoint,
    Map<String, dynamic> data, {
    bool requiresAuth = true,
  }) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _jsonHeaders(requiresAuth: requiresAuth);
      final response = await _dio.put(endpoint, data: data);
      return response;
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    } catch (e) {
      throw Exception('Failed to put data: $e');
    }
  }

  // POST multipart/form-data with fields + single file
  Future<Response<dynamic>> postMultipartSingleFile(
    String endpoint, {
    required Map<String, dynamic> fields,
    File? file,
    String fileFieldName = 'photo',
    bool requiresAuth = true,
  }) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _multipartHeaders(requiresAuth: requiresAuth);

      final formMap = <String, dynamic>{};
      formMap.addAll(fields);

      if (file != null) {
        formMap[fileFieldName] = await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        );
      }

      final formData = FormData.fromMap(formMap);

      return await _dio.post(endpoint, data: formData);
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    }
  }

  // PUT multipart/form-data with fields + single file
  Future<Response<dynamic>> putMultipartSingleFile(
    String endpoint, {
    required Map<String, dynamic> fields,
    File? file,
    String fileFieldName = 'photo',
    bool requiresAuth = true,
  }) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _multipartHeaders(requiresAuth: requiresAuth);

      final formMap = <String, dynamic>{};
      formMap.addAll(fields);

      if (file != null) {
        formMap[fileFieldName] = await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        );
      }

      final formData = FormData.fromMap(formMap);

      return await _dio.put(endpoint, data: formData);
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    }
  }

  // POST multipart/form-data with fields + multiple files
  Future<Response<dynamic>> postMultipart(
    String endpoint,
    Map<String, dynamic> fields,
    List<String> filePaths,
    String fileFieldName, {
    bool requiresAuth = true,
  }) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _multipartHeaders(requiresAuth: requiresAuth);

      final formMap = <String, dynamic>{};
      formMap.addAll(fields);

      // Handle files array
      if (filePaths.isNotEmpty) {
        final List<MultipartFile> files = [];
        for (final path in filePaths) {
          files.add(await MultipartFile.fromFile(path));
        }
        formMap[fileFieldName] = files;
      }

      // Laravel needs explicit empty array indicator for validation
      if (filePaths.isEmpty) {
        formMap['$fileFieldName[0]'] = '';
      }

      final formData = FormData.fromMap(formMap);

      final response = await _dio.post(endpoint, data: formData);
      return response;
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    } catch (e) {
      throw Exception('Failed to post multipart: $e');
    }
  }

  // PUT multipart/form-data with fields + multiple files
  Future<Response<dynamic>> putMultipart(
    String endpoint,
    Map<String, dynamic> fields,
    List<String> filePaths,
    String fileFieldName, {
    bool requiresAuth = true,
  }) async {
    try {
      _ensureAuthIfRequired(requiresAuth, endpoint);

      _dio.options.headers = _multipartHeaders(requiresAuth: requiresAuth);

      final List<MultipartFile> files = [];
      for (final path in filePaths) {
        files.add(await MultipartFile.fromFile(path));
      }

      final formMap = <String, dynamic>{};
      formMap.addAll(fields);
      formMap[fileFieldName] = files;

      final formData = FormData.fromMap(formMap);

      final response = await _dio.put(endpoint, data: formData);
      return response;
    } on DioException catch (e) {
      _handleDioException(e);
      rethrow;
    } catch (e) {
      throw Exception('Failed to put multipart: $e');
    }
  }

  // Time Tracker APIs
  Future<Response<dynamic>> clockIn({
    String? siteId, // onsite
    String? seriesId, // onsite
    String? regionId, // patrol
    String? shiftId, // patrol
    double? latitude,
    double? longitude,
    String? inReason,
  }) async {
    try {
      final data = <String, dynamic>{};

      // ✅ Onsite payload: siteId + seriesId
      if (siteId != null && siteId.trim().isNotEmpty) {
        data['siteId'] = int.tryParse(siteId) ?? siteId;
      }
      if (seriesId != null && seriesId.trim().isNotEmpty) {
        data['seriesId'] = int.tryParse(seriesId) ?? seriesId;
      }

      // ✅ Patrol payload: regionId + shiftId
      if (regionId != null && regionId.trim().isNotEmpty) {
        data['regionId'] = int.tryParse(regionId) ?? regionId;
      }
      if (shiftId != null && shiftId.trim().isNotEmpty) {
        data['shiftId'] = int.tryParse(shiftId) ?? shiftId;
      }

      if (latitude != null) {
        data['latitude'] = latitude;
        data['lat'] = latitude; // alternate flag
      }
      if (longitude != null) {
        data['longitude'] = longitude;
        data['lng'] = longitude; // alternate flag
      }
      if (inReason != null && inReason.trim().isNotEmpty) {
        data['inReason'] = inReason.trim();
      }
      return await postData(ApiURL.timeTrackerClockIn, data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response<dynamic>> startBreak(
    String sessionId, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final endpoint = ApiURL.timeTrackerBreakStart.replaceAll(
        '{sessionId}',
        sessionId,
      );
      final Map<String, dynamic> data = {
        'breakStartAt': sfNow().toIso8601String(),
      };
      if (latitude != null) {
        data['latitude'] = latitude;
        data['lat'] = latitude;
      }
      if (longitude != null) {
        data['longitude'] = longitude;
        data['lng'] = longitude;
      }
      return await postData(endpoint, data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response<dynamic>> endBreak(
    String sessionId, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final endpoint = ApiURL.timeTrackerBreakEnd.replaceAll(
        '{sessionId}',
        sessionId,
      );
      final Map<String, dynamic> data = {
        'breakEndAt': sfNow().toIso8601String(),
      };
      if (latitude != null) {
        data['latitude'] = latitude;
        data['lat'] = latitude;
      }
      if (longitude != null) {
        data['longitude'] = longitude;
        data['lng'] = longitude;
      }
      return await postData(endpoint, data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response<dynamic>> clockOut(
    String sessionId, {
    String? outReason,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final endpoint = ApiURL.timeTrackerClockOut.replaceAll(
        '{sessionId}',
        sessionId,
      );
      final Map<String, dynamic> data = {
        'clockOutAt': sfNow().toIso8601String(),
      };
      if (outReason != null && outReason.trim().isNotEmpty) {
        data['outReason'] = outReason.trim();
      }
      if (latitude != null) {
        data['latitude'] = latitude;
        data['lat'] = latitude;
      }
      if (longitude != null) {
        data['longitude'] = longitude;
        data['lng'] = longitude;
      }
      return await postData(endpoint, data);
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> getCurrentSession() async {
    try {
      final storedUser = box.read('userInfo');
      final rawUserId = box.read('userId');
      final fallbackUserId = storedUser is Map ? storedUser['id'] : null;
      final officerId = (rawUserId ?? fallbackUserId)?.toString().trim() ?? '';

      if (officerId.isEmpty) {
        throw Exception('Officer ID missing. Please login again.');
      }

      return await getData(
        '${ApiURL.timeTrackerCurrentSession}?officer_id=$officerId',
        requiresAuth: true,
      );
    } catch (e) {
      rethrow;
    }
  }

  void _handleDioException(DioException e) {
    if (e.response != null) {
      _log('Dio error', tag: 'API', error: e.response?.data);
    } else {
      _log('Dio error (no response)', tag: 'API', error: e);
    }

    final statusCode = e.response?.statusCode;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        throw Exception(
          'Connection timed out. Please check your internet connection and try again.',
        );
      case DioExceptionType.sendTimeout:
        throw Exception('Request timed out. Please try again.');
      case DioExceptionType.receiveTimeout:
        throw Exception('Server took too long to respond. Please try again.');
      case DioExceptionType.badResponse:
        if (statusCode == 401) {
          throw Exception(
            'Your session has expired. Please sign in again to continue.',
          );
        } else if (statusCode == 403) {
          throw Exception('You do not have permission to perform this action.');
        } else if (statusCode == 404) {
          throw Exception('The requested resource could not be found.');
        } else if (statusCode == 422) {
          final data = e.response?.data;
          if (data is Map && data['message'] != null) {
            throw Exception(data['message'].toString());
          }
          throw Exception(
            'Invalid data provided. Please check your input and try again.',
          );
        } else if (statusCode != null && statusCode >= 500) {
          throw Exception('Server error occurred. Please try again later.');
        } else if (statusCode != null && statusCode >= 400) {
          final data = e.response?.data;
          if (data is Map && data['message'] != null) {
            throw Exception(data['message'].toString());
          }
          throw Exception('Request failed. Please try again.');
        } else {
          throw Exception('Something went wrong. Please try again.');
        }
      case DioExceptionType.cancel:
        throw Exception('Request was cancelled.');
      case DioExceptionType.badCertificate:
        throw Exception('Security certificate error. Please contact support.');
      case DioExceptionType.connectionError:
        if (e.error is SocketException) {
          throw Exception(
            'No internet connection. Please check your network and try again.',
          );
        }
        throw Exception(
          'Connection error. Please check your internet connection.',
        );
      case DioExceptionType.unknown:
        if (e.error is SocketException) {
          throw Exception(
            'No internet connection. Please check your network and try again.',
          );
        }
        throw Exception('An unexpected error occurred. Please try again.');
      // ignore: unreachable_switch_default
      default:
        throw Exception('An unexpected error occurred. Please try again.');
    }
  }

  /// Performs logout cleanup when 401 is detected
  /// Reuses the same logic as SettingsController.handleLogout
  Future<void> _performLogout() async {
    if (_isLoggingOut) return;

    // ✅ Double-guard: do not "logout" if no real session
    if (!_hasValidSession) {
      box.remove('sessionExpired');
      return;
    }

    _isLoggingOut = true;

    try {
      _log('Performing auto-logout due to 401', tag: 'API');

      box.write('sessionExpired', true);

      if (getx.Get.isRegistered<TimeController>()) {
        getx.Get.delete<TimeController>(force: true);
      }
      if (getx.Get.isRegistered<UserController>()) {
        getx.Get.delete<UserController>(force: true);
      }

      await NotificationManager.instance.cancelAll();
      await NativeAuthSession.instance.clearSession();
      box.write('sessionExpired', true);

      if (getx.Get.isRegistered<AuthController>()) {
        getx.Get.delete<AuthController>(force: true);
      }
      getx.Get.offAll(
        () => const AuthScreen(),
        arguments: {
          'sessionExpired': true,
          'skipAutoLogin': true,
        },
      );
    } catch (e, stack) {
      _log('Error during auto-logout', tag: 'API', error: e, stack: stack);
    } finally {
      _isLoggingOut = false;
    }
  }
}
