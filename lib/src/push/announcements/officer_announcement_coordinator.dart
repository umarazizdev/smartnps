import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'officer_announcement_push.dart';

class OfficerAnnouncementCoordinator {
  OfficerAnnouncementCoordinator._();

  static final OfficerAnnouncementCoordinator instance =
      OfficerAnnouncementCoordinator._();

  @visibleForTesting
  OfficerAnnouncementCoordinator.forTesting();

  String? _pendingRecipientPublicId;
  Uri? _pendingDestinationUrl;
  String? _currentlyDeliveringRecipientPublicId;
  String? _lastSuccessfullyDeliveredRecipientPublicId;

  Future<bool> Function(String recipientPublicId)? _deliverToWebView;
  bool Function()? _isDeliveryReady;
  void Function(Uri? destinationUrl)? _ensureOfficerWebViewVisible;

  String? get pendingRecipientPublicId => _pendingRecipientPublicId;

  String? get lastSuccessfullyDeliveredRecipientPublicId =>
      _lastSuccessfullyDeliveredRecipientPublicId;

  @visibleForTesting
  Uri? get pendingDestinationUrl => _pendingDestinationUrl;

  void attach({
    required Future<bool> Function(String recipientPublicId) deliverToWebView,
    required bool Function() isDeliveryReady,
    required void Function(Uri? destinationUrl) ensureOfficerWebViewVisible,
  }) {
    _deliverToWebView = deliverToWebView;
    _isDeliveryReady = isDeliveryReady;
    _ensureOfficerWebViewVisible = ensureOfficerWebViewVisible;

    final pending = _pendingRecipientPublicId;
    if (pending != null) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Announcement] attach with pending '
          'Recipient: ${OfficerAnnouncementPush.redactRecipientPublicId(pending)}',
        );
      }
      if (!(_isDeliveryReady?.call() ?? false)) {
        _ensureOfficerWebViewVisible?.call(_pendingDestinationUrl);
      }
      unawaited(tryDeliverPending(source: 'attach'));
    }
  }

  void detach() {
    _deliverToWebView = null;
    _isDeliveryReady = null;
    _ensureOfficerWebViewVisible = null;
  }

  void onForeground(OfficerAnnouncementPush push) {
    _logEvent('foreground', push.recipientPublicId);
    if (_isDeliveryReady?.call() ?? false) {
      unawaited(
        _deliver(
          push.recipientPublicId,
          source: 'foreground',
          clearPendingOnSuccess: false,
        ),
      );
      return;
    }

    if (_pendingRecipientPublicId == null) {
      _pendingRecipientPublicId = push.recipientPublicId;
      _pendingDestinationUrl = push.destinationUrl;
    }
  }

  void onOpened(
    OfficerAnnouncementPush push, {
    required String source,
  }) {
    _logEvent(source, push.recipientPublicId);
    _pendingRecipientPublicId = push.recipientPublicId;
    _pendingDestinationUrl = push.destinationUrl;

    if (_isDeliveryReady?.call() ?? false) {
      unawaited(tryDeliverPending(source: source));
      return;
    }

    _ensureOfficerWebViewVisible?.call(push.destinationUrl);
    unawaited(tryDeliverPending(source: source));
  }

  Future<void> tryDeliverPending({String source = 'ready'}) async {
    final pending = _pendingRecipientPublicId;
    if (pending == null) return;
    if (!(_isDeliveryReady?.call() ?? false)) return;
    await _deliver(
      pending,
      source: source,
      clearPendingOnSuccess: true,
    );
  }

  Future<bool> _deliver(
    String recipientPublicId, {
    required String source,
    required bool clearPendingOnSuccess,
  }) async {
    final deliver = _deliverToWebView;
    if (deliver == null) return false;
    if (!(_isDeliveryReady?.call() ?? false)) return false;

    if (_currentlyDeliveringRecipientPublicId == recipientPublicId) {
      return false;
    }

    _currentlyDeliveringRecipientPublicId = recipientPublicId;
    try {
      final ok = await deliver(recipientPublicId);
      if (ok) {
        _lastSuccessfullyDeliveredRecipientPublicId = recipientPublicId;
        if (clearPendingOnSuccess &&
            _pendingRecipientPublicId == recipientPublicId) {
          _pendingRecipientPublicId = null;
          _pendingDestinationUrl = null;
        }
        if (kDebugMode) {
          debugPrint(
            '[SmartNPS360][Announcement] delivered source=$source '
            'Recipient: ${OfficerAnnouncementPush.redactRecipientPublicId(recipientPublicId)}',
          );
        }
      } else if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Announcement] delivery not confirmed source=$source '
          'Recipient: ${OfficerAnnouncementPush.redactRecipientPublicId(recipientPublicId)}',
        );
      }
      return ok;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartNPS360][Announcement] delivery error: $e');
      }
      return false;
    } finally {
      if (_currentlyDeliveringRecipientPublicId == recipientPublicId) {
        _currentlyDeliveringRecipientPublicId = null;
      }
    }
  }

  static String buildDeliveryJavaScript(String recipientPublicId) {
    final payload = jsonEncode({
      'recipient_public_id': recipientPublicId,
    });
    return '''
(() => {
  if (typeof window.smartnpsOfficerAnnouncementReceived !== 'function') {
    return false;
  }
  window.smartnpsOfficerAnnouncementReceived($payload);
  return true;
})();
''';
  }

  static bool normalizeJavaScriptBoolean(dynamic result) {
    if (result == true) return true;
    if (result == false || result == null) return false;
    final text = result
        .toString()
        .toLowerCase()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();
    return text == 'true' || text == '1';
  }

  static Map<String, dynamic> javascriptPayload(String recipientPublicId) {
    return {'recipient_public_id': recipientPublicId};
  }

  void _logEvent(String source, String recipientPublicId) {
    if (!kDebugMode) return;
    debugPrint(
      '[SmartNPS360][Announcement] source=$source '
      'Recipient: ${OfficerAnnouncementPush.redactRecipientPublicId(recipientPublicId)}',
    );
  }

  @visibleForTesting
  void resetForTesting() {
    _pendingRecipientPublicId = null;
    _pendingDestinationUrl = null;
    _currentlyDeliveringRecipientPublicId = null;
    _lastSuccessfullyDeliveredRecipientPublicId = null;
    detach();
  }
}
