import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

import '../app/app_navigator.dart';
import '../widgets/glass_action_dialog.dart';
import 'capture_review_screen.dart';
import 'visit_gps_session.dart';
import 'visit_media_draft_store.dart';
import 'visit_media_geo.dart';
import 'visit_orientation.dart';
import 'visit_video_flow_controller.dart';

class VisitVideoRecorderController extends GetxController
    with WidgetsBindingObserver {
  /// Same quality order as before the crash fix.
  ///
  /// iOS skips [ResolutionPreset.max] (process-fatal on some devices) and uses
  /// [ResolutionPreset.ultraHigh] (4K) — the resolution Log Visit opens with now.
  static const List<ResolutionPreset> _preferredPresets = [
    ResolutionPreset.max,
    ResolutionPreset.ultraHigh,
    ResolutionPreset.veryHigh,
    ResolutionPreset.high,
  ];

  /// Last-resort presets only if preferred ones fail to initialize.
  static const List<ResolutionPreset> _fallbackPresets = [
    ResolutionPreset.medium,
    ResolutionPreset.low,
  ];

  static List<ResolutionPreset> get _captureQualityPreference {
    if (Platform.isIOS) {
      return const [
        ResolutionPreset.ultraHigh,
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
        ..._fallbackPresets,
      ];
    }
    return const [
      ..._preferredPresets,
      ..._fallbackPresets,
    ];
  }

  /// Match the format used before hardening (jpeg). On iOS the plugin maps it
  /// to BGRA for the preview pipeline.
  static const ImageFormatGroup _imageFormat = ImageFormatGroup.jpeg;

  static final Map<String, ({double min, double max})> _androidZoomCache = {};
  static String? _cachedLogicalZoomCameraName;
  static String? _cachedUltraWideCameraName;
  static ResolutionPreset? _lastSuccessfulPreset;
  static List<String>? _cachedBackCameraIds;
  static bool _androidProbeComplete = false;
  static List<CameraDescription>? _cachedAvailableCameras;

  final isInitializingCamera = true.obs;
  final isStartingRecording = false.obs;
  final isStoppingRecording = false.obs;
  final isCapturingPhoto = false.obs;
  final isRecording = false.obs;
  final cameraError = Rxn<String>();
  final recordingSeconds = 0.obs;

  final currentZoom = 1.0.obs;
  final recordingZoomDisplay = 1.0.obs;
  final minZoom = 1.0.obs;
  final maxZoom = 1.0.obs;

  final stablePreviewAspect = Rxn<double>();

  final isPortrait = true.obs;
  final focusUiPoint = Rxn<Offset>();
  final pendingCapturePath = RxnString();
  final pendingCaptureIsPhoto = false.obs;
  final isResolvingCaptureGps = false.obs;

  bool _stopRequestedWhileStarting = false;
  bool _isRecorderPrepared = false;
  final zoomDragStartDy = 0.0.obs;
  final recordingGestureActive = false.obs;
  Timer? _focusReticleTimer;
  int _focusRequestId = 0;
  bool _gpsDialogVisible = false;
  String? _pendingDurablePath;
  int _zoomAnimToken = 0;

  CameraController? cameraController;
  Timer? _recordingTimer;
  CameraDescription? _activeCamera;
  CameraDescription? _wideCamera;
  CameraDescription? _ultraWideCamera;
  CameraDescription? _androidLogicalZoomCamera;
  final Map<String, ({double min, double max})> _androidZoomRanges = {};
  final isSwitchingLens = false.obs;
  final lensHoldImage = Rxn<ui.Image>();
  final lensHoldVisible = false.obs;
  final lensHoldOpacity = 1.0.obs;
  final previewCaptureKey = GlobalKey();
  final lensGeneration = 0.obs;
  double? _lastHardwareZoom;
  double _recordingDragUiStart = 1.0;
  double? _dragZoomTarget;
  bool _dragZoomPumping = false;
  bool _androidDragZoomPumping = false;
  int _lensHoldToken = 0;
  int _androidProbeToken = 0;
  int _cameraOpenToken = 0;
  Future<void> _cameraOpenChain = Future<void>.value();
  List<CameraDescription> _backCameras = const [];

  bool get hasPendingCapture => pendingCapturePath.value != null;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    unawaited(VisitOrientation.enableCaptureOrientations());
    _syncOrientationFromMetrics();
    if (!Get.isRegistered<VisitVideoFlowController>()) {
      Get.put(VisitVideoFlowController());
    }
    unawaited(initCamera());
  }

  @override
  void onClose() {
    _zoomAnimToken++;
    _androidProbeToken++;
    _cameraOpenToken++;
    _dragZoomTarget = null;
    clearLensHoldFrame();
    _focusReticleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final controller = cameraController;
    cameraController = null;
    if (controller != null && controller.value.isRecordingVideo) {
      unawaited(controller.stopVideoRecording());
    }
    _stopRecordingTimer(reset: false);
    try {
      controller?.dispose();
    } catch (_) {}
    super.onClose();
  }

  @override
  void didChangeMetrics() {
    _syncOrientationFromMetrics();
  }

  void syncOrientation(Orientation orientation) {
    _applyPortrait(orientation == Orientation.portrait);
  }

  void _syncOrientationFromMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.isEmpty) return;
    _applyPortrait(size.height >= size.width);
  }

  void _applyPortrait(bool portrait) {
    if (isClosed) return;
    if (isPortrait.value == portrait) return;
    isPortrait.value = portrait;

    if (portrait &&
        (isRecording.value ||
            isStartingRecording.value ||
            (cameraController?.value.isRecordingVideo ?? false))) {
      unawaited(stopRecording(moveToPreview: false));
    }
  }

  Future<void> initCamera() async {
    isInitializingCamera.value = true;
    cameraError.value = null;

    try {
      final cameras = await _loadAvailableCameras();
      if (isClosed) return;

      if (cameras.isEmpty) {
        cameraError.value = 'No camera found on this device.';
        isInitializingCamera.value = false;
        return;
      }

      _resolveBackLenses(cameras);
      if (_isAndroidZoomTuning) {
        _restoreAndroidZoomCache(_backCameras);
      }

      final back = _isAndroidZoomTuning
          ? _androidPickInitialCamera(cameras)
          : (_ultraWideCamera ??
                _wideCamera ??
                cameras.firstWhere(
                  (c) => c.lensDirection == CameraLensDirection.back,
                  orElse: () => cameras.first,
                ));

      await _openCamera(back, uiZoom: 1.0, showInitializing: true);
      if (isClosed) return;

      if (_isAndroidZoomTuning && !_androidProbeComplete) {
        unawaited(_scheduleAndroidBackgroundProbe(_backCameras));
      }
    } catch (_) {
      if (isClosed) return;
      cameraError.value = 'Unable to open camera. Please check permissions.';
      isInitializingCamera.value = false;
    }
  }

  Future<List<CameraDescription>> _loadAvailableCameras() async {
    final cached = _cachedAvailableCameras;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final cameras = await availableCameras();
    _cachedAvailableCameras = cameras;
    return cameras;
  }

  Future<void> _scheduleAndroidBackgroundProbe(
    List<CameraDescription> backs,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (isClosed || _androidProbeComplete) return;
    await _probeAndroidBackCamerasInBackground(backs);
  }

  void _resolveBackLenses(List<CameraDescription> cameras) {
    final backs = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();
    _backCameras = backs;

    if (backs.isEmpty) {
      _wideCamera = cameras.first;
      _ultraWideCamera = null;
      return;
    }

    CameraDescription? byType(CameraLensType type) {
      for (final camera in backs) {
        if (camera.lensType == type) return camera;
      }
      return null;
    }

    _wideCamera = byType(CameraLensType.wide) ?? backs.first;
    _ultraWideCamera = byType(CameraLensType.ultraWide);
    if (Platform.isAndroid && _ultraWideCamera == null && backs.length > 1) {
      _ultraWideCamera = _androidPickUltraWideCamera(backs, _wideCamera!);
    }
  }

  void _restoreAndroidZoomCache(List<CameraDescription> backs) {
    final ids = backs.map((c) => c.name).toList()..sort();
    final cachedIds = _cachedBackCameraIds;
    final cacheValid = cachedIds != null &&
        cachedIds.length == ids.length &&
        List.generate(ids.length, (i) => cachedIds[i] == ids[i])
            .every((match) => match);

    if (!cacheValid) {
      _androidZoomCache.clear();
      _cachedLogicalZoomCameraName = null;
      _cachedUltraWideCameraName = null;
      _androidProbeComplete = false;
      _cachedBackCameraIds = ids;
      _androidZoomRanges.clear();
      _androidLogicalZoomCamera = null;
      return;
    }

    _androidZoomRanges
      ..clear()
      ..addAll(_androidZoomCache);

    CameraDescription? byName(String? name) {
      if (name == null) return null;
      for (final camera in backs) {
        if (camera.name == name) return camera;
      }
      return null;
    }

    _androidLogicalZoomCamera = byName(_cachedLogicalZoomCameraName);
    final cachedUltra = byName(_cachedUltraWideCameraName);
    if (cachedUltra != null) {
      _ultraWideCamera = cachedUltra;
    }
  }

  void _persistAndroidZoomCache() {
    _androidZoomCache
      ..clear()
      ..addAll(_androidZoomRanges);
    _cachedLogicalZoomCameraName = _androidLogicalZoomCamera?.name;
    _cachedUltraWideCameraName = _ultraWideCamera?.name;
    _cachedBackCameraIds = _backCameras.map((c) => c.name).toList()..sort();
  }

  CameraDescription _androidPickInitialCamera(List<CameraDescription> cameras) {
    if (_androidLogicalZoomCamera != null) return _androidLogicalZoomCamera!;
    return _wideCamera ??
        cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
  }

  Future<void> _probeAndroidBackCamerasInBackground(
    List<CameraDescription> backs,
  ) async {
    final token = ++_androidProbeToken;
    if (backs.isEmpty) {
      _androidProbeComplete = true;
      return;
    }

    CameraDescription? lowestMinCamera = _androidLogicalZoomCamera;
    var lowestMin = _androidLogicalZoomCamera == null
        ? double.infinity
        : (_androidZoomRanges[_androidLogicalZoomCamera!.name]?.min ??
            double.infinity);

    final activeName = _activeCamera?.name;
    if (activeName != null &&
        cameraController != null &&
        cameraController!.value.isInitialized) {
      _androidZoomRanges[activeName] = (
        min: minZoom.value,
        max: maxZoom.value,
      );
      if (minZoom.value < lowestMin) {
        lowestMin = minZoom.value;
        lowestMinCamera = _activeCamera;
      }
    }

    for (final camera in backs) {
      if (isClosed || token != _androidProbeToken) return;
      if (_androidZoomRanges.containsKey(camera.name)) continue;

      final probe = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await probe.initialize();
        if (isClosed || token != _androidProbeToken) {
          try {
            await probe.dispose();
          } catch (_) {}
          return;
        }
        if (!probe.value.isInitialized) continue;
        final minZ = await probe.getMinZoomLevel();
        final maxZ = await probe.getMaxZoomLevel();
        _androidZoomRanges[camera.name] = (min: minZ, max: maxZ);
        if (minZ < lowestMin) {
          lowestMin = minZ;
          lowestMinCamera = camera;
        }
        if (minZ < 0.95) {
          _androidLogicalZoomCamera = camera;
          _persistAndroidZoomCache();
          _androidProbeComplete = true;
          try {
            await probe.dispose();
          } catch (_) {}
          return;
        }
      } catch (_) {
      } finally {
        try {
          await probe.dispose();
        } catch (_) {}
      }
    }

    if (isClosed || token != _androidProbeToken) return;

    if (lowestMinCamera != null && lowestMin < 0.95) {
      _androidLogicalZoomCamera = lowestMinCamera;
    } else {
      _assignAndroidUltraFromProbe(backs);
    }

    _persistAndroidZoomCache();
    _androidProbeComplete = true;
  }

  void _assignAndroidUltraFromProbe(List<CameraDescription> backs) {
    if (_ultraWideCamera != null) {
      return;
    }
    final wide = _wideCamera;
    if (wide == null) return;

    for (final camera in backs) {
      if (camera.name == '2') {
        _ultraWideCamera = camera;
        return;
      }
    }

    final others = backs.where((camera) => camera.name != wide.name).toList();
    if (others.isEmpty) return;

    others.sort((a, b) {
      final maxA = _androidZoomRanges[a.name]?.max ?? double.infinity;
      final maxB = _androidZoomRanges[b.name]?.max ?? double.infinity;
      final byMax = maxA.compareTo(maxB);
      if (byMax != 0) return byMax;
      return _androidCameraSortKey(a).compareTo(_androidCameraSortKey(b));
    });
    _ultraWideCamera = others.first;
  }

  double? _androidProbedMinZoom(CameraDescription? camera) {
    if (camera == null) return null;
    return _androidZoomRanges[camera.name]?.min;
  }

  int _androidCameraSortKey(CameraDescription camera) {
    final match = RegExp(r'\d+').firstMatch(camera.name);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 999;
    }
    return camera.name.hashCode;
  }

  CameraDescription? _androidPickUltraWideCamera(
    List<CameraDescription> backs,
    CameraDescription wide,
  ) {
    final candidates = backs
        .where((camera) => camera.name != wide.name)
        .toList();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;
    candidates.sort(
      (a, b) => _androidCameraSortKey(a).compareTo(_androidCameraSortKey(b)),
    );
    return candidates.first;
  }

  bool _isAndroidUltraWideActive() {
    if (!_isAndroidZoomTuning) return false;
    final ultra = _ultraWideCamera;
    final active = _activeCamera;
    return ultra != null && active != null && active.name == ultra.name;
  }

  CameraDescription _androidTargetLensForUiZoom(double uiZoom) {
    final wide = _wideCamera ?? _activeCamera!;
    if (uiZoom < 0.75) {
      if (_androidLogicalZoomCamera != null) return _androidLogicalZoomCamera!;
      if (_ultraWideCamera != null) return _ultraWideCamera!;
      return _activeCamera ?? wide;
    }
    if (_androidLogicalZoomCamera != null) return _androidLogicalZoomCamera!;
    return wide;
  }

  Future<bool> _captureLensHoldFrame() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (isClosed) return false;
      final context = previewCaptureKey.currentContext;
      if (context == null || !context.mounted) {
        return false;
      }
      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) {
        return false;
      }
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final dpr = views.isNotEmpty ? views.first.devicePixelRatio : 1.0;
      final image = await boundary.toImage(pixelRatio: dpr.clamp(1.0, 1.5));
      if (isClosed) {
        image.dispose();
        return false;
      }
      final previous = lensHoldImage.value;
      lensHoldImage.value = image;
      lensHoldOpacity.value = 1.0;
      lensHoldVisible.value = true;
      previous?.dispose();
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearLensHoldFrame() {
    _lensHoldToken++;
    final image = lensHoldImage.value;
    lensHoldImage.value = null;
    lensHoldVisible.value = false;
    lensHoldOpacity.value = 1.0;
    image?.dispose();
  }

  void _fadeOutLensHold() {
    if (!lensHoldVisible.value || lensHoldImage.value == null) return;
    final token = ++_lensHoldToken;
    lensHoldOpacity.value = 0.0;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (isClosed || token != _lensHoldToken) return;
      clearLensHoldFrame();
    });
  }

  Future<void> _openCamera(
    CameraDescription description, {
    required double uiZoom,
    bool showInitializing = false,
    bool isRecovery = false,
  }) {
    // Serialize opens — concurrent AVFoundation sessions are a common crash source.
    final next = _cameraOpenChain.catchError((_) {}).then(
      (_) => _openCameraUnlocked(
        description,
        uiZoom: uiZoom,
        showInitializing: showInitializing,
        isRecovery: isRecovery,
      ),
    );
    _cameraOpenChain = next.catchError((_) {});
    return next;
  }

  Future<void> _openCameraUnlocked(
    CameraDescription description, {
    required double uiZoom,
    bool showInitializing = false,
    bool isRecovery = false,
  }) async {
    final openToken = ++_cameraOpenToken;
    final previousController = cameraController;
    final previousCamera = _activeCamera;
    final previousMin = minZoom.value;
    final previousMax = maxZoom.value;
    final previousHw = _lastHardwareZoom;
    final previousUi = currentZoom.value;
    final previousAspect = stablePreviewAspect.value;
    final isLensSwitch =
        !showInitializing && previousController != null && !isRecovery;

    if (showInitializing) {
      isInitializingCamera.value = true;
    }
    cameraError.value = null;

    var hasHold = false;
    if (isLensSwitch) {
      hasHold = await _captureLensHoldFrame();
      if (isClosed || openToken != _cameraOpenToken) return;
    }

    cameraController = null;

    if (previousController != null) {
      try {
        if (previousController.value.isRecordingVideo) {
          try {
            await previousController.stopVideoRecording();
          } catch (_) {}
        }
        await previousController.dispose();
      } catch (_) {}
      // Brief settle only when swapping lenses — keeps open snappy otherwise.
      if (isLensSwitch) {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
      if (isClosed || openToken != _cameraOpenToken) {
        isInitializingCamera.value = false;
        return;
      }
    }

    if (isClosed || openToken != _cameraOpenToken) {
      isInitializingCamera.value = false;
      return;
    }

    CameraController? controller;

    try {
      controller = await _openBestQualityController(description);
      if (isClosed || openToken != _cameraOpenToken) {
        await controller.dispose();
        return;
      }
      if (!controller.value.isInitialized) {
        throw StateError('Camera initialized flag is false');
      }

      final zoomLevels = await Future.wait<double>([
        controller.getMinZoomLevel(),
        controller.getMaxZoomLevel(),
      ]);
      final fetchedMinZoom = zoomLevels[0];
      final fetchedMaxZoom = zoomLevels[1];

      minZoom.value = fetchedMinZoom;
      maxZoom.value = fetchedMaxZoom < fetchedMinZoom
          ? fetchedMinZoom
          : fetchedMaxZoom;

      if (_isAndroidZoomTuning) {
        _androidZoomRanges[description.name] = (
          min: minZoom.value,
          max: maxZoom.value,
        );
        if (minZoom.value < 0.95) {
          _androidLogicalZoomCamera = description;
        }
        _persistAndroidZoomCache();
      }

      final hardwareZoom = _hardwareZoomForUi(
        uiZoom,
        description: description,
        min: minZoom.value,
        max: maxZoom.value,
      );
      try {
        await controller.setZoomLevel(hardwareZoom);
        _lastHardwareZoom = hardwareZoom;
      } catch (_) {}

      if (isClosed || openToken != _cameraOpenToken) {
        await controller.dispose();
        return;
      }

      _isRecorderPrepared = false;

      final aspect = controller.value.aspectRatio;
      if (aspect > 0) {
        stablePreviewAspect.value = aspect;
      }

      cameraController = controller;
      _activeCamera = description;
      currentZoom.value = uiZoom;
      lensGeneration.value++;
      isInitializingCamera.value = false;
      cameraError.value = null;

      unawaited(_configureCameraSession(controller, description));
      unawaited(_prepareRecorder(controller));

      if (isLensSwitch && hasHold) {
        _fadeOutLensHold();
      } else {
        clearLensHoldFrame();
      }
    } catch (e) {
      clearLensHoldFrame();
      try {
        await controller?.dispose();
      } catch (_) {}

      if (openToken != _cameraOpenToken || isClosed) {
        isInitializingCamera.value = false;
        return;
      }

      cameraController = null;
      _activeCamera = null;
      minZoom.value = previousMin;
      maxZoom.value = previousMax;
      _lastHardwareZoom = previousHw;
      currentZoom.value = previousUi;
      stablePreviewAspect.value = previousAspect;
      lensGeneration.value++;

      if (isRecovery) {
        isInitializingCamera.value = false;
        cameraError.value = 'Unable to open camera. Please check permissions.';
        return;
      }

      final fallback = previousCamera ?? _wideCamera;
      if (fallback != null && fallback.name != description.name) {
        try {
          await _openCameraUnlocked(
            fallback,
            uiZoom: previousUi <= 0 ? 1.0 : previousUi.clamp(1.0, 2.0),
            showInitializing: true,
            isRecovery: true,
          );
          return;
        } catch (_) {}
      }

      isInitializingCamera.value = false;
      cameraError.value = 'Unable to open camera. Please check permissions.';
    }
  }

  Future<void> _configureCameraSession(
    CameraController controller,
    CameraDescription description,
  ) async {
    if (isClosed || !identical(cameraController, controller)) return;
    try {
      await Future.wait([
        controller.setFocusMode(FocusMode.auto),
        controller.setExposureMode(ExposureMode.auto),
      ]);
      if (isClosed || !identical(cameraController, controller)) return;
      if (description.lensType == CameraLensType.ultraWide) {
        final maxOffset = await controller.getMaxExposureOffset();
        final minOffset = await controller.getMinExposureOffset();
        final bump = (maxOffset * 0.15).clamp(0.0, maxOffset);
        await controller.setExposureOffset(bump.clamp(minOffset, maxOffset));
      }
    } catch (_) {}
  }

  Future<CameraController> _openBestQualityController(
    CameraDescription description,
  ) async {
    Object? lastError;

    // Prefer the preset that already worked this session — usually one init.
    final presets = <ResolutionPreset>[];
    final remembered = _lastSuccessfulPreset;
    if (remembered != null &&
        !(Platform.isIOS && remembered == ResolutionPreset.max)) {
      presets.add(remembered);
    }
    for (final preset in _captureQualityPreference) {
      if (!presets.contains(preset)) presets.add(preset);
    }
    if (Platform.isIOS) {
      presets.removeWhere((preset) => preset == ResolutionPreset.max);
    }

    for (final preset in presets) {
      if (isClosed) {
        throw StateError('Camera controller closed during initialize.');
      }

      final controller = CameraController(
        description,
        preset,
        enableAudio: true,
        imageFormatGroup: _imageFormat,
      );

      try {
        await controller.initialize();
        if (!controller.value.isInitialized) {
          throw StateError('Camera initialized flag is false');
        }
        _lastSuccessfulPreset = preset;
        return controller;
      } catch (e) {
        lastError = e;
        try {
          await controller.dispose();
        } catch (_) {}
      }
    }

    throw lastError ?? StateError('Unable to initialize camera.');
  }

  Future<void> _prepareRecorder(CameraController controller) async {
    if (_isRecorderPrepared) return;
    try {
      await controller.prepareForVideoRecording();
      _isRecorderPrepared = true;
    } catch (_) {
      _isRecorderPrepared = false;
    }
  }

  Future<void> focusAt({
    required Offset normalizedPoint,
    required Offset uiPoint,
  }) async {
    if (isClosed) return;
    if (isCapturingPhoto.value) return;

    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final x = normalizedPoint.dx.clamp(0.0, 1.0);
    final y = normalizedPoint.dy.clamp(0.0, 1.0);
    final point = Offset(x, y);

    focusUiPoint.value = uiPoint;
    _focusReticleTimer?.cancel();
    _focusReticleTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!isClosed) focusUiPoint.value = null;
    });

    final requestId = ++_focusRequestId;
    try {
      await controller.setFocusMode(FocusMode.locked);
      if (isClosed || requestId != _focusRequestId) return;
      await controller.setFocusPoint(point);
      if (isClosed || requestId != _focusRequestId) return;
      await controller.setExposurePoint(point);
      if (isClosed || requestId != _focusRequestId) return;
      await controller.setExposureMode(ExposureMode.locked);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (isClosed || requestId != _focusRequestId) return;
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {
      try {
        await controller.setFocusPoint(point);
        await controller.setExposurePoint(point);
      } catch (_) {}
    }
  }

  Future<void> capturePhoto({bool moveToPreview = true}) async {
    if (isPortrait.value) return;
    if (isCapturingPhoto.value || hasPendingCapture) return;
    if (isSwitchingLens.value) return;
    if (isRecording.value ||
        isStartingRecording.value ||
        isStoppingRecording.value) {
      return;
    }

    final controller = cameraController;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;
    if (controller.value.isTakingPicture) return;
    if (controller.value.isRecordingVideo) return;

    isCapturingPhoto.value = true;

    try {
      final file = await controller.takePicture();
      if (isClosed) return;

      if (!moveToPreview) {
        isCapturingPhoto.value = false;
        return;
      }

      pendingCapturePath.value = file.path;
      pendingCaptureIsPhoto.value = true;
      isCapturingPhoto.value = false;
      await _finalizePendingCapture();
    } catch (_) {
      if (!isClosed) {
        isCapturingPhoto.value = false;
        _clearPendingCapture();
      }
    }
  }

  Future<void> _finalizePendingCapture() async {
    final path = pendingCapturePath.value;
    if (path == null || path.isEmpty) return;

    final isPhoto = pendingCaptureIsPhoto.value;
    final type = isPhoto ? VisitMediaType.photo : VisitMediaType.video;

    final flow = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController(), permanent: true);

    final capturedAt = DateTime.now();
    await flow.registerCaptureDraft(
      VisitMediaItem(path: path, type: type, capturedAt: capturedAt),
    );
    if (isClosed) return;

    final warm = VisitGpsSession.instance.latestUsableFresh;
    final hasWarmGeo = warm != null;
    if (!hasWarmGeo) {
      isResolvingCaptureGps.value = true;
    }

    final geoFuture = hasWarmGeo
        ? Future<VisitMediaGeo>.value(
            VisitMediaGeo(
              capturedAt: capturedAt,
              latitude: warm.latitude,
              longitude: warm.longitude,
              accuracyMeters: warm.accuracy,
            ),
          )
        : VisitMediaGeo.captureFast();
    final persistFuture = flow.finalizeCaptureDraft(
      previewPath: path,
      type: type,
    );

    try {
      final durableItem = await persistFuture;
      if (isClosed) return;
      if (durableItem != null) {
        _pendingDurablePath = durableItem.path;
      }

      final openPath = _pendingDurablePath ?? path;

      if (hasWarmGeo) {
        final geo = await geoFuture;
        if (isClosed) return;
        await flow.updateCaptureGeo(mediaPath: openPath, geo: geo);
        if (_pendingDurablePath != null && _pendingDurablePath != path) {
          await VisitMediaDraftStore.instance.deleteQuietly(path);
        }
        if (isClosed) return;

        final opened = CaptureReviewScreen.open(
          filePath: openPath,
          mediaType: type,
          geo: geo,
          resolveLocationInBackground: false,
        );
        _clearPendingCapture();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Get.isRegistered<VisitVideoRecorderController>()) {
            Get.delete<VisitVideoRecorderController>(force: true);
          }
        });
        await opened;
        return;
      }

      if (_pendingDurablePath != null && _pendingDurablePath != path) {
        await VisitMediaDraftStore.instance.deleteQuietly(path);
      }
      if (isClosed) return;

      final opened = CaptureReviewScreen.open(
        filePath: openPath,
        mediaType: type,
        geo: VisitMediaGeo(capturedAt: capturedAt),
        resolveLocationInBackground: true,
      );

      _clearPendingCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.isRegistered<VisitVideoRecorderController>()) {
          Get.delete<VisitVideoRecorderController>(force: true);
        }
      });
      unawaited(geoFuture);
      await opened;
    } catch (_) {
      isResolvingCaptureGps.value = false;
      final shouldRetry = await _showGpsFailedDialog();
      if (shouldRetry) {
        await _finalizePendingCapture();
      } else {
        await _discardPendingCaptureAndLeave();
      }
    } finally {
      if (!isClosed) {
        isResolvingCaptureGps.value = false;
      }
    }
  }

  Future<bool> _showGpsFailedDialog() async {
    if (isClosed || _gpsDialogVisible) return false;
    _gpsDialogVisible = true;
    try {
      final failure = await VisitMediaGeo.describeFailure();
      final context = AppNavigator.key.currentContext ?? Get.context;
      if (context == null || !context.mounted || isClosed) return false;

      final retry = await GlassActionDialog.show(
        context: context,
        icon: Icons.gps_off_rounded,
        title: 'Failed to get GPS',
        message: failure,
        primaryLabel: 'Retry',
        secondaryLabel: 'Cancel',
        iconColor: const Color(0xFFE53935),
        variant: GlassActionDialogVariant.error,
        barrierDismissible: false,
        useRootNavigator: true,
      );
      return retry == true;
    } finally {
      _gpsDialogVisible = false;
    }
  }

  Future<void> _discardPendingCaptureAndLeave() async {
    final path = pendingCapturePath.value;
    final durable = _pendingDurablePath;
    final flow = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : null;
    if (flow != null) {
      if (durable != null) {
        await flow.removeByPath(durable, deleteMediaFile: true);
      }
      if (path != null) {
        await flow.removeByPath(path, deleteMediaFile: true);
      }
    }
    await VisitMediaDraftStore.instance.deleteQuietly(path);
    await VisitMediaDraftStore.instance.deleteQuietly(durable);
    _clearPendingCapture();
    await _leaveCaptureScreen();
  }

  void _clearPendingCapture() {
    pendingCapturePath.value = null;
    pendingCaptureIsPhoto.value = false;
    isResolvingCaptureGps.value = false;
    _pendingDurablePath = null;
  }

  Future<void> _leaveCaptureScreen() async {
    Get.back();
    if (Get.isRegistered<VisitVideoRecorderController>()) {
      Get.delete<VisitVideoRecorderController>(force: true);
    }
  }

  Future<void> startRecording() async {
    if (isPortrait.value) return;
    if (isCapturingPhoto.value || hasPendingCapture) return;
    if (isSwitchingLens.value) return;

    final controller = cameraController;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;
    if (controller.value.isRecordingVideo) return;
    if (isStartingRecording.value || isStoppingRecording.value) return;

    isStartingRecording.value = true;
    _stopRequestedWhileStarting = false;

    try {
      if (!_isRecorderPrepared) {
        await _prepareRecorder(controller);
      }

      try {
        await controller.startVideoRecording();
      } catch (_) {
        _isRecorderPrepared = false;
        await _prepareRecorder(controller);
        await controller.startVideoRecording();
      }

      if (isClosed) return;

      if (_stopRequestedWhileStarting) {
        isStartingRecording.value = false;
        await stopRecording();
        return;
      }

      isRecording.value = true;
      _startRecordingTimer();
      if (!recordingGestureActive.value) {
        final hw = (_lastHardwareZoom ?? _hardwareZoomForUi(currentZoom.value))
            .clamp(minZoom.value, maxZoom.value);
        _recordingDragUiStart = _continuousUiZoomFromHardware(
          hw,
        ).clamp(0.5, 2.0);
        recordingZoomDisplay.value = _recordingDragUiStart;
      }
    } catch (_) {
    } finally {
      if (!isClosed) isStartingRecording.value = false;
    }
  }

  Future<void> stopRecording({bool moveToPreview = true}) async {
    if (isStoppingRecording.value) return;

    if (isStartingRecording.value) {
      _stopRequestedWhileStarting = true;
      return;
    }

    final controller = cameraController;
    if (controller == null) return;
    if (!controller.value.isRecordingVideo) return;

    isStoppingRecording.value = true;

    try {
      isRecording.value = false;
      _stopRecordingTimer(reset: true);
      endZoomDrag();
      recordingGestureActive.value = false;

      final file = await controller.stopVideoRecording();
      if (isClosed) return;

      if (moveToPreview) {
        pendingCapturePath.value = file.path;
        pendingCaptureIsPhoto.value = false;
        isStoppingRecording.value = false;
        await _finalizePendingCapture();
      } else {
        try {
          final recorded = File(file.path);
          if (recorded.existsSync()) {
            recorded.deleteSync();
          }
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      if (!isClosed) {
        isStoppingRecording.value = false;
        unawaited(resetZoom());
      }
      _isRecorderPrepared = false;
      final c = cameraController;
      if (c != null && c.value.isInitialized) {
        unawaited(_prepareRecorder(c));
      }
    }
  }

  List<double> get zoomPresets => const [0.5, 1.0, 2.0];

  bool get _usesDualWideVirtualZoom {
    if (_isAndroidZoomTuning) return false;
    final active = _activeCamera;
    if (active == null) return false;
    if (active.lensType == CameraLensType.ultraWide) return true;
    return _ultraWideCamera != null && active.name == _ultraWideCamera!.name;
  }

  bool isZoomPresetSelected(double preset) {
    return isZoomChipActive(preset);
  }

  int activeZoomChipIndex() {
    final z = currentZoom.value;
    if (z < 0.75) return 0;
    if (z < 1.5) return 1;
    return 2;
  }

  bool isZoomChipActive(double preset) {
    final presets = zoomPresets;
    final idx = presets.indexOf(preset);
    if (idx < 0) return false;
    return idx == activeZoomChipIndex();
  }

  String zoomChipLabel(double preset, {bool short = true}) {
    final active = isZoomChipActive(preset);
    if (active) {
      final label = formatZoomLabel(currentZoom.value);
      return label.replaceAll('×', 'x');
    }
    if ((preset - 0.5).abs() < 0.01) return short ? '.5' : '0.5x';
    if ((preset - 2.0).abs() < 0.01) return '2';
    return '1';
  }

  double _continuousUiZoomFromHardware(double hardwareZoom) {
    if (_usesDualWideVirtualZoom) {
      return (hardwareZoom / 2.0).clamp(0.5, 2.0);
    }
    final minHw = minZoom.value;
    if (minHw < 0.95) {
      return hardwareZoom.clamp(0.5, 2.0);
    }
    if (_isAndroidUltraWideActive() && (hardwareZoom - minHw).abs() < 0.05) {
      return 0.5;
    }
    return hardwareZoom.clamp(0.5, 2.0);
  }

  static String formatZoomLabel(double zoom) {
    final clamped = zoom.clamp(0.5, 2.0);
    final rounded = (clamped * 10).round() / 10.0;
    if ((rounded - 0.5).abs() < 0.05) return '0.5×';
    if ((rounded - rounded.roundToDouble()).abs() < 0.05) {
      return '${rounded.round()}×';
    }
    return '${rounded.toStringAsFixed(1)}×';
  }

  double _hardwareZoomForUi(
    double uiZoom, {
    CameraDescription? description,
    double? min,
    double? max,
  }) {
    final lens = description ?? _activeCamera;
    final minZ = min ?? minZoom.value;
    final maxZ = max ?? maxZoom.value;

    if (!_isAndroidZoomTuning) {
      final dualWide =
          lens != null &&
          (lens.lensType == CameraLensType.ultraWide ||
              (_ultraWideCamera != null &&
                  lens.name == _ultraWideCamera!.name));
      if (dualWide) {
        return (uiZoom * 2.0).clamp(minZ, maxZ);
      }
    }

    if (_isAndroidZoomTuning && uiZoom < 0.75) {
      final probedMin = _androidProbedMinZoom(lens);
      final effectiveMin = probedMin ?? minZ;
      if (effectiveMin < 0.95) return uiZoom.clamp(effectiveMin, maxZ);
      return effectiveMin;
    }

    return uiZoom.clamp(minZ, maxZ);
  }

  double _uiZoomFromHardware(double hardwareZoom) {
    if (_usesDualWideVirtualZoom) {
      final ui = hardwareZoom / 2.0;
      if (ui <= 0.7) return 0.5;
      if (ui >= 1.7) return 2.0;
      if (ui >= 0.85 && ui <= 1.25) return 1.0;
      return ui.clamp(0.5, 2.0);
    }
    final minHw = minZoom.value;
    if (minHw < 0.95) {
      return hardwareZoom.clamp(0.5, 2.0);
    }
    if (_isAndroidUltraWideActive() && (hardwareZoom - minHw).abs() < 0.05) {
      return 0.5;
    }
    if (hardwareZoom >= 1.85) return 2.0;
    if (hardwareZoom >= 0.85 && hardwareZoom <= 1.25) return 1.0;
    return hardwareZoom.clamp(0.5, 2.0);
  }

  Future<void> setZoomPreset(double preset) async {
    if (isClosed || hasPendingCapture || isCapturingPhoto.value) {
      return;
    }
    if (isSwitchingLens.value || isInitializingCamera.value) {
      return;
    }

    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await initCamera();
      return;
    }

    if (_isAndroidZoomTuning) {
      final targetLens = _androidTargetLensForUiZoom(preset);
      final active = _activeCamera;
      if (active != null && targetLens.name != active.name) {
        isSwitchingLens.value = true;
        try {
          await _openCamera(targetLens, uiZoom: preset);
        } catch (_) {
          cameraError.value ??=
              'Unable to open camera. Please check permissions.';
        } finally {
          isSwitchingLens.value = false;
        }
        return;
      }
    }

    final targetLens = _isAndroidZoomTuning
        ? _androidTargetLensForUiZoom(preset)
        : _activeCamera;
    final targetRange = _isAndroidZoomTuning && targetLens != null
        ? _androidZoomRanges[targetLens.name]
        : null;
    final hardwareTarget = _hardwareZoomForUi(
      preset,
      description: targetLens,
      min: targetRange?.min,
      max: targetRange?.max,
    );
    final safeMin = targetRange?.min ?? minZoom.value;
    final safeMax = targetRange?.max ?? maxZoom.value;
    final safeZoom = hardwareTarget.clamp(safeMin, safeMax);

    if (_isAndroidZoomTuning &&
        preset < 0.75 &&
        _ultraWideCamera != null &&
        _activeCamera != null) {
      final currentHw =
          (_lastHardwareZoom ?? _hardwareZoomForUi(currentZoom.value)).clamp(
            minZoom.value,
            maxZoom.value,
          );
      if ((safeZoom - currentHw).abs() < 0.02 &&
          _activeCamera!.name != _ultraWideCamera!.name) {
        isSwitchingLens.value = true;
        try {
          await _openCamera(_ultraWideCamera!, uiZoom: preset);
        } catch (_) {
          cameraError.value ??=
              'Unable to open camera. Please check permissions.';
        } finally {
          isSwitchingLens.value = false;
        }
        return;
      }
    }

    await _animateZoomTo(safeZoom, uiZoom: preset);
  }

  bool get _isAndroidZoomTuning => Platform.isAndroid;

  Future<void> _animateZoomTo(double target, {double? uiZoom}) async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final to = target.clamp(minZoom.value, maxZoom.value);
    final uiEnd = uiZoom ?? currentZoom.value;

    if (_isAndroidZoomTuning) {
      final fromA = (_lastHardwareZoom ?? _hardwareZoomForUi(currentZoom.value))
          .clamp(minZoom.value, maxZoom.value);
      final deltaA = to - fromA;
      final uiFromA = currentZoom.value;
      final token = ++_zoomAnimToken;

      if (deltaA.abs() < 0.01) {
        if (!isClosed) {
          currentZoom.value = uiEnd;
          recordingZoomDisplay.value = uiEnd;
        }
        try {
          await controller.setZoomLevel(to);
          _lastHardwareZoom = to;
        } catch (_) {}
        return;
      }

      const androidDurationMs = 100;
      const androidSteps = 8;
      final stepMs = (androidDurationMs / androidSteps).round().clamp(10, 14);

      for (var i = 1; i <= androidSteps; i++) {
        if (isClosed || token != _zoomAnimToken) return;
        final t = Curves.easeInOutCubic.transform(i / androidSteps);
        final zoom = (fromA + deltaA * t).clamp(minZoom.value, maxZoom.value);
        final ui = (uiFromA + (uiEnd - uiFromA) * t).clamp(0.5, 2.0);
        currentZoom.value = ui;
        recordingZoomDisplay.value = ui;
        unawaited(
          controller
              .setZoomLevel(zoom)
              .then((_) {
                _lastHardwareZoom = zoom;
              })
              .catchError((_) {}),
        );
        if (i < androidSteps) {
          await Future<void>.delayed(Duration(milliseconds: stepMs));
        }
      }
      if (isClosed || token != _zoomAnimToken) return;
      try {
        await controller.setZoomLevel(to);
        _lastHardwareZoom = to;
        if (!isClosed && token == _zoomAnimToken) {
          currentZoom.value = uiEnd;
          recordingZoomDisplay.value = uiEnd;
        }
      } catch (_) {}
      return;
    }

    final from = (_lastHardwareZoom ?? _hardwareZoomForUi(currentZoom.value))
        .clamp(minZoom.value, maxZoom.value);
    final delta = to - from;
    final uiFrom = currentZoom.value;

    if (delta.abs() < 0.02) {
      if (!isClosed) currentZoom.value = uiEnd;
      return;
    }

    final token = ++_zoomAnimToken;

    const durationMs = 320;
    const steps = 24;
    final stepMs = (durationMs / steps).round().clamp(8, 24);

    for (var i = 1; i <= steps; i++) {
      if (isClosed || token != _zoomAnimToken) return;
      final t = Curves.easeInOutCubic.transform(i / steps);
      final zoom = (from + delta * t).clamp(minZoom.value, maxZoom.value);
      try {
        await controller.setZoomLevel(zoom);
        _lastHardwareZoom = zoom;
        if (!isClosed && token == _zoomAnimToken) {
          currentZoom.value = uiFrom + (uiEnd - uiFrom) * t;
        }
      } catch (_) {
        return;
      }
      if (i < steps) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }

    if (isClosed || token != _zoomAnimToken) return;
    try {
      await controller.setZoomLevel(to);
      _lastHardwareZoom = to;
      if (!isClosed && token == _zoomAnimToken) {
        currentZoom.value = uiEnd;
      }
    } catch (_) {}
  }

  void _cancelZoomAnimation() {
    _zoomAnimToken++;
  }

  void _syncUiZoomFromHardware(double hardwareZoom) {
    final ui = _continuousUiZoomFromHardware(hardwareZoom);
    if (isRecording.value) {
      recordingZoomDisplay.value = ui;
      currentZoom.value = ui;
    } else {
      currentZoom.value = _uiZoomFromHardware(hardwareZoom);
    }
  }

  void onRecordingGestureStart(Offset globalPosition) {
    recordingGestureActive.value = true;
    zoomDragStartDy.value = globalPosition.dy;
    beginZoomDrag();
  }

  void onRecordingGestureEnd() {
    recordingGestureActive.value = false;
    endZoomDrag();
  }

  void beginZoomDrag() {
    final hw = (_lastHardwareZoom ?? _hardwareZoomForUi(currentZoom.value))
        .clamp(minZoom.value, maxZoom.value);
    _dragZoomTarget = hw;
    _recordingDragUiStart = _continuousUiZoomFromHardware(hw).clamp(0.5, 2.0);
    recordingZoomDisplay.value = _recordingDragUiStart;
    currentZoom.value = _recordingDragUiStart;
  }

  void endZoomDrag() {
    final target = _dragZoomTarget;
    _dragZoomTarget = null;
    if (_isAndroidZoomTuning && target != null) {
      unawaited(_snapAndroidDragZoom(target));
    }
  }

  double _recordingZoomDragDelta(Offset globalPosition) {
    final dragDy = globalPosition.dy - zoomDragStartDy.value;
    return -dragDy;
  }

  double get _recordingZoomMaxDragDistance =>
      _isAndroidZoomTuning ? 220.0 : 520.0;

  Future<void> _snapAndroidDragZoom(double target) async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final snap = target.clamp(minZoom.value, maxZoom.value);
    try {
      await controller.setZoomLevel(snap);
      _lastHardwareZoom = snap;
    } catch (_) {}
  }

  Future<void> _pumpDragZoomAndroid() async {
    if (_androidDragZoomPumping) return;
    _androidDragZoomPumping = true;

    try {
      while (!isClosed) {
        final target = _dragZoomTarget;
        final controller = cameraController;
        if (target == null ||
            controller == null ||
            !controller.value.isInitialized ||
            (!isRecording.value &&
                !isStartingRecording.value &&
                !recordingGestureActive.value)) {
          break;
        }

        final current = (_lastHardwareZoom ?? minZoom.value).clamp(
          minZoom.value,
          maxZoom.value,
        );
        final gap = target - current;

        if (gap.abs() < 0.003) {
          if (gap.abs() >= 0.0005) {
            final snap = target.clamp(minZoom.value, maxZoom.value);
            try {
              await controller.setZoomLevel(snap);
              _lastHardwareZoom = snap;
            } catch (_) {
              break;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (_dragZoomTarget == null ||
              (_dragZoomTarget! - target).abs() < 0.003) {
            break;
          }
          continue;
        }

        final alpha = gap.abs() > 0.2 ? 0.30 : 0.45;
        final next = (current + gap * alpha).clamp(
          minZoom.value,
          maxZoom.value,
        );
        try {
          await controller.setZoomLevel(next);
          _lastHardwareZoom = next;
        } catch (_) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _androidDragZoomPumping = false;
      if (!isClosed &&
          _dragZoomTarget != null &&
          (isRecording.value || recordingGestureActive.value) &&
          (_lastHardwareZoom == null ||
              (_dragZoomTarget! - _lastHardwareZoom!).abs() > 0.004)) {
        unawaited(_pumpDragZoomAndroid());
      }
    }
  }

  void setZoomFromDrag({
    Offset? globalPosition,
    double? dragDy,
    double? maxDragDistance,
  }) {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (!recordingGestureActive.value &&
        !isRecording.value &&
        !isStartingRecording.value) {
      return;
    }

    _cancelZoomAnimation();

    final dragLimit = maxDragDistance ?? _recordingZoomMaxDragDistance;
    final zoomDelta = globalPosition != null
        ? _recordingZoomDragDelta(globalPosition)
        : -(dragDy ?? 0);
    final clampedDelta = zoomDelta.clamp(-dragLimit, dragLimit);

    const uiMax = 2.0;
    const uiMin = 0.5;
    final uiStart = _recordingDragUiStart.clamp(uiMin, uiMax);
    final double uiTarget;
    if (clampedDelta >= 0) {
      final progress = clampedDelta / dragLimit;
      uiTarget = (uiStart + (uiMax - uiStart) * progress).clamp(uiMin, uiMax);
    } else {
      final progress = (-clampedDelta) / dragLimit;
      uiTarget = (uiStart - (uiStart - uiMin) * progress).clamp(uiMin, uiMax);
    }
    final hwTarget = _hardwareZoomForUi(
      uiTarget,
    ).clamp(minZoom.value, maxZoom.value);

    recordingZoomDisplay.value = uiTarget;
    currentZoom.value = uiTarget;
    _dragZoomTarget = hwTarget;

    if (_isAndroidZoomTuning) {
      unawaited(_pumpDragZoomAndroid());
      return;
    }

    unawaited(_pumpDragZoom());
  }

  Future<void> _pumpDragZoom() async {
    if (_dragZoomPumping) return;
    _dragZoomPumping = true;

    try {
      while (!isClosed) {
        final target = _dragZoomTarget;
        final controller = cameraController;
        if (target == null ||
            controller == null ||
            !controller.value.isInitialized ||
            (!isRecording.value &&
                !isStartingRecording.value &&
                !recordingGestureActive.value)) {
          break;
        }

        final current = (_lastHardwareZoom ?? minZoom.value).clamp(
          minZoom.value,
          maxZoom.value,
        );
        final gap = target - current;

        if (gap.abs() < 0.004) {
          if (gap.abs() >= 0.0005) {
            try {
              await controller.setZoomLevel(target);
              _lastHardwareZoom = target;
              _syncUiZoomFromHardware(target);
            } catch (_) {
              break;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (_dragZoomTarget == null ||
              (_dragZoomTarget! - target).abs() < 0.004) {
            break;
          }
          continue;
        }

        final alpha = gap.abs() > 0.25 ? 0.08 : 0.12;
        final next = (current + gap * alpha).clamp(
          minZoom.value,
          maxZoom.value,
        );
        try {
          await controller.setZoomLevel(next);
          _lastHardwareZoom = next;
          _syncUiZoomFromHardware(next);
        } catch (_) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      _dragZoomPumping = false;
      if (!isClosed &&
          _dragZoomTarget != null &&
          (isRecording.value || recordingGestureActive.value) &&
          (_lastHardwareZoom == null ||
              (_dragZoomTarget! - _lastHardwareZoom!).abs() > 0.005)) {
        unawaited(_pumpDragZoom());
      }
    }
  }

  Future<void> resetZoom() async {
    endZoomDrag();
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    await setZoomPreset(1.0);
  }

  void _startRecordingTimer() {
    _stopRecordingTimer(reset: true);
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) recordingSeconds.value += 1;
    });
  }

  void _stopRecordingTimer({bool reset = false}) {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (reset && !isClosed) {
      recordingSeconds.value = 0;
    }
  }

  Future<void> handleLeave() async {
    if (hasPendingCapture) {
      await _discardPendingCaptureAndLeave();
      return;
    }
    final controller = cameraController;
    final recording = controller?.value.isRecordingVideo ?? false;
    if (recording) {
      await stopRecording(moveToPreview: false);
    }
    await _leaveCaptureScreen();
  }
}
