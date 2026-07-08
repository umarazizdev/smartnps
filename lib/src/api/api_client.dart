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
          if (kDebugMode) {
            final safeHeaders = Map<String, dynamic>.from(options.headers);
            final auth = safeHeaders['Authorization']?.toString();
            if (auth != null && auth.startsWith('Bearer ')) {
              final raw = auth.substring('Bearer '.length);
              final redacted = raw.length <= 10
                  ? 'Bearer ***'
                  : 'Bearer ${raw.substring(0, 6)}…${raw.substring(raw.length - 4)}';
              safeHeaders['Authorization'] = redacted;
            }
            debugPrint(
              '[ApiClient] ${options.method} ${options.uri} headers=$safeHeaders',
            );
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode == 401) {
            final retried = await _refreshAndRetryRequest(response.requestOptions);
            if (retried != null) {
              handler.resolve(retried);
              return;
            }
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final retried = await _refreshAndRetryRequest(error.requestOptions);
            if (retried != null) {
              handler.resolve(retried);
              return;
            }
          }
          handler.next(error);
        },
      ),
    );
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
