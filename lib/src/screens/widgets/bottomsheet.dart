import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

enum IconMode { fixed, relative }

class ShowBottomSheet {
  static void show({
    required BuildContext context,
    required String title,
    required String buttonTitle,
    required String description,
    required String iconAssetPath,
    required VoidCallback onTap,
    Color? buttonColor,
    bool? isBackButton,
    VoidCallback? onSecondaryTap,
    IconMode iconMode = IconMode.fixed,
  }) {
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(isDark ? 128 : 89),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) => AppBottomSheet(
        title: title,
        description: description,
        buttonTitle: buttonTitle,
        iconAssetPath: iconAssetPath,
        onTap: onTap,
        buttonColor: buttonColor,
        isBackButton: isBackButton,
        onSecondaryTap: onSecondaryTap,
        iconMode: iconMode,
      ),
    );
  }
}

class AppBottomSheet extends StatelessWidget {
  final String title;
  final String buttonTitle;
  final Color? buttonColor;
  final bool? isBackButton;
  final String description;
  final String iconAssetPath;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final IconMode iconMode;

  const AppBottomSheet({
    super.key,
    required this.title,
    required this.buttonTitle,
    this.buttonColor,
    this.isBackButton = true,
    required this.description,
    required this.iconAssetPath,
    required this.onTap,
    this.onSecondaryTap,
    this.iconMode = IconMode.fixed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final iconSize = size.width * 0.2;
    final buttonHeight = size.height * 0.06;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Glass card (clipped & blurred)
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
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
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: size.width * 0.05,
                      right: size.width * 0.05,
                      top: iconSize * 0.9, // space so icon can "sit" here
                      bottom: MediaQuery.of(context).padding.bottom + 6.0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            color: isDark
                                ? cDarkTextPrimary
                                : Colors.black.withAlpha(230),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: size.height * 0.015),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: size.height * 0.3,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: size.width * 0.06,
                              ),
                              child: Text(
                                description,
                                textAlign: TextAlign.center,
                                style: textTheme.titleMedium?.copyWith(
                                  height: 1.4,
                                  color: isDark
                                      ? cDarkTextSecondary
                                      : Colors.black.withAlpha(191),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: size.height * 0.02),
                        _buildButtons(size, buttonHeight, isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Floating icon pill – now NOT clipped
          Positioned(
            top: -iconSize * 0.6,
            left: (size.width - iconSize) / 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              cDarkCardColor.withAlpha(204),
                              cDarkBorderColor.withAlpha(153),
                            ]
                          : [
                              Colors.white.withAlpha(179),
                              Colors.white.withAlpha(77),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),

                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 26 : 13),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(iconSize * 0.32),
                    child: Image.asset(
                      iconAssetPath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.broken_image,
                        size: iconSize * 0.5,
                        color: isDark ? cDarkIconColor : Colors.grey[400],
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
  }

  Widget _buildButtons(Size size, double buttonHeight, bool isDark) {
    if (isBackButton ?? true) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: buttonHeight,
              child: OutlinedButton(
                onPressed: () {
                  Get.back();
                  onSecondaryTap?.call();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cTransparent, width: 1.5),
                  backgroundColor: isDark
                      ? cDarkBorderColor.withAlpha(128)
                      : Colors.white.withAlpha(64),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Cancel",
                  style: TextStyle(
                    fontSize: size.width * 0.045,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? cDarkTextPrimary
                        : Colors.black.withAlpha(217),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: size.width * 0.03),
          Expanded(
            child: SizedBox(
              height: buttonHeight,
              child: ElevatedButton(
                onPressed: () {
                  Get.back();
                  onTap();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor ?? cPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  buttonTitle,
                  style: TextStyle(
                    fontSize: size.width * 0.045,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return SizedBox(
        width: double.infinity,
        height: buttonHeight,
        child: ElevatedButton(
          onPressed: () {
            Get.back();
            onTap();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonColor ?? cPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            buttonTitle,
            style: TextStyle(
              fontSize: size.width * 0.045,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
  }
}
