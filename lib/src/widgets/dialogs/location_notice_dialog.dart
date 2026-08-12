import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationNoticeDialog extends StatelessWidget {
  const LocationNoticeDialog({super.key, this.onClose});

  final VoidCallback? onClose;

  static final Uri privacyPolicyUri = Uri.parse(
    'https://smartnps360.com/privacy-policy',
  );

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => LocationNoticeDialog(
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final opened = await launchUrl(
      privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await launchUrl(privacyPolicyUri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3B091A3A),
                  blurRadius: 34,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final designWidth = constraints.maxWidth * 1.12;
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: designWidth,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _NoticeHeader(onClose: onClose),
                              const SizedBox(height: 7),
                              const _HeroNotice(),
                              const SizedBox(height: 8),
                              const _SectionLabel(),
                              const SizedBox(height: 5),
                              const _StepsPanel(),
                              const SizedBox(height: 7),
                              const _PrivacyPanel(),
                              const SizedBox(height: 7),
                              const _ContactPanel(),
                              const SizedBox(height: 7),
                              _ActionArea(
                                onClose: onClose,
                                onOpenPolicy: () =>
                                    unawaited(_openPrivacyPolicy()),
                              ),
                            ],
                          ),
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
  }
}

class _NoticeHeader extends StatelessWidget {
  const _NoticeHeader({required this.onClose});

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
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE0E8F5)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120B2259),
                    blurRadius: 18,
                    offset: Offset(0, 8),
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
            const Expanded(
              child: Text(
                'SmartNPS360 Location Notice',
                maxLines: 2,
                style: TextStyle(
                  color: Color(0xFF0B2259),
                  fontSize: 21,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE0E8F5)),
                ),
                child: IconButton(
                  onPressed: onClose,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF0B2259),
                  iconSize: 26,
                  tooltip: 'Close',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFEFF5FF),
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Your trust and privacy are our priority.',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF2A63C7),
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
  const _HeroNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCADAFF), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E2A63C7),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: const [
            _CircleIcon(
              icon: Icons.location_on_rounded,
              background: Color(0xFFEAF2FF),
              color: Color(0xFF0B2259),
              size: 38,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location is used only while you are clocked in on an active shift.',
                    style: TextStyle(
                      color: Color(0xFF0B2259),
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'It supports safety, patrol verification, and attendance.',
                    style: TextStyle(
                      color: Color(0xFF657084),
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
  const _SectionLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFDDE5F0))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'HOW IT WORKS',
            style: TextStyle(
              color: Color(0xFF0B2259),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFDDE5F0))),
      ],
    );
  }
}

class _StepsPanel extends StatelessWidget {
  const _StepsPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E6EF)),
      ),
      child: const ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        child: Column(
          children: [
            _NoticeStep(
              icon: Icons.schedule_rounded,
              title: 'While You Are On Duty',
              body:
                  'SmartNPS360 may collect and use your location, including in the background.',
              color: Color(0xFF13865F),
              iconBackground: Color(0xFFE6F8F0),
            ),
            _StepDivider(),
            _NoticeStep(
              icon: Icons.logout_rounded,
              title: 'When You Clock Out',
              body: 'Tracking stops when your shift ends and you clock out.',
              color: Color(0xFF2A63C7),
              iconBackground: Color(0xFFECF3FF),
            ),
            _StepDivider(),
            _NoticeStep(
              icon: Icons.my_location_rounded,
              title: 'Leaving the Site (If Enabled)',
              body:
                  'If enabled, leaving the site can clock you out and stop tracking.',
              color: Color(0xFF6B38C7),
              iconBackground: Color(0xFFF2EAFF),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Color iconBackground;

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
                  style: const TextStyle(
                    color: Color(0xFF5C687A),
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
  const _StepDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 60),
      child: Divider(height: 1, color: Color(0xFFE7ECF3)),
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x3313865F)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAFBF3), Color(0xFFF8FCFF)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: const [
            _CircleIcon(
              icon: Icons.lock_rounded,
              background: Color(0xFFD9F5E6),
              color: Color(0xFF13865F),
              size: 38,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Privacy Matters',
                    style: TextStyle(
                      color: Color(0xFF13865F),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'We do not track you off duty or when you are not clocked in. Your data is used solely to support safety, security, and operational needs.',
                    style: TextStyle(
                      color: Color(0xFF4E5B6C),
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
  const _ContactPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A235A), Color(0xFF244D9A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26173E85),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Questions?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'We\'re here to help. Contact our Privacy Team.',
              style: TextStyle(
                color: Color(0xFFEDF3FF),
                fontSize: 12.4,
                height: 1.25,
              ),
            ),
            SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: [
                _ContactItem(
                  icon: Icons.mail_outline_rounded,
                  text: 'privacy@smartnps360.com',
                ),
                _ContactItem(icon: Icons.call_outlined, text: '415-800-4372'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({required this.onClose, required this.onOpenPolicy});

  final VoidCallback? onClose;
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: onClose,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0B2259),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(42),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: const Text('I Understand'),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onOpenPolicy,
          icon: const Icon(Icons.open_in_new_rounded, size: 14),
          label: const Text('View Full Privacy Policy'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0B2259),
            minimumSize: const Size.fromHeight(32),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
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
