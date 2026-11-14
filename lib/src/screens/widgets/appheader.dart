import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:shimmer/shimmer.dart';

class AppHeader extends StatelessWidget {
  final double height;
  final _userCtrl = Get.find<UserController>();

  AppHeader({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.paddingOf(context).top;
    final preferredHeight = height * 0.14;
    final resolvedHeight = preferredHeight < (topInset + 72)
        ? topInset + 72
        : preferredHeight;

    return Container(
      height: resolvedHeight,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Obx(() {
              final profile = _userCtrl.profileData.value;
              if (profile == null) {
                return Shimmer.fromColors(
                  baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
                  highlightColor: isDark
                      ? cDarkCardColor.withAlpha(128)
                      : Colors.grey.shade100,
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? cDarkBorderColor : Colors.grey[300],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            color: isDark ? cDarkBorderColor : Colors.grey[300],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 80,
                            height: 12,
                            color: isDark ? cDarkBorderColor : Colors.grey[300],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              final name = profile['fullName']?.toString() ?? 'Officer Name';
              final role = profile['role']?.toString().toUpperCase() ?? 'Role';
              final photo = profile['photoURL']?.toString();

              return Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: photo != null && photo.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(photo),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: isDark ? cDarkBorderColor : Colors.grey[300],
                    ),
                    child: (photo == null || photo.isEmpty)
                        ? Center(
                            child: Text(
                              name.isNotEmpty ? name[0] : 'O',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark ? cDarkTextPrimary : cDarkText,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "$role Security Officer",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: isDark
                              ? cDarkTextSecondary
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
            // InkWell(
            //   overlayColor: WidgetStatePropertyAll(cTransparent),
            //   onTap: () => Get.to(NotificationScreen()),
            //   child: Container(
            //     padding: const EdgeInsets.all(8),
            //     decoration: BoxDecoration(
            //       shape: BoxShape.circle,
            //       border: Border.all(color: Colors.grey.shade300, width: 1),
            //     ),
            //     child: Image.asset(
            //       'assets/Icons/notification-outline.png',
            //       height: 24,
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
