import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/widgets/auth_glass_popup.dart';

class ForgotPasswordController extends GetxController {
  final officerNumberController = TextEditingController();
  final isLoading = false.obs;
  final isSent = false.obs;
  final message = ''.obs;

  final ApiService _api = ApiService();

  void _showErrorPopup(String text, {String title = 'Notice'}) {
    message.value = text;
    final context = Get.context;
    if (context == null || text.isEmpty) return;
    AuthGlassPopup.showMessage(
      context,
      title: title,
      message: text,
      onDismissed: () {
        if (!isSent.value) {
          message.value = '';
        }
      },
    );
  }

  Future<void> submit() async {
    final officerNumber = officerNumberController.text.trim();
    message.value = '';

    if (officerNumber.isEmpty) {
      _showErrorPopup(
        'Please enter your officer number.',
        title: 'Missing Information',
      );
      return;
    }

    try {
      isLoading.value = true;
      final response = await _api.postData(
        ApiURL.forgotPassword,
        {
          'employee_no': officerNumber,
          'officer_number': officerNumber,
        },
        requiresAuth: false,
      );

      final data = response.data;
      final serverMessage = _extractMessage(data);
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        isSent.value = true;
        message.value = serverMessage.isNotEmpty
            ? serverMessage
            : 'OTP sent. Check your messages to continue.';
        return;
      }

      _showErrorPopup(
        serverMessage.isNotEmpty
            ? serverMessage
            : 'Unable to send OTP. Please try again.',
        title: 'Unable to Send OTP',
      );
    } on DioException catch (e) {
      _showErrorPopup(_mapDioError(e), title: 'Unable to Send OTP');
    } catch (e) {
      _showErrorPopup(_mapGenericError(e), title: 'Unable to Send OTP');
    } finally {
      isLoading.value = false;
    }
  }

  String _mapGenericError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('could not be found') ||
        lower.contains('not found') ||
        (lower.contains('route') && lower.contains('found'))) {
      return 'OTP service is temporarily unavailable. Please try again later.';
    }
    if (raw.isNotEmpty) return raw;
    return 'Unable to send OTP. Please try again.';
  }

  void resetForm() {
    isSent.value = false;
    message.value = '';
  }

  String _mapDioError(DioException e) {
    final data = e.response?.data;
    final serverMessage = _extractMessage(data);
    final status = e.response?.statusCode;

    if (serverMessage.isNotEmpty) {
      final lower = serverMessage.toLowerCase();
      if (lower.contains('route') && lower.contains('could not be found')) {
        return 'OTP service is temporarily unavailable. Please try again later.';
      }
      return serverMessage;
    }

    if (status == 404) {
      return 'No account found with this officer number.';
    }
    if (status == 422) {
      return 'Please enter a valid officer number.';
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'No internet connection. Please check your network and try again.';
    }
    return 'Unable to send OTP. Please try again.';
  }

  String _extractMessage(dynamic data) {
    if (data is Map) {
      final message = data['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString().trim();
      }
      final errors = data['errors'];
      if (errors is Map) {
        for (final key in ['employee_no', 'officer_number', 'email']) {
          final value = errors[key];
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
        }
      }
    }
    if (data is String &&
        data.trim().isNotEmpty &&
        !data.trim().startsWith('<')) {
      return data.trim();
    }
    return '';
  }

  @override
  void onClose() {
    officerNumberController.dispose();
    super.onClose();
  }
}
