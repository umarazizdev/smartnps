import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBack)
                Row(
                  children: [
                    InkWell(
                      overlayColor: const WidgetStatePropertyAll(cTransparent),
                      onTap: Get.back,
                      child: Container(
                        padding: const EdgeInsets.all(8),
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
                        child: const Icon(
                          Icons.arrow_back_ios_rounded,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Help & Support",
                          style: textTheme.headlineLarge?.copyWith(
                            color: isDark
                                ? cDarkTextPrimary
                                : const Color(0xFF111827),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // const SizedBox(height: 4),
                        // const Text(
                        //   "Get assistance from our team",
                        //   style: TextStyle(color: cDarkGreyclr, fontSize: 13.5),
                        // ),
                      ],
                    ),
                  ],
                )
              else ...[
                Text(
                  "Help & Support",
                  style: textTheme.headlineLarge?.copyWith(
                    color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // const SizedBox(height: 4),
                // const Text(
                //   "Get assistance from our team",
                //   style: TextStyle(color: cDarkGreyclr, fontSize: 13.5),
                // ),
              ],
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        color: isDark ? cDarkCardColor : cWhite,
                        child: Padding(
                          padding: const EdgeInsets.all(18.0),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF17365D)
                                      : cPrimary.withAlpha(20),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.headset_mic_rounded,
                                  size: 44,
                                  color: isDark
                                      ? const Color(0xFF2563EB)
                                      : cPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Need Assistance?',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? cDarkTextPrimary
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Our admin team is ready to help with account, schedules, or technical issues.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cDarkGreyclr,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _statTile(
                                      icon: Icons.access_time_rounded,
                                      label: 'Availability',
                                      value: '24/7',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _statTile(
                                      icon: Icons.speed_rounded,
                                      label: 'Response',
                                      value: '1-5 mins',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Choose Contact Method",
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? cDarkTextPrimary
                                : const Color(0xFF111827),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildContactButton(
                        context: context,
                        icon: 'assets/Icons/whatsapp.png',
                        label: "WhatsApp Support",
                        subtitle: "Message us for quick support",
                        color: const Color(0xFF25D366),
                        onTap: () => _launchWhatsApp(context),
                      ),

                      const SizedBox(height: 12),

                      _buildContactButton(
                        context: context,
                        icon: 'assets/Icons/phone.png',
                        label: "Phone Support",
                        subtitle: "Direct phone support",
                        color: isDark ? cPrimary.withAlpha(240) : cPrimary,
                        onTap: () => _launchPhoneCall(context),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF071A33)
                              : cPrimary.withAlpha(13),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF0F2F57)
                                : cPrimary.withAlpha(51),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: isDark
                                  ? const Color(0xFF1D4ED8)
                                  : cPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Please have your employee ID and relevant details ready to expedite the support process.",
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF3B82F6)
                                      : cPrimary.withAlpha(230),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark ? cDarkInputFillColor : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? cDarkBorderColor : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E3A5F)
                      : cPrimary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isDark ? const Color(0xFF2563EB) : cPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: cDarkGreyclr,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? cDarkTextPrimary
                            : const Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactButton({
    required BuildContext context,
    required String icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color darkBorderColor = Color.lerp(color, Colors.black, 0.28)!;

    final Color darkIconBgColor = Color.lerp(color, cDarkCardColor, 0.70)!;

    final Color darkIconColor = Color.lerp(color, Colors.white, 0.08)!;

    final Color darkArrowColor = Color.lerp(color, Colors.white, 0.20)!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : cWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? darkBorderColor.withAlpha(180)
                : color.withAlpha(51),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withAlpha(38) : color.withAlpha(26),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? darkIconBgColor : color.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                icon,
                height: 28,
                width: 28,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    icon.contains('whatsapp')
                        ? Icons.chat_bubble_rounded
                        : Icons.phone_rounded,
                    size: 28,
                    color: isDark ? darkIconColor : color,
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? cDarkTextSecondary : cDarkGreyclr,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 18,
              color: isDark ? darkArrowColor : color,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchWhatsApp(BuildContext context) async {
    final phone = waPhone.replaceAll('+', '').replaceAll(' ', '');
    final msg = Uri.encodeComponent('Hello, I need assistance.');

    final appUri = Uri.parse('whatsapp://send?phone=$phone&text=$msg');
    final webUri = Uri.parse('https://wa.me/$phone?text=$msg');

    try {
      // Try opening WhatsApp directly (best UX)
      if (await canLaunchUrl(appUri)) {
        final ok = await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      }

      // Fallback: universal link (may open browser if user disabled default handling)
      final okWeb = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );

      if (!okWeb && context.mounted) {
        AppSnackBar.show(
          context,
          'Unable to open WhatsApp on this device.',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          'Unable to open WhatsApp. Please try again.',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _launchPhoneCall(BuildContext context) async {
    try {
      final phoneUrl = Uri.parse('tel:$contactNumberRaw');

      final launched = await launchUrl(phoneUrl);

      if (!launched && context.mounted) {
        AppSnackBar.show(
          context,
          'Unable to make phone calls on this device',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        _log('Error launching phone dialer', tag: 'Help', error: e);
        AppSnackBar.show(
          context,
          'Unable to open phone dialer. Please try again.',
          type: SnackBarType.error,
        );
      }
    }
  }
}
