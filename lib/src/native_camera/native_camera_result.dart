import 'capture_type.dart';

class NativeCameraResult {
  const NativeCameraResult({
    required this.path,
    required this.type,
    required this.capturedAt,
    this.captureId,
    this.width,
    this.height,
    this.durationMs,
    this.cameraPosition,
    this.lens,
    this.zoomFactor,
    this.fileSizeBytes,
    this.mimeType,
    this.orientationDegrees,
    this.extensionMode,
    this.captureMode,
    this.fallbackLevel,
    this.photoDimensions,
  });

  final String path;
  final CaptureType type;
  final DateTime capturedAt;

  /// Stable identity for one physical native capture across Review → Draft.
  final String? captureId;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? cameraPosition;
  final String? lens;
  final double? zoomFactor;
  final int? fileSizeBytes;
  final String? mimeType;
  final int? orientationDegrees;
  final String? extensionMode;
  final String? captureMode;
  final String? fallbackLevel;
  final String? photoDimensions;

  bool get isPhoto => type == CaptureType.photo;
  bool get isVideo => type == CaptureType.video;

  bool get isRearCamera {
    final pos = cameraPosition?.toLowerCase().trim();
    return pos == 'back' || pos == 'rear';
  }

  factory NativeCameraResult.fromMap(Map<Object?, Object?> map) {
    final type = CaptureTypeCodec.tryParse(map['type']) ?? CaptureType.photo;
    final capturedAtMs = _asInt(map['capturedAtMs']);
    return NativeCameraResult(
      path: map['path']?.toString() ?? '',
      type: type,
      capturedAt: capturedAtMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(capturedAtMs),
      captureId: map['captureId']?.toString(),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      durationMs: _asInt(map['durationMs']),
      cameraPosition: map['cameraPosition']?.toString(),
      lens: map['lens']?.toString(),
      zoomFactor: _asDouble(map['zoomFactor']),
      fileSizeBytes: _asInt(map['fileSizeBytes']),
      mimeType: map['mimeType']?.toString(),
      orientationDegrees: _asInt(map['orientationDegrees']),
      extensionMode: map['extensionMode']?.toString(),
      captureMode: map['captureMode']?.toString(),
      fallbackLevel: map['fallbackLevel']?.toString(),
      photoDimensions: map['photoDimensions']?.toString(),
    );
  }

  Map<String, Object?> toMap() => {
    'path': path,
    'type': type.wireName,
    'capturedAtMs': capturedAt.millisecondsSinceEpoch,
    'captureId': captureId,
    'width': width,
    'height': height,
    'durationMs': durationMs,
    'cameraPosition': cameraPosition,
    'lens': lens,
    'zoomFactor': zoomFactor,
    'fileSizeBytes': fileSizeBytes,
    'mimeType': mimeType,
    'orientationDegrees': orientationDegrees,
    'extensionMode': extensionMode,
    'captureMode': captureMode,
    'fallbackLevel': fallbackLevel,
    'photoDimensions': photoDimensions,
  };

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
