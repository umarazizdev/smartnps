import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_repository.dart';

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  final Dio dio = Dio();

  bool _installed = false;

  void ensureAuthInterceptorInstalled() {
    if (_installed) return;
    _installed = true;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (AuthRepository.isRefreshRequest(options)) {
            handler.next(options);
            return;
          }

          final token = await AuthRepository.instance.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode == 401) {
            final retried = await _refreshAndRetryRequest(response.requestOptions);
            if (retried != null) {
              _logApiResult(retried.requestOptions, retried.statusCode);
              handler.resolve(retried);
              return;
            }
          }
          _logApiResult(response.requestOptions, response.statusCode);
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final retried = await _refreshAndRetryRequest(error.requestOptions);
            if (retried != null) {
              _logApiResult(retried.requestOptions, retried.statusCode);
              handler.resolve(retried);
              return;
            }
          }
          _logApiError(error);
          handler.next(error);
        },
      ),
    );
  }

  static void _logApiResult(RequestOptions options, int? statusCode) {
    logHttpResult(options.method, options.uri, statusCode);
  }

  static void _logApiError(DioException error) {
    logHttpError(
      error.requestOptions.method,
      error.requestOptions.uri,
      error.response?.statusCode ?? 0,
      _errorMessage(error),
    );
  }

  static void logHttpResult(String method, Uri uri, int? statusCode) {
    if (!kDebugMode) return;
    // debugPrint(
    //   '[ApiClient] $method ${_pathFromUri(uri)} status=${statusCode ?? 0}',
    // );
  }

  static void logHttpError(
    String method,
    Uri uri,
    int statusCode,
    String error,
  ) {
    if (!kDebugMode) return;
    // debugPrint(
    //   '[ApiClient] $method ${_pathFromUri(uri)} status=$statusCode error=$error',
    // );
  }

  static String _pathFromUri(Uri uri) {
    if (uri.hasQuery) return '${uri.path}?${uri.query}';
    return uri.path;
  }

  static String _errorMessage(DioException error) {
    final data = error.response?.data;
    if (data != null) return data.toString();
    if (error.message != null && error.message!.isNotEmpty) {
      return error.message!;
    }
    return error.type.name;
  }

  Future<Response<dynamic>?> _refreshAndRetryRequest(
    RequestOptions request,
  ) async {
    if (AuthRepository.isRefreshRequest(request)) return null;
    if (AuthRepository.hasRefreshRetry(request)) return null;

    AuthRepository.markRefreshRetry(request);
    final newToken = await AuthRepository.instance.refreshAccessToken();
    if (newToken == null || newToken.isEmpty) return null;

    final headers = Map<String, dynamic>.from(request.headers);
    headers['Authorization'] = 'Bearer $newToken';

    try {
      return await dio.fetch<dynamic>(
        request.copyWith(
          headers: headers,
          extra: Map<String, dynamic>.from(request.extra),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
