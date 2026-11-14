import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/filtercontroller.dart'
    show FilterController;
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/widgets/dropdownwidget.dart';

Future<void> showFilterBottomSheet({
  required BuildContext context,
  required void Function(Map<String, dynamic> filters) onApply,
  VoidCallback? onReset,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final FilterController fc = Get.isRegistered<FilterController>()
      ? Get.find<FilterController>()
      : Get.put(FilterController());

  fc.beginEdit();
  fc.fetchFilterLists();

  await Get.bottomSheet(
    MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: SafeArea(
        child: _FilterBottomSheetBody(onApply: onApply, onReset: onReset),
      ),
    ),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(isDark ? 128 : 89),
  );
}

class _FilterBottomSheetBody extends StatefulWidget {
  final void Function(Map<String, dynamic> filters) onApply;
  final VoidCallback? onReset;

  const _FilterBottomSheetBody({required this.onApply, this.onReset});

  @override
  State<_FilterBottomSheetBody> createState() => _FilterBottomSheetBodyState();
}

class _FilterBottomSheetBodyState extends State<_FilterBottomSheetBody> {
  late final FilterController fc;
  final TextEditingController _siteSearchController = TextEditingController();
  final FocusNode _siteFocusNode = FocusNode();
  final LayerLink _siteLayerLink = LayerLink();
  final GlobalKey _siteFieldKey = GlobalKey();
  OverlayEntry? _siteOverlayEntry;
  StreamSubscription<bool>? _showSub;
  StreamSubscription<dynamic>? _filteredSub;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    fc = Get.find<FilterController>();

    if (fc.selectedSite.value.isNotEmpty &&
        fc.selectedSite.value != fc.sites.first) {
      _siteSearchController.text = fc.selectedSite.value;
    }

    _showSub = fc.showSiteDropdown.stream.listen((show) {
      if (show) {
        _insertSiteOverlay();
      } else {
        _removeSiteOverlay();
      }
    });

    _filteredSub = fc.filteredSites.stream.listen((_) {
      _siteOverlayEntry?.markNeedsBuild();
    });

    _siteFocusNode.addListener(() {
      if (!_siteFocusNode.hasFocus) {
        fc.showSiteDropdown.value = false;
      }
    });
  }

  void _dismissKeyboardAndSiteOverlay() {
    fc.showSiteDropdown.value = false;
    _removeSiteOverlay();
    FocusManager.instance.primaryFocus?.unfocus();
    _siteFocusNode.unfocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showSub?.cancel();
    _filteredSub?.cancel();
    _removeSiteOverlay();
    _siteSearchController.dispose();
    _siteFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final textTheme = Theme.of(context).textTheme;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: h * 0.85,
            minHeight: 180,
            maxWidth: w,
          ),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      cDarkCardColor.withAlpha(230),
                      cDarkBackground.withAlpha(204),
                    ]
                  : [Colors.white.withAlpha(115), Colors.white.withAlpha(38)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: isDark
                  ? cDarkBorderColor.withAlpha(166)
                  : Colors.white.withAlpha(64),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 77 : 38),
                blurRadius: 20,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "Filter Reports",
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
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
                    onTap: () => Get.back(),
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
              const SizedBox(height: 6),
              Text(
                "(choose site, shift & seriousness level)",
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
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(bottom: keyboardOpen ? 12 : 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Obx(() {
                        final isLoading = fc.sitesLoading.value;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All Sites',
                              style: TextStyle(
                                color: isDark
                                    ? cDarkTextPrimary
                                    : const Color(0xFF374151),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            CompositedTransformTarget(
                              link: _siteLayerLink,
                              key: _siteFieldKey,
                              child: TextFormField(
                                controller: _siteSearchController,
                                focusNode: _siteFocusNode,
                                readOnly: isLoading,
                                onChanged: (value) {
                                  fc.searchSites(value);
                                  fc.showSiteDropdown.value =
                                      value.isNotEmpty && !isLoading;
                                },
                                onTap: () {
                                  if (!isLoading &&
                                      _siteSearchController.text.isNotEmpty) {
                                    fc.showSiteDropdown.value = true;
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: isLoading
                                      ? 'Loading sites...'
                                      : 'Search and select site...',
                                  filled: true,
                                  fillColor: isDark
                                      ? cDarkInputFillColor
                                      : Colors.white.withAlpha(153),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_siteSearchController.text.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.clear,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            _siteSearchController.clear();
                                            fc.searchSites('');
                                            fc.selectedSite.value =
                                                fc.sites.first;
                                            fc.showSiteDropdown.value = false;
                                          },
                                        ),
                                      if (!isLoading)
                                        IconButton(
                                          icon: Icon(
                                            fc.showSiteDropdown.value
                                                ? Icons
                                                      .keyboard_arrow_up_rounded
                                                : Icons
                                                      .keyboard_arrow_down_rounded,
                                            color: isDark
                                                ? cDarkIconColor
                                                : const Color(0xFF6B7280),

                                            size: 24,
                                          ),
                                          onPressed: () {
                                            if (_siteSearchController
                                                .text
                                                .isEmpty) {
                                              fc.searchSites('');
                                            }
                                            fc.showSiteDropdown.value =
                                                !fc.showSiteDropdown.value;
                                            if (fc.showSiteDropdown.value) {
                                              _siteFocusNode.requestFocus();
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? cDarkBorderColor
                                          : Colors.white.withAlpha(178),
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: const Color(
                                        0xFF007AFF,
                                      ).withAlpha(204),
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 16),
                      Obx(
                        () => PaddedOverlayDropdown(
                          label: "All Shifts",
                          value: fc.selectedShift.value,
                          items: fc.shifts.toList(),
                          hint: "Select shift...",
                          isLoading: fc.shiftsLoading.value,
                          onOpen: _dismissKeyboardAndSiteOverlay,
                          menuHorizontalMargin: 16,
                          onChanged: (v) => fc.setShift(v),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Obx(
                        () => PaddedOverlayDropdown(
                          label: "Any Level",
                          value: fc.selectedSeriousness.value,
                          items: fc.seriousnessLevels.toList(),
                          hint: "Select level...",
                          isLoading: false,
                          onOpen: _dismissKeyboardAndSiteOverlay,
                          menuHorizontalMargin: 16,
                          onChanged: (v) => fc.setSeriousness(v),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: keyboardOpen
                    ? const SizedBox.shrink()
                    : SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  fc.showSiteDropdown.value = false;
                                  _removeSiteOverlay();
                                  _siteFocusNode.unfocus();
                                  fc.resetApplied();
                                  if (widget.onReset != null) {
                                    widget.onReset!();
                                  }
                                  Get.back();
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
                                      "Reset",
                                      style: textTheme.bodyLarge!.copyWith(
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
                              child: Obx(() {
                                final canSave =
                                    fc.hasDraftActiveFilters &&
                                    !fc.sitesLoading.value;

                                return GestureDetector(
                                  onTap: canSave
                                      ? () {
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          fc.applyDraft();
                                          final filters = fc.toMap();
                                          Get.back();
                                          widget.onApply(filters);
                                        }
                                      : null,
                                  child: Opacity(
                                    opacity: canSave ? 1.0 : 0.45,
                                    child: Container(
                                      height: 44,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        color: canSave
                                            ? const Color(0xFF007AFF)
                                            : (isDark
                                                  ? cDarkBorderColor
                                                  : Colors.grey.shade400),
                                      ),
                                      child: Center(
                                        child: Text(
                                          "Save",
                                          style: textTheme.bodyLarge!.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiteDropdownOverlay(List<Map<String, dynamic>> items) {
    final controller = fc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Builder(
        builder: (context) {
          return Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: isDark ? cDarkCardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 77 : 38),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final site = items[index];
                final siteName = (site['name'] ?? '').toString();
                final isSelected = controller.selectedSite.value == siteName;

                return InkWell(
                  onTap: () {
                    _siteSearchController.text = siteName;
                    controller.setSite(siteName);
                    controller.showSiteDropdown.value = false;
                    _siteFocusNode.unfocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                                ? const Color(0xFF3B82F6).withAlpha(26)
                                : cPrimary.withAlpha(26))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            siteName,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? (isDark
                                        ? const Color(0xFF3B82F6)
                                        : cPrimary)
                                  : (isDark
                                        ? cDarkTextPrimary
                                        : Colors.black87),
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check,
                            color: isDark ? const Color(0xFF3B82F6) : cPrimary,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _insertSiteOverlay() {
    if (_siteOverlayEntry != null) return;

    _siteOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  fc.showSiteDropdown.value = false;
                  _siteFocusNode.unfocus();
                },
              ),
            ),
            CompositedTransformFollower(
              link: _siteLayerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 56 + 6),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width - 32,
                  ),
                  child: _buildSiteDropdownOverlay(fc.filteredSites.toList()),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_siteOverlayEntry!);
  }

  void _removeSiteOverlay() {
    _siteOverlayEntry?.remove();
    _siteOverlayEntry = null;
  }
}
