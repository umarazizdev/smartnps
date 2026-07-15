import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/auth/auth_session_manager.dart';
import 'package:smartnps360/src/push/officer_announcement_coordinator.dart';
import 'package:smartnps360/src/push/officer_announcement_push.dart';

void main() {
  const uuidA = '123e4567-e89b-12d3-a456-426614174000';
  const uuidB = '223e4567-e89b-12d3-a456-426614174111';

  late OfficerAnnouncementCoordinator coordinator;
  late List<String> delivered;
  late List<Uri?> ensureVisibleCalls;
  var ready = false;
  var deliverResult = true;

  setUp(() {
    coordinator = OfficerAnnouncementCoordinator.forTesting();
    delivered = <String>[];
    ensureVisibleCalls = <Uri?>[];
    ready = false;
    deliverResult = true;

    coordinator.attach(
      deliverToWebView: (id) async {
        delivered.add(id);
        return deliverResult;
      },
      isDeliveryReady: () => ready,
      ensureOfficerWebViewVisible: (url) {
        ensureVisibleCalls.add(url);
      },
    );
  });

  tearDown(() {
    coordinator.resetForTesting();
  });

  OfficerAnnouncementPush push(String id, {Uri? url}) {
    return OfficerAnnouncementPush(
      recipientPublicId: id,
      destinationUrl: url,
    );
  }

  group('JavaScript serialization', () {
    test('payload includes only recipient_public_id', () {
      final payload = OfficerAnnouncementCoordinator.javascriptPayload(uuidA);
      expect(payload.keys, ['recipient_public_id']);
      expect(payload['recipient_public_id'], uuidA);
      expect(payload.containsKey('title'), isFalse);
      expect(payload.containsKey('body'), isFalse);
      expect(payload.containsKey('message'), isFalse);
    });

    test('JSON encoding safely escapes values', () {
      const tricky =
          '123e4567-e89b-12d3-a456-426614174000';
      final js = OfficerAnnouncementCoordinator.buildDeliveryJavaScript(tricky);
      expect(js.contains(jsonEncode({'recipient_public_id': tricky})), isTrue);
      expect(js.contains('smartnpsOfficerAnnouncementReceived'), isTrue);
      expect(js.contains('title'), isFalse);
      expect(js.contains('body'), isFalse);
    });

    test('normalizeJavaScriptBoolean handles common WebView results', () {
      expect(
        OfficerAnnouncementCoordinator.normalizeJavaScriptBoolean(true),
        isTrue,
      );
      expect(
        OfficerAnnouncementCoordinator.normalizeJavaScriptBoolean('true'),
        isTrue,
      );
      expect(
        OfficerAnnouncementCoordinator.normalizeJavaScriptBoolean('"true"'),
        isTrue,
      );
      expect(
        OfficerAnnouncementCoordinator.normalizeJavaScriptBoolean(false),
        isFalse,
      );
      expect(
        OfficerAnnouncementCoordinator.normalizeJavaScriptBoolean(null),
        isFalse,
      );
    });
  });

  group('Foreground delivery', () {
    test('foreground message attempts immediate WebView delivery', () async {
      ready = true;
      coordinator.onForeground(push(uuidA));
      await Future<void>.delayed(Duration.zero);
      expect(delivered, [uuidA]);
      expect(coordinator.pendingRecipientPublicId, isNull);
    });

    test('foreground keeps pending when WebView not ready', () async {
      ready = false;
      coordinator.onForeground(push(uuidA));
      await Future<void>.delayed(Duration.zero);
      expect(delivered, isEmpty);
      expect(coordinator.pendingRecipientPublicId, uuidA);
    });

    test('foreground does not overwrite existing tap pending', () async {
      ready = false;
      coordinator.onOpened(push(uuidA), source: 'opened-app');
      coordinator.onForeground(push(uuidB));
      expect(coordinator.pendingRecipientPublicId, uuidA);
      expect(ensureVisibleCalls, isNotEmpty);
    });
  });

  group('Opened / cold-launch / readiness', () {
    test('background tap stores pending UUID when not ready', () async {
      ready = false;
      final dest = Uri.parse('https://smartnps360.com/officer/dashboard');
      coordinator.onOpened(push(uuidA, url: dest), source: 'opened-app');
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.pendingRecipientPublicId, uuidA);
      expect(ensureVisibleCalls, [dest]);
      expect(delivered, isEmpty);
    });

    test('background tap delivers when already ready', () async {
      ready = true;
      coordinator.onOpened(push(uuidA), source: 'opened-app');
      await Future<void>.delayed(Duration.zero);
      expect(delivered, [uuidA]);
      expect(coordinator.pendingRecipientPublicId, isNull);
      expect(ensureVisibleCalls, isEmpty);
    });

    test('initial message stores pending UUID', () async {
      ready = false;
      coordinator.onOpened(push(uuidA), source: 'cold-launch');
      expect(coordinator.pendingRecipientPublicId, uuidA);
    });

    test('pending UUID waits for WebView readiness', () async {
      ready = false;
      coordinator.onOpened(push(uuidA), source: 'opened-app');
      await coordinator.tryDeliverPending(source: 'webview-ready');
      expect(delivered, isEmpty);

      ready = true;
      await coordinator.tryDeliverPending(source: 'webview-ready');
      expect(delivered, [uuidA]);
      expect(coordinator.pendingRecipientPublicId, isNull);
    });

    test('pending UUID waits while login page is active', () async {
      ready = false;
      coordinator.onOpened(push(uuidA), source: 'cold-launch');
      await coordinator.tryDeliverPending(source: 'webview-ready');
      expect(delivered, isEmpty);
      expect(coordinator.pendingRecipientPublicId, uuidA);
    });

    test('successful delivery clears pending state', () async {
      ready = true;
      deliverResult = true;
      coordinator.onOpened(push(uuidA), source: 'opened-app');
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.pendingRecipientPublicId, isNull);
      expect(coordinator.lastSuccessfullyDeliveredRecipientPublicId, uuidA);
    });

    test('failed delivery retains pending state', () async {
      ready = true;
      deliverResult = false;
      coordinator.onOpened(push(uuidA), source: 'opened-app');
      await Future<void>.delayed(Duration.zero);
      expect(delivered, [uuidA]);
      expect(coordinator.pendingRecipientPublicId, uuidA);
    });

    test(
      'repeated WebView load callbacks do not duplicate successful delivery',
      () async {
        ready = true;
        coordinator.onOpened(push(uuidA), source: 'opened-app');
        await Future<void>.delayed(Duration.zero);
        expect(delivered, [uuidA]);

        await coordinator.tryDeliverPending(source: 'webview-ready');
        await coordinator.tryDeliverPending(source: 'webview-ready');
        expect(delivered, [uuidA]);
      },
    );
  });

  group('AuthSessionManager.isOfficerApplicationUrl', () {
    test('accepts officer dashboard host/path', () {
      expect(
        AuthSessionManager.isOfficerApplicationUrl(
          Uri.parse('https://smartnps360.com/officer/dashboard'),
        ),
        isTrue,
      );
    });

    test('rejects login page', () {
      expect(
        AuthSessionManager.isOfficerApplicationUrl(
          Uri.parse('https://smartnps360.com/officer/login'),
        ),
        isFalse,
      );
    });

    test('rejects untrusted host', () {
      expect(
        AuthSessionManager.isOfficerApplicationUrl(
          Uri.parse('https://evil.example/officer/dashboard'),
        ),
        isFalse,
      );
    });
  });
}
