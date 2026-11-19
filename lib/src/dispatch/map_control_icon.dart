import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Resolution-independent map controls with consistent optical weight.
class MapControlIcon extends StatelessWidget {
  const MapControlIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });
  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String paths;
    if (icon == Icons.add_rounded) {
      paths = '<path d="M12 5v14M5 12h14"/>';
    } else if (icon == Icons.remove_rounded) {
      paths = '<path d="M5 12h14"/>';
    } else if (icon == Icons.close_rounded) {
      paths = '<path d="m6 6 12 12M18 6 6 18"/>';
    } else if (icon == Icons.arrow_back_rounded) {
      paths = '<path d="M19 12H5m0 0 6-6m-6 6 6 6"/>';
    } else if (icon == Icons.pin_drop_rounded) {
      paths =
          '<path d="M12 21s-6-5.3-6-10a6 6 0 1 1 12 0c0 4.7-6 10-6 10z"/><circle cx="12" cy="11" r="2.4" fill="currentColor" stroke="none"/>';
    } else if (icon == Icons.my_location_rounded) {
      paths =
          '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2.5" fill="currentColor" stroke="none"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>';
    } else if (icon == Icons.alt_route_rounded) {
      paths =
          '<path d="M8 20V8m-3 3 3-3 3 3M16 4v9a5 5 0 0 1-5 5H8m5-11 3-3 3 3"/>';
    } else if (icon == Icons.fullscreen_rounded) {
      paths =
          '<path d="M9 4H4v5m0-5 6 6m5-6h5v5m0-5-6 6M4 15v5h5m-5 0 6-6m10 1v5h-5m5 0-6-6"/>';
    } else if (icon == Icons.zoom_out_map_rounded) {
      paths =
          '<rect x="7" y="7" width="10" height="10" rx="1.5"/><path d="M4 9V4h5M20 9V4h-5M4 15v5h5m11-5v5h-5"/>';
    } else {
      paths =
          '<path d="M9 4H4v5m0-5 6 6m5-6h5v5m0-5-6 6M4 15v5h5m-5 0 6-6m10 1v5h-5m5 0-6-6"/>';
    }
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><g stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">$paths</g></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
