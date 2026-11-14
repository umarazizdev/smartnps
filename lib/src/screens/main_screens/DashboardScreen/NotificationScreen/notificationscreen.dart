import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    final h = MediaQuery.of(context).size.height * 1;
    final w = MediaQuery.of(context).size.width * 1;
    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      overlayColor: WidgetStatePropertyAll(cTransparent),
                      onTap: () {
                        Get.back();
                      },
                      child: Container(
                        padding: EdgeInsets.all(w * 0.025),
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withAlpha(51)
                                  : const Color(0xff939393).withAlpha(26),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          color: isDark ? cDarkCardColor : cWhite,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          size: w * 0.06,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: w * 0.2),
                  Text(
                    "Notifications",
                    style: textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
              SizedBox(height: h * 0.32),

              Column(
                children: [
                  Image.asset(
                    'assets/Icons/notification-outline.png',
                    color: cIconDefault,
                    height: h * 0.1,
                  ),
                  SizedBox(height: h * 0.03),

                  Text(
                    "No Notifications Yet!",
                    style: textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: h * 0.005),
                  SizedBox(
                    width: w * 0.9,
                    child: Text(
                      "We'll let you know when there will be something to update you.",
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: cIconDefault,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
