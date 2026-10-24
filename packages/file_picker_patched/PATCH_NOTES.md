# file_picker (patched)

Local override of `file_picker` 11.0.3 used via `dependency_overrides`.

## Why

Upstream skips applying the Kotlin Gradle Plugin on AGP 9+, assuming
built-in Kotlin is enabled. Flutter still defaults to
`android.builtInKotlin=false`, so Kotlin sources never compile and the app
fails with `cannot find symbol: class FilePickerPlugin`.

This patch applies KGP whenever built-in Kotlin is disabled.
