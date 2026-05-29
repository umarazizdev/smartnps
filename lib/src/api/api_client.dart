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
      ),
    );
  }
}
