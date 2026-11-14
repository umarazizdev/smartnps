import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class DARCameraController extends GetxController with WidgetsBindingObserver {
  CameraController? cameraController;
  final isInitializing = true.obs;
  final isCapturing = false.obs;
  final errorMessage = RxnString();
  final isPreviewMode = false.obs;
  final previewFile = Rxn<File>();

  bool get isPermanentDenied =>
      (errorMessage.value ?? '').toLowerCase().contains('settings');

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    initializeCamera();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraController?.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
      cameraController = null;
      return;
    }

    if (state == AppLifecycleState.resumed && !isPreviewMode.value) {
      initializeCamera();
    }
  }

  Future<void> initializeCamera() async {
    isInitializing.value = true;
    errorMessage.value = null;
    try {
      final status = await Permission.camera.status;
      PermissionStatus grantedStatus = status;

      if (status.isDenied) {
        grantedStatus = await Permission.camera.request();
      }

      if (!grantedStatus.isGranted) {
        isInitializing.value = false;
        errorMessage.value = grantedStatus.isPermanentlyDenied
            ? 'Camera permission is required. Please enable it in Settings.'
            : 'Camera permission denied. Please allow access and retry.';
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        isInitializing.value = false;
        errorMessage.value = 'No camera available on this device.';
        return;
      }

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await cameraController?.dispose();
      cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await cameraController!.initialize();
      isInitializing.value = false;
      update();
    } catch (_) {
      isInitializing.value = false;
      errorMessage.value = 'Failed to initialize camera. Please try again.';
      update();
    }
  }

  Future<void> captureImage() async {
    final controller = cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        isCapturing.value) {
      return;
    }

    try {
      isCapturing.value = true;
      final image = await controller.takePicture();
      previewFile.value = File(image.path);
      isPreviewMode.value = true;
    } catch (_) {
      Get.snackbar(
        'Error',
        'Failed to capture image. Please try again.',
        backgroundColor: cRed.withAlpha(220),
        colorText: cWhite,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isCapturing.value = false;
    }
  }

  Future<void> cancelPreview() async {
    final file = previewFile.value;
    previewFile.value = null;
    isPreviewMode.value = false;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> closeCameraFlow() async {
    final file = previewFile.value;
    previewFile.value = null;
    isPreviewMode.value = false;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    Get.back();
  }

  void addPreview() {
    final file = previewFile.value;
    if (file != null) {
      Get.back(result: file);
    }
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}

class DARCameraScreen extends StatelessWidget {
  const DARCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DARCameraController());
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (controller.isPreviewMode.value) {
          await controller.cancelPreview();
        } else {
          Get.back();
        }
      },
      child: Scaffold(
        backgroundColor: cBlack,
        body: SafeArea(
          child: Obx(() {
            if (controller.isInitializing.value) {
              return const Center(
                child: CircularProgressIndicator(color: cWhite),
              );
            }
            if (controller.errorMessage.value != null) {
              return _DARCameraErrorView(controller: controller);
            }
            if (controller.isPreviewMode.value) {
              return _DARCameraPreviewView(controller: controller);
            }
            return GetBuilder<DARCameraController>(
              builder: (_) => _DARCameraCaptureView(controller: controller),
            );
          }),
        ),
      ),
    );
  }
}

class _DARCameraCaptureView extends StatelessWidget {
  final DARCameraController controller;
  const _DARCameraCaptureView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final camera = controller.cameraController;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: cWhite));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(camera),
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: cBlack.withAlpha(120),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Get.back(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back_rounded, color: cWhite, size: 24),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: const Center(
            child: Text(
              'Capture DAR Photo',
              style: TextStyle(
                color: cWhite,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 20,
          right: 20,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cBlack.withAlpha(120),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Fresh camera capture only',
                  style: TextStyle(color: cWhite, fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              Obx(
                () => GestureDetector(
                  onTap: controller.isCapturing.value
                      ? null
                      : controller.captureImage,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cWhite, width: 4),
                      color: cWhite.withAlpha(
                        controller.isCapturing.value ? 70 : 95,
                      ),
                    ),
                    child: controller.isCapturing.value
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: cWhite,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DARCameraPreviewView extends StatelessWidget {
  final DARCameraController controller;
  const _DARCameraPreviewView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final file = controller.previewFile.value;
    if (file == null) {
      return const Center(child: CircularProgressIndicator(color: cWhite));
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(file, fit: BoxFit.cover),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [cBlack.withAlpha(180), cTransparent],
                  ),
                ),
              ),
              const Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Preview',
                    style: TextStyle(
                      color: cWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: cBlack.withAlpha(120),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: controller.closeCameraFlow,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close_rounded, color: cWhite, size: 24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: cBlack,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: controller.cancelPreview,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cWhite),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Retake',
                    style: TextStyle(
                      color: cWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: controller.addPreview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(
                      color: cWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DARCameraErrorView extends StatelessWidget {
  final DARCameraController controller;
  const _DARCameraErrorView({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cRed.withAlpha(40),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.camera_alt_outlined,
                color: cWhite,
                size: 30,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              controller.errorMessage.value ?? 'Unable to open camera.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: cWhite, fontSize: 15),
            ),
            const SizedBox(height: 20),
            if (controller.isPermanentDenied)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: controller.openSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Open Settings'),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: controller.initializeCamera,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: cWhite),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Retry', style: TextStyle(color: cWhite)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Get.back(),
              child: const Text(
                'Go Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
