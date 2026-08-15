# geolocator_android (patched)

Local override of `geolocator_android` 5.0.3 used via `dependency_overrides`.

## Why

With UI + `flutter_background_service` engines both using Geolocator, canceling a
position stream on one engine logged:

`There is still another flutter engine connected, not stopping location service`

as an **error**, even though that engine's `locationClient` was still stopped
correctly. This fork softens those logs to `Log.d` and clarifies the message.
