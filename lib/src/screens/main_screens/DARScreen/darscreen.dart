import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/createdar.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/dardetailscreen.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/darmodel.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/filtercontroller.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/filterscreen.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/dar_list_controller.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/timer_controller.dart';
import 'package:shimmer/shimmer.dart';

import 'package:smartnps360/src/screens/utilities/const.dart';

class DARScreen extends StatefulWidget {
  const DARScreen({super.key});

  @override
  State<DARScreen> createState() => _DARScreenState();
}

class _DARScreenState extends State<DARScreen> {
  final FilterController _fc = Get.put(FilterController());
  final TimeController _tc = Get.find<TimeController>();
  final DarListController _listC = Get.put(DarListController());
  final TextEditingController _searchController = TextEditingController();
  final _storage = GetStorage();

  @override
  void initState() {
    super.initState();
    if (_listC.allDars.isEmpty) _listC.fetchDars(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    _searchController.clear();
    _listC.search('');

    _fc.resetApplied();
    _listC.applyFilters(_fc.toMap());

    await _listC.fetchDars(reset: true);
  }

  void _openFilter() {
    _fc.fetchFilterLists().then((_) {
      _fc.beginEdit();

      showFilterBottomSheet(
        // ignore: use_build_context_synchronously
        context: context,
        onApply: (filters) {
          _fc.applyDraft();
          _listC.applyFilters(_fc.toMap());
        },
        onReset: () {
          _fc.resetApplied();
          _listC.applyFilters(_fc.toMap());
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final roleRaw = _storage.read('role');
    final isOnSiteOfficer = roleRaw is String && roleRaw == onSiteOfficer;
    final onDuty = _tc.onDuty.value;
    final showFab = (isOnSiteOfficer && onDuty == true);

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: showFab
          ? Obx(() {
              final visible = _listC.isFabVisible.value;
              return AnimatedSlide(
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeInOut,
                offset: visible ? Offset.zero : const Offset(0, 1.2),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 550),
                  opacity: visible ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FloatingActionButton.extended(
                      onPressed: () {
                        Get.to(const CreatDARScreen());
                      },
                      elevation: 7,
                      backgroundColor: cPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      icon: const Icon(
                        Icons.add_rounded,
                        color: cWhite,
                        size: 21,
                      ),
                      label: const Text(
                        'Add DAR',
                        style: TextStyle(
                          color: cWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .1,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            })
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Activity Report',
                style: textTheme.headlineMedium?.copyWith(
                  fontSize: 24,
                  color: isDark ? cDarkTextPrimary : const Color(0xff030B17),
                  fontWeight: FontWeight.w700,
                  height: 1.08,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'View and filter your reports.',
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: isDark ? cDarkTextSecondary : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 18),

              Obx(
                () => _SearchAndFilterBar(
                  controller: _searchController,
                  activeFilterCount: _fc.activeFilterCount,
                  onChanged: _listC.search,
                  onFilterTap: _openFilter,
                ),
              ),

              Obx(() {
                if (!_fc.hasActiveFilters) return const SizedBox(height: 14);
                final activeFilters = _fc.getActiveFilters();
                final count = _fc.activeFilterCount;

                return Container(
                  margin: const EdgeInsets.only(top: 14, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active Filters',
                            style: textTheme.labelMedium?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? cDarkTextSecondary
                                  : const Color(0xFF667085),
                            ),
                          ),
                          if (count > 0)
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                _fc.resetApplied();
                                _listC.applyFilters(_fc.toMap());
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Clear All',
                                  style: textTheme.labelMedium?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFF60A5FA)
                                        : cPrimary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: activeFilters.map((filter) {
                          return _filterChip(
                            context: context,
                            label: filter['label']!,
                            onRemove: () {
                              _fc.removeFilter(filter['type']!);
                              _listC.applyFilters(_fc.toMap());
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),

              Expanded(
                child: Obx(() {
                  final list = _listC.dars;
                  if (_listC.loading.value && list.isEmpty) {
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 170),
                      itemCount: 6,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (context, index) =>
                          _darSkeletonCard(context),
                    );
                  }
                  if (list.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _onRefresh,
                      color: cPrimary,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 170),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * .48,
                            child: _EmptyDarState(isDark: isDark),
                          ),
                        ],
                      ),
                    );
                  }

                  return NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction == ScrollDirection.reverse) {
                        if (_listC.isFabVisible.value) {
                          _listC.setFabVisible(false);
                        }
                      } else if (notification.direction ==
                              ScrollDirection.forward ||
                          notification.direction == ScrollDirection.idle) {
                        if (!_listC.isFabVisible.value) {
                          _listC.setFabVisible(true);
                        }
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: _onRefresh,
                      displacement: 40.0,
                      strokeWidth: 2.5,
                      color: cPrimary,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.only(bottom: 170),
                        itemCount: list.length + (_listC.hasMore.value ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 11),
                        itemBuilder: (context, index) {
                          if (index >= list.length) {
                            _listC.fetchDars(loadMore: true);
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.3,
                                  ),
                                ),
                              ),
                            );
                          }
                          final r = list[index];
                          return _darCard(context, r);
                        },
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchAndFilterBar extends StatelessWidget {
  const _SearchAndFilterBar({
    required this.controller,
    required this.activeFilterCount,
    required this.onChanged,
    required this.onFilterTap,
  });

  final TextEditingController controller;
  final int activeFilterCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: isDark ? cDarkCardColor : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? cDarkBorderColor : const Color(0xFFE8EDF3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 45 : 10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 21,
                  color: isDark ? cDarkTextSecondary : const Color(0xFF667085),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    cursorColor: cPrimary,
                    style: textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF111827),
                    ),
                    decoration: InputDecoration(
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: true,
                      fillColor: Colors.transparent,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Search DAR',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                        color: isDark
                            ? cDarkTextSecondary
                            : const Color(0xFF8A93A3),
                      ),
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          overlayColor: WidgetStatePropertyAll(cTransparent),
          borderRadius: BorderRadius.circular(18),
          onTap: onFilterTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? cDarkCardColor : Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: isDark
                          ? cDarkBorderColor
                          : const Color(0xFFE8EDF3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 45 : 10),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.tune_rounded,
                      size: 22,
                      color: isDark
                          ? cDarkTextSecondary
                          : const Color(0xFF667085),
                    ),
                  ),
                ),
                if (activeFilterCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3B82F6) : cPrimary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isDark ? cDarkCardColor : cWhite,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        activeFilterCount > 9 ? '9+' : '$activeFilterCount',
                        style: const TextStyle(
                          color: cWhite,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _darCard(BuildContext context, DarModel data) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final photos = data.photos;
  final statusColor = getStatusTextColor(data.status, isDark: isDark);

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () {
        Get.to(DARDetailScreen(data: data));
      },
      borderRadius: BorderRadius.circular(17),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isDark ? cDarkBorderColor : const Color(0xFFE8EDF3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 48 : 10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 16,
                  color: isDark ? cDarkTextSecondary : const Color(0xFF667085),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${DateFormat.yMMMd().format(data.dateTime)} • ${DateFormat.jm().format(data.dateTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark
                          ? cDarkTextSecondary
                          : const Color(0xFF667085),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _DarStatusBadge(status: data.status),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              data.siteName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.8,
                height: 1.16,
                letterSpacing: -0.15,
                color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Shift: ${data.shift}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? cDarkTextSecondary : const Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 11),
              _PhotoStrip(photos: photos, statusColor: statusColor),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DarStatusBadge extends StatelessWidget {
  const _DarStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = getStatusBgColor(status, isDark: isDark);
    final textColor = getStatusTextColor(status, isDark: isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: textColor.withAlpha(isDark ? 95 : 45),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_darStatusIcon(status), size: 14, color: textColor),
          const SizedBox(width: 5),
          Text(
            formatStatusText(status),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _darStatusIcon(String status) {
  final s = status.trim().toLowerCase();

  if (s.contains('good')) {
    return Icons.check_circle_outline_rounded;
  }
  if (s.contains('moderate') || s.contains('mooderate')) {
    return Icons.warning_amber_rounded;
  }
  if (s.contains('incident')) {
    return Icons.report_problem_outlined;
  }
  if (s.contains('critical')) {
    return Icons.crisis_alert_rounded;
  }

  return Icons.info_outline_rounded;
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.statusColor});

  final List<String> photos;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 8.0;
        final tileWidth = (constraints.maxWidth - (spacing * 2)) / 3;
        final tileHeight = tileWidth * .66;

        return Row(
          children: [
            _photoTile(context, photos[0], tileWidth, tileHeight),
            if (photos.length > 1) ...[
              SizedBox(width: spacing),
              _photoTile(context, photos[1], tileWidth, tileHeight),
            ],
            if (photos.length > 2) ...[
              SizedBox(width: spacing),
              _photoOverlayTile(
                context,
                photos[2],
                photos.length - 2,
                tileWidth,
                tileHeight,
                statusColor,
              ),
            ] else if (photos.length == 2) ...[
              SizedBox(width: spacing),
              SizedBox(width: tileWidth, height: tileHeight),
            ],
          ],
        );
      },
    );
  }
}

Widget _photoTile(
  BuildContext context,
  String url,
  double width,
  double height,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? cDarkDividerColor : const Color(0xFFF3F6FA),
      ),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;

          return Container(
            color: isDark ? cDarkDividerColor : const Color(0xFFF3F6FA),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? cDarkTextSecondary : cPrimary,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: isDark ? cDarkBorderColor : const Color(0xFFE5E7EB),
            child: Icon(
              Icons.broken_image_outlined,
              size: 22,
              color: isDark ? cDarkIconColor : const Color(0xFF98A2B3),
            ),
          );
        },
      ),
    ),
  );
}

Widget _photoOverlayTile(
  BuildContext context,
  String url,
  int extraCount,
  double width,
  double height,
  Color statusColor,
) {
  return Stack(
    alignment: Alignment.center,
    children: [
      _photoTile(context, url, width, height),
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withAlpha(45), Colors.black.withAlpha(174)],
          ),
        ),
        child: Center(
          child: Text(
            '+$extraCount',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _filterChip({
  required BuildContext context,
  required String label,
  required VoidCallback onRemove,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final badgeColor = isDark ? const Color(0xFF60A5FA) : cPrimary;

  return InkWell(
    overlayColor: WidgetStateProperty.all(cTransparent),
    borderRadius: BorderRadius.circular(999),
    onTap: onRemove,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeColor.withAlpha(70), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_outlined, size: 13, color: badgeColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: badgeColor,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Icon(Icons.close_rounded, size: 15, color: badgeColor),
        ],
      ),
    ),
  );
}

class _EmptyDarState extends StatelessWidget {
  const _EmptyDarState({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isDark ? cDarkBorderColor : const Color(0xFFE8EDF3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cPrimary.withAlpha(isDark ? 36 : 20),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                color: isDark ? const Color(0xFF60A5FA) : cPrimary,
                size: 25,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No reports found',
              style: TextStyle(
                color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Try changing your search or filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? cDarkTextSecondary : const Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _darSkeletonCard(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? cDarkCardColor : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark ? cDarkBorderColor : const Color(0xFFE8EDF3),
      ),
    ),
    child: Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: isDark
                      ? cDarkBorderColor.withAlpha(179)
                      : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _skelLine(context: context, h: 12, radius: 6)),
              const SizedBox(width: 10),
              _skelLine(context: context, h: 26, w: 88, radius: 999),
            ],
          ),
          const SizedBox(height: 12),
          _skelLine(context: context, h: 17, w: double.infinity, radius: 6),
          const SizedBox(height: 7),
          _skelLine(context: context, h: 13, w: 180, radius: 6),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _skelPhoto(context)),
              const SizedBox(width: 9),
              Expanded(child: _skelPhoto(context)),
              const SizedBox(width: 9),
              Expanded(child: _skelPhoto(context)),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _skelPhoto(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return AspectRatio(
    aspectRatio: 1.38,
    child: Container(
      decoration: BoxDecoration(
        color: isDark ? cDarkBorderColor.withAlpha(179) : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

Widget _skelLine({
  required BuildContext context,
  double? w,
  double h = 14,
  double radius = 6,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: isDark
          ? cDarkBorderColor.withAlpha(179)
          : Colors.grey.shade300.withAlpha(255),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
