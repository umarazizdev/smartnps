import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/crashlytics/crashlytics_reporter.dart';

void main() {
  group('CrashlyticsReporter webview noise filters', () {
    test('ignores disposed InAppWebView evaluateJavascript MissingPlugin', () {
      final error = MissingPluginException(
        'No implementation found for method evaluateJavascript on channel '
        'com.pichillilorenzo/flutter_inappwebview_3',
      );
      expect(CrashlyticsReporter.shouldIgnoreError(error), isTrue);
      expect(CrashlyticsReporter.isNonFatalError(error), isTrue);
    });

    test('marks WebSettings ClassCast as non-fatal', () {
      const text =
          'PlatformException(error, android.webkit.WebSettingsWrapper cannot '
          'be cast to com.android.webview.chromium.ContentSettingsAdapter, '
          'null, java.lang.ClassCastException)';
      expect(CrashlyticsReporter.shouldIgnoreError(text), isFalse);
      expect(CrashlyticsReporter.isNonFatalError(text), isTrue);
    });
  });
}
