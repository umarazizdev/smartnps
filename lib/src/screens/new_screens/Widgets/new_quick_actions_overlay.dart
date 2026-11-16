import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Dashboard/new_dashboard_controller.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_controller.dart';
import 'package:smartnps360/src/screens/new_screens/new_models.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class NewQuickActionsDialog extends StatelessWidget {
  const NewQuickActionsDialog({super.key});

  static Future<void> show() async {
    final main = Get.find<NewMainController>();
    final dash = Get.isRegistered<NewDashboardController>()
        ? Get.find<NewDashboardController>()
        : Get.put(NewDashboardController(), permanent: true);

    if (main.quickActionsOpen.value && Get.isDialogOpen == true) {
      dismiss();
      return;
    }
    main.quickActionsOpen.value = false;
    dash.healShortcuts();
    dash.quickActionsEditing.value = false;
    main.quickActionsOpen.value = true;
    try {
      await Get.dialog(
        const NewQuickActionsDialog(),
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(140),
      );
    } finally {
      main.quickActionsOpen.value = false;
      dash.quickActionsEditing.value = false;
    }
  }

  static void dismiss() {
    if (Get.isDialogOpen == true) {
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dash = Get.find<NewDashboardController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.78;
    final width = media.size.width.clamp(280.0, 420.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border.all(
            color: isDark ? const Color(0xFF40526A) : const Color(0xFFC9D8EA),
            width: 1.2,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFF1B2738),
                    Color(0xFF172233),
                    Color(0xFF121D2D),
                  ]
                : const [
                    Color(0xFFFFFFFF),
                    Color(0xFFF9FBFE),
                    Color(0xFFF1F5FA),
                  ],
            stops: const [0, .52, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 70 : 24),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
          child: SizedBox(
            height: maxHeight,
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quick Actions',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  height: 1.15,
                                  color: isDark
                                      ? NewUi.textDark
                                      : NewUi.textLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Obx(
                                () => Text(
                                  dash.quickActionsEditing.value
                                      ? 'Hold and drag to rearrange'
                                      : 'Select an action to continue',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                    height: 1.2,
                                    color: isDark
                                        ? NewUi.textMutedDark
                                        : NewUi.textMutedLight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Obx(() {
                            final editing = dash.quickActionsEditing.value;
                            return SizedBox(
                              height: 36,
                              child: TextButton(
                                onPressed: dash.toggleQuickActionEdit,
                                style: TextButton.styleFrom(
                                  foregroundColor: cPrimary,
                                  backgroundColor: cPrimary.withAlpha(
                                    isDark ? 28 : 12,
                                  ),
                                  side: BorderSide(
                                    color: cPrimary.withAlpha(isDark ? 65 : 42),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: const Size(0, 36),
                                  maximumSize: const Size(double.infinity, 36),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      editing
                                          ? Icons.check_rounded
                                          : Icons.edit_outlined,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      editing ? 'Done' : 'Edit',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: IconButton(
                              onPressed: dismiss,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.white.withAlpha(12)
                                    : const Color(0xFFF0F4F9),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white.withAlpha(24)
                                      : const Color(0xFFDCE4EE),
                                ),
                                shape: const CircleBorder(),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: isDark
                                    ? NewUi.textMutedDark
                                    : NewUi.textMutedLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Obx(() {
                      final editing = dash.quickActionsEditing.value;
                      final items = List<NewShortcutItem>.from(
                        dash.allQuickActions,
                      ).where((e) => !e.hidden).toList();
                      final scale = (MediaQuery.sizeOf(context).width / 390)
                          .clamp(0.85, 1.12);
                      return GridView.builder(
                        padding: EdgeInsets.fromLTRB(2, 2, 2, 8 * scale),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4 * scale,
                          crossAxisSpacing: 4 * scale,
                          childAspectRatio: 1.12,
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _QaTile(
                            key: ValueKey('qa_${item.id}_$index'),
                            item: item,
                            editing: editing,
                            onTap: () {
                              if (editing) return;
                              dismiss();
                              Future.microtask(
                                () => dash.handleShortcut(item.id),
                              );
                            },
                            onReorder: dash.reorderQuickAction,
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QaTile extends StatelessWidget {
  const _QaTile({
    super.key,
    required this.item,
    required this.editing,
    required this.onTap,
    required this.onReorder,
  });

  final NewShortcutItem item;
  final bool editing;
  final VoidCallback onTap;
  final void Function(NewShortcutItem from, NewShortcutItem to) onReorder;

  Widget _tileBody({
    required bool isDark,
    required Color color,
    required double scale,
    required bool highlight,
  }) {
    final iconBox = 44.0 * scale;
    final iconSize = 22.0 * scale;
    final badgeMin = 20.0 * scale;
    final hasBadge = item.badge != null && item.badge!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: highlight
            ? color.withAlpha(isDark ? 28 : 14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14 * scale),
        border: highlight
            ? Border.all(color: color.withAlpha(140), width: 1.4)
            : null,
      ),
      padding: EdgeInsets.fromLTRB(4 * scale, 5 * scale, 4 * scale, 3 * scale),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: iconBox,
                  height: iconBox,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color.withAlpha(isDark ? 36 : 18),
                            borderRadius: BorderRadius.circular(13 * scale),
                            border: Border.all(
                              color: color.withAlpha(isDark ? 90 : 65),
                            ),
                          ),
                          child: Icon(
                            newIcon(item.iconKey),
                            color: isDark
                                ? Color.lerp(color, Colors.white, .16)
                                : color,
                            size: iconSize,
                          ),
                        ),
                      ),
                      if (hasBadge)
                        Positioned(
                          top: -5 * scale,
                          right: -5 * scale,
                          child: Container(
                            constraints: BoxConstraints(
                              minWidth: badgeMin,
                              minHeight: badgeMin,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 5 * scale,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: NewUi.danger,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF11162A)
                                    : Colors.white,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: NewUi.danger.withAlpha(70),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              item.badge!,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5 * scale,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 6 * scale),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    height: 1.15,
                    color: isDark ? NewUi.textDark : NewUi.textLight,
                  ),
                ),
              ],
            ),
          ),
          if (editing)
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 18 * scale,
                height: 18 * scale,
                decoration: BoxDecoration(
                  color: color.withAlpha(22),
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: color.withAlpha(55)),
                ),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 12 * scale,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = newColor(item.colorKey);
    final enabled = item.enabled;
    final scale = (MediaQuery.sizeOf(context).width / 390).clamp(0.85, 1.12);

    if (!editing) {
      return Opacity(
        opacity: enabled ? 1 : 0.42,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: _tileBody(
            isDark: isDark,
            color: color,
            scale: scale,
            highlight: false,
          ),
        ),
      );
    }

    return DragTarget<NewShortcutItem>(
      onWillAcceptWithDetails: (details) => details.data.id != item.id,
      onAcceptWithDetails: (details) {
        HapticFeedback.selectionClick();
        onReorder(details.data, item);
      },
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return LongPressDraggable<NewShortcutItem>(
          data: item,
          delay: const Duration(milliseconds: 180),
          hapticFeedbackOnStart: true,
          maxSimultaneousDrags: 1,
          feedback: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: BorderRadius.circular(16 * scale),
            child: SizedBox(
              width: 108 * scale,
              height: 118 * scale,
              child: Opacity(
                opacity: 0.95,
                child: _tileBody(
                  isDark: isDark,
                  color: color,
                  scale: scale,
                  highlight: true,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.28,
            child: _tileBody(
              isDark: isDark,
              color: color,
              scale: scale,
              highlight: false,
            ),
          ),
          child: _tileBody(
            isDark: isDark,
            color: color,
            scale: scale,
            highlight: highlight,
          ),
        );
      },
    );
  }
}
