class NativeCameraException implements Exception {
  const NativeCameraException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  bool get isCanceled => code == NativeCameraErrorCode.canceled;
  bool get isPortraitRejected =>
      code == NativeCameraErrorCode.portraitCaptureRejected;
  bool get isPermissionDenied =>
      code == NativeCameraErrorCode.permissionDenied ||
      code == NativeCameraErrorCode.permissionPermanentlyDenied ||
      code == NativeCameraErrorCode.microphonePermissionDenied;

  @override
  String toString() => 'NativeCameraException($code): $message';
}

abstract final class NativeCameraErrorCode {
  static const canceled = 'canceled';
  static const permissionDenied = 'permission_denied';
  static const permissionPermanentlyDenied = 'permission_permanently_denied';
  static const microphonePermissionDenied = 'microphone_permission_denied';
  static const noRearCamera = 'no_rear_camera';
  static const cameraInUse = 'camera_in_use';
  static const initFailed = 'init_failed';
  static const captureFailed = 'capture_failed';
  static const recordingFailed = 'recording_failed';
  static const insufficientStorage = 'insufficient_storage';
  static const interrupted = 'interrupted';
  static const portraitCaptureRejected = 'portrait_capture_rejected';
  static const rearCameraRequired = 'rear_camera_required';
  static const fileCreateFailed = 'file_create_failed';
  static const unsupported = 'unsupported';
  static const unknown = 'unknown';
}
