import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capture_onboarding_step.dart';
import 'capture_quality.dart';
import 'capture_type.dart';
import 'native_camera_capabilities.dart';
import 'native_camera_error.dart';
import 'native_camera_result.dart';

export 'capture_onboarding_step.dart';
export 'capture_quality.dart';
export 'capture_type.dart';
export 'native_camera_capabilities.dart';
export 'native_camera_error.dart';
export 'native_camera_result.dart';

class NativeCamera {
  NativeCamera._();

  static const MethodChannel _channel = MethodChannel(
    'com.smartnps360.app/native_camera',
  );

  static NativeCameraCapabilities? _cachedCaps;
  static CaptureType? _cachedCapsType;
  static bool _lastOnboardingCompleted = false;

  static bool takeLastOnboardingCompleted() {
    final value = _lastOnboardingCompleted;
    _lastOnboardingCompleted = false;
    return value;
  }

  static Future<NativeCameraResult?> open({
    CaptureType type = CaptureType.photo,
    bool allowModeSwitch = true,
    bool landscapeOnly = true,
    bool rearCameraOnly = true,
    CaptureQuality quality = CaptureQuality.maximum,
    bool preferHeic = false,
    bool showOnboarding = false,
    List<CaptureOnboardingStep> onboardingSteps =
        const <CaptureOnboardingStep>[],
  }) async {
    _lastOnboardingCompleted = false;
    try {
      if (kDebugMode) {
        debugPrint(
          '[NativeCamera] CAMERA_OPEN_REQUEST type=${type.wireName} '
          'onboarding=$showOnboarding steps=${onboardingSteps.length}',
        );
      }
      final raw = await _channel.invokeMethod<dynamic>('open', <String, Object?>{
        'type': type.wireName,
        'allowModeSwitch': allowModeSwitch,
        'landscapeOnly': landscapeOnly,
        'rearCameraOnly': rearCameraOnly,
        'quality': quality.wireName,
        'preferHeic': preferHeic,
        'showOnboarding': showOnboarding,
        'onboardingSteps': onboardingSteps
            .map((step) => step.toWire())
            .toList(growable: false),
      });

      if (raw == null) return null;
      if (raw is! Map) {
        throw const NativeCameraException(
          code: NativeCameraErrorCode.unknown,
          message: 'Unexpected camera result payload.',
        );
      }

      final map = Map<Object?, Object?>.from(raw);
      _lastOnboardingCompleted = map['onboardingCompleted'] == true;
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
