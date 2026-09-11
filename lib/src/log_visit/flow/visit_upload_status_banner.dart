import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'visit_video_flow_controller.dart';

class VisitUploadStatusBanner extends StatelessWidget {
  const VisitUploadStatusBanner({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<VisitVideoFlowController>()) {
      return const SizedBox.shrink();
    }
    final flow = Get.find<VisitVideoFlowController>();

    return Obx(() {
      if (!flow.isUploading.value) return const SizedBox.shrink();

      final current = flow.uploadProgressCurrent.value;
      final total = flow.uploadProgressTotal.value;
      final countLabel = total > 0 ? '$current/$total' : '…';

      final bg = isDark ? const Color(0xFF2563EB) : const Color(0xFF1D4ED8);

      return SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: bg.withValues(alpha: 0.40),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _UploadingDots(color: Colors.white),
                    const SizedBox(width: 7),
                    Text(
                      flow.isQueueUploading.value
                          ? 'Queue uploading… $countLabel'
                          : 'Uploading… $countLabel',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _UploadingDots extends StatefulWidget {
  const _UploadingDots({required this.color});

  final Color color;

  @override
  State<_UploadingDots> createState() => _UploadingDotsState();
}

class _UploadingDotsState extends State<_UploadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = (_controller.value * 3).floor() % 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final active = index <= phase;
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 2),
              child: Opacity(
                opacity: active ? 1 : 0.35,
                child: Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
