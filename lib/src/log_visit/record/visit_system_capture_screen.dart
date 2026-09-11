import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../log_visit_theme.dart';
import 'visit_orientation_prompt_overlay.dart';
import 'visit_system_capture_controller.dart';

class VisitSystemCaptureScreen extends GetView<VisitSystemCaptureController> {
  const VisitSystemCaptureScreen({super.key});

  @override
  VisitSystemCaptureController get controller {
    if (!Get.isRegistered<VisitSystemCaptureController>()) {
      Get.put(VisitSystemCaptureController());
    }
    return Get.find<VisitSystemCaptureController>();
  }

  @override
  Widget build(BuildContext context) {
    final mediaOrientation = MediaQuery.orientationOf(context);
    if (controller.isPortrait.value !=
        (mediaOrientation == Orientation.portrait)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!Get.isRegistered<VisitSystemCaptureController>()) return;
        controller.syncOrientation(mediaOrientation);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => controller.handleLeave(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Obx(() {
            final portraitBlocked = controller.isPortrait.value;
            final launching = controller.isLaunchingCamera.value;
            final resolvingGps = controller.isResolvingCaptureGps.value;
            final error = controller.cameraError.value;
            final busy = controller.isBusy;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (portraitBlocked)
                  const VisitOrientationPromptOverlay(
                    mode: VisitOrientationPromptMode.landscape,
                  )
                else
                  _buildChooser(
                    busy: busy,
                    error: error,
                  ),
                Positioned(
                  top: 10,
                  left: 14,
                  child: _GlassCircleButton(
                    onTap: controller.handleLeave,
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                if (launching || resolvingGps)
                  _BusyOverlay(
                    label: resolvingGps
                        ? 'Getting location…'
                        : 'Opening camera…',
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildChooser({
    required bool busy,
    required String? error,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _CaptureModeButton(
                    icon: Icons.photo_camera_rounded,
                    label: 'Photo',
                    enabled: !busy,
                    onTap: controller.capturePhoto,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _CaptureModeButton(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    enabled: !busy,
                    accent: cOrange,
                    onTap: controller.captureVideo,
                  ),
                ),
              ],
            ),
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CaptureModeButton extends StatelessWidget {
  const _CaptureModeButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    this.accent = cPrimary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x99000000),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  valueColor: AlwaysStoppedAnimation<Color>(cOrange),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(child: child),
        ),
      ),
    );
  }
}
