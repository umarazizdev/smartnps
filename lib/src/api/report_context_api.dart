import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../log_visit/flow/visit_flow_kind.dart';
import 'api_client.dart';
import 'api_urls.dart';
import 'visit_upload_api.dart';

class ReportContextResult {
  const ReportContextResult({
    required this.success,
    this.reportContextId,
    this.clientDraftId,
    this.visitType,
    this.siteId,
    this.regionId,
    this.siteName,
    this.regionName,
    this.timeSheetId,
    this.issuedAt,
    this.idempotent = false,
    this.statusCode,
    this.code,
    this.message,
    this.isNetworkFailure = false,
  });

  final bool success;
  final String? reportContextId;
  final String? clientDraftId;
  final String? visitType;
  final int? siteId;
  final int? regionId;
  final String? siteName;
  final String? regionName;
  final int? timeSheetId;
  final DateTime? issuedAt;
  final bool idempotent;
  final int? statusCode;
  final String? code;
  final String? message;
  final bool isNetworkFailure;

  String get displayMessage {
    final text = message?.trim();
    if (text != null && text.isNotEmpty) return text;
    if (isNetworkFailure) {
      return 'You need an internet connection to start this report.';
    }
    return 'Could not authorize this report draft.';
  }
}

class ReportContextApi {
  ReportContextApi._();

  static final ReportContextApi instance = ReportContextApi._();

  Future<ReportContextResult> issueContext({
    required String clientDraftId,
    required VisitFlowKind visitKind,
    required int siteId,
  }) async {
    final draftId = clientDraftId.trim();
    if (draftId.isEmpty) {
      return const ReportContextResult(
        success: false,
        code: 'missing_client_draft_id',
        message: 'Missing draft id for report context.',
      );
    }
    if (!visitKind.isStructuredReport) {
      return const ReportContextResult(
        success: false,
        code: 'invalid_visit_type',
        message: 'Report context is only for issue and incident reports.',
      );
    }

    ApiClient.instance.ensureAuthInterceptorInstalled();

    final body = <String, dynamic>{
      'client_draft_id': draftId,
      'visit_type': visitKind.visitTypeValue,
      'site_id': siteId,
    };

    if (kDebugMode) {
      debugPrint(
        '[ReportContextApi] POST ${ApiUrls.reportContextsUrl} body=$body',
      );
    }

    try {
      final response = await ApiClient.instance.dio.post<dynamic>(
        ApiUrls.reportContextsUrl,
        data: body,
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final result = _parseResponse(response);
      if (kDebugMode) {
        debugPrint(
          '[ReportContextApi] '
          '${result.success ? 'SUCCESS' : 'FAIL'} '
          'status=${result.statusCode} '
          'reportContextId=${result.reportContextId} '
          'idempotent=${result.idempotent} '
          'message=${result.displayMessage}',
        );
      }
      return result;
    } on DioException catch (error) {
      ApiClient.logHttpError(
        error.requestOptions.method,
        error.requestOptions.uri,
        error.response?.statusCode ?? 0,
        error.message ?? error.type.name,
      );
      final network = VisitUploadResult.isNetworkDioException(error);
      if (error.response != null && !network) {
        return _parseResponse(error.response!);
      }
      return ReportContextResult(
        success: false,
        statusCode: error.response?.statusCode,
        message: error.message ?? 'Network error while authorizing report.',
        isNetworkFailure: true,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[ReportContextApi] ERROR unexpected=$error');
      }
      return ReportContextResult(
        success: false,
        message: error.toString(),
        isNetworkFailure: error is SocketException || error is HttpException,
      );
    }
  }

  ReportContextResult _parseResponse(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final map = _asMap(response.data);
    final successFlag = map?['success'];
    final ok =
        successFlag == true ||
        (successFlag == null && status >= 200 && status < 300);

    final issuedRaw = map?['issued_at'] ?? map?['issuedAt'];
    DateTime? issuedAt;
    if (issuedRaw is String && issuedRaw.trim().isNotEmpty) {
      issuedAt = DateTime.tryParse(issuedRaw.trim());
    }

    return ReportContextResult(
      success: ok &&
          ((map?['report_context_id'] ?? map?['reportContextId'])
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true),
      reportContextId: _string(
        map?['report_context_id'] ?? map?['reportContextId'],
      ),
      clientDraftId: _string(
        map?['client_draft_id'] ?? map?['clientDraftId'],
      ),
      visitType: _string(map?['visit_type'] ?? map?['visitType']),
      siteId: _int(map?['site_id'] ?? map?['siteId']),
      regionId: _int(map?['region_id'] ?? map?['regionId']),
      siteName: _string(map?['site_name'] ?? map?['siteName']),
      regionName: _string(map?['region_name'] ?? map?['regionName']),
      timeSheetId: _int(map?['time_sheet_id'] ?? map?['timeSheetId']),
      issuedAt: issuedAt,
      idempotent: map?['idempotent'] == true,
      statusCode: status,
      code: _string(map?['code']),
      message: _string(map?['message']),
      isNetworkFailure: false,
    );
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
