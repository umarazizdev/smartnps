import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

enum SnackBarType { info, success, error }

class AppSnackBar {
  AppSnackBar._();

  static void show(
    BuildContext context,
    String title, {
    SnackBarType type = SnackBarType.info,
    String? message,
    Function()? onCompletion,
  }) {
    if (Get.isSnackbarOpen) return;

    final Color color;
    final IconData icon;

    switch (type) {
      case SnackBarType.success:
        color = Color(0xFF43A047);
        icon = Icons.check_circle_rounded;
        break;
      case SnackBarType.error:
        color = Color(0xFFE53935);
        icon = Icons.error_rounded;
        break;
      default:
        color = cPrimary;
        icon = Icons.info_rounded;
    }

    Get.rawSnackbar(
      messageText: Text(
        title.tr,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cWhite),
      ),
      snackPosition: SnackPosition.TOP,
      backgroundColor: color,
      borderRadius: 12,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      icon: Icon(icon, color: cWhite, size: 26),
      forwardAnimationCurve: Curves.easeOutBack,
      duration: const Duration(seconds: 2),
    );

    if (onCompletion != null) onCompletion();
  }
}
