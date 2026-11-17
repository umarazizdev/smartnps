import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:smartnps360/src/screens/controllers/auth_controller.dart';
import 'package:smartnps360/src/screens/controllers/passwordvisibiltycontroller.dart';
import 'package:smartnps360/src/screens/main_screens/forgot_password_screen.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';

class _NpsAuthPalette {
  static const background = Color(0xFF0B192D);
  static const backgroundTop = Color(0xFF10233C);
  static const backgroundBottom = Color(0xFF071222);
  static const surface = Color(0xFF172E4C);
  static const surfaceBorder = Color(0xFF496B94);
  static const focusedBorder = Color(0xFF76B5FF);
  static const tabTrack = Color(0xFF122943);
  static const heading = Color(0xFFF8FAFF);
  static const body = Color(0xFFCAD5E7);
  static const secondary = Color(0xFFB6C8E0);
  static const hint = Color(0xFFA1B3CD);
  static const inputIcon = Color(0xFFA3B8D2);
  static const blueTop = Color(0xFF2F9BFF);
  static const blueMid = Color(0xFF157BFC);
  static const blueBottom = Color(0xFF065AF0);
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _bgMid = _NpsAuthPalette.background;
  static const _blue = _NpsAuthPalette.blueMid;
  static const _tabTrack = _NpsAuthPalette.tabTrack;
  static const _cornflower = _NpsAuthPalette.surfaceBorder;
  static const _titleColor = _NpsAuthPalette.heading;
  static const _subtitleColor = _NpsAuthPalette.body;
  static const _formSubtitleColor = _NpsAuthPalette.secondary;

  late final AuthController authController;
  bool _initialized = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _formKey = GlobalKey();
  BuildContext? _focusedFieldContext;
  bool _imeWasVisible = false;

  late final AnimationController _enterController;
  late final AnimationController _sealController;
  late final AnimationController _logoFlipController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<Offset> _subtitleSlide;
  late final Animation<double> _tabsFade;
  late final Animation<Offset> _tabsSlide;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(_systemUi);
    if (Get.isRegistered<AuthController>()) {
      Get.delete<AuthController>(force: true);
    }
    authController = Get.put(AuthController(), permanent: false);

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
    _tabsFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: enterCurve, curve: const Interval(0.38, 0.88)),
    );
    _tabsSlide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: enterCurve,
            curve: const Interval(0.38, 0.88),
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
    _enterController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialized) return;
      _initialized = true;
      _bootstrap();
    });
  }

  void _bootstrap() {
    final args = Get.arguments;
    final sessionExpired = args is Map && args['sessionExpired'] == true;
    final skipAutoLogin =
        sessionExpired || (args is Map && args['skipAutoLogin'] == true);
    if (sessionExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        authController.showMessagePopup(
          'Session expired. Please sign in again.',
          title: 'Session Expired',
        );
      });
    }
    authController.initializeApp(skipAutoLogin: skipAutoLogin);
  }

  void _replayLogoFlip() {
    if (!mounted) return;
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _logoFlipController.value = 1;
      return;
    }
    if (_enterController.status != AnimationStatus.completed) {
      return;
    }
    _logoFlipController.forward(from: 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _enterController.dispose();
    _sealController.dispose();
    _logoFlipController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 40;
    if (_imeWasVisible && !imeVisible) {
      FocusManager.instance.primaryFocus?.unfocus();
      authController.updateInputFocusState(false);
      authController.updatePasswordFocusState(false);
      _focusedFieldContext = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    } else if (!_imeWasVisible && imeVisible) {
      _scheduleFormReveal(delayMs: 160);
    } else if (imeVisible &&
        (authController.isInputFocused.value ||
            authController.isPasswordFieldFocused.value)) {
      _scheduleFormReveal(delayMs: 160);
    }
    _imeWasVisible = imeVisible;
  }

  void _scheduleFormReveal({int delayMs = 100}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        _revealFocusedForm();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _revealFocusedForm();
        });
      });
    });
  }

  void _revealFocusedForm() {
    final ctx = _focusedFieldContext;
    if (ctx == null || !ctx.mounted) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _onFieldFocusChanged(bool hasFocus, [BuildContext? fieldContext]) {
    authController.updateInputFocusState(hasFocus);
    if (hasFocus) {
      _focusedFieldContext = fieldContext;
      _scheduleFormReveal();
    } else if (_focusedFieldContext == fieldContext) {
      _focusedFieldContext = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewSize = media.size;
    final safe = media.padding;
    final systemKeyboard = media.viewInsets.bottom;
    final width = viewSize.width;
    final height = viewSize.height;
    final baseScale = (width / 375).clamp(0.96, 1.24);
    final platformBoost = defaultTargetPlatform == TargetPlatform.iOS
        ? 1.06
        : 1.03;
    final scale = (baseScale * platformBoost).clamp(0.98, 1.30);
    final sealSize = math.min(400.0, width * 0.95);
    final sidePad = (width * 0.06).clamp(16.0, 28.0);
    final topGap = (height * 0.025).clamp(10.0, 20.0);
    final topPad = math.max(
      safe.top + 4.0,
      math.max(safe.top, 12.0) + (16.0 * scale) + topGap - 20.0,
    );
    final tallScreen = height >= 780;
    final bottomInset = math.max(safe.bottom, media.viewPadding.bottom);
    final bottomSafe = math.max(bottomInset, 12.0);
    final logoSize = (102.0 * scale).clamp(90.0, 124.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUi,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: _bgMid,
        extendBody: false,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _OfficerAuthBackground()),
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
                child: Obx(() {
                  authController.isInputFocused.value;
                  authController.isPasswordFieldFocused.value;
                  final imeOpen = systemKeyboard > 40;
                  final keyboardOpen = imeOpen;
                  final bottomPad = imeOpen
                      ? systemKeyboard + (8.0 * scale)
                      : bottomSafe + ((tallScreen ? 10.0 : 16.0) * scale);
                  final contentTopPad = keyboardOpen
                      ? math.max(safe.top + 8.0, 16.0 * scale)
                      : topPad;
                  return AnimatedPadding(
                    duration: Duration(milliseconds: imeOpen ? 0 : 180),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(
                      left: sidePad,
                      right: sidePad,
                      top: contentTopPad,
                      bottom: bottomPad,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final balanceTall = tallScreen && !keyboardOpen;
                        return SingleChildScrollView(
                          controller: _scrollController,
                          physics: const ClampingScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Column(
                              mainAxisAlignment: balanceTall
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              children: [
                                if (!keyboardOpen) ...[
                                  _buildBrand(logoSize: logoSize, scale: scale),
                                  SizedBox(height: 28 * scale),
                                  FadeTransition(
                                    opacity: _tabsFade,
                                    child: SlideTransition(
                                      position: _tabsSlide,
                                      child: _buildAuthTabs(scale: scale),
                                    ),
                                  ),
                                  SizedBox(height: 28 * scale),
                                ],
                                KeyedSubtree(
                                  key: _formKey,
                                  child: FadeTransition(
                                    opacity: _formFade,
                                    child: SlideTransition(
                                      position: _formSlide,
                                      child: Obx(
                                        () => authController.isRegisterTab.value
                                            ? _buildRegisterForm(
                                                context,
                                                scale: scale,
                                              )
                                            : _buildLoginForm(
                                                context,
                                                scale: scale,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: keyboardOpen
                                      ? 16 * scale
                                      : (tallScreen ? 8.0 : 14.0) * scale,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
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
        SizedBox(height: 20 * scale),
        FadeTransition(
          opacity: _titleFade,
          child: SlideTransition(
            position: _titleSlide,
            child: Text(
              'National Protective Service',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24 * scale,
                fontWeight: FontWeight.w700,
                color: _titleColor,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        SizedBox(height: 4 * scale),
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

  Widget _buildAuthTabs({required double scale}) {
    return Obx(() {
      final isRegister = authController.isRegisterTab.value;
      return Container(
        padding: EdgeInsets.all(3 * scale),
        decoration: BoxDecoration(
          color: _tabTrack,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cornflower.withValues(alpha: 0.55)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = 3 * scale;
            final pillWidth = (constraints.maxWidth - inset * 2) / 2;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: const Cubic(0.22, 1, 0.36, 1),
                  top: 0,
                  bottom: 0,
                  left: isRegister ? pillWidth + inset : inset,
                  child: Container(
                    width: pillWidth,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _NpsAuthPalette.blueTop,
                          _NpsAuthPalette.blueMid,
                          _NpsAuthPalette.blueBottom,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _blue.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _tabButton(
                        label: 'Login',
                        active: !isRegister,
                        scale: scale,
                        onTap: () => authController.switchTab(false),
                      ),
                    ),
                    Expanded(
                      child: _tabButton(
                        label: 'Register',
                        active: isRegister,
                        scale: scale,
                        onTap: () => authController.switchTab(true),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    });
  }

  Widget _tabButton({
    required String label,
    required bool active,
    required double scale,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48 * scale,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : _NpsAuthPalette.secondary,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, {required double scale}) {
    return Form(
      key: authController.loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome Back',
            style: TextStyle(
              fontSize: 27 * scale,
              fontWeight: FontWeight.w700,
              color: _titleColor,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
          SizedBox(height: 6 * scale),
          Text(
            'Sign in to continue your application.',
            style: TextStyle(
              color: _formSubtitleColor,
              height: 1.55,
              fontSize: 15 * scale,
            ),
          ),
          SizedBox(height: 24 * scale),
          _OfficerAuthField(
            controller: authController.loginEmailController,
            hintText: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            scale: scale,
            onFocusChanged: (hasFocus, ctx) =>
                _onFieldFocusChanged(hasFocus, ctx),
          ),
          SizedBox(height: 16 * scale),
          _OfficerAuthPasswordField(
            controller: authController.loginPasswordController,
            hintText: 'Password',
            controllerTag: 'login_password',
            onFocusChanged: (hasFocus, ctx) {
              authController.updatePasswordFocusState(hasFocus);
              _onFieldFocusChanged(hasFocus, ctx);
            },
            scale: scale,
          ),
          SizedBox(height: 12 * scale),
          Obx(
            () => Row(
              children: [
                SizedBox(
                  width: 22 * scale,
                  height: 22 * scale,
                  child: Checkbox(
                    value: authController.rememberMe.value,
                    onChanged: (value) {
                      authController.setRememberMe(value ?? false);
                    },
                    activeColor: _NpsAuthPalette.blueMid,
                    checkColor: Colors.white,
                    side: BorderSide(
                      color: _NpsAuthPalette.secondary,
                      width: 1.4,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                SizedBox(width: 8 * scale),
                Expanded(
                  child: Text(
                    'Remember me',
                    style: TextStyle(
                      fontSize: 14.5 * scale,
                      color: _NpsAuthPalette.body,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Get.to(
                      () => const ForgotPasswordScreen(),
                      transition: Transition.cupertino,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                    )?.then((_) {
                      if (!mounted) return;
                      _replayLogoFlip();
                    });
                  },
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
                    'Forgot password?',
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24 * scale),
          Obx(
            () => _OfficerPrimaryButton(
              label: 'Login and continue',
              loading: authController.isLoading.value,
              scale: scale,
              onPressed: authController.isLoading.value
                  ? null
                  : authController.handleLogin,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(BuildContext context, {required double scale}) {
    final isCompact = MediaQuery.sizeOf(context).width < 560;

    return Form(
      key: authController.registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Your Account',
            style: TextStyle(
              fontSize: 27 * scale,
              fontWeight: FontWeight.w700,
              color: _titleColor,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
          SizedBox(height: 6 * scale),
          Text(
            'Create an account to save your application and continue later on this device.',
            style: TextStyle(
              color: _formSubtitleColor,
              height: 1.55,
              fontSize: 15 * scale,
            ),
          ),
          SizedBox(height: 24 * scale),
          _buildFieldPair(
            isCompact: isCompact,
            scale: scale,
            first: _OfficerAuthField(
              controller: authController.regFirstNameController,
              hintText: 'First name',
              icon: Icons.person_outline,
              scale: scale,
              onFocusChanged: _onFieldFocusChanged,
            ),
            second: _OfficerAuthField(
              controller: authController.regLastNameController,
              hintText: 'Last name',
              icon: Icons.person_outline,
              scale: scale,
              onFocusChanged: _onFieldFocusChanged,
            ),
          ),
          SizedBox(height: 16 * scale),
          _OfficerAuthField(
            controller: authController.regEmailController,
            hintText: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            scale: scale,
            onFocusChanged: _onFieldFocusChanged,
          ),
          SizedBox(height: 16 * scale),
          _buildFieldPair(
            isCompact: isCompact,
            scale: scale,
            first: _OfficerAuthField(
              controller: authController.regPhoneController,
              hintText: 'Phone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              scale: scale,
              onFocusChanged: _onFieldFocusChanged,
            ),
            second: _buildDateField(
              context,
              controller: authController.regDobController,
              scale: scale,
            ),
          ),
          SizedBox(height: 16 * scale),
          _buildPasswordPair(isCompact: isCompact, scale: scale),
          SizedBox(height: 24 * scale),
          Obx(
            () => _OfficerPrimaryButton(
              label: 'Create account and start application',
              loading: authController.isLoading.value,
              scale: scale,
              onPressed: authController.isLoading.value
                  ? null
                  : authController.handleRegister,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordPair({required bool isCompact, required double scale}) {
    final createField = _OfficerAuthPasswordField(
      controller: authController.regPasswordController,
      hintText: 'Create password',
      controllerTag: 'create_password',
      onFocusChanged: (hasFocus, ctx) {
        authController.updatePasswordFocusState(hasFocus);
        _onFieldFocusChanged(hasFocus, ctx);
      },
      scale: scale,
    );
    final confirmField = _OfficerAuthPasswordField(
      controller: authController.regPassword2Controller,
      hintText: 'Confirm password',
      controllerTag: 'confirm_password',
      onFocusChanged: (hasFocus, ctx) {
        authController.updatePasswordFocusState(hasFocus);
        _onFieldFocusChanged(hasFocus, ctx);
      },
      scale: scale,
    );
    if (isCompact) {
      return Column(
        children: [
          createField,
          SizedBox(height: 16 * scale),
          confirmField,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: createField),
        SizedBox(width: 14 * scale),
        Expanded(child: confirmField),
      ],
    );
  }

  Widget _buildFieldPair({
    required bool isCompact,
    required double scale,
    required Widget first,
    required Widget second,
  }) {
    if (isCompact) {
      return Column(
        children: [
          first,
          SizedBox(height: 16 * scale),
          second,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        SizedBox(width: 14 * scale),
        Expanded(child: second),
      ],
    );
  }

  Widget _buildDateField(
    BuildContext context, {
    required TextEditingController controller,
    required double scale,
  }) {
    return GestureDetector(
      onTap: () => _pickDate(context, controller),
      child: AbsorbPointer(
        child: _OfficerAuthField(
          controller: controller,
          hintText: 'Date of birth',
          icon: Icons.date_range_outlined,
          keyboardType: TextInputType.none,
          scale: scale,
        ),
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final now = sfNow();
    final minDate = DateTime(1900);
    final defaultDate = DateTime(1990);

    DateTime initialDate = defaultDate;
    if (controller.text.trim().isNotEmpty) {
      try {
        initialDate = DateFormat('MM/dd/yyyy').parse(controller.text.trim());
      } catch (_) {
        initialDate = defaultDate;
      }
    }
    if (initialDate.isBefore(minDate)) initialDate = minDate;
    if (initialDate.isAfter(now)) initialDate = now;

    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    if (isIOS) {
      DateTime tempPicked = initialDate;
      final DateTime? pickedDate = await showCupertinoModalPopup<DateTime>(
        context: context,
        builder: (context) {
          return Container(
            height: 320,
            decoration: BoxDecoration(
              color: _NpsAuthPalette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: _NpsAuthPalette.secondary),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context, tempPicked),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        brightness: Brightness.dark,
                        primaryColor: _NpsAuthPalette.blueMid,
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        initialDateTime: initialDate,
                        minimumDate: minDate,
                        maximumDate: now,
                        onDateTimeChanged: (value) => tempPicked = value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (pickedDate != null) {
        controller.text = DateFormat('MM/dd/yyyy').format(pickedDate);
      }
      return;
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: minDate,
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _blue,
              onPrimary: Colors.white,
              surface: _bgMid,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate != null) {
      controller.text = DateFormat('MM/dd/yyyy').format(pickedDate);
    }
  }
}

class _OfficerAuthBackground extends StatelessWidget {
  const _OfficerAuthBackground();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _OfficerAuthBackgroundPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _OfficerAuthBackgroundPainter extends CustomPainter {
  const _OfficerAuthBackgroundPainter();

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

class _OfficerPrimaryButton extends StatelessWidget {
  const _OfficerPrimaryButton({
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

class _OfficerAuthField extends StatefulWidget {
  const _OfficerAuthField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.scale = 1,
    this.onFocusChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final double scale;
  final void Function(bool hasFocus, BuildContext context)? onFocusChanged;

  @override
  State<_OfficerAuthField> createState() => _OfficerAuthFieldState();
}

class _OfficerAuthFieldState extends State<_OfficerAuthField> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    final hasFocus = _focusNode.hasFocus;
    if (_focused != hasFocus) {
      setState(() => _focused = hasFocus);
      widget.onFocusChanged?.call(hasFocus, context);
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
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: _NpsAuthPalette.surface,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
              ),
              child: TextField(
                focusNode: _focusNode,
                controller: widget.controller,
                keyboardType: widget.keyboardType,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: _NpsAuthPalette.focusedBorder,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: true,
                  fillColor: _NpsAuthPalette.surface,
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: _NpsAuthPalette.hint,
                    fontSize: 17 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficerAuthPasswordField extends StatefulWidget {
  const _OfficerAuthPasswordField({
    required this.controller,
    required this.hintText,
    required this.controllerTag,
    this.onFocusChanged,
    this.scale = 1,
  });

  final TextEditingController controller;
  final String hintText;
  final String controllerTag;
  final void Function(bool hasFocus, BuildContext context)? onFocusChanged;
  final double scale;

  @override
  State<_OfficerAuthPasswordField> createState() =>
      _OfficerAuthPasswordFieldState();
}

class _OfficerAuthPasswordFieldState extends State<_OfficerAuthPasswordField> {
  late final FocusNode _focusNode;
  late final PasswordVisibilityController _visibility;
  bool _ownsController = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocus);
    if (Get.isRegistered<PasswordVisibilityController>(
      tag: widget.controllerTag,
    )) {
      _visibility = Get.find<PasswordVisibilityController>(
        tag: widget.controllerTag,
      );
    } else {
      _visibility = Get.put(
        PasswordVisibilityController(),
        tag: widget.controllerTag,
      );
      _ownsController = true;
    }
  }

  void _onFocus() {
    final hasFocus = _focusNode.hasFocus;
    if (_focused != hasFocus) {
      setState(() => _focused = hasFocus);
      widget.onFocusChanged?.call(hasFocus, context);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    if (_ownsController &&
        Get.isRegistered<PasswordVisibilityController>(
          tag: widget.controllerTag,
        )) {
      Get.delete<PasswordVisibilityController>(tag: widget.controllerTag);
    }
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
      child: Obx(
        () => Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 21 * scale,
              color: _focused
                  ? _NpsAuthPalette.focusedBorder
                  : _NpsAuthPalette.inputIcon,
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: const InputDecorationTheme(
                    filled: true,
                    fillColor: _NpsAuthPalette.surface,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
                child: TextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  obscureText: !_visibility.isVisible.value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: _NpsAuthPalette.focusedBorder,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: true,
                    fillColor: _NpsAuthPalette.surface,
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      color: _NpsAuthPalette.hint,
                      fontSize: 17 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _visibility.toggleVisibility,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _visibility.isVisible.value
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 21 * scale,
                color: _focused
                    ? _NpsAuthPalette.focusedBorder
                    : _NpsAuthPalette.inputIcon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
