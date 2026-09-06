import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capture_quality.dart';
import 'capture_type.dart';
import 'native_camera_capabilities.dart';
import 'native_camera_error.dart';
import 'native_camera_result.dart';

export 'capture_quality.dart';
export 'capture_type.dart';
export 'native_camera_capabilities.dart';
export 'native_camera_error.dart';
export 'native_camera_result.dart';

/// Opens the in-app native CameraX / AVFoundation capture UI.
///
/// Returns the original captured file path + metadata, or `null` when the
/// user cancels. Does not stream preview frames through Flutter.
class NativeCamera {
  NativeCamera._();

  static const MethodChannel _channel = MethodChannel(
    'com.smartnps360.app/native_camera',
  );

  static NativeCameraCapabilities? _cachedCaps;
  static CaptureType? _cachedCapsType;

  /// Opens the native camera UI and returns one capture result.
  ///
  /// [type] is the initial mode. When [allowModeSwitch] is true the native UI
  /// may switch between photo and video.
  ///
  /// Photos are always rear-camera-only. Videos follow [rearCameraOnly].
  static Future<NativeCameraResult?> open({
    CaptureType type = CaptureType.photo,
    bool allowModeSwitch = true,
    bool landscapeOnly = true,
    bool rearCameraOnly = true,
    CaptureQuality quality = CaptureQuality.maximum,
    bool preferHeic = false,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('[NativeCamera] CAMERA_OPEN_REQUEST type=${type.wireName}');
      }
      final raw = await _channel.invokeMethod<dynamic>('open', <String, Object?>{
        'type': type.wireName,
        'allowModeSwitch': allowModeSwitch,
        'landscapeOnly': landscapeOnly,
        'rearCameraOnly': rearCameraOnly,
        'quality': quality.wireName,
        'preferHeic': preferHeic,
      });

      if (raw == null) return null;
      if (raw is! Map) {
        throw const NativeCameraException(
          code: NativeCameraErrorCode.unknown,
          message: 'Unexpected camera result payload.',
        );
      }

      final map = Map<Object?, Object?>.from(raw);
      if (map['canceled'] == true) return null;

      final result = NativeCameraResult.fromMap(map);
      if (result.path.isEmpty) {
        throw const NativeCameraException(
          code: NativeCameraErrorCode.fileCreateFailed,
          message: 'Camera returned an empty file path.',
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw NativeCameraException(
        code: error.code.isEmpty ? NativeCameraErrorCode.unknown : error.code,
        message: error.message ?? 'Native camera failed.',
        details: error.details,
      );
    } on MissingPluginException catch (error) {
      throw NativeCameraException(
        code: NativeCameraErrorCode.unsupported,
        message: 'Native camera plugin is not registered.',
        details: error.message,
      );
    }
  }

  /// Process-scoped capability snapshot. Safe to call repeatedly; probes once
  /// per [type] until [invalidateCapabilitiesCache] is called.
  static Future<NativeCameraCapabilities> getCapabilities({
    CaptureType type = CaptureType.photo,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedCaps != null &&
        _cachedCapsType == type) {
      return _cachedCaps!;
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'getCapabilities',
        <String, Object?>{'type': type.wireName},
      );
      if (raw is! Map) {
        final empty = const NativeCameraCapabilities();
        _cachedCaps = empty;
        _cachedCapsType = type;
        return empty;
      }
      final caps = NativeCameraCapabilities.fromMap(
        Map<Object?, Object?>.from(raw),
      );
      _cachedCaps = caps;
      _cachedCapsType = type;
      return caps;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NativeCamera] getCapabilities failed: $error');
      }
      return const NativeCameraCapabilities();
    }
  }

  static void invalidateCapabilitiesCache() {
    _cachedCaps = null;
    _cachedCapsType = null;
  }
}
