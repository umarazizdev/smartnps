import 'package:flutter/material.dart';

class AuthGlassPopup {
  AuthGlassPopup._();

  static const Color border = Color(0xFF7EA5E2);
  static const Color cardTop = Color(0xFF1B3454);
  static const Color cardBottom = Color(0xFF0E203C);
  static const Color closeFill = Color(0xFF314B70);
  static const Color bodyColor = Color(0xFFCAD5E7);
  static const Color titleColor = Color(0xFFF8FAFF);

  static const Color _red = Color(0xFFFF6671);
  static const Color _green = Color(0xFF45D4A2);
  static const Color _blue = Color(0xFF76B5FF);
  static const Color _scrim = Color(0xAD040B17);

  static double _scale(BuildContext context) =>
      (MediaQuery.sizeOf(context).width / 390).clamp(0.96, 1.08).toDouble();

  static Future<void> showMessage(
    BuildContext context, {
    required String title,
    required String message,
    bool success = false,
    String buttonLabel = 'Got it',
    VoidCallback? onDismissed,
  }) async {
    final scale = _scale(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: _scrim,
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _Shell(
              scale: scale,
              onClose: () => Navigator.of(dialogContext).pop(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  
                  SizedBox(height: 14 * scale),
                  Center(
                    child: _StatusIcon(
                      scale: scale,
                      color: success ? _green : _red,
                      icon: success
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                    ),
                  ),
                  SizedBox(height: 18 * scale),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21 * scale,
                      height: 1.22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: titleColor,
                    ),
                  ),
                  SizedBox(height: 11 * scale),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: bodyColor,
                      fontSize: 15 * scale,
                      height: 1.48,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: 25 * scale),
                  _PrimaryButton(
                    label: buttonLabel,
                    scale: scale,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    onDismissed?.call();
  }

  
  static Future<void> showWelcomeNotice(BuildContext context) {
    final scale = _scale(context);
    final scrollController = ScrollController();
    var hasReachedEnd = false;
    var initialCheckScheduled = false;

    final titleStyle = TextStyle(
      fontSize: 18 * scale,
      height: 1.32,
      fontWeight: FontWeight.w700,
      color: titleColor,
      letterSpacing: -0.25,
    );
    final paragraphStyle = TextStyle(
      color: bodyColor,
      height: 1.55,
      fontSize: 15 * scale,
      fontWeight: FontWeight.w400,
    );

    final future = showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: _scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox.expand(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        if (!initialCheckScheduled) {
                          initialCheckScheduled = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!scrollController.hasClients) return;
                            final atEnd =
                                scrollController.position.maxScrollExtent <= 0;
                            if (atEnd != hasReachedEnd && context.mounted) {
                              setDialogState(() => hasReachedEnd = atEnd);
                            }
                          });
                        }

                        return _Shell(
                          scale: scale,
                          expand: true,
                          onClose: () => Navigator.of(dialogContext).pop(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: 14 * scale),
                              Center(
                                child: _StatusIcon(
                                  scale: scale,
                                  color: _blue,
                                  icon: Icons.info_outline_rounded,
                                ),
                              ),
                              SizedBox(height: 18 * scale),
                              Text(
                                'Professional Guard Registration Notice & Acknowledgment',
                                textAlign: TextAlign.center,
                                style: titleStyle,
                              ),
                              SizedBox(height: 20 * scale),
                              Expanded(
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    final metrics = notification.metrics;
                                    final atEnd =
                                        metrics.maxScrollExtent <= 0 ||
                                        metrics.pixels >=
                                            metrics.maxScrollExtent - 8;
                                    if (atEnd != hasReachedEnd) {
                                      setDialogState(
                                        () => hasReachedEnd = atEnd,
                                      );
                                    }
                                    return false;
                                  },
                                  child: SingleChildScrollView(
                                    controller: scrollController,
                                    physics: const ClampingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'By proceeding with this application, you acknowledge and agree that all information provided must be accurate, complete, and truthful to the best of your knowledge.',
                                          style: paragraphStyle,
                                        ),
                                        SizedBox(height: 14 * scale),
                                        Text(
                                          'This application is part of the employment screening process with National Protective Service and may include background verification, employment history review, and compliance with applicable state and federal regulations.',
                                          style: paragraphStyle,
                                        ),
                                        SizedBox(height: 14 * scale),
                                        Text(
                                          'Any false statements, omissions, or misrepresentations may result in disqualification from employment or termination if discovered after hire.',
                                          style: paragraphStyle,
                                        ),
                                        SizedBox(height: 14 * scale),
                                        Text(
                                          'All information submitted will be kept confidential and used solely for employment and compliance purposes in accordance with company policies and applicable laws.',
                                          style: paragraphStyle,
                                        ),
                                        SizedBox(height: 14 * scale),
                                        Text.rich(
                                          TextSpan(
                                            style: paragraphStyle,
                                            children: [
                                              const TextSpan(
                                                text: 'By tapping "',
                                              ),
                                              TextSpan(
                                                text: 'Get Started',
                                                style: paragraphStyle.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: titleColor,
                                                ),
                                              ),
                                              const TextSpan(
                                                text:
                                                    '", you confirm your understanding and consent to proceed with the application process.',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 14 * scale),
                              Container(
                                height: 1,
                                color: border.withValues(alpha: 0.28),
                              ),
                              SizedBox(height: 12 * scale),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: hasReachedEnd
                                      ? null
                                      : () {
                                          if (!scrollController.hasClients) {
                                            return;
                                          }
                                          final end = scrollController
                                              .position
                                              .maxScrollExtent;
                                          scrollController.animateTo(
                                            end,
                                            duration: const Duration(
                                              milliseconds: 420,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          );
                                        },
                                  borderRadius: BorderRadius.circular(
                                    12 * scale,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8 * scale,
                                      vertical: 6 * scale,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (!hasReachedEnd) ...[
                                          Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 22 * scale,
                                            color: bodyColor.withValues(
                                              alpha: 0.95,
                                            ),
                                            weight: 700,
                                          ),
                                          SizedBox(width: 4 * scale),
                                        ],
                                        Flexible(
                                          child: Text(
                                            hasReachedEnd
                                                ? 'Reading complete. You can continue.'
                                                : 'Scroll to read the complete notice',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: bodyColor.withValues(
                                                alpha: 0.88,
                                              ),
                                              fontSize: 13.5 * scale,
                                              height: 1.35,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 16 * scale),
                              _PrimaryButton(
                                label: 'Get Started',
                                scale: scale,
                                onTap: hasReachedEnd
                                    ? () =>
                                          Navigator.of(dialogContext).pop()
                                    : null,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return future.whenComplete(scrollController.dispose);
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.scale,
    required this.onClose,
    required this.child,
    this.expand = false,
  });

  final double scale;
  final VoidCallback onClose;
  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27 * scale),
        border: Border.all(color: AuthGlassPopup.border, width: 1.35),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AuthGlassPopup.cardTop,
            Color(0xFF132B4A),
            AuthGlassPopup.cardBottom,
          ],
          stops: [0, 0.53, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22 * scale,
          22 * scale,
          22 * scale,
          21 * scale,
        ),
        child: child,
      ),
    );

    return Stack(
      fit: expand ? StackFit.expand : StackFit.loose,
      children: [
        if (expand) Positioned.fill(child: surface) else surface,
        Positioned(
          top: 10 * scale,
          right: 10 * scale,
          child: Semantics(
            button: true,
            label: 'Close dialog',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  height: 44 * scale,
                  width: 44 * scale,
                  child: Center(
                    child: Ink(
                      width: 38 * scale,
                      height: 38 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AuthGlassPopup.closeFill.withValues(alpha: 0.86),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 21 * scale,
                        color: const Color(0xFFF1F6FF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.scale,
    required this.color,
    required this.icon,
  });

  final double scale;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64 * scale,
      height: 64 * scale,
      decoration: BoxDecoration(
        color: const Color(0xFF2E3C5A),
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(
          color: const Color(0xFF728AB1).withValues(alpha: 0.72),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 37 * scale, color: color),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.scale,
    required this.onTap,
  });

  final String label;
  final double scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15 * scale);
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          height: 53 * scale,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF2F9BFF),
                      Color(0xFF157BFC),
                      Color(0xFF065AF0),
                    ],
                    stops: [0, 0.48, 1],
                  )
                : null,
            color: enabled ? null : const Color(0xFF243652),
            border: Border.all(
              color: enabled
                  ? const Color(0xFF78B9FF).withValues(alpha: 0.58)
                  : AuthGlassPopup.border.withValues(alpha: 0.34),
              width: 0.8,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF096DFF).withValues(alpha: 0.23),
                      blurRadius: 15,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.05,
                color: enabled
                    ? Colors.white
                    : AuthGlassPopup.bodyColor.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

