import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/native_theme_controller.dart';
import '../../app/app_routes.dart';
import '../../debug/debug_env_pin_dialog.dart';
import '../../utilities/app_config.dart';
import 'glass_action_dialog.dart';

class _NoticeScale extends InheritedWidget {
  const _NoticeScale({required this.scale, required super.child});
  final double scale;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_NoticeScale>()
            ?.scale ??
        1.0;
  }

  static double compute(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final widthScale = size.width / 390;
    final heightScale = size.height / 844;
    return ((widthScale * 0.7) + (heightScale * 0.3)).clamp(0.86, 1.14);
  }

  @override
  bool updateShouldNotify(_NoticeScale oldWidget) => scale != oldWidget.scale;
}

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
        shellBg: const Color(0xFF081322),
        shellBorder: const Color(0xFF34445D),
        shellShadow: Colors.black.withValues(alpha: 0.55),
        headerTitle: Colors.white,
        logoCircleBg: const Color(AppConfig.cDarkCardColor),
        logoCircleBorder: const Color(0xFF34445D),
        logoCircleShadow: Colors.black.withValues(alpha: 0.35),
        closeBtnBg: const Color(AppConfig.cDarkCardColor),
        closeBtnBorder: const Color(0xFF34445D),
        closeBtnIcon: Colors.white.withValues(alpha: 0.92),
        taglineBg: const Color(0xFF203D64),
        taglineText: const Color(0xFFB5D9FF),
        heroBg: const Color(0xFF183B66),
        heroBorder: const Color(0xFF2A4A7A),
        heroShadow: Colors.black.withValues(alpha: 0.35),
        heroIconBg: const Color(0xFF203D64),
        heroIconColor: const Color(0xFFB5D9FF),
        heroTitle: Colors.white,
        heroBody: const Color(0xFFCADFF6),
        sectionDivider: const Color(0xFF34445D),
        sectionLabel: const Color(0xFFB5D9FF),
        stepsBg: const Color(0xFF172337),
        stepsBorder: const Color(0xFF34445D),
        stepBody: const Color(0xFFE3EAF5),
        stepDivider: const Color(0xFF34445D),
        onDutyColor: const Color(0xFF91E6AD),
        onDutyIconBg: const Color(0xFF164536),
        clockOutColor: const Color(0xFF8AD8FF),
        clockOutIconBg: const Color(0xFF203D64),
        leavingSiteColor: const Color(0xFFE0A9FF),
        leavingSiteIconBg: const Color(0xFF392B58),
        privacyBorder: const Color(0x5934D399),
        privacyGradient: const [Color(0xFF102D2C), Color(0xFF142832)],
        privacyTitle: const Color(0xFF91E6AD),
        privacyBody: Colors.white.withValues(alpha: 0.68),
        privacyIconBg: const Color(0xFF164536),
        privacyIconColor: const Color(0xFF91E6AD),
        contactGradient: const [Color(0xFF153D70), Color(0xFF0B2346)],
        contactBorder: const Color(0xFF397AB9),
        contactShadow: const Color(0x33071B38),
        contactTitle: Colors.white,
        contactBody: const Color(0xFFDCEBFF),
        contactPillBg: Colors.white.withValues(alpha: 0.18),
        contactPillBorder: Colors.white.withValues(alpha: 0.32),
        contactPillFg: Colors.white,
        primaryBtnBg: const Color(0xFF3B82F6),
        primaryBtnFg: Colors.white,
        policyLink: const Color(0xFFB5D9FF),
        policyDocBg: const Color(0xFF081322),
        policyDocBorder: const Color(0xFF34445D),
        policyDocShadow: Colors.black.withValues(alpha: 0.55),
        policyDocTitle: Colors.white,
        policyDocDivider: const Color(0xFF34445D),
        policyDocSpinner: const Color(0xFFB5D9FF),
        policyDocError: Colors.white.withValues(alpha: 0.88),
      );
    }
    return const _LocationNoticeColors(
      shellBg: Color(0xFFF5F8FD),
      shellBorder: Colors.white,
      shellShadow: Color(0x3B091A3A),
      headerTitle: Color(0xFF0B2259),
      logoCircleBg: Colors.white,
      logoCircleBorder: Color(0xFFE0E8F5),
      logoCircleShadow: Color(0x120B2259),
      closeBtnBg: Colors.white,
      closeBtnBorder: Color(0xFFE0E8F5),
      closeBtnIcon: Color(0xFF0B2259),
      taglineBg: Color(0xFFE2EDFF),
      taglineText: Color(0xFF1558BD),
      heroBg: Color(0xFFF8FBFF),
      heroBorder: Color(0xFFD6E6FF),
      heroShadow: Color(0x0E2A63C7),
      heroIconBg: Color(0xFFEAF2FF),
      heroIconColor: Color(0xFF0B2259),
      heroTitle: Color(0xFF0B2259),
      heroBody: Color(0xFF344A69),
      sectionDivider: Color(0xFFDDE5F0),
      sectionLabel: Color(0xFF0B2259),
      stepsBg: Colors.white,
      stepsBorder: Color(0xFFE0E6EF),
      stepBody: Color(0xFF35445C),
      stepDivider: Color(0xFFE7ECF3),
      onDutyColor: Color(0xFF086139),
      onDutyIconBg: Color(0xFFE6F8F0),
      clockOutColor: Color(0xFF1558BD),
      clockOutIconBg: Color(0xFFECF3FF),
      leavingSiteColor: Color(0xFF7022BB),
      leavingSiteIconBg: Color(0xFFF2EAFF),
      privacyBorder: Color(0x3313865F),
      privacyGradient: [Color(0xFFEAFBF3), Color(0xFFF8FCFF)],
      privacyTitle: Color(0xFF086139),
      privacyBody: Color(0xFF4E5B6C),
      privacyIconBg: Color(0xFFD9F5E6),
      privacyIconColor: Color(0xFF086139),
      contactGradient: [Color(0xFF075DA7), Color(0xFF062653)],
      contactBorder: Color(0xFF397AB9),
      contactShadow: Color(0x220B3B80),
      contactTitle: Colors.white,
      contactBody: Color(0xFFDCEBFF),
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
      policyDocSpinner: Color(0xFF1558BD),
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
    final documentFuture = fetch(uri);
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
              documentFuture: documentFuture,
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
        final scale = _NoticeScale.compute(context);
        final isLandscape = media.orientation == Orientation.landscape;
        final maxHeight = media.size.height - media.padding.vertical - (20 * scale);
        final maxWidth = isLandscape
        ? GlassActionDialog.landscapeMaxWidth
        : (media.size.width >= 820 ? 680.0 : media.size.width - (18 * scale));
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 40 * scale : 9 * scale,
              vertical: isLandscape ? 12 * scale : 10 * scale,
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: _NoticeScale(
              scale: scale,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.shellBg,
                        Color.alphaBlend(
                          const Color(0xFF4F8DFF).withAlpha(12),
                          colors.shellBg,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24 * scale),
                    border: Border.all(color: colors.shellBorder, width: 2 * scale),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shellShadow,
                        blurRadius: 34 * scale,
                        offset: Offset(0, 14 * scale),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24 * scale),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _StickyNoticeShell(
                          colors: colors,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          onClose: onClose,
                          onOpenSummary: () => unawaited(_openPolicy(
                            context,
                            title: 'Privacy Policy Summary',
                            uri: privacyPolicySummaryUri,
                          )),
                          onOpenFull: () => unawaited(_openPolicy(
                            context,
                            title: 'Full Privacy Policy',
                            uri: privacyPolicyFullUri,
                          )),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    });
  }
}

class _StickyNoticeShell extends StatefulWidget {
  const _StickyNoticeShell({
    required this.colors,
    required this.maxWidth,
    required this.maxHeight,
    required this.onClose,
    required this.onOpenSummary,
    required this.onOpenFull,
  });
  final _LocationNoticeColors colors;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback? onClose;
  final VoidCallback onOpenSummary;
  final VoidCallback onOpenFull;

  @override
  State<_StickyNoticeShell> createState() => _StickyNoticeShellState();
}

class _StickyNoticeShellState extends State<_StickyNoticeShell> {
  final ScrollController _controller = ScrollController();
  bool _showScrollCue = false;
  bool _hasOverflow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollCue);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollCue());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollCue);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollCue() {
    if (!_controller.hasClients) {
      if (_showScrollCue || _hasOverflow) {
        setState(() {
          _showScrollCue = false;
          _hasOverflow = false;
        });
      }
      return;
    }
    final position = _controller.position;
    final hasOverflow = position.maxScrollExtent > 8;
    final canScrollMore =
        hasOverflow && position.pixels < position.maxScrollExtent - 12;
    if (canScrollMore != _showScrollCue || hasOverflow != _hasOverflow) {
      setState(() {
        _showScrollCue = canScrollMore;
        _hasOverflow = hasOverflow;
      });
    }
  }

  Future<void> _scrollToEnd() async {
    if (!_controller.hasClients) return;
    await _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final scale = _NoticeScale.of(context);
    final scrollCueTopInset = 4 * scale;
    final scrollCueHeight = (32 * scale) + scrollCueTopInset;
    final scrollCueGap = 5 * scale;
    final scrollCueClearance = scrollCueHeight + scrollCueGap;
    final header = _NoticeHeader(
      colors: colors,
      onClose: widget.onClose,
    );
    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        14 * scale,
        10 * scale,
        14 * scale,
        14 * scale + (_hasOverflow ? scrollCueClearance : 0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrustTagline(colors: colors),
          SizedBox(height: 10 * scale),
          _HeroNotice(colors: colors),
          SizedBox(height: 8 * scale),
          _SectionLabel(colors: colors),
          SizedBox(height: 5 * scale),
          _StepsPanel(colors: colors),
          SizedBox(height: 7 * scale),
          _PrivacyPanel(colors: colors),
          SizedBox(height: 7 * scale),
          _ContactPanel(colors: colors),
        ],
      ),
    );
    final footer = Material(
      color: colors.shellBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: colors.sectionDivider),
          Padding(
            padding: EdgeInsets.fromLTRB(
              14 * scale,
              8 * scale,
              14 * scale,
              6 * scale,
            ),
            child: _ActionArea(
              colors: colors,
              onClose: widget.onClose,
              onOpenSummary: widget.onOpenSummary,
              onOpenFull: widget.onOpenFull,
            ),
          ),
        ],
      ),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final useFullScroll = widget.maxHeight < (430 * scale) || textScale > 1.4;
    final scrollCue = IgnorePointer(
      ignoring: !_showScrollCue,
      child: AnimatedOpacity(
        opacity: _showScrollCue ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: _ScrollDownCue(
          colors: colors,
          height: scrollCueHeight,
          topInset: scrollCueTopInset,
          onTap: () => unawaited(_scrollToEnd()),
        ),
      ),
    );
    if (useFullScroll) {
      return SizedBox(
        width: widget.maxWidth,
        height: widget.maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  SingleChildScrollView(
                    controller: _controller,
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [header, body],
                    ),
                  ),
                  scrollCue,
                ],
              ),
            ),
            footer,
          ],
        ),
      );
    }
    return SizedBox(
      width: widget.maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Flexible(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _updateScrollCue();
                return false;
              },
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Scrollbar(
                    controller: _controller,
                    child: SingleChildScrollView(
                      controller: _controller,
                      primary: false,
                      child: body,
                    ),
                  ),
                  scrollCue,
                ],
              ),
            ),
          ),
          footer,
        ],
      ),
    );
  }
}

class _ScrollDownCue extends StatefulWidget {
  const _ScrollDownCue({
    required this.colors,
    required this.height,
    required this.topInset,
    required this.onTap,
  });
  final _LocationNoticeColors colors;
  final double height;
  final double topInset;
  final VoidCallback onTap;

  @override
  State<_ScrollDownCue> createState() => _ScrollDownCueState();
}

class _ScrollDownCueState extends State<_ScrollDownCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bobController;
  late final Animation<double> _bob;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bob = Tween<double>(begin: 0, end: 2.5).animate(
      CurvedAnimation(parent: _bobController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final scale = _NoticeScale.of(context);
    final cueColor = colors.heroBody.withValues(alpha: 0.7);
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.shellBg.withValues(alpha: 0),
                colors.shellBg.withValues(alpha: 0.72),
                colors.shellBg,
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: widget.topInset),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Scroll to read more',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cueColor,
                    fontSize: 11.5 * scale,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _bob.value * scale),
                      child: child,
                    );
                  },
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14 * scale,
                    color: cueColor,
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

class _NoticeHeader extends StatelessWidget {
  const _NoticeHeader({required this.colors, required this.onClose});
  final _LocationNoticeColors colors;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scale = _NoticeScale.of(context);
    final logoSize = 44 * scale;
    final closeSize = 44 * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            16 * scale,
            16 * scale,
            12 * scale,
            16 * scale,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF075DA7), Color(0xFF051C45)],
            ),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(23 * scale),
            ),
          ),
          child: Row(
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
                      blurRadius: 18 * scale,
                      offset: Offset(0, 8 * scale),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(2 * scale),
                  child: ClipOval(
                    child: DebugEnvLogoHotspot(
                      width: logoSize,
                      height: logoSize,
                      padding: EdgeInsets.zero,
                      borderRadius: 28 * scale,
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 38 * scale,
                margin: EdgeInsets.symmetric(horizontal: 10 * scale),
                color: Colors.white.withAlpha(140),
              ),
              Expanded(
                child: Text(
                  'SmartNPS360\nLocation Notice',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19 * scale,
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 10 * scale),
              Material(
                color: Colors.white.withAlpha(30),
                shape: const CircleBorder(),
                elevation: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withAlpha(70)),
                  ),
                  child: IconButton(
                    onPressed: onClose,
                    constraints: BoxConstraints.tightFor(
                      width: closeSize,
                      height: closeSize,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    iconSize: 26 * scale,
                    tooltip: 'Close',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrustTagline extends StatelessWidget {
  const _TrustTagline({required this.colors});
  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    final scale = _NoticeScale.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.taglineBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 7 * scale,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_rounded,
              color: const Color(0xFF1684FF),
              size: 17 * scale,
            ),
            SizedBox(width: 7 * scale),
            Flexible(
              child: Text(
                'Your trust and privacy are our priority.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.taglineText,
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroNotice extends StatelessWidget {
  const _HeroNotice({required this.colors});
  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    final scale = _NoticeScale.of(context);
    final pinSize = 70 * scale;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 100 * scale),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: NativeThemeController.instance.isDark
                ? const [Color(0xFF1A416F), Color(0xFF0B203B)]
                : const [
                    Color(0xFFF9FCFF),
                    Color(0xFFD2E5FF),
                    Color(0xFFB8D7FF),
                  ],
          ),
          borderRadius: BorderRadius.circular(16 * scale),
          border: Border.all(color: colors.heroBorder, width: 1.5 * scale),
          boxShadow: [
            BoxShadow(
              color: colors.heroShadow,
              blurRadius: 12 * scale,
              offset: Offset(0, 4 * scale),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 10 * scale,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location is used only while you are clocked in on an active shift.',
                      style: TextStyle(
                        color: colors.heroTitle,
                        fontSize: 15 * scale,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      'It supports safety, patrol verification, and attendance.',
                      style: TextStyle(
                        color: colors.heroBody,
                        fontSize: 12.5 * scale,
                        height: 1.32,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10 * scale),
              SizedBox(
                width: pinSize,
                height: pinSize,
                child: SvgPicture.asset(
                  NativeThemeController.instance.isDark
                      ? 'assets/images/location_pin_dark.svg'
                      : 'assets/images/location_pin_light.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
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
    final scale = _NoticeScale.of(context);
    return Row(
      children: [
        Expanded(child: Divider(color: colors.sectionDivider)),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 10 * scale),
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 6 * scale,
          ),
          decoration: BoxDecoration(
            color: colors.taglineBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'HOW IT WORKS',
            style: TextStyle(
              color: colors.sectionLabel,
              fontSize: 10 * scale,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5 * scale,
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
    final scale = _NoticeScale.of(context);
    final gap = SizedBox(height: 3 * scale);
    return Column(
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
        gap,
        _NoticeStep(
          icon: Icons.restaurant_rounded,
          title: 'During An Unpaid Meal Break',
          body:
          'Location tracking pauses during unpaid meal breaks and resumes when you return to duty.',
          color: colors.leavingSiteColor,
          iconBackground: colors.leavingSiteIconBg,
          bodyColor: colors.stepBody,
        ),
        gap,
        _NoticeStep(
          icon: Icons.logout_rounded,
          title: 'When You Clock Out',
          body: 'Tracking stops when your shift ends and you clock out.',
          color: colors.clockOutColor,
          iconBackground: colors.clockOutIconBg,
          bodyColor: colors.stepBody,
        ),
        gap,
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
    final scale = _NoticeScale.of(context);
    return Container(
      margin: EdgeInsets.symmetric(vertical: 2 * scale),
      padding: EdgeInsets.fromLTRB(
        12 * scale,
        10 * scale,
        12 * scale,
        10 * scale,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
              iconBackground.withAlpha(35),
              colorsForStep(context),
            ),
            colorsForStep(context),
          ],
        ),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: bodyColor.withAlpha(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(7),
            blurRadius: 6 * scale,
            offset: Offset(0, 2 * scale),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CircleIcon(
            icon: icon,
            background: iconBackground,
            color: color,
            size: 42 * scale,
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 15 * scale,
                    height: 1.16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  body,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 13 * scale,
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
  Color colorsForStep(BuildContext context) =>
  NativeThemeController.instance.isDark
  ? const Color(0xFF18263B)
  : Colors.white;
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel({required this.colors});
  final _LocationNoticeColors colors;

  @override
  Widget build(BuildContext context) {
    final scale = _NoticeScale.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: colors.privacyBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.privacyGradient,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(12 * scale),
        child: Row(
          children: [
            _CircleIcon(
              icon: Icons.lock_rounded,
              background: colors.privacyIconBg,
              color: colors.privacyIconColor,
              size: 46 * scale,
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Privacy Matters',
                    style: TextStyle(
                      color: colors.privacyTitle,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    'We do not track you off duty or when you are not clocked in. Your data is used solely to support safety, security, and operational needs.',
                    style: TextStyle(
                      color: colors.privacyBody,
                      fontSize: 13 * scale,
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
    final scale = _NoticeScale.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(color: colors.contactBorder, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.contactGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.contactShadow,
            blurRadius: 14 * scale,
            offset: Offset(0, 7 * scale),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(12 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
                Expanded(child: Text(
                    'Questions?',
                    style: TextStyle(
                      color: colors.contactTitle,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  Icons.support_agent_rounded,
                  color: colors.contactBody,
                  size: 25 * scale,
                ),
            ]),
            SizedBox(height: 3 * scale),
            Text(
              'We\'re here to help. Contact our Privacy Team.',
              style: TextStyle(
                color: colors.contactBody,
                fontSize: 12.4 * scale,
                height: 1.25,
              ),
            ),
            SizedBox(height: 7 * scale),
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
                SizedBox(width: 8 * scale),
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
    final scale = _NoticeScale.of(context);
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
            padding: EdgeInsets.symmetric(
              horizontal: 8 * scale,
              vertical: 5 * scale,
            ),
            child: Row(
              children: [
                Icon(icon, color: colors.contactPillFg, size: 14 * scale),
                SizedBox(width: 5 * scale),
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
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 2 * scale),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.contactPillFg,
                  size: 15 * scale,
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
    final scale = _NoticeScale.of(context);
    final buttonHeight = 40 * scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12 * scale),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: NativeThemeController.instance.isDark
              ? const [Color(0xFF299FF4), Color(0xFF0756C8)]
              : const [Color(0xFF075DA7), Color(0xFF051C45)],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.heroShadow,
                blurRadius: 8 * scale,
                offset: Offset(0, 3 * scale),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: onClose == null
                  ? colors.primaryBtnBg.withAlpha(100)
                  : Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: colors.primaryBtnFg,
              minimumSize: Size.fromHeight(buttonHeight),
              maximumSize: Size.fromHeight(buttonHeight),
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 0),
              elevation: 0,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11 * scale),
              ),
              textStyle: TextStyle(
                fontSize: 16 * scale,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            child: const Text('I Understand'),
          ),
        ),
        SizedBox(height: 2 * scale),
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
    final scale = _NoticeScale.of(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 11 * scale),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: colors.policyLink,
        minimumSize: Size(0, 26 * scale),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.symmetric(
          horizontal: 4 * scale,
          vertical: 1 * scale,
        ),
        textStyle: TextStyle(
          fontSize: 11.5 * scale,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
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
    final isLandscape = media.orientation == Orientation.landscape;
    final maxWidth = isLandscape
    ? 600.0
    : (media.size.width >= 820 ? 760.0 : media.size.width - 18);
    final maxHeight = media.size.height - media.padding.vertical - 24;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 40 : 9,
        vertical: isLandscape ? 12 : 12,
      ),
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
    final scale = _NoticeScale.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            background,
            Color.alphaBlend(color.withAlpha(20), background),
          ],
        ),
        borderRadius: BorderRadius.circular(11 * scale),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(18),
            blurRadius: 6 * scale,
            offset: Offset(0, 2 * scale),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
