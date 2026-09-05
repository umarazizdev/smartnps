import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/native_theme_controller.dart';
import '../../app/app_routes.dart';
import '../../utilities/app_config.dart';

class _LocationNoticeColors {
  const _LocationNoticeColors({
    required this.shellBg,
    required this.shellBorder,
    required this.shellShadow,
    required this.headerTitle,
    required this.logoCircleBg,
    required this.logoCircleBorder,
    required this.logoCircleShadow,
    required this.closeBtnBg,
    required this.closeBtnBorder,
    required this.closeBtnIcon,
    required this.taglineBg,
    required this.taglineText,
    required this.heroBg,
    required this.heroBorder,
    required this.heroShadow,
    required this.heroIconBg,
    required this.heroIconColor,
    required this.heroTitle,
    required this.heroBody,
    required this.sectionDivider,
    required this.sectionLabel,
    required this.stepsBg,
    required this.stepsBorder,
    required this.stepBody,
    required this.stepDivider,
    required this.onDutyColor,
    required this.onDutyIconBg,
    required this.clockOutColor,
    required this.clockOutIconBg,
    required this.leavingSiteColor,
    required this.leavingSiteIconBg,
    required this.privacyBorder,
    required this.privacyGradient,
    required this.privacyTitle,
    required this.privacyBody,
    required this.privacyIconBg,
    required this.privacyIconColor,
    required this.contactGradient,
    required this.contactBorder,
    required this.contactShadow,
    required this.contactTitle,
    required this.contactBody,
    required this.contactPillBg,
    required this.contactPillBorder,
    required this.contactPillFg,
    required this.primaryBtnBg,
    required this.primaryBtnFg,
    required this.policyLink,
    required this.policyDocBg,
    required this.policyDocBorder,
    required this.policyDocShadow,
    required this.policyDocTitle,
    required this.policyDocDivider,
    required this.policyDocSpinner,
    required this.policyDocError,
  });

  final Color shellBg;
  final Color shellBorder;
  final Color shellShadow;
  final Color headerTitle;
  final Color logoCircleBg;
  final Color logoCircleBorder;
  final Color logoCircleShadow;
  final Color closeBtnBg;
  final Color closeBtnBorder;
  final Color closeBtnIcon;
  final Color taglineBg;
  final Color taglineText;
  final Color heroBg;
  final Color heroBorder;
  final Color heroShadow;
  final Color heroIconBg;
  final Color heroIconColor;
  final Color heroTitle;
  final Color heroBody;
  final Color sectionDivider;
  final Color sectionLabel;
  final Color stepsBg;
  final Color stepsBorder;
  final Color stepBody;
  final Color stepDivider;
  final Color onDutyColor;
  final Color onDutyIconBg;
  final Color clockOutColor;
  final Color clockOutIconBg;
  final Color leavingSiteColor;
  final Color leavingSiteIconBg;
  final Color privacyBorder;
  final List<Color> privacyGradient;
  final Color privacyTitle;
  final Color privacyBody;
  final Color privacyIconBg;
  final Color privacyIconColor;
  final List<Color> contactGradient;
  final Color contactBorder;
  final Color contactShadow;
  final Color contactTitle;
  final Color contactBody;
  final Color contactPillBg;
  final Color contactPillBorder;
  final Color contactPillFg;
  final Color primaryBtnBg;
  final Color primaryBtnFg;
  final Color policyLink;
  final Color policyDocBg;
  final Color policyDocBorder;
  final Color policyDocShadow;
  final Color policyDocTitle;
  final Color policyDocDivider;
  final Color policyDocSpinner;
  final Color policyDocError;

  static _LocationNoticeColors of(bool isDark) {
    if (isDark) {
      return _LocationNoticeColors(
        shellBg: const Color(0xFF0F1724),
        shellBorder: const Color(0xFF2A3548),
        shellShadow: Colors.black.withValues(alpha: 0.55),
        headerTitle: Colors.white,
        logoCircleBg: const Color(AppConfig.cDarkCardColor),
        logoCircleBorder: const Color(0xFF2A3548),
        logoCircleShadow: Colors.black.withValues(alpha: 0.35),
        closeBtnBg: const Color(AppConfig.cDarkCardColor),
        closeBtnBorder: const Color(0xFF2A3548),
        closeBtnIcon: Colors.white.withValues(alpha: 0.92),
        taglineBg: const Color(0xFF1E3A5F),
        taglineText: const Color(0xFF93C5FD),
        heroBg: const Color(AppConfig.cDarkCardColor),
        heroBorder: const Color(0xFF2A4A7A),
        heroShadow: Colors.black.withValues(alpha: 0.35),
        heroIconBg: const Color(0xFF1E3A5F),
        heroIconColor: const Color(0xFF93C5FD),
        heroTitle: Colors.white,
        heroBody: Colors.white.withValues(alpha: 0.68),
        sectionDivider: const Color(0xFF2A3548),
        sectionLabel: const Color(0xFF93C5FD),
        stepsBg: const Color(AppConfig.cDarkCardColor),
        stepsBorder: const Color(0xFF2A3548),
        stepBody: Colors.white.withValues(alpha: 0.62),
        stepDivider: const Color(0xFF2A3548),
        onDutyColor: const Color(0xFF34D399),
        onDutyIconBg: const Color(0xFF14532D),
        clockOutColor: const Color(0xFF60A5FA),
        clockOutIconBg: const Color(0xFF1E3A5F),
        leavingSiteColor: const Color(0xFFA78BFA),
        leavingSiteIconBg: const Color(0xFF3B2667),
        privacyBorder: const Color(0x5934D399),
        privacyGradient: const [Color(0xFF142A22), Color(0xFF162033)],
        privacyTitle: const Color(0xFF34D399),
        privacyBody: Colors.white.withValues(alpha: 0.68),
        privacyIconBg: const Color(0xFF14532D),
        privacyIconColor: const Color(0xFF34D399),
        contactGradient: const [Color(0xFF0F766E), Color(0xFF115E59)],
        contactBorder: const Color(0xFF2DD4BF),
        contactShadow: const Color(0x66115E59),
        contactTitle: Colors.white,
        contactBody: const Color(0xFFCCFBF1),
        contactPillBg: Colors.white.withValues(alpha: 0.18),
        contactPillBorder: Colors.white.withValues(alpha: 0.32),
        contactPillFg: Colors.white,
        primaryBtnBg: const Color(0xFF3B82F6),
        primaryBtnFg: Colors.white,
        policyLink: const Color(0xFF93C5FD),
        policyDocBg: const Color(0xFF0F1724),
        policyDocBorder: const Color(0xFF2A3548),
        policyDocShadow: Colors.black.withValues(alpha: 0.55),
        policyDocTitle: Colors.white,
        policyDocDivider: const Color(0xFF2A3548),
        policyDocSpinner: const Color(0xFF93C5FD),
        policyDocError: Colors.white.withValues(alpha: 0.88),
      );
    }

    return const _LocationNoticeColors(
      shellBg: Color(0xFFF8FAFD),
      shellBorder: Colors.white,
      shellShadow: Color(0x3B091A3A),
      headerTitle: Color(0xFF0B2259),
      logoCircleBg: Colors.white,
      logoCircleBorder: Color(0xFFE0E8F5),
      logoCircleShadow: Color(0x120B2259),
      closeBtnBg: Colors.white,
      closeBtnBorder: Color(0xFFE0E8F5),
      closeBtnIcon: Color(0xFF0B2259),
      taglineBg: Color(0xFFEFF5FF),
      taglineText: Color(0xFF2A63C7),
      heroBg: Colors.white,
      heroBorder: Color(0xFFCADAFF),
      heroShadow: Color(0x0E2A63C7),
      heroIconBg: Color(0xFFEAF2FF),
      heroIconColor: Color(0xFF0B2259),
      heroTitle: Color(0xFF0B2259),
      heroBody: Color(0xFF657084),
      sectionDivider: Color(0xFFDDE5F0),
      sectionLabel: Color(0xFF0B2259),
      stepsBg: Colors.white,
      stepsBorder: Color(0xFFE0E6EF),
      stepBody: Color(0xFF5C687A),
      stepDivider: Color(0xFFE7ECF3),
      onDutyColor: Color(0xFF13865F),
      onDutyIconBg: Color(0xFFE6F8F0),
      clockOutColor: Color(0xFF2A63C7),
      clockOutIconBg: Color(0xFFECF3FF),
      leavingSiteColor: Color(0xFF6B38C7),
      leavingSiteIconBg: Color(0xFFF2EAFF),
      privacyBorder: Color(0x3313865F),
      privacyGradient: [Color(0xFFEAFBF3), Color(0xFFF8FCFF)],
      privacyTitle: Color(0xFF13865F),
      privacyBody: Color(0xFF4E5B6C),
      privacyIconBg: Color(0xFFD9F5E6),
      privacyIconColor: Color(0xFF13865F),
      contactGradient: [Color(0xFF14B8A6), Color(0xFF0D9488)],
      contactBorder: Color(0xFF2DD4BF),
      contactShadow: Color(0x330D9488),
      contactTitle: Colors.white,
      contactBody: Color(0xFFCCFBF1),
      contactPillBg: Color(0x29FFFFFF),
      contactPillBorder: Color(0x42FFFFFF),
      contactPillFg: Colors.white,
      primaryBtnBg: Color(0xFF0B2259),
      primaryBtnFg: Colors.white,
      policyLink: Color(0xFF0B2259),
      policyDocBg: Colors.white,
      policyDocBorder: Color(0xFFE0E8F5),
      policyDocShadow: Color(0x33091A3A),
      policyDocTitle: Color(0xFF0B2259),
      policyDocDivider: Color(0xFFE0E8F5),
      policyDocSpinner: Color(0xFF2A63C7),
      policyDocError: Color(0xFF0B2259),
    );
  }
}

class PolicyDocumentContent {
  const PolicyDocumentContent.html(this.html) : bytes = null, isPdf = false;

  const PolicyDocumentContent.pdf(this.bytes) : html = null, isPdf = true;

  final String? html;
  final Uint8List? bytes;
  final bool isPdf;
}

class LocationNoticeDialog extends StatelessWidget {
  const LocationNoticeDialog({
    super.key,
    this.onClose,
    this.onFetchPolicyDocument,
  });

  final VoidCallback? onClose;

  final Future<PolicyDocumentContent?> Function(Uri uri)? onFetchPolicyDocument;

  static final Uri privacyPolicyFullUri = Uri.parse(
    'https://smartnps360.com/officer/documents/privacy_policy_full',
  );
  static final Uri privacyPolicySummaryUri = Uri.parse(
    'https://smartnps360.com/officer/documents/privacy_policy_summary',
  );
  static final Uri privacyEmailUri = Uri(
    scheme: 'mailto',
    path: 'privacy@smartnps360.com',
  );
  static final Uri privacyPhoneUri = Uri(scheme: 'tel', path: '+14158004372');

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => LocationNoticeDialog(
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  static Future<void> openContactUri(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _openPolicy(
    BuildContext context, {
    required String title,
    required Uri uri,
  }) async {
    final fetch = onFetchPolicyDocument;
    if (fetch == null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return Obx(() {
          final colors = _LocationNoticeColors.of(
            NativeThemeController.instance.isDark,
          );
          return _PolicyDocumentDialog(
            title: title,
            uri: uri,
            documentFuture: fetch(uri),
            colors: colors,
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final colors = _LocationNoticeColors.of(
        NativeThemeController.instance.isDark,
      );
      final media = MediaQuery.of(context);
      final maxHeight = media.size.height - media.padding.vertical - 20;
      final maxWidth = media.size.width >= 820 ? 680.0 : media.size.width - 18;

      return PopScope(
        canPop: false,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.shellBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.shellBorder, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: colors.shellShadow,
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _NoticeHeader(colors: colors, onClose: onClose),
                              const SizedBox(height: 7),
                              _HeroNotice(colors: colors),
                              const SizedBox(height: 8),
                              _SectionLabel(colors: colors),
                              const SizedBox(height: 5),
                              _StepsPanel(colors: colors),
                              const SizedBox(height: 7),
                              _PrivacyPanel(colors: colors),
                              const SizedBox(height: 7),
                              _ContactPanel(colors: colors),
                              const SizedBox(height: 7),
                              _ActionArea(
                                colors: colors,
                                onClose: onClose,
                                onOpenSummary: () => unawaited(
                                  _openPolicy(
                                    context,
                                    title: 'Privacy Policy Summary',
                                    uri: privacyPolicySummaryUri,
                                  ),
                                ),
                                onOpenFull: () => unawaited(
                                  _openPolicy(
                                    context,
                                    title: 'Full Privacy Policy',
                                    uri: privacyPolicyFullUri,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _NoticeHeader extends StatelessWidget {
  const _NoticeHeader({required this.colors, required this.onClose});

  final _LocationNoticeColors colors;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.logoCircleBg,
                shape: BoxShape.circle,
                border: Border.all(color: colors.logoCircleBorder),
                boxShadow: [
                  BoxShadow(
                    color: colors.logoCircleShadow,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: Image.asset(
                    'assets/npslogo.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'SmartNPS360 Location Notice',
                maxLines: 2,
                style: TextStyle(
                  color: colors.headerTitle,
                  fontSize: 21,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: colors.closeBtnBg,
              shape: const CircleBorder(),
              elevation: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.closeBtnBorder),
                ),
                child: IconButton(
                  onPressed: onClose,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded),
                  color: colors.closeBtnIcon,
                  iconSize: 26,
                  tooltip: 'Close',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.taglineBg,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Your trust and privacy are our priority.',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.taglineText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroNotice extends StatelessWidget {
  const _HeroNotice({required this.colors});

  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.heroBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.heroBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.heroShadow,
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _CircleIcon(
              icon: Icons.location_on_rounded,
              background: colors.heroIconBg,
              color: colors.heroIconColor,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location is used only while you are clocked in on an active shift.',
                    style: TextStyle(
                      color: colors.heroTitle,
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'It supports safety, patrol verification, and attendance.',
                    style: TextStyle(
                      color: colors.heroBody,
                      fontSize: 12.5,
                      height: 1.32,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.colors});

  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: colors.sectionDivider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'HOW IT WORKS',
            style: TextStyle(
              color: colors.sectionLabel,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: colors.sectionDivider)),
      ],
    );
  }
}

class _StepsPanel extends StatelessWidget {
  const _StepsPanel({required this.colors});

  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.stepsBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.stepsBorder),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        child: Column(
          children: [
            _NoticeStep(
              icon: Icons.schedule_rounded,
              title: 'While You Are On Duty',
              body:
                  'SmartNPS360 may collect and use your location, including in the background.',
              color: colors.onDutyColor,
              iconBackground: colors.onDutyIconBg,
              bodyColor: colors.stepBody,
            ),
            _StepDivider(color: colors.stepDivider),
            _NoticeStep(
              icon: Icons.logout_rounded,
              title: 'When You Clock Out',
              body: 'Tracking stops when your shift ends and you clock out.',
              color: colors.clockOutColor,
              iconBackground: colors.clockOutIconBg,
              bodyColor: colors.stepBody,
            ),
            _StepDivider(color: colors.stepDivider),
            _NoticeStep(
              icon: Icons.my_location_rounded,
              title: 'Leaving the Site (If Enabled)',
              body:
                  'If enabled, leaving the site can clock you out and stop tracking.',
              color: colors.leavingSiteColor,
              iconBackground: colors.leavingSiteIconBg,
              bodyColor: colors.stepBody,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeStep extends StatelessWidget {
  const _NoticeStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.iconBackground,
    required this.bodyColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Color iconBackground;
  final Color bodyColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CircleIcon(
            icon: icon,
            background: iconBackground,
            color: color,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14.5,
                    height: 1.16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 12.2,
                    height: 1.26,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDivider extends StatelessWidget {
  const _StepDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(height: 1, color: color),
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel({required this.colors});

  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.privacyBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.privacyGradient,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _CircleIcon(
              icon: Icons.lock_rounded,
              background: colors.privacyIconBg,
              color: colors.privacyIconColor,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Privacy Matters',
                    style: TextStyle(
                      color: colors.privacyTitle,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'We do not track you off duty or when you are not clocked in. Your data is used solely to support safety, security, and operational needs.',
                    style: TextStyle(
                      color: colors.privacyBody,
                      fontSize: 12.2,
                      height: 1.26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactPanel extends StatelessWidget {
  const _ContactPanel({required this.colors});

  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.contactBorder, width: 1.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.contactGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.contactShadow,
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Questions?',
              style: TextStyle(
                color: colors.contactTitle,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'We\'re here to help. Contact our Privacy Team.',
              style: TextStyle(
                color: colors.contactBody,
                fontSize: 12.4,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _ContactItem(
                    colors: colors,
                    icon: Icons.mail_outline_rounded,
                    text: 'privacy@smartnps360.com',
                    uri: LocationNoticeDialog.privacyEmailUri,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _ContactItem(
                    colors: colors,
                    icon: Icons.call_outlined,
                    text: '+1 415-800-4372',
                    uri: LocationNoticeDialog.privacyPhoneUri,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({
    required this.colors,
    required this.icon,
    required this.text,
    required this.uri,
  });

  final _LocationNoticeColors colors;
  final IconData icon;
  final String text;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.contactPillBg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => unawaited(LocationNoticeDialog.openContactUri(uri)),
        borderRadius: BorderRadius.circular(999),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.contactPillBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Icon(icon, color: colors.contactPillFg, size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: colors.contactPillFg,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.contactPillFg,
                  size: 15,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.colors,
    required this.onClose,
    required this.onOpenSummary,
    required this.onOpenFull,
  });

  final _LocationNoticeColors colors;
  final VoidCallback? onClose;
  final VoidCallback onOpenSummary;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: onClose,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primaryBtnBg,
            foregroundColor: colors.primaryBtnFg,
            minimumSize: const Size.fromHeight(54),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: const Text('I Understand'),
        ),
        const SizedBox(height: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PolicyButton(
              colors: colors,
              icon: Icons.open_in_new_rounded,
              label: 'View Privacy Policy Summary',
              onPressed: onOpenSummary,
            ),
            _PolicyButton(
              colors: colors,
              icon: Icons.open_in_new_rounded,
              label: 'View Full Privacy Policy',
              onPressed: onOpenFull,
            ),
          ],
        ),
      ],
    );
  }
}

class _PolicyButton extends StatelessWidget {
  const _PolicyButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final _LocationNoticeColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 12),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: colors.policyLink,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PolicyDocumentDialog extends StatelessWidget {
  const _PolicyDocumentDialog({
    required this.title,
    required this.uri,
    required this.documentFuture,
    required this.colors,
  });

  final String title;
  final Uri uri;
  final Future<PolicyDocumentContent?> documentFuture;
  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width >= 820 ? 760.0 : media.size.width - 18;
    final maxHeight = media.size.height - media.padding.vertical - 24;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.policyDocBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.policyDocBorder),
            boxShadow: [
              BoxShadow(
                color: colors.policyDocShadow,
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.policyDocTitle,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: colors.policyDocTitle,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.policyDocDivider),
                Expanded(
                  child: FutureBuilder<PolicyDocumentContent?>(
                    future: documentFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: colors.policyDocSpinner,
                            ),
                          ),
                        );
                      }

                      final doc = snapshot.data;
                      if (doc == null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Unable to load this document. Please try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.policyDocError,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }

                      if (doc.isPdf && doc.bytes != null) {
                        return _PolicyPdfView(bytes: doc.bytes!);
                      }

                      final html = doc.html;
                      if (html == null || html.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Unable to load this document. Please try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.policyDocError,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }

                      return InAppWebView(
                        initialData: InAppWebViewInitialData(
                          data: html,
                          mimeType: 'text/html',
                          encoding: 'utf-8',
                          baseUrl: WebUri(AppRoutes.webBaseUrl),
                          historyUrl: WebUri.uri(uri),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          supportZoom: true,
                          transparentBackground: false,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicyPdfView extends StatefulWidget {
  const _PolicyPdfView({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PolicyPdfView> createState() => _PolicyPdfViewState();
}

class _PolicyPdfViewState extends State<_PolicyPdfView> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openData(widget.bytes),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewPinch(controller: _controller);
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.background,
    required this.color,
    this.size = 50,
  });

  final IconData icon;
  final Color background;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
