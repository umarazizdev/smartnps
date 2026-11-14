import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/forgot_password_controller.dart';

class _NpsAuthPalette {
  static const background = Color(0xFF0B192D);
  static const backgroundTop = Color(0xFF10233C);
  static const backgroundBottom = Color(0xFF071222);
  static const surface = Color(0xFF172E4C);
  static const surfaceBorder = Color(0xFF496B94);
  static const focusedBorder = Color(0xFF76B5FF);
  static const heading = Color(0xFFF8FAFF);
  static const body = Color(0xFFCAD5E7);
  static const secondary = Color(0xFFB6C8E0);
  static const hint = Color(0xFFA1B3CD);
  static const inputIcon = Color(0xFFA3B8D2);
  static const blueTop = Color(0xFF2F9BFF);
  static const blueMid = Color(0xFF157BFC);
  static const blueBottom = Color(0xFF065AF0);
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  static const _bgMid = _NpsAuthPalette.background;
  static const _titleColor = _NpsAuthPalette.heading;
  static const _subtitleColor = _NpsAuthPalette.body;
  static const _formSubtitleColor = _NpsAuthPalette.secondary;

  static const _systemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  late final ForgotPasswordController controller;
  late final AnimationController _enterController;
  late final AnimationController _sealController;
  late final AnimationController _logoFlipController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<Offset> _subtitleSlide;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(_systemUi);
    if (Get.isRegistered<ForgotPasswordController>()) {
      Get.delete<ForgotPasswordController>(force: true);
    }
    controller = Get.put(ForgotPasswordController());

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _sealController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 45),
    )..repeat();

    _logoFlipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    final enterCurve = CurvedAnimation(
      parent: _enterController,
      curve: const Cubic(0.22, 1, 0.36, 1),
    );
    _logoScale = Tween<double>(begin: 0.88, end: 1).animate(
      CurvedAnimation(
        parent: _enterController,
        curve: const Interval(0.08, 0.55, curve: Cubic(0.22, 1, 0.36, 1)),
      ),
    );

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _enterController,
        curve: const Interval(0.02, 0.52, curve: Curves.easeOut),
      ),
    );
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: enterCurve, curve: const Interval(0.18, 0.7)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: enterCurve, curve: const Interval(0.18, 0.7)),
        );
    _subtitleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: enterCurve, curve: const Interval(0.28, 0.78)),
    );
    _subtitleSlide =
        Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(
          CurvedAnimation(
            parent: enterCurve,
            curve: const Interval(0.28, 0.78),
          ),
        );
    _formFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: enterCurve, curve: const Interval(0.48, 1)),
    );
    _formSlide = Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: enterCurve, curve: const Interval(0.48, 1)),
        );

    _enterController.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      if (WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations) {
        return;
      }
      _logoFlipController.forward(from: 0);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startPageOpenAfterRoute();
    });
  }

  void _startPageOpenAfterRoute() {
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _playPageOpenAnimation();
      return;
    }

    void listener(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listener);
      if (mounted) {
        _playPageOpenAnimation();
      }
    }

    animation.addStatusListener(listener);
  }

  void _playPageOpenAnimation() {
    if (!mounted) return;
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _enterController.value = 1;
      _logoFlipController.value = 1;
      return;
    }
    _logoFlipController.stop();
    _logoFlipController.reset();
    _enterController
      ..stop()
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    _sealController.dispose();
    _logoFlipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewSize = media.size;
    final width = viewSize.width;
    final height = viewSize.height;
    final safe = media.padding;
    final viewKeyboard =
        View.of(context).viewInsets.bottom / media.devicePixelRatio;
    final keyboard = math.max(media.viewInsets.bottom, viewKeyboard);
    final baseScale = (width / 375).clamp(0.96, 1.24);
    final platformBoost = defaultTargetPlatform == TargetPlatform.iOS
        ? 1.06
        : 1.03;
    final scale = (baseScale * platformBoost).clamp(0.98, 1.30);
    final sidePad = (width * 0.06).clamp(16.0, 28.0);
    final topGap = (height * 0.025).clamp(10.0, 20.0);
    final topPad = math.max(
      safe.top + 4.0,
      math.max(safe.top, 12.0) + (16.0 * scale) + topGap - 20.0,
    );
    final bottomSafe = math.max(safe.bottom, 12.0);
    final imeOpen = keyboard > 40;
    final keyboardOpen = imeOpen;
    final focusedPad = imeOpen ? keyboard : 0.0;
    final bottomPad = focusedPad > 0
        ? focusedPad + (8.0 * scale)
        : bottomSafe + (16.0 * scale);
    final contentTopPad = keyboardOpen
        ? math.max(
            safe.top + 4.0,
            math.max(safe.top, 12.0) + (8.0 * scale) - 20.0,
          )
        : topPad;
    final sealSize = math.min(400.0, width * 0.95);
    final logoSize = (102.0 * scale).clamp(90.0, 124.0);

    final tallScreenBrandOffset = keyboardOpen
        ? 0.0
        : math.min(44.0, math.max(0.0, (height - 700.0) * 0.20));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUi,
      child: Scaffold(
        backgroundColor: _bgMid,
        resizeToAvoidBottomInset: false,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _ForgotAuthBackground()),
            Positioned(
              left: (viewSize.width - sealSize) / 2,
              top: (viewSize.height - sealSize) / 2,
              width: sealSize,
              height: sealSize,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _sealController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _sealController.value * 2 * math.pi,
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                  child: Opacity(
                    opacity: 0.03,
                    child: Image.asset(
                      'assets/images/nps_seal.webp',
                      width: sealSize,
                      height: sealSize,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, error, stackTrace) => Image.asset(
                        'assets/images/npslogo.png',
                        width: sealSize,
                        height: sealSize,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.min(430, width)),
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    left: sidePad,
                    right: sidePad,
                    top: contentTopPad,
                    bottom: bottomPad,
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          0,
                          height - contentTopPad - bottomPad,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (!keyboardOpen) ...[
                            SizedBox(height: tallScreenBrandOffset),
                            _buildBrand(logoSize: logoSize, scale: scale),
                            SizedBox(height: 36 * scale),
                          ],
                          FadeTransition(
                            opacity: _formFade,
                            child: SlideTransition(
                              position: _formSlide,
                              child: Obx(
                                () => controller.isSent.value
                                    ? _buildSuccess(scale)
                                    : _buildForm(scale),
                              ),
                            ),
                          ),
                          SizedBox(height: keyboardOpen ? 12 * scale : 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand({required double logoSize, required double scale}) {
    return Column(
      children: [
        FadeTransition(
          opacity: _logoFade,
          child: ScaleTransition(
            scale: _logoScale,
            child: AnimatedBuilder(
              animation: _logoFlipController,
              child: Image.asset(
                'assets/images/nps_seal.webp',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, error, stackTrace) => Image.asset(
                  'assets/images/npslogo.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              builder: (context, seal) {
                final progress = Curves.easeInOutCubic.transform(
                  _logoFlipController.value,
                );
                final angle = 2 * math.pi * progress;
                final showBack = math.cos(angle) < 0;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(angle),

                  child: showBack
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(math.pi),
                          child: seal,
                        )
                      : seal,
                );
              },
            ),
          ),
        ),
        SizedBox(height: 28 * scale),
        FadeTransition(
          opacity: _titleFade,
          child: SlideTransition(
            position: _titleSlide,
            child: Text(
              'National Protective Service',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23 * scale,
                fontWeight: FontWeight.w700,
                color: _titleColor,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        SizedBox(height: 12 * scale),
        FadeTransition(
          opacity: _subtitleFade,
          child: SlideTransition(
            position: _subtitleSlide,
            child: Text(
              'Digital registration and application portal',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w400,
                color: _subtitleColor,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reset Password',
          style: TextStyle(
            fontSize: 25 * scale,
            fontWeight: FontWeight.w700,
            color: _titleColor,
            letterSpacing: -0.2,
            height: 1.2,
          ),
        ),
        SizedBox(height: 12 * scale),
        Text(
          'Enter your officer number to receive an OTP.',
          style: TextStyle(
            color: _formSubtitleColor,
            height: 1.5,
            fontSize: 15 * scale,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: 24 * scale),
        _ForgotInputField(
          controller: controller.officerNumberController,
          hintText: 'Officer Number',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.text,
          scale: scale,
          onSubmitted: (_) => controller.submit(),
        ),
        SizedBox(height: 24 * scale),
        Obx(
          () => _ForgotPrimaryButton(
            label: 'Send OTP',
            loading: controller.isLoading.value,
            scale: scale,
            onPressed: controller.isLoading.value ? null : controller.submit,
          ),
        ),
        SizedBox(height: 22 * scale),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => Get.back(),
            style: TextButton.styleFrom(
              foregroundColor: _NpsAuthPalette.secondary,
              padding: EdgeInsets.symmetric(
                horizontal: 4 * scale,
                vertical: 4 * scale,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Back to login',
              style: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OTP sent',
          style: TextStyle(
            fontSize: 25 * scale,
            fontWeight: FontWeight.w700,
            color: _titleColor,
            letterSpacing: -0.2,
            height: 1.2,
          ),
        ),
        SizedBox(height: 8 * scale),
        Text(
          controller.message.value.isNotEmpty
              ? controller.message.value
              : 'OTP sent. Check your messages to continue.',
          style: TextStyle(
            color: _formSubtitleColor,
            height: 1.5,
            fontSize: 15 * scale,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: 12 * scale),
        Text(
          controller.officerNumberController.text.trim(),
          style: TextStyle(
            fontSize: 16 * scale,
            height: 1.4,
            color: _NpsAuthPalette.heading,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 22 * scale),
        _ForgotPrimaryButton(
          label: 'Back to login',
          scale: scale,
          onPressed: () => Get.back(),
        ),
        SizedBox(height: 14 * scale),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: controller.resetForm,
            style: TextButton.styleFrom(
              foregroundColor: _NpsAuthPalette.secondary,
              padding: EdgeInsets.symmetric(
                horizontal: 4 * scale,
                vertical: 4 * scale,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Try another number',
              style: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ForgotAuthBackground extends StatelessWidget {
  const _ForgotAuthBackground();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _ForgotAuthBackgroundPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _ForgotAuthBackgroundPainter extends CustomPainter {
  const _ForgotAuthBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _NpsAuthPalette.backgroundTop,
          _NpsAuthPalette.background,
          _NpsAuthPalette.backgroundBottom,
        ],
        stops: [0.0, 0.4, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final navyGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.55, -1.15),
        radius: 1.35,
        colors: [
          const Color(0xFF315478).withValues(alpha: 0.38),
          const Color(0xFF315478).withValues(alpha: 0.15),
          const Color(0xFF315478).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.28, 0.62],
      ).createShader(rect);
    canvas.drawRect(rect, navyGlow);

    final goldGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-1.0, -1.0),
        radius: 0.85,
        colors: [
          const Color(0xFFC8A050).withValues(alpha: 0.035),
          const Color(0xFFC8A050).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.38],
      ).createShader(rect);
    canvas.drawRect(rect, goldGlow);

    final blueGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.70),
        radius: 1.05,
        colors: [
          const Color(0xFF157BFC).withValues(alpha: 0.055),
          const Color(0xFF157BFC).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.52],
      ).createShader(rect);
    canvas.drawRect(rect, blueGlow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ForgotInputField extends StatefulWidget {
  const _ForgotInputField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.scale,
    this.keyboardType = TextInputType.text,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final double scale;
  final TextInputType keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_ForgotInputField> createState() => _ForgotInputFieldState();
}

class _ForgotInputFieldState extends State<_ForgotInputField> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 4 * scale,
      ),
      decoration: BoxDecoration(
        color: _NpsAuthPalette.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: _focused
              ? _NpsAuthPalette.focusedBorder
              : _NpsAuthPalette.surfaceBorder.withValues(alpha: 0.62),
          width: _focused ? 1.3 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: _NpsAuthPalette.blueMid.withValues(alpha: 0.13),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            widget.icon,
            size: 21 * scale,
            color: _focused
                ? _NpsAuthPalette.focusedBorder
                : _NpsAuthPalette.inputIcon,
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: TextField(
              focusNode: _focusNode,
              controller: widget.controller,
              keyboardType: widget.keyboardType,
              textInputAction: TextInputAction.send,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17 * scale,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _NpsAuthPalette.focusedBorder,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: _NpsAuthPalette.hint,
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForgotPrimaryButton extends StatelessWidget {
  const _ForgotPrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.scale = 1,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 15.5 * scale,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.05,
      height: 1.25,
      color: Colors.white,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: 18 * scale,
            vertical: 14 * scale,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: loading
                  ? const [
                      Color(0xFF64748B),
                      Color(0xFF475569),
                      Color(0xFF334155),
                    ]
                  : const [
                      _NpsAuthPalette.blueTop,
                      _NpsAuthPalette.blueMid,
                      _NpsAuthPalette.blueBottom,
                    ],
            ),
            border: Border.all(
              color: _NpsAuthPalette.focusedBorder.withValues(alpha: 0.45),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _NpsAuthPalette.blueMid.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (54 * scale) - (28 * scale)),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 18 * scale,
                      height: 18 * scale,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: labelStyle,
                      maxLines: 2,
                      softWrap: true,
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
