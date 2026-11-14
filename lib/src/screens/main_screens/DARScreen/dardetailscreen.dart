import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/darmodel.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';

class DARDetailScreen extends StatefulWidget {
  final DarModel data;
  const DARDetailScreen({super.key, required this.data});

  @override
  State<DARDetailScreen> createState() => _DARDetailScreenState();
}

class _DARDetailScreenState extends State<DARDetailScreen> {
  final ApiService _apiService = ApiService();
  late DarModel dar;
  final RxBool isLoading = false.obs;

  @override
  void initState() {
    super.initState();
    dar = widget.data;
    _fetchDetail(dar.id.toString());
  }

  Future<void> _fetchDetail(String darId) async {
    try {
      isLoading.value = true;

      final resp = await _apiService.getData(
        ApiURL.getDarDetail.replaceAll('{darId}', darId),
      );

      if (resp is Map<String, dynamic>) {
        setState(() {
          dar = DarModel.fromJson(resp);
        });
      }
    } catch (e) {
      AppSnackBar.show(
        // ignore: use_build_context_synchronously
        context,
        'Failed to load full DAR details',
        type: SnackBarType.error,
      );
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      body: SafeArea(
        child: Column(
          children: [
            // ------- Header -------
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _BackCircleButton(onTap: () => Get.back()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Center(
                      child: Text(
                        'DAR Details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? cDarkTextPrimary
                                  : const Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ) ??
                            TextStyle(
                              color: isDark
                                  ? cDarkTextPrimary
                                  : const Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ------- Content -------
            Expanded(
              child: Obx(() {
                if (isLoading.value) {
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: isDark ? const Color(0xFF3B82F6) : cPrimary,
                    ),
                  );
                }

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StatusBadge(status: dar.status),
                            const SizedBox(height: 18),

                            // Incident-only fields
                            if ((dar.seriousness ?? '').toLowerCase() ==
                                'incident') ...[
                              _SectionTitle(title: 'Incident Details'),
                              const SizedBox(height: 10),
                              _InfoItem(
                                label: 'Police Notified',
                                value: (dar.policeNotified == true)
                                    ? 'Yes'
                                    : 'No',
                              ),
                              if (dar.policeNotified == true) ...[
                                const _InfoDivider(),
                                _InfoItem(
                                  label: 'Police Report Number',
                                  value: dar.policeReportNumber ?? 'N/A',
                                ),
                              ],
                              const _InfoDivider(),
                              _InfoItem(
                                label: 'Manager Notified',
                                value: (dar.managerNotified == true)
                                    ? 'Yes'
                                    : 'No',
                              ),
                              if (dar.managerNotified == true) ...[
                                const _InfoDivider(),
                                _InfoItem(
                                  label: 'Manager Name',
                                  value: dar.managerName ?? 'N/A',
                                ),
                              ],
                              const SizedBox(height: 14),
                            ],

                            _InfoItem(
                              label: 'Reported At',
                              value:
                                  '${DateFormat.yMMMd().format(dar.dateTime.toLocal())} • ${DateFormat.jm().format(dar.dateTime.toLocal())}',
                            ),
                            const _InfoDivider(),
                            _InfoItem(label: 'Site Name', value: dar.siteName),
                            const _InfoDivider(),
                            _InfoItem(
                              label: 'Shift Type',
                              value: dar.shiftType,
                            ),
                            const _InfoDivider(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _InfoItem(
                                    label: 'Guard Group',
                                    value: dar.guardGroup,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 48,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  color: isDark
                                      ? cDarkBorderColor.withAlpha(120)
                                      : const Color(0xFFE5E7EB),
                                ),
                                Expanded(
                                  child: _InfoItem(
                                    label: 'Unit Number',
                                    value: dar.unitNumber,
                                  ),
                                ),
                              ],
                            ),
                            const _InfoDivider(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _InfoItem(
                                    label: 'Location (GPS)',
                                    value:
                                        (dar.latitude != null &&
                                            dar.longitude != null)
                                        ? '${dar.latitude}, ${dar.longitude}'
                                        : 'N/A',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _OpenMapsButton(
                                  onTap: () {
                                    openMap(
                                      dar.siteName,
                                      dar.latitude ?? 0.0,
                                      dar.longitude ?? 0.0,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(title: 'Description'),
                            const SizedBox(height: 8),
                            Text(
                              dar.description?.trim().isNotEmpty == true
                                  ? dar.description!
                                  : 'No description provided',
                              style:
                                  textTheme.bodyMedium?.copyWith(
                                    color: isDark
                                        ? cDarkTextPrimary
                                        : const Color(0xFF111827),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    height: 1.35,
                                  ) ??
                                  TextStyle(
                                    color: isDark
                                        ? cDarkTextPrimary
                                        : const Color(0xFF111827),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    height: 1.35,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            const _InfoDivider(noVerticalPadding: true),
                            const SizedBox(height: 14),
                            _SectionTitle(title: 'Photos'),
                            const SizedBox(height: 10),
                            _buildImagesGrid(),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> openMap(String locationName, double lat, double lng) async {
    final availableMaps = await MapLauncher.installedMaps;

    await availableMaps.first.showMarker(
      coords: Coords(lat, lng),
      title: locationName,
    );
  }

  Widget _buildImagesGrid() {
    if (dar.photos.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dar.photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final image = dar.photos[index];

        return InkWell(
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black.withAlpha(
                Theme.of(context).brightness == Brightness.dark ? 217 : 242,
              ),
              builder: (_) => Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: cTransparent,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: InteractiveViewer(
                    child: Center(
                      child: Image.network(image, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              image,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  color: isDark ? cDarkDividerColor : const Color(0xFFF1F5F9),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? const Color(0xFF3B82F6) : cPrimary,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  color: isDark ? cDarkBorderColor : const Color(0xFFE5E7EB),
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 22,
                    color: isDark ? cDarkIconColor : const Color(0xFF94A3B8),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _BackCircleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackCircleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      overlayColor: const WidgetStatePropertyAll(cTransparent),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : cWhite,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 45 : 10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 19,
          color: isDark ? cDarkIconColor : const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cDarkCardColor : cWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? cDarkBorderColor.withAlpha(120)
              : const Color(0xFFE9EDF3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 45 : 12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Text(
      title,
      style:
          Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
            letterSpacing: -0.1,
            height: 1.2,
          ) ??
          TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
            letterSpacing: -0.1,
            height: 1.2,
          ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
              textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
                height: 1.2,
              ) ??
              TextStyle(
                fontSize: 12.5,
                color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          value?.trim().isNotEmpty == true ? value! : 'N/A',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              textTheme.bodyMedium?.copyWith(
                fontSize: 14.5,
                color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: -0.1,
              ) ??
              TextStyle(
                fontSize: 14.5,
                color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: -0.1,
              ),
        ),
      ],
    );
  }
}

class _InfoDivider extends StatelessWidget {
  final bool noVerticalPadding;

  const _InfoDivider({this.noVerticalPadding = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: noVerticalPadding ? 0 : 13),
      child: Container(
        height: 1,
        color: isDark
            ? cDarkBorderColor.withAlpha(120)
            : const Color(0xFFE9EDF3),
      ),
    );
  }
}

class _OpenMapsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OpenMapsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : cWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? cDarkBorderColor : const Color(0xFFD6DEE8),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 17,
              color: isDark ? const Color(0xFF60A5FA) : cPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              'Open in Maps',
              style:
                  Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isDark ? const Color(0xFF60A5FA) : cPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ) ??
                  TextStyle(
                    color: isDark ? const Color(0xFF60A5FA) : cPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = getStatusTextColor(status, isDark: isDark);
    final bgColor = getStatusBgColor(status, isDark: isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: textColor.withAlpha(isDark ? 95 : 45),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_darStatusIcon(status), size: 15, color: textColor),
          const SizedBox(width: 6),
          Text(
            formatStatusText(status),
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.1,
                ) ??
                TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.1,
                ),
          ),
        ],
      ),
    );
  }
}

IconData _darStatusIcon(String status) {
  final s = status.toLowerCase().trim();

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
