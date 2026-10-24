# video_thumbnail (patched)

Local override of `video_thumbnail` 0.5.6 used via `dependency_overrides`.

## Why

Upstream Android build still calls `jcenter()`, which was removed in Gradle 9+.
That blocks AGP 9 / Gradle 9 builds required by current Flutter.

Also updates Java 17 compile options and clears deprecated/unchecked Java
compiler notes from the Android plugin sources.
