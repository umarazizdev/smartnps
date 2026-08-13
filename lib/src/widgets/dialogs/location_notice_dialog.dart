import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

/// Privacy policy payload fetched through the main WebView session.
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

  /// Fetches policy content via the main WebView session (same as dashboard).
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
        return _PolicyDocumentDialog(
          title: title,
          uri: uri,
          documentFuture: fetch(uri),
        );
      },
    );
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Questions?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'We\'re here to help. Contact our Privacy Team.',
              style: TextStyle(
                color: Color(0xFFEDF3FF),
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
                    icon: Icons.mail_outline_rounded,
                    text: 'privacy@smartnps360.com',
                    uri: LocationNoticeDialog.privacyEmailUri,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _ContactItem(
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
    required this.icon,
    required this.text,
    required this.uri,
  });

  final IconData icon;
  final String text;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => unawaited(LocationNoticeDialog.openContactUri(uri)),
        borderRadius: BorderRadius.circular(999),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFEAF3FF), size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFEAF3FF),
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
    required this.onClose,
    required this.onOpenSummary,
    required this.onOpenFull,
  });

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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PolicyButton(
              icon: Icons.open_in_new_rounded,
              label: 'View Privacy Policy Summary',
              onPressed: onOpenSummary,
            ),
            _PolicyButton(
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
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 13),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF0B2259),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        textStyle: const TextStyle(fontSize: 11.1, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PolicyDocumentDialog extends StatelessWidget {
  const _PolicyDocumentDialog({
    required this.title,
    required this.uri,
    required this.documentFuture,
  });

  final String title;
  final Uri uri;
  final Future<PolicyDocumentContent?> documentFuture;

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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE0E8F5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33091A3A),
                blurRadius: 34,
                offset: Offset(0, 14),
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
                          style: const TextStyle(
                            color: Color(0xFF0B2259),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF0B2259),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE0E8F5)),
                Expanded(
                  child: FutureBuilder<PolicyDocumentContent?>(
                    future: documentFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: Color(0xFF2A63C7),
                            ),
                          ),
                        );
                      }

                      final doc = snapshot.data;
                      if (doc == null) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Unable to load this document. Please try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF0B2259),
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
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Unable to load this document. Please try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF0B2259),
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
                          baseUrl: WebUri('https://smartnps360.com/'),
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
