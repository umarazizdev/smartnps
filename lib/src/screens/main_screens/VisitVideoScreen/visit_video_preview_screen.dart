import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:video_player/video_player.dart';

import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_flow_controller.dart';
import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_player_controller.dart';
import 'package:smartnps360/src/screens/main_screens/VisitVideoScreen/visit_video_recorder_screen.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class VisitVideoPreviewScreen extends StatefulWidget {
  static const String routeName = '/visit-video-preview';

  const VisitVideoPreviewScreen({super.key});

  @override
  State<VisitVideoPreviewScreen> createState() =>
      _VisitVideoPreviewScreenState();
}

class _VisitVideoPreviewScreenState extends State<VisitVideoPreviewScreen> {
  late final VisitVideoFlowController _flowController;
  final Map<String, Future<Uint8List?>> _thumbnailFutures =
      <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    _flowController = Get.isRegistered<VisitVideoFlowController>()
        ? Get.find<VisitVideoFlowController>()
        : Get.put(VisitVideoFlowController());
  }

  Future<void> _removeVideo(int index) async {
    if (index >= 0 && index < _flowController.recordedVideoPaths.length) {
      final path = _flowController.recordedVideoPaths[index];
      _thumbnailFutures.remove(path);
    }
    _flowController.removeVideoAt(index);
  }

  Future<Uint8List?> _getThumbnail(String videoPath) {
    return _thumbnailFutures.putIfAbsent(videoPath, () async {
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final file = File(videoPath);
          if (!await file.exists()) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }

          const probeTimes = <int>[1000, 2000, 3000, 500, 0];
          for (final timeMs in probeTimes) {
            final bytes = await vt.VideoThumbnail.thumbnailData(
              video: videoPath,
              imageFormat: vt.ImageFormat.JPEG,
              timeMs: timeMs,
              maxWidth: 320,
              quality: 75,
            );

            if (bytes != null && bytes.isNotEmpty) {
              return bytes;
            }
          }
        } catch (_) {}

        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      return null;
    });
  }

  Future<void> _uploadAllVideos() async {
    final count = _flowController.recordedVideoPaths.length;
    if (count == 0) {
      Get.snackbar(
        'No videos',
        'Please record at least one video before upload.',
      );
      return;
    }

    Get.snackbar(
      'Upload queued',
      '$count video(s) are ready to upload.',
      backgroundColor: cPrimary,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _openVideoPreview(String path) async {
    await Get.to(
      () => VisitVideoPlayerDialog(
        videoPath: path,
        onDelete: () {
          _removeVideo(_flowController.recordedVideoPaths.indexOf(path));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      appBar: AppBar(
        title: const Text('Upload Visit Videos'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Obx(() {
          final videos = _flowController.recordedVideoPaths;
          final hasVideos = videos.isNotEmpty;

          return Column(
            children: [
              Expanded(
                child: videos.isEmpty
                    ? _buildEmptyState(isDark)
                    : _buildVideoList(videos, isDark),
              ),
              _buildBottomActions(hasVideos),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 62,
              color: isDark ? cDarkIconColor : Colors.grey.shade500,
            ),
            const SizedBox(height: 14),
            Text(
              'No videos recorded yet',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Capture your first visit video using camera-only recording.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? cDarkTextSecondary : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions(bool hasVideos) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? cDarkBackground
              : cMainBg,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? cDarkBorderColor
                  : Colors.grey.shade200,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Get.to(() => const VisitVideoRecorderScreen()),
                icon: const Icon(Icons.videocam_rounded),
                label: Text(hasVideos ? 'Record More' : 'Record Video'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: hasVideos ? _uploadAllVideos : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cPrimary,
                  disabledBackgroundColor: Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  hasVideos
                      ? 'Upload (${_flowController.recordedVideoPaths.length})'
                      : 'Upload',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoList(List<String> videos, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemBuilder: (_, index) {
        final path = videos[index];

        return InkWell(
          onTap: () => _openVideoPreview(path),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: getCardDecoration(context),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 54,
                        child: FutureBuilder<Uint8List?>(
                          future: _getThumbnail(path),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                snapshot.data != null) {
                              return Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                              );
                            }

                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Container(
                                color: Colors.black12,
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return Container(
                              color: Colors.grey.shade300,
                              child: const Icon(
                                Icons.video_file_rounded,
                                color: Colors.black54,
                                size: 26,
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        width: 72,
                        height: 54,
                        color: Colors.black.withAlpha(38),
                      ),
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Video ${index + 1}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? cDarkTextPrimary : cDarkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? cDarkTextSecondary
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      barrierColor: Colors.black.withAlpha(isDark ? 128 : 77),
                      builder: (ctx) {
                        return Dialog(
                          elevation: 0,
                          insetPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          backgroundColor: Colors.transparent,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  gradient: LinearGradient(
                                    colors: isDark
                                        ? [
                                            cDarkCardColor.withAlpha(230),
                                            cDarkBackground.withAlpha(204),
                                          ]
                                        : [
                                            Colors.white.withAlpha(115),
                                            Colors.white.withAlpha(38),
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(
                                        isDark ? 77 : 38,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 420,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Delete Video?',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark
                                                      ? cDarkTextPrimary
                                                      : Colors.black.withAlpha(
                                                          217,
                                                        ),
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              overlayColor:
                                                  const WidgetStatePropertyAll(
                                                    Colors.transparent,
                                                  ),
                                              onTap: () =>
                                                  Navigator.of(ctx).pop(false),
                                              child: Icon(
                                                Icons.close,
                                                size: 24,
                                                color: isDark
                                                    ? cDarkIconColor
                                                    : Colors.black.withAlpha(
                                                        191,
                                                      ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Divider(
                                          thickness: 1,
                                          color: isDark
                                              ? cDarkBorderColor.withAlpha(166)
                                              : Colors.white.withAlpha(128),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Are you sure you want to delete this video? This action cannot be undone.',
                                          style: TextStyle(
                                            color: isDark
                                                ? cDarkTextSecondary
                                                : Colors.black.withAlpha(191),
                                            height: 1.3,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () => Navigator.of(
                                                  ctx,
                                                ).pop(false),
                                                child: Container(
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                    color: isDark
                                                        ? cDarkInputFillColor
                                                        : Colors.white
                                                              .withAlpha(153),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      'Cancel',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: isDark
                                                            ? cDarkTextPrimary
                                                            : Colors.black
                                                                  .withAlpha(
                                                                    217,
                                                                  ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () =>
                                                    Navigator.of(ctx).pop(true),
                                                child: Container(
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                    color: cRed,
                                                  ),
                                                  child: const Center(
                                                    child: Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                    if (confirmed == true) {
                      _removeVideo(index);
                    }
                  },
                  icon: Image.asset(
                    'assets/Icons/delete.png',
                    width: 22,
                    height: 22,
                    color: cRed,
                  ),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: videos.length,
    );
  }
}

class VisitVideoPlayerDialog extends StatefulWidget {
  final String videoPath;
  final VoidCallback? onDelete;

  const VisitVideoPlayerDialog({
    super.key,
    required this.videoPath,
    this.onDelete,
  });

  @override
  State<VisitVideoPlayerDialog> createState() => _VisitVideoPlayerDialogState();
}

class _VisitVideoPlayerDialogState extends State<VisitVideoPlayerDialog> {
  late final VisitVideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(
      VisitVideoPlayerController(videoPath: widget.videoPath),
      tag: widget.videoPath,
    );
  }

  @override
  void dispose() {
    Get.delete<VisitVideoPlayerController>(tag: widget.videoPath);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.videoPath.split('/').last;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            /// 🎬 FULLSCREEN VIDEO
            Positioned.fill(
              child: Obx(() {
                if (_controller.isLoading.value) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(cOrange),
                    ),
                  );
                }

                if (_controller.errorMessage.value != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _controller.errorMessage.value!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }

                final videoCtrl = _controller.videoController;
                if (videoCtrl == null || !videoCtrl.value.isInitialized) {
                  return const Center(
                    child: Text(
                      'Unable to load this video',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return _buildVideoArea(videoCtrl);
              }),
            ),

            /// 🔝 TOP BAR OVERLAY
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha(160),
                        Colors.black.withAlpha(0),
                      ],
                    ),
                  ),
                  child: _buildTopBar(fileName),
                ),
              ),
            ),

            /// 🔻 CONTROLS OVERLAY
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Obx(() => _buildControlBar()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(String fileName) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: _showFrostedMenu,
            icon: const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _showFrostedMenu() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            /// tap outside to close
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(color: Colors.transparent),
              ),
            ),

            /// 📍 POSITION MENU (top right)
            Positioned(
              top: 55,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                cDarkCardColor.withAlpha(230),
                                cDarkBackground.withAlpha(204),
                              ]
                            : [
                                Colors.white.withAlpha(115),
                                Colors.white.withAlpha(38),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 77 : 38),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),

                    /// MENU ITEMS
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _showDeleteDialog();
                          },
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showDeleteDialog();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/Icons/delete.png',
                                    width: 20,
                                    height: 20,
                                    color: cRed,
                                  ),
                                  const SizedBox(
                                    width: 12,
                                  ), // 👈 increase spacing
                                  const Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(isDark ? 128 : 77),
      builder: (ctx) {
        return Dialog(
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            cDarkCardColor.withAlpha(230),
                            cDarkBackground.withAlpha(204),
                          ]
                        : [
                            Colors.white.withAlpha(115),
                            Colors.white.withAlpha(38),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 77 : 38),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Delete Video?',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? cDarkTextPrimary
                                      : Colors.black.withAlpha(217),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => Navigator.of(ctx).pop(false),
                              child: Icon(
                                Icons.close,
                                size: 24,
                                color: isDark
                                    ? cDarkIconColor
                                    : Colors.black.withAlpha(191),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          thickness: 1,
                          color: isDark
                              ? cDarkBorderColor.withAlpha(166)
                              : Colors.white.withAlpha(128),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Are you sure you want to delete this video? This action cannot be undone.',
                          style: TextStyle(
                            color: isDark
                                ? cDarkTextSecondary
                                : Colors.black.withAlpha(191),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.of(ctx).pop(false),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: isDark
                                        ? cDarkInputFillColor
                                        : Colors.white.withAlpha(153),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? cDarkTextPrimary
                                            : Colors.black.withAlpha(217),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.of(ctx).pop(true),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: cRed,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      widget.onDelete?.call(); // delete from parent list
      Get.back(); // close preview screen
    }
  }

  Widget _buildVideoArea(VideoPlayerController videoCtrl) {
    return GestureDetector(
      onTap: _controller.togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          /// 🎬 FULL WIDTH VIDEO
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: FittedBox(
              fit: BoxFit.cover, // 🔥 THIS IS THE KEY CHANGE
              child: SizedBox(
                width: videoCtrl.value.size.width,
                height: videoCtrl.value.size.height,
                child: VideoPlayer(videoCtrl),
              ),
            ),
          ),
          const SizedBox(),

          /// ▶ CENTER PLAY BUTTON
          Obx(() {
            if (_controller.isPlaying.value ||
                _controller.isSeeking.value ||
                _controller.wasPlayingBeforeSeek.value) {
              return const SizedBox();
            }

            return AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 52,
                  color: Colors.white,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    if (_controller.isLoading.value || !_controller.isPlayerReady) {
      return const SizedBox(height: 24);
    }

    final durationMs = _controller.durationMs.value;
    final positionMs = _controller.positionMs.value.clamp(
      0,
      durationMs == 0 ? 0 : durationMs,
    );

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(210),
          border: const Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: cOrange,
                inactiveTrackColor: Colors.white24,
                thumbColor: cOrange,
                overlayColor: cOrange.withAlpha(40),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: durationMs <= 0 ? 0 : positionMs.toDouble(),
                min: 0,
                max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                onChangeStart: (_) {
                  _controller.wasPlayingBeforeSeek.value =
                      _controller.isPlaying.value;
                  _controller.isSeeking.value = true;
                },

                onChanged: (v) async {
                  await _controller.seekTo(v.round());
                },

                onChangeEnd: (_) async {
                  final shouldResume = _controller.wasPlayingBeforeSeek.value;

                  _controller.isSeeking.value = false;
                  _controller.wasPlayingBeforeSeek.value = false;

                  if (shouldResume && !_controller.isPlaying.value) {
                    final controller = _controller.videoController;
                    if (controller != null && controller.value.isInitialized) {
                      await controller.play();
                    }
                  }
                },
              ),
            ),

            Row(
              children: [
                SizedBox(
                  width: 46,
                  child: IconButton(
                    onPressed: _controller.togglePlayPause,
                    icon: Icon(
                      _controller.isPlaying.value
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: IconButton(
                    onPressed: _controller.toggleMute,
                    icon: Icon(
                      _controller.isMuted.value || _controller.volume.value == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withAlpha(35),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: _controller.volume.value,
                      min: 0,
                      max: 1,
                      onChanged: _controller.setPlayerVolume,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 82),
                  child: Text(
                    '${formatMMSS((positionMs / 1000).floor())} / ${formatMMSS((durationMs / 1000).floor())}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
