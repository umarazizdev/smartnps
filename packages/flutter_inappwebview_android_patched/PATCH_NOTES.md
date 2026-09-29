# flutter_inappwebview_android (patched)

Local override of `flutter_inappwebview_android` 1.1.3 used via `dependency_overrides`.

## Why

Crashlytics issue `e7aeb743…` (build 148): creating `InAppWebView` crashed with

`android.webkit.WebSettingsWrapper cannot be cast to com.android.webview.chromium.ContentSettingsAdapter`

inside `WebSettingsCompat.setForceDarkStrategy` / related darkening APIs on some
Android 11 OEM/emulator WebView builds.

Upstream fixed this in `6.2.0-beta.1+` by catching the ClassCastException. Stable
`6.1.5` still crashes. This fork wraps `setForceDark`, `setForceDarkStrategy`, and
`setAlgorithmicDarkeningAllowed` in try/catch so WebView creation can continue.
