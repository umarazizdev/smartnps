class NativeCameraCapabilities {
  const NativeCameraCapabilities({
    this.rearCameraAvailable = false,
    this.logicalMultiCamera = false,
    this.hdrPhoto = false,
    this.nightPhoto = false,
    this.autoExtension = false,
    this.flash = false,
    this.torch = false,
    this.tapToFocus = false,
    this.continuousAutofocus = false,
    this.exposureCompensation = false,
    this.minExposureIndex,
    this.maxExposureIndex,
    this.exposureStep,
    this.minExposureBias,
    this.maxExposureBias,
    this.stabilization = false,
    this.heic = false,
    this.lowLightBoost = false,
    this.virtualDeviceFusion = false,
    this.distortionCorrection = false,
    this.ultraWide = false,
    this.telephoto = false,
    this.hdrVideo = false,
    this.videoHd = false,
    this.videoFhd = false,
    this.videoUhd = false,
    this.highQualityCapture = false,
    this.maxPhotoWidth,
    this.maxPhotoHeight,
    this.usefulZoomLevels = const <double>[],
    this.minZoom = 1,
    this.maxZoom = 1,
    this.supportedExtensionModes = const <String>[],
    this.availableSceneModes = const <String>[],
  });

  final bool rearCameraAvailable;
  final bool logicalMultiCamera;

  /// Android CameraX HDR Extension (not a soft heuristic).
  final bool hdrPhoto;

  /// Android CameraX NIGHT Extension. Always false on iOS (no public Night API).
  final bool nightPhoto;

  /// Android CameraX AUTO Extension, or iOS virtual multi-cam device.
  final bool autoExtension;

  final bool flash;
  final bool torch;
  final bool tapToFocus;
  final bool continuousAutofocus;
  final bool exposureCompensation;

  /// Android CameraX exposure index range (nullable when unsupported).
  final int? minExposureIndex;
  final int? maxExposureIndex;
  final double? exposureStep;

  /// iOS EV bias range (nullable when unsupported).
  final double? minExposureBias;
  final double? maxExposureBias;

  final bool stabilization;
  final bool heic;
  final bool lowLightBoost;
  final bool virtualDeviceFusion;
  final bool distortionCorrection;
  final bool ultraWide;
  final bool telephoto;
  final bool hdrVideo;
  final bool videoHd;
  final bool videoFhd;
  final bool videoUhd;
  final bool highQualityCapture;
  final int? maxPhotoWidth;
  final int? maxPhotoHeight;
  final List<double> usefulZoomLevels;
  final double minZoom;
  final double maxZoom;

  /// Wire labels: `auto`, `hdr`, `night` (Android Extensions only).
  final List<String> supportedExtensionModes;
  final List<String> availableSceneModes;

  bool get hasSelectableAndroidExtensions =>
      supportedExtensionModes.isNotEmpty;

  factory NativeCameraCapabilities.fromMap(Map<Object?, Object?> map) {
    final zooms = <double>[];
    final rawZooms = map['usefulZoomLevels'];
    if (rawZooms is List) {
      for (final item in rawZooms) {
        final value = item is num
            ? item.toDouble()
            : double.tryParse(item?.toString() ?? '');
        if (value != null) zooms.add(value);
      }
    }

    final extensions = <String>[];
    final rawExt = map['supportedExtensionModes'] ?? map['extensionModes'];
    if (rawExt is List) {
      for (final item in rawExt) {
        final label = item?.toString().trim().toLowerCase();
        if (label != null && label.isNotEmpty) extensions.add(label);
      }
    } else {
      // Back-compat: derive from individual flags when list missing.
      if (map['autoExtension'] == true) extensions.add('auto');
      if (map['hdrPhoto'] == true) extensions.add('hdr');
      if (map['nightPhoto'] == true) extensions.add('night');
    }

    final scenes = <String>[];
    final rawScenes = map['availableSceneModes'];
    if (rawScenes is List) {
      for (final item in rawScenes) {
        final label = item?.toString();
        if (label != null && label.isNotEmpty) scenes.add(label);
      }
    }

    return NativeCameraCapabilities(
      rearCameraAvailable: map['rearCameraAvailable'] == true ||
          map['flash'] == true ||
          map['tapToFocus'] == true ||
          zooms.isNotEmpty,
      logicalMultiCamera: map['logicalMultiCamera'] == true,
      hdrPhoto: map['hdrPhoto'] == true,
      nightPhoto: map['nightPhoto'] == true,
      autoExtension: map['autoExtension'] == true,
      flash: map['flash'] == true,
      torch: map['torch'] == true,
      tapToFocus: map['tapToFocus'] == true,
      continuousAutofocus: map['continuousAutofocus'] == true,
      exposureCompensation: map['exposureCompensation'] == true,
      minExposureIndex: _asInt(map['minExposureIndex']),
      maxExposureIndex: _asInt(map['maxExposureIndex']),
      exposureStep: _asDouble(map['exposureStep']),
      minExposureBias: _asDouble(map['minExposureBias']),
      maxExposureBias: _asDouble(map['maxExposureBias']),
      stabilization: map['stabilization'] == true,
      heic: map['heic'] == true,
      lowLightBoost: map['lowLightBoost'] == true,
      virtualDeviceFusion: map['virtualDeviceFusion'] == true,
      distortionCorrection: map['distortionCorrection'] == true,
      ultraWide: map['ultraWide'] == true,
      telephoto: map['telephoto'] == true,
      hdrVideo: map['hdrVideo'] == true,
      videoHd: map['videoHd'] == true,
      videoFhd: map['videoFhd'] == true,
      videoUhd: map['videoUhd'] == true,
      highQualityCapture: map['highQualityCapture'] == true,
      maxPhotoWidth: _asInt(map['maxPhotoWidth']),
      maxPhotoHeight: _asInt(map['maxPhotoHeight']),
      usefulZoomLevels: zooms,
      minZoom: _asDouble(map['minZoom']) ?? 1,
      maxZoom: _asDouble(map['maxZoom']) ?? 1,
      supportedExtensionModes: extensions,
      availableSceneModes: scenes,
    );
  }

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
