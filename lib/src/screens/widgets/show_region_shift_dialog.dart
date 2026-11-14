import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/scopecontroller.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

Future<void> showRegionShiftDialog(
  BuildContext context, {
  required Future<void> Function() onSave,
  Future<void> Function()? onCancel,
}) async {
  final h = MediaQuery.of(context).size.height;
  final w = MediaQuery.of(context).size.width;
  final textTheme = Theme.of(context).textTheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final ScopeController sc = Get.isRegistered<ScopeController>()
      ? Get.find<ScopeController>()
      : Get.put(ScopeController());

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController scopeSearchController = TextEditingController();
  final GlobalKey scopeFieldKey = GlobalKey();
  final LayerLink scopeLayerLink = LayerLink();
  final ValueNotifier<bool> scopeOverlayOpen = ValueNotifier<bool>(false);
  bool controllersDisposed = false;
  bool suppressScopeInsert = false;
  scopeSearchController.addListener(() {
    sc.regionQuery.value = scopeSearchController.text;
  });
  final RxString draftRegion = ''.obs;
  final RxString draftShift = ''.obs;

  OverlayEntry? scopeOverlayEntry;
  List<String> filteredScopeItems = <String>[];
  void scheduleScopeOverlayRebuild() {
    if (scopeOverlayEntry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        scopeOverlayEntry?.markNeedsBuild();
      } catch (_) {}
    });
  }

  late final Worker draftRegionWorker;
  draftRegionWorker = ever<String>(draftRegion, (_) {
    scheduleScopeOverlayRebuild();
  });
  int? findIdByName(String name, String dataKey) {
    final items = box.read(dataKey) as List<dynamic>?;
    if (items == null) return null;
    for (final item in items) {
      if (item is Map) {
        final itemName = (item['label'] ?? item['name'] ?? item['title'] ?? '')
            .toString();
        if (itemName == name) {
          return item['id'] is int ? item['id'] : int.tryParse('${item['id']}');
        }
      }
    }
    return null;
  }

  void removeScopeOverlay() {
    try {
      scopeOverlayEntry?.remove();
    } catch (_) {}
    scopeOverlayEntry = null;
    try {
      scopeOverlayOpen.value = false;
    } catch (_) {}
    // Prevent immediate re-opening caused by focus/change events.
    suppressScopeInsert = true;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      suppressScopeInsert = false;
    });
  }

  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void resetDraft() {
    removeScopeOverlay();
    dismissKeyboard();
    try {
      if (!controllersDisposed) scopeSearchController.clear();
    } catch (_) {}
    draftRegion.value = '';
    draftShift.value = '';
    sc.selectedShift.value = '';
    sc.shifts.clear();
  }

  Future<void> closeDialog() async {
    resetDraft();
    await Future<void>.delayed(Duration.zero);
    if (Get.isDialogOpen ?? false) {
      Get.back();
    }
  }

  void insertScopeOverlay(BuildContext dialogContext) {
    if (suppressScopeInsert) return;
    removeScopeOverlay();

    final renderBox =
        scopeFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldSize =
        renderBox?.size ??
        Size(MediaQuery.of(dialogContext).size.width * 0.8, 56);
    final offset = renderBox?.localToGlobal(Offset.zero) ?? const Offset(16, 0);

    final mq = MediaQuery.of(dialogContext);
    final screenHeight = mq.size.height;
    final keyboardHeight = mq.viewInsets.bottom;

    final availableBelow =
        screenHeight - keyboardHeight - (offset.dy + fieldSize.height) - 12;
    final availableAbove = offset.dy - mq.padding.top - 12;

    const maxDesired = 240.0;
    final showBelow = availableBelow >= 110 || availableBelow >= availableAbove;

    final overlayHeight = showBelow
        ? availableBelow.clamp(110.0, maxDesired)
        : availableAbove.clamp(110.0, maxDesired);

    final fieldWidth = fieldSize.width;
    final fieldHeight = fieldSize.height;

    final offsetForFollower = showBelow
        ? Offset(0, fieldHeight + 6)
        : Offset(0, -overlayHeight - 6);

    scopeOverlayEntry = OverlayEntry(
      builder: (_) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              CompositedTransformFollower(
                link: scopeLayerLink,
                showWhenUnlinked: false,
                offset: offsetForFollower,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TapRegion(
                    onTapOutside: (_) {
                      removeScopeOverlay();
                      dismissKeyboard();
                    },

                    child: SizedBox(
                      width: fieldWidth,
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(12),
                        color: isDark ? cDarkCardColor : Colors.white,
                        child: Container(
                          constraints: BoxConstraints(maxHeight: overlayHeight),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 77 : 31),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: filteredScopeItems.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark
                                  ? cDarkBorderColor
                                  : Colors.black.withAlpha(15),
                            ),
                            itemBuilder: (_, index) {
                              final item = filteredScopeItems[index];
                              final selected = draftRegion.value == item;
                              return InkWell(
                                onTap: () async {
                                  scopeSearchController.text = item;
                                  draftRegion.value = item;
                                  draftShift.value = '';
                                  sc.selectedShift.value = '';
                                  sc.shifts.clear();

                                  final regionId = findIdByName(
                                    item,
                                    'regionsData',
                                  );

                                  // Close overlay and keyboard immediately so the
                                  // dialog can show loading state right away.
                                  removeScopeOverlay();
                                  dismissKeyboard();

                                  if (regionId != null) {
                                    // Ensure loading flag is true immediately
                                    sc.shiftsLoading.value = true;
                                    await sc.fetchShifts(regionId: regionId);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: selected
                                                ? cPrimary
                                                : (isDark
                                                      ? cDarkTextPrimary
                                                      : const Color(
                                                          0xff111827,
                                                        )),
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(
                                          Icons.check,
                                          size: 18,
                                          color: cPrimary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    Overlay.of(dialogContext, rootOverlay: false).insert(scopeOverlayEntry!);
    try {
      scopeOverlayOpen.value = true;
    } catch (_) {}
  }

  resetDraft();

  await Get.dialog(
    PopScope(
      canPop: false,
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (!didPop) closeDialog();
      },
      child: TapRegionSurface(
        child: Dialog(
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
                    constraints: BoxConstraints(
                      maxWidth: w * 0.9,
                      minWidth: w * 0.85,
                    ),
                    child: Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "Select Region & Shift",
                                    style: textTheme.titleLarge?.copyWith(
                                      color: isDark
                                          ? cDarkTextPrimary
                                          : Colors.black.withAlpha(217),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  overlayColor: const WidgetStatePropertyAll(
                                    Colors.transparent,
                                  ),
                                  onTap: () async => await closeDialog(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? cDarkDividerColor.withAlpha(179)
                                          : const Color(0x1A000000),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? cDarkBorderColor.withAlpha(166)
                                            : Colors.white.withAlpha(51),
                                        width: 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.close,
                                      size: 20,
                                      color: isDark
                                          ? cDarkIconColor
                                          : Colors.black.withAlpha(191),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              "(showing current + today's upcoming)",
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? cDarkTextSecondary
                                    : Colors.black.withAlpha(115),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Divider(
                              thickness: 1,
                              color: isDark
                                  ? cDarkBorderColor.withAlpha(166)
                                  : Colors.white.withAlpha(128),
                            ),
                            const SizedBox(height: 16),
                            StatefulBuilder(
                              builder: (ctx, refresh) {
                                final isLoading = sc.regionsLoading.value;
                                filteredScopeItems = filteredScopeItems.isEmpty
                                    ? sc.regions.toList()
                                    : filteredScopeItems;
                                scheduleScopeOverlayRebuild();
                                void applyFilter(String value) {
                                  final source = sc.regions;
                                  filteredScopeItems = value.isEmpty
                                      ? source.toList()
                                      : source
                                            .where(
                                              (s) => s.toLowerCase().contains(
                                                value.toLowerCase(),
                                              ),
                                            )
                                            .toList();
                                  if (scopeOverlayEntry != null) {
                                    scheduleScopeOverlayRebuild();
                                  }
                                  if (filteredScopeItems.isNotEmpty) {
                                    insertScopeOverlay(ctx);
                                  } else {
                                    removeScopeOverlay();
                                  }
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Region",
                                      style: textTheme.labelMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    CompositedTransformTarget(
                                      link: scopeLayerLink,
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: TextFormField(
                                          key: scopeFieldKey,
                                          controller: scopeSearchController,
                                          textInputAction: TextInputAction.done,
                                          onChanged: (value) {
                                            applyFilter(value);
                                          },
                                          onTap: () {
                                            applyFilter(
                                              scopeSearchController.text.trim(),
                                            );
                                          },
                                          onEditingComplete: () {
                                            removeScopeOverlay();
                                            dismissKeyboard();
                                          },
                                          decoration: InputDecoration(
                                            hintText: "Search region...",
                                            filled: true,
                                            fillColor: isDark
                                                ? cDarkInputFillColor
                                                : Colors.white.withAlpha(153),
                                            suffixIcon: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Obx(
                                                  () =>
                                                      sc.regionQuery.value
                                                          .trim()
                                                          .isNotEmpty
                                                      ? IconButton(
                                                          splashColor: Colors
                                                              .transparent,
                                                          highlightColor: Colors
                                                              .transparent,
                                                          hoverColor: Colors
                                                              .transparent,
                                                          focusColor: Colors
                                                              .transparent,
                                                          icon: const Icon(
                                                            Icons.clear,
                                                            size: 20,
                                                          ),
                                                          onPressed: () {
                                                            scopeSearchController
                                                                .clear();
                                                            draftRegion.value =
                                                                '';
                                                            draftShift.value =
                                                                '';
                                                            sc
                                                                    .selectedShift
                                                                    .value =
                                                                '';
                                                            sc.shifts.clear();
                                                            removeScopeOverlay();
                                                            dismissKeyboard();
                                                          },
                                                        )
                                                      : const SizedBox.shrink(),
                                                ),
                                                if (!isLoading)
                                                  ValueListenableBuilder<bool>(
                                                    valueListenable:
                                                        scopeOverlayOpen,
                                                    builder: (_, open, _) {
                                                      return IconButton(
                                                        splashColor:
                                                            Colors.transparent,
                                                        highlightColor:
                                                            Colors.transparent,
                                                        hoverColor:
                                                            Colors.transparent,
                                                        focusColor:
                                                            Colors.transparent,

                                                        icon: Icon(
                                                          open
                                                              ? Icons
                                                                    .keyboard_arrow_up_rounded
                                                              : Icons
                                                                    .keyboard_arrow_down_rounded,
                                                          size: 24,
                                                          color: isDark
                                                              ? cDarkIconColor
                                                              : cIconDefault,
                                                        ),
                                                        onPressed: () {
                                                          if (scopeOverlayEntry !=
                                                              null) {
                                                            removeScopeOverlay();
                                                            dismissKeyboard();
                                                            return;
                                                          }
                                                          dismissKeyboard();
                                                          filteredScopeItems =
                                                              sc.regions
                                                                  .toList();
                                                          if (filteredScopeItems
                                                              .isNotEmpty) {
                                                            insertScopeOverlay(
                                                              ctx,
                                                            );
                                                          }
                                                        },
                                                      );
                                                    },
                                                  ),
                                              ],
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 14,
                                                ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide(
                                                color: isDark
                                                    ? cDarkBorderColor
                                                    : Colors.white.withAlpha(
                                                        179,
                                                      ),
                                                width: 1,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide(
                                                color: const Color(
                                                  0xFF007AFF,
                                                ).withAlpha(204),
                                                width: 1.2,
                                              ),
                                            ),
                                          ),
                                          validator: (v) {
                                            final val = (v ?? '').trim();
                                            if (val.isEmpty) {
                                              return 'Please select Region';
                                            }
                                            if (!sc.regions.contains(val)) {
                                              return 'Please select a valid Region from the list';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Obx(() {
                              final hasRegion = draftRegion.value.isNotEmpty;
                              final shiftsLoadedButEmpty =
                                  hasRegion &&
                                  !sc.shiftsLoading.value &&
                                  sc.shifts.isEmpty;

                              String shiftHint;
                              if (!hasRegion) {
                                shiftHint = "Please select region first";
                              } else if (shiftsLoadedButEmpty) {
                                shiftHint =
                                    "No shifts available for this region";
                              } else {
                                shiftHint = "Select shift...";
                              }

                              return _OverlayDropdownField(
                                label: "Shift",
                                value: draftShift.value,
                                items: sc.shifts.toList(),
                                hint: shiftHint,
                                isLoading: sc.shiftsLoading.value,
                                isEmptyAfterLoad: shiftsLoadedButEmpty,
                                textTheme: textTheme,
                                menuHorizontalMargin: 16,
                                maxMenuHeight: 240,
                                onChanged: (v) {
                                  if (v == null || v.isEmpty) return;
                                  draftShift.value = v;
                                  sc.selectedShift.value = v;
                                },
                              );
                            }),
                            SizedBox(height: h * 0.18),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () async {
                                      resetDraft();
                                      if (onCancel != null) await onCancel();
                                      if (Get.isDialogOpen ?? false) {
                                        Get.back(result: true);
                                      }
                                    },
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
                                          "Cancel",
                                          style: textTheme.labelMedium!
                                              .copyWith(
                                                color: isDark
                                                    ? cDarkTextPrimary
                                                    : Colors.black.withAlpha(
                                                        217,
                                                      ),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Obx(() {
                                  final canSave =
                                      draftRegion.value.isNotEmpty &&
                                      draftShift.value.isNotEmpty;

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: canSave
                                          ? () async {
                                              removeScopeOverlay();
                                              dismissKeyboard();
                                              final ok =
                                                  formKey.currentState
                                                      ?.validate() ??
                                                  true;
                                              if (!ok) return;

                                              sc.setRegion(
                                                draftRegion.value,
                                                fetch: false,
                                              );
                                              sc.setShift(
                                                draftShift.value,
                                                persist: true,
                                              );

                                              if (Get.isDialogOpen ?? false) {
                                                Get.back(result: true);
                                              }

                                              await onSave();
                                              // Clear transient UI state after save completes
                                              resetDraft();
                                            }
                                          : null,
                                      child: Opacity(
                                        opacity: canSave ? 1.0 : 0.45,
                                        child: Container(
                                          height: 44,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            color: canSave
                                                ? const Color(0xFF007AFF)
                                                : (isDark
                                                      ? cDarkBorderColor
                                                      : Colors.grey.shade400),
                                          ),
                                          child: Center(
                                            child: Text(
                                              "Save",
                                              style: textTheme.labelLarge!
                                                  .copyWith(
                                                    color: Colors.white,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha(isDark ? 128 : 77),
  );

  removeScopeOverlay();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      scopeSearchController.dispose();
    } catch (_) {}
    try {
      draftRegionWorker.dispose();
    } catch (_) {}
    try {
      scopeOverlayOpen.dispose();
    } catch (_) {}
  });
  Future.microtask(() {
    controllersDisposed = true;
  });
}

class _OverlayDropdownField extends StatefulWidget {
  const _OverlayDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.hint,
    required this.onChanged,
    required this.isLoading,
    required this.isEmptyAfterLoad,
    required this.textTheme,
    required this.menuHorizontalMargin,
    required this.maxMenuHeight,
  });

  final String label;
  final String value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;
  final bool isLoading;
  final bool isEmptyAfterLoad;
  final TextTheme textTheme;
  final double menuHorizontalMargin;
  final double maxMenuHeight;

  @override
  State<_OverlayDropdownField> createState() => _OverlayDropdownFieldState();
}

class _OverlayDropdownFieldState extends State<_OverlayDropdownField>
    with WidgetsBindingObserver {
  final GlobalKey _fieldKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;
  bool _suppressInsert = false;
  final ValueNotifier<bool> _overlayOpen = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remove();
    try {
      _overlayOpen.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _remove();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
    _suppressInsert = true;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      _suppressInsert = false;
    });
    try {
      _overlayOpen.value = false;
    } catch (_) {}
  }

  void _toggle() {
    if (_suppressInsert) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_entry != null) {
      _remove();
      return;
    }

    if (widget.isLoading || widget.items.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final fieldSize = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;
    final keyboardH = mq.viewInsets.bottom;

    final availableBelow =
        screenH - keyboardH - (offset.dy + fieldSize.height) - 12;
    final availableAbove = offset.dy - mq.padding.top - 12;

    final maxDesired = widget.maxMenuHeight;
    final showBelow = availableBelow >= 110 || availableBelow >= availableAbove;

    final overlayH = showBelow
        ? availableBelow.clamp(110.0, maxDesired)
        : availableAbove.clamp(110.0, maxDesired);

    final m = widget.menuHorizontalMargin;
    final left = offset.dx.clamp(m, screenW - m);
    final width = fieldSize.width.clamp(0.0, screenW - 2 * m);

    final followerOffset = showBelow
        ? Offset(0, fieldSize.height + 6)
        : Offset(0, -overlayH - 6);

    _entry = OverlayEntry(
      builder: (_) {
        return Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  width: width,
                  top: 0,
                  child: CompositedTransformFollower(
                    link: _layerLink,
                    showWhenUnlinked: false,
                    offset: followerOffset,
                    child: TapRegion(
                      onTapOutside: (_) => _remove(),
                      child: Material(
                        color: isDark
                            ? cDarkCardColor
                            : Colors.white.withAlpha(250),
                        elevation: 10,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          constraints: BoxConstraints(maxHeight: overlayH),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 77 : 31),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: widget.items.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark
                                  ? cDarkBorderColor
                                  : Colors.black.withAlpha(15),
                            ),
                            itemBuilder: (_, i) {
                              final item = widget.items[i];
                              final selected =
                                  widget.value.isNotEmpty &&
                                  widget.value == item;

                              return InkWell(
                                onTap: () {
                                  widget.onChanged(item);
                                  _remove();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item,
                                          overflow: TextOverflow.ellipsis,
                                          style: widget.textTheme.labelLarge!
                                              .copyWith(
                                                color: selected
                                                    ? cPrimary
                                                    : (isDark
                                                          ? cDarkTextPrimary
                                                          : const Color(
                                                              0xff111827,
                                                            )),
                                                fontWeight: selected
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(
                                          Icons.check,
                                          size: 18,
                                          color: cPrimary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: false).insert(_entry!);
    try {
      _overlayOpen.value = true;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasValue =
        widget.value.isNotEmpty && widget.items.contains(widget.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: widget.textTheme.labelMedium!.copyWith()),
        const SizedBox(height: 4),
        CompositedTransformTarget(
          link: _layerLink,
          child: InkWell(
            key: _fieldKey,
            borderRadius: BorderRadius.circular(14),
            onTap: _toggle,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? cDarkInputFillColor
                    : Colors.white.withAlpha(153),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.isEmptyAfterLoad
                      ? Colors.orange.withAlpha(128)
                      : (isDark
                            ? cDarkBorderColor
                            : Colors.white.withAlpha(179)),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: widget.isLoading
                        ? Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark
                                        ? cDarkTextSecondary
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Loading...',
                                style: widget.textTheme.labelLarge!.copyWith(
                                  color: isDark
                                      ? cDarkTextSecondary
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            hasValue ? widget.value : widget.hint,
                            overflow: TextOverflow.ellipsis,
                            style: widget.textTheme.labelLarge!.copyWith(
                              color: hasValue
                                  ? (isDark
                                        ? cDarkTextPrimary
                                        : const Color(0xff111827))
                                  : (widget.isEmptyAfterLoad
                                        ? Colors.orange.shade700
                                        : (isDark
                                              ? cDarkTextSecondary
                                              : Colors.grey)),
                            ),
                          ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _overlayOpen,
                    builder: (_, open, _) {
                      return Icon(
                        open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark
                            ? cDarkIconColor
                            : const Color(0xFF6B7280),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
