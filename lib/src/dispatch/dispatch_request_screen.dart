import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../widgets/sheets/app_bottom_sheet_motion.dart';
import 'dispatch_decline_note_input.dart';
import 'dispatch_expired_sheet_controller.dart';
import 'dispatch_request_controller.dart';
import 'dispatch_request_data.dart';
import 'dispatch_response_panel.dart';
import 'dispatch_route_map.dart';
import 'dispatch_scale.dart';

export 'dispatch_request_data.dart';

class DispatchRequestScreen extends StatefulWidget {
  const DispatchRequestScreen({
    super.key,
    this.request = const DispatchRequestData(
      address: 'Horizon Plaza',
      city: '',
      summary:
          'Suspicious person near the parking entrance. Check the area and report your findings to dispatch.',
      score: 97,
      arrivalMinutes: 9,
      distanceMiles: 1.8,
      siteLatitude: 28.477741852243042,
      siteLongitude: 70.40424054232736,
    ),
  });

  static const bool openExpiredOnTimerEnd =
      DispatchRequestConfig.openExpiredOnTimerEnd;

  final DispatchRequestData request;

  @override
  State<DispatchRequestScreen> createState() => _DispatchRequestScreenState();
}

class _DispatchRequestScreenState extends State<DispatchRequestScreen> {
  late final DispatchRequestController _controller;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<DispatchRequestController>(
      tag: DispatchRequestController.tag,
    )) {
      Get.delete<DispatchRequestController>(
        tag: DispatchRequestController.tag,
        force: true,
      );
    }
    _controller = Get.put(
      DispatchRequestController(request: widget.request),
      tag: DispatchRequestController.tag,
    );
  }

  @override
  void dispose() {
    if (Get.isRegistered<DispatchRequestController>(
      tag: DispatchRequestController.tag,
    )) {
      Get.delete<DispatchRequestController>(
        tag: DispatchRequestController.tag,
        force: true,
      );
    }
    super.dispose();
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Theme(
      data: ThemeData(brightness: brightness, useMaterial3: true),
      child: _DispatchRequestBody(
        controller: _controller,
        onSubmitted: (declining) => _showResult(
          declining
              ? 'Decline reason submitted to dispatch.'
              : 'Explanation submitted to dispatch.',
        ),
      ),
    );
  }
}

class _DispatchRequestBody extends StatelessWidget {
  const _DispatchRequestBody({
    required this.controller,
    required this.onSubmitted,
  });

  final DispatchRequestController controller;
  final void Function(bool declining) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Obx(() {
      if (controller.consumeExitToDashboard()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).maybePop();
          }
        });
        return Scaffold(
          backgroundColor: colors.dashboard,
          body: const SizedBox.expand(),
        );
      }

      final declining = controller.declining.value;
      final expired = controller.expired.value;
      final Widget sheet;
      if (expired || declining) {
        sheet = _ExpiredSheet(
          key: ValueKey(declining ? 'dispatch-decline' : 'dispatch-expired'),
          declining: declining,
          request: controller.request,
          onSubmitted: () => onSubmitted(declining),
        );
      } else {
        sheet = _RequestSheet(
          key: const ValueKey('dispatch-request'),
          controller: controller,
          onAccept:
              ({
                bool launchNavigation = false,
                bool deferDashboardExit = false,
              }) => controller.acceptAndOpenMap(
                context: context,
                launchNavigation: launchNavigation,
                deferDashboardExit: deferDashboardExit,
              ),
          onDecline: controller.decline,
        );
      }

      return Scaffold(
        backgroundColor: colors.dashboard,
        body: AppEmbeddedBottomSheetFrame(
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : AppBottomSheetMotion.openDuration,
            reverseDuration: reduceMotion
                ? Duration.zero
                : AppBottomSheetMotion.closeDuration,
            switchInCurve: AppBottomSheetMotion.openCurve,
            switchOutCurve: AppBottomSheetMotion.closeCurve,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[...previousChildren, ?currentChild],
              );
            },
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: sheet,
          ),
        ),
      );
    });
  }
}

class _RequestSheet extends StatelessWidget {
  const _RequestSheet({
    super.key,
    required this.controller,
    required this.onAccept,
    required this.onDecline,
  });

  final DispatchRequestController controller;
  final Future<void> Function({bool launchNavigation, bool deferDashboardExit})
  onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    final request = controller.request;
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    return Obx(() {
      final secondsLeft = controller.secondsLeft.value;
      final arrivalMinutes = controller.arrivalMinutes.value;
      final distanceMiles = controller.distanceMiles.value;
      final accepted = controller.accepted.value;
      final actionsEnabled =
          !accepted &&
          (secondsLeft > 0 || !DispatchRequestConfig.openExpiredOnTimerEnd);
      return _SheetFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _StatusPill(
                iconColor: colors.blue,
                background: colors.badgeBackground,
                label: 'NEW RESPONSE REQUEST',
                foreground: colors.badgeForeground,
                compact: true,
              ),
            ),
            SizedBox(height: scale.s(14)),
            Row(
              children: [
                Container(
                  width: scale.s(40),
                  height: scale.s(40),
                  padding: EdgeInsets.all(scale.s(8)),
                  decoration: BoxDecoration(
                    color: colors.redSoft,
                    borderRadius: BorderRadius.circular(scale.s(12)),
                  ),
                  child: SvgPicture.asset('assets/images/dispatch_siren.svg'),
                ),
                SizedBox(width: scale.s(12)),
                Expanded(
                  child: Text(
                    'Response requested',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: scale.sp(22),
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: scale.s(8)),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: colors.text,
                  size: scale.s(20),
                ),
                SizedBox(width: scale.s(8)),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: request.address,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (request.city.trim().isNotEmpty)
                          TextSpan(text: '  ·  ${request.city}'),
                      ],
                    ),
                    style: TextStyle(
                      color: colors.text,
                      fontSize: scale.sp(16),
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: scale.sectionGap),
            _GradientCard(
              padding: EdgeInsets.all(scale.s(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReferenceIcon(asset: 'dispatch_clipboard.svg'),
                  SizedBox(width: scale.s(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Incident Summary',
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: scale.sp(15),
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: scale.s(5)),
                        Text(
                          request.summary,
                          style: TextStyle(
                            color: colors.label,
                            fontSize: scale.sp(13),
                            height: 1.4,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: scale.sectionGap),
            Row(
              children: [
                _ReferenceIcon(asset: 'dispatch_navigation.svg', size: 28),
                SizedBox(width: scale.s(10)),
                Expanded(
                  child: Text(
                    'Route to the site',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: scale.sp(16),
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: scale.s(10)),
            DispatchRouteMap(
              onAccept: accepted || actionsEnabled
                  ? () => onAccept(
                      launchNavigation: false,
                      deferDashboardExit: true,
                    )
                  : null,
              onDecline: actionsEnabled ? onDecline : null,
              onRouteSnapshot: controller.applyRouteSnapshot,
              responseSecondsLeft: controller.secondsLeftListenable,
              responseTotalSeconds: request.responseSeconds,
              site: request.site,
              siteName: request.address,
              siteSubtitle: request.city,
              isDark: colors.isDark,
              height: scale.mapHeight,
              onMetrics: controller.applyMetrics,
            ),
            SizedBox(height: scale.s(12)),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.schedule_outlined,
                    label: 'Estimated arrival',
                    value: '$arrivalMinutes min',
                  ),
                ),
                SizedBox(width: scale.s(10)),
                Expanded(
                  child: _Metric(
                    icon: Icons.location_on_outlined,
                    label: 'Distance to site',
                    value: '$distanceMiles mi',
                  ),
                ),
              ],
            ),
            SizedBox(height: scale.metricsToCountdownGap),
            DispatchResponsePanel(
              secondsLeft: secondsLeft,
              totalSeconds: request.responseSeconds,
              onAccept: accepted || actionsEnabled
                  ? () => onAccept(launchNavigation: false)
                  : null,
              onDecline: actionsEnabled ? onDecline : null,
            ),
          ],
        ),
      );
    });
  }
}

class _ExpiredSheet extends StatefulWidget {
  const _ExpiredSheet({
    super.key,
    required this.request,
    required this.onSubmitted,
    this.declining = false,
  });

  final bool declining;

  final DispatchRequestData request;
  final VoidCallback onSubmitted;

  @override
  State<_ExpiredSheet> createState() => _ExpiredSheetState();
}

class _ExpiredSheetState extends State<_ExpiredSheet> {
  late final DispatchExpiredSheetController _sheetController;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<DispatchExpiredSheetController>(
      tag: DispatchExpiredSheetController.tag,
    )) {
      Get.delete<DispatchExpiredSheetController>(
        tag: DispatchExpiredSheetController.tag,
        force: true,
      );
    }
    _sheetController = Get.put(
      DispatchExpiredSheetController(onSubmitted: widget.onSubmitted),
      tag: DispatchExpiredSheetController.tag,
    );
  }

  @override
  void dispose() {
    if (Get.isRegistered<DispatchExpiredSheetController>(
      tag: DispatchExpiredSheetController.tag,
    )) {
      Get.delete<DispatchExpiredSheetController>(
        tag: DispatchExpiredSheetController.tag,
        force: true,
      );
    }
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    _sheetController.submit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: scale.s(44),
                height: scale.s(44),
                decoration: BoxDecoration(
                  color: colors.redSoft,
                  borderRadius: BorderRadius.circular(scale.s(12)),
                ),
                child: Icon(
                  widget.declining
                      ? Icons.cancel_outlined
                      : Icons.schedule_outlined,
                  color: colors.red,
                  size: scale.s(24),
                ),
              ),
              SizedBox(width: scale.s(12)),
              Expanded(
                child: Text(
                  widget.declining
                      ? 'DECLINE DISPATCH REQUEST'
                      : 'REQUEST EXPIRED · 30 SECONDS',
                  style: TextStyle(
                    color: colors.red,
                    fontWeight: FontWeight.w700,
                    fontSize: scale.sp(13.5),
                    letterSpacing: .2,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scale.s(14)),
          Text(
            widget.declining
                ? 'Why are you declining?'
                : 'You missed a dispatch request',
            style: TextStyle(
              color: colors.text,
              fontSize: scale.sp(22),
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
          ),
          SizedBox(height: scale.s(8)),
          Text(
            widget.declining
                ? 'Please provide a reason so dispatch can reassign this request.'
                : 'You did not accept or decline in time. Please explain why you couldn’t respond.',
            style: TextStyle(
              color: colors.label,
              fontSize: scale.sp(14.5),
              height: 1.4,
            ),
          ),
          SizedBox(height: scale.sectionGap),
          _GradientCard(
            child: Row(
              children: [
                Container(
                  width: scale.s(40),
                  height: scale.s(40),
                  decoration: BoxDecoration(
                    color: colors.blueSoft,
                    borderRadius: BorderRadius.circular(scale.s(10)),
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: colors.blueStrong,
                    size: scale.s(22),
                  ),
                ),
                SizedBox(width: scale.s(12)),
                Container(width: 1, height: scale.s(32), color: colors.border),
                SizedBox(width: scale.s(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.address,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: scale.sp(16),
                        ),
                      ),
                      Text(
                        widget.request.city.trim().isEmpty
                            ? 'Priority response'
                            : '${widget.request.city} · Priority response',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.label,
                          fontSize: scale.sp(13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: scale.s(14)),
          Container(
            padding: EdgeInsets.all(scale.s(14)),
            decoration: BoxDecoration(
              color: colors.warningSoft,
              border: Border.all(color: colors.warningBorder),
              borderRadius: BorderRadius.circular(scale.cardRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: colors.warning,
                  size: scale.s(22),
                ),
                SizedBox(width: scale.s(10)),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: widget.declining
                              ? 'A text or voice reason is required. '
                              : 'Dispatch notified of timeout. ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: widget.declining
                              ? 'Your note will be sent to dispatch when you confirm the decline.'
                              : 'The assignment has expired. Your text or voice explanation will be attached to the missed request.',
                        ),
                      ],
                    ),
                    style: TextStyle(
                      color: colors.warning,
                      fontSize: scale.sp(13),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: scale.s(18)),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: widget.declining
                            ? 'Reason for declining '
                            : 'Why didn’t you respond? ',
                      ),
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: colors.red),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: scale.sp(16),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: scale.s(9),
                  vertical: scale.s(5),
                ),
                decoration: BoxDecoration(
                  color: colors.badgeBackground,
                  borderRadius: BorderRadius.circular(scale.s(20)),
                ),
                child: Text(
                  'REQUIRED',
                  style: TextStyle(
                    color: colors.label,
                    fontWeight: FontWeight.w700,
                    fontSize: scale.sp(10.5),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scale.s(4)),
          Text(
            widget.declining
                ? 'Explain why you cannot accept this assignment with a text or voice note.'
                : 'Explain what prevented you from responding within 30 seconds with a text or voice note.',
            style: TextStyle(color: colors.label, fontSize: scale.sp(13)),
          ),
          SizedBox(height: scale.s(12)),
          Obx(
            () => DispatchDeclineNoteInput(
              textController: _sheetController.textController,
              isDark: colors.isDark,
              declining: widget.declining,
              errorText: _sheetController.errorMessage.value,
              onChanged: _sheetController.clearError,
              onVoicePathChanged: _sheetController.setVoicePath,
            ),
          ),
          SizedBox(height: scale.s(14)),
          _PrimaryButton(
            onPressed: _submit,
            child: Text(
              widget.declining
                  ? 'Confirm decline'
                  : 'Submit explanation to dispatch',
              style: TextStyle(fontSize: scale.sp(16)),
            ),
          ),
          SizedBox(height: scale.s(12)),
          Text(
            widget.declining
                ? 'Dispatch will receive your reason for declining.'
                : 'This explanation does not reopen the expired request.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.label, fontSize: scale.sp(13)),
          ),
        ],
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    return Container(
      width: scale.size.width,
      constraints: BoxConstraints(maxHeight: scale.sheetHeight),
      decoration: BoxDecoration(
        color: colors.sheet,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(scale.sheetRadius),
        ),
        border: colors.isDark ? Border.all(color: colors.border) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.35 : 0.12),
            blurRadius: scale.s(24),
            offset: Offset(0, -scale.s(6)),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: scale.bottomSafePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: scale.s(10)),
            Container(
              width: scale.handleWidth,
              height: scale.handleHeight,
              decoration: BoxDecoration(
                color: colors.handle,
                borderRadius: BorderRadius.circular(scale.s(20)),
              ),
            ),
            SizedBox(height: scale.s(10)),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  scale.s(20),
                  0,
                  scale.s(20),
                  scale.s(4),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.background,
    required this.label,
    required this.foreground,
    this.iconColor,
    this.compact = false,
  });

  final Color background;
  final String label;
  final Color foreground;
  final Color? iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: scale.s(28)),
      padding: EdgeInsets.symmetric(
        horizontal: scale.s(compact ? 10 : 12),
        vertical: scale.s(compact ? 6 : 8),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(scale.s(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconColor != null) ...[
            _PulsingDot(color: iconColor!),
            SizedBox(width: scale.s(compact ? 7 : 9)),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: scale.sp(compact ? 11 : 12.5),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceIcon extends StatelessWidget {
  const _ReferenceIcon({required this.asset, this.size = 32});
  final String asset;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    final side = scale.s(size);
    return Container(
      width: side,
      height: side,
      padding: EdgeInsets.all(scale.s(6)),
      decoration: BoxDecoration(
        color: colors.blueSoft,
        borderRadius: BorderRadius.circular(scale.s(10)),
      ),
      child: SvgPicture.asset('assets/images/$asset'),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => SizedBox(
        width: scale.s(18),
        height: scale.s(18),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: scale.s(10 + 8 * _pulse.value),
              height: scale.s(10 + 8 * _pulse.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: .24 * (1 - _pulse.value)),
                border: Border.all(
                  color: widget.color.withValues(
                    alpha: .85 * (1 - _pulse.value),
                  ),
                  width: scale.s(1.5),
                ),
              ),
            ),
            Container(
              width: scale.s(8),
              height: scale.s(8),
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientCard extends StatelessWidget {
  const _GradientCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    return Container(
      padding: padding ?? EdgeInsets.all(scale.s(14)),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(scale.cardRadius),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.18 : 0.04),
            blurRadius: scale.s(8),
            offset: Offset(0, scale.s(2)),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: scale.s(64)),
      padding: EdgeInsets.symmetric(
        horizontal: scale.s(12),
        vertical: scale.s(10),
      ),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(scale.cardRadius),
        border: Border.all(color: colors.border.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.16 : 0.03),
            blurRadius: scale.s(6),
            offset: Offset(0, scale.s(2)),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: scale.s(32),
            height: scale.s(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.blueSoft,
              borderRadius: BorderRadius.circular(scale.s(9)),
            ),
            child: Icon(icon, color: colors.blueStrong, size: scale.s(18)),
          ),
          SizedBox(width: scale.s(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.label,
                    fontSize: scale.sp(11),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: scale.s(2)),
                Text(
                  value,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: scale.sp(18),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = _DispatchColors.of(context);
    final scale = DispatchScale.of(context);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: colors.buttonGradient,
          borderRadius: BorderRadius.circular(scale.cardRadius),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF2866DF).withValues(alpha: 0.22),
                    blurRadius: scale.s(10),
                    offset: Offset(0, scale.s(4)),
                  ),
                ]
              : const [],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(scale.buttonHeight),
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: scale.s(12)),
            textStyle: TextStyle(
              fontSize: scale.sp(15),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(scale.cardRadius),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

@immutable
class _DispatchColors {
  const _DispatchColors({required this.isDark});

  factory _DispatchColors.of(BuildContext context) =>
      _DispatchColors(isDark: Theme.of(context).brightness == Brightness.dark);

  final bool isDark;

  Color get dashboard =>
      isDark ? const Color(0xFF0A1520) : const Color(0xFFE8EEF8);
  Color get sheet => isDark ? const Color(0xFF101D2B) : const Color(0xFFFAFBFE);
  Color get text => isDark ? const Color(0xFFF1F5FC) : const Color(0xFF102541);
  Color get label => isDark ? const Color(0xFFA6B7CC) : const Color(0xFF52647D);
  Color get muted => isDark ? const Color(0xFF8CA2B9) : const Color(0xFF64748B);
  Color get blue => isDark ? const Color(0xFF70AEFF) : const Color(0xFF2866DF);
  Color get blueStrong =>
      isDark ? const Color(0xFF93C5FD) : const Color(0xFF2856D9);
  Color get blueSoft =>
      isDark ? const Color(0xFF1A3148) : const Color(0xFFE8F0FC);
  Color get blueTrack =>
      isDark ? const Color(0xFF2A4058) : const Color(0xFFD5E4F8);
  Color get badgeBackground =>
      isDark ? const Color(0xFF192F4D) : const Color(0xFFE5EEFC);
  Color get badgeForeground =>
      isDark ? const Color(0xFF93C5FD) : const Color(0xFF2856D9);
  Color get urgencyBlueSoft =>
      isDark ? const Color(0xFF152A42) : const Color(0xFFEEF4FC);
  Color get urgencyAmber =>
      isDark ? const Color(0xFFFBBF55) : const Color(0xFFC17A12);
  Color get urgencyAmberSoft =>
      isDark ? const Color(0xFF302617) : const Color(0xFFFFF7E7);
  Color get urgencyAmberTrack =>
      isDark ? const Color(0xFF4A3A22) : const Color(0xFFF3E2C2);
  Color get urgencyRed =>
      isDark ? const Color(0xFFFF737D) : const Color(0xFFDC3545);
  Color get urgencyRedSoft =>
      isDark ? const Color(0xFF351F29) : const Color(0xFFFFF0F0);
  Color get urgencyRedTrack =>
      isDark ? const Color(0xFF4A2A33) : const Color(0xFFF5D0D3);
  Color get orange => urgencyAmber;
  Color get orangeSoft => urgencyAmberSoft;
  Color get red => urgencyRed;
  Color get redSoft => urgencyRedSoft;
  Color get panel => isDark ? const Color(0xFF1B2D42) : const Color(0xFFF8FAFE);
  Color get input => isDark ? const Color(0xFF142437) : const Color(0xFFFFFFFF);
  Color get border =>
      isDark ? const Color(0xFF2D415A) : const Color(0xFFDCE5F2);
  Color get handle =>
      isDark ? const Color(0xFF4A6078) : const Color(0xFFC5D0E0);
  Color get warning =>
      isDark ? const Color(0xFFFBBF55) : const Color(0xFF8E5105);
  Color get warningSoft =>
      isDark ? const Color(0xFF302617) : const Color(0xFFFFF8E7);
  Color get warningBorder =>
      isDark ? const Color(0xFFD79B2B) : const Color(0xFFF2C260);
  Color get declineText =>
      isDark ? const Color(0xFFF1F5FC) : const Color(0xFF102541);
  Color get declineBackground =>
      isDark ? const Color(0xFF162636) : const Color(0xFFF7F9FD);
  Color get declineBorder =>
      isDark ? const Color(0xFF2D415A) : const Color(0xFFD0DBEA);
  LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [Color(0xFF1B2D42), Color(0xFF142437)]
        : const [Color(0xFFF8FAFE), Color(0xFFEDF4FF)],
  );
  LinearGradient get buttonGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF367FF5), Color(0xFF2356D5)],
  );

  @override
  bool operator ==(Object other) =>
      other is _DispatchColors && other.isDark == isDark;

  @override
  int get hashCode => isDark.hashCode;
}
