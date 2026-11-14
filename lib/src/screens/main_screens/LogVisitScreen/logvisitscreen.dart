import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smartnps360/src/screens/main_screens/LogVisitScreen/logvisitcontroller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/widgets/gradientbutton.dart';
import 'package:smartnps360/src/screens/main_screens/DashboardScreen/assignmentmodel.dart';

class LogVisitScreen extends StatefulWidget {
  final Assignment assignment;

  const LogVisitScreen({super.key, required this.assignment});

  @override
  State<LogVisitScreen> createState() => _LogVisitScreenState();
}

class _LogVisitScreenState extends State<LogVisitScreen> {
  late final LogVisitController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(
      LogVisitController(
        scheduleId: widget.assignment.scheduleId,
        siteId: widget.assignment.siteId,
      ),
    );
  }

  @override
  void dispose() {
    Get.delete<LogVisitController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSiteInfoCard(),
            Obx(
              () =>
                  _controller.locationPermissionStatus.value ==
                      LocationPermissionStatus.granted
                  ? Expanded(child: _buildMapSection())
                  : Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: _buildLocationPermissionSection(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildBackButton(),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: Text(
                "Log Visit",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isDark ? cDarkTextPrimary : const Color(0xff030B17),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => Get.back(),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : cWhite,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0xFF111827))
                  .withAlpha(isDark ? 77 : 10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_back_ios_rounded,
          color: isDark ? cDarkIconColor : const Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _buildSiteInfoCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: getCardDecoration(context).copyWith(
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.black).withAlpha(
              isDark ? 51 : 15,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cPrimary.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.info_outline, size: 16, color: cPrimary),
              ),
              const SizedBox(width: 8),
              Text(
                'Site Information',
                style: cSectionHeadingStyle.copyWith(
                  fontSize: 15,
                  color: isDark ? cDarkTextPrimary : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CompactInfoRow(
            icon: Icons.location_on,
            value: widget.assignment.site,
            isDark: isDark,
          ),
          const SizedBox(height: 6),
          _CompactInfoRow(
            icon: Icons.access_time,
            value: _formatTime(
              widget.assignment.startTime,
              widget.assignment.endTime,
            ),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPermissionSection() {
    return Obx(() {
      switch (_controller.locationPermissionStatus.value) {
        case LocationPermissionStatus.denied:
          return _buildPermissionRequestCard();
        case LocationPermissionStatus.permanentlyDenied:
          return _buildPermissionDeniedCard();
        case LocationPermissionStatus.granted:
          return const SizedBox.shrink();
        default:
          return _buildLoadingCard();
      }
    });
  }

  Widget _buildPermissionRequestCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark
              ? [cDarkCardColor.withAlpha(242), cDarkCardColor.withAlpha(217)]
              : [Colors.white.withAlpha(115), Colors.white.withAlpha(38)],
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Column(
            children: [
              _buildIconContainer(Icons.location_on_outlined, cPrimary),
              const SizedBox(height: 16),
              Text(
                'Location Access Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? cDarkTextPrimary : cDarkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'To log your visit, we need access to your current location',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? cDarkTextSecondary
                      : Colors.black.withAlpha(153),
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                text: 'Grant Location Access',
                onPressed: () => _controller.requestLocationPermission(),
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: getCardDecoration(context).copyWith(
        color: isDark ? const Color(0xFF3A1D1D) : const Color(0xFFFEE2E2),
      ),
      child: Column(
        children: [
          _buildIconContainer(Icons.location_off_outlined, cRed),
          const SizedBox(height: 16),
          Text(
            'Location Permission Denied',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cDarkText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please enable location access from device settings',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? cDarkTextSecondary : Colors.black.withAlpha(179),
            ),
          ),
          const SizedBox(height: 20),
          _buildPrimaryButton(
            'Open Settings',
            cRed,
            () => _controller.openAppSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      // Show loading indicator while fetching location
      if (_controller.isLoadingLocation.value) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          height: 300,
          decoration: BoxDecoration(
            color: isDark ? cDarkCardColor : cWhite,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 51 : 20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Fetching your location...',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? cDarkTextSecondary : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final location = _controller.currentLocation.value;
      // Only show map when we have user location coordinates
      if (location == null) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          height: 300,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF3E3111) : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 51 : 20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_searching,
                  size: 48,
                  color: isDark
                      ? const Color(0xFFF0B35A)
                      : Colors.orange.shade700,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to fetch your location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFF8DDAE)
                        : Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please ensure location services are enabled and try again',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFFE6B673)
                        : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _controller.refreshLocation(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Show map only when we have valid user location
      return _MapWidget(controller: _controller, location: location);
    });
  }

  Widget _buildLoadingCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: getCardDecoration(
        context,
      ).copyWith(color: isDark ? cDarkCardColor : cWhite),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildIconContainer(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 48, color: color),
    );
  }

  Widget _buildPrimaryButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatTime(String startTime, String endTime) {
    try {
      final start = DateTime.parse(startTime);
      final end = DateTime.parse(endTime);
      return '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - '
          '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}

// Compact info row for site information
class _CompactInfoRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool isDark;
  const _CompactInfoRow({
    required this.icon,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cPrimary.withAlpha(179)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? cDarkTextPrimary : cDarkText,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// Helper widget for site info rows
// ignore: unused_element
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: cPrimary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? cDarkTextSecondary : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: cDarkText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Separate widget for map to prevent unnecessary rebuilds
class _MapWidget extends StatelessWidget {
  final LogVisitController controller;
  final Position location;

  const _MapWidget({required this.controller, required this.location});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: Obx(
                    () => GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(location.latitude, location.longitude),
                        zoom: 15,
                      ),
                      markers: controller.markers.toSet(),
                      circles: controller.circles,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: true,
                      onMapCreated: (GoogleMapController mapController) {
                        controller.onMapCreated(mapController);
                      },
                      // padding: const EdgeInsets.only(bottom: 60),
                    ),
                  ),
                ),
                // Refresh Location Button
                Positioned(
                  right: 6,
                  bottom: 10,
                  child: Obx(
                    () => FloatingActionButton(
                      mini: true,
                      backgroundColor: isDark ? cDarkCardColor : Colors.white,
                      elevation: 4,
                      onPressed: controller.isLoadingLocation.value
                          ? null
                          : () => controller.refreshLocation(),
                      child: controller.isLoadingLocation.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cPrimary,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.my_location,
                              color: isDark ? cDarkIconColor : cPrimary,
                              size: 20,
                            ),
                    ),
                  ),
                ),
                // Loading overlay until map is ready
                Obx(
                  () => !controller.isMapReady.value
                      ? Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? cDarkCardColor.withAlpha(230)
                                : Colors.white.withAlpha(230),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading map...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? cDarkTextPrimary
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildLogVisitButton(),
        ],
      ),
    );
  }

  Widget _buildLogVisitButton() {
    return Obx(() {
      final isDark = Theme.of(Get.context!).brightness == Brightness.dark;
      final distance = controller.distanceToSite.value;
      final isWithinRange = controller.isWithinRange.value;
      final siteCoords = controller.siteCoordinates.value;
      final hasLocation = controller.currentLocation.value != null;

      // Show distance indicator if we have both locations
      return Column(
        children: [
          // Distance indicator
          if (hasLocation && siteCoords != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isWithinRange
                    ? (isDark
                          ? const Color(0xFF123B2C)
                          : const Color(0xFFD1FAE5))
                    : (isDark
                          ? const Color(0xFF3A1D1D)
                          : const Color(0xFFFEE2E2)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isWithinRange
                      ? (isDark
                            ? const Color(0xFF5DD9A3)
                            : const Color(0xFF10B981))
                      : (isDark
                            ? const Color(0xFFF07A7A)
                            : const Color(0xFFEF4444)),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isWithinRange ? Icons.check_circle : Icons.info_outline,
                    color: isWithinRange
                        ? (isDark
                              ? const Color(0xFF93E5C3)
                              : const Color(0xFF059669))
                        : (isDark
                              ? const Color(0xFFF8A3A3)
                              : const Color(0xFFDC2626)),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isWithinRange
                          ? 'You are ${distance.toStringAsFixed(0)}m from site - Ready to log'
                          : 'You are ${distance.toStringAsFixed(0)}m from site - Move within 200m',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isWithinRange
                            ? (isDark
                                  ? const Color(0xFFC5F4DF)
                                  : const Color(0xFF065F46))
                            : (isDark
                                  ? const Color(0xFFFDD2D2)
                                  : const Color(0xFF991B1B)),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Log Visit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (controller.isLoggingVisit.value || !isWithinRange)
                  ? null
                  : () => controller.logVisit(),
              style: ElevatedButton.styleFrom(
                backgroundColor: isWithinRange
                    ? cPrimary
                    : (isDark ? cDarkBorderColor : Colors.grey),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: isWithinRange ? 4 : 0,
                shadowColor: isWithinRange ? cPrimary.withAlpha(102) : null,
                disabledBackgroundColor: isDark
                    ? cDarkBorderColor
                    : Colors.grey.shade300,
              ),
              child: controller.isLoggingVisit.value
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isWithinRange ? Icons.location_on : Icons.lock,
                          color: isWithinRange
                              ? Colors.white
                              : (isDark
                                    ? cDarkTextSecondary
                                    : Colors.grey.shade600),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isWithinRange ? 'Log Visit' : 'Out of Range',
                          style: TextStyle(
                            color: isWithinRange
                                ? Colors.white
                                : (isDark
                                      ? cDarkTextSecondary
                                      : Colors.grey.shade600),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      );
    });
  }
}
