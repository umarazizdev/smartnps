import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/connectivitycontroller.dart';
import 'package:smartnps360/src/screens/main_screens/auth_screen.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_screen.dart';
import 'package:smartnps360/src/screens/widgets/nointernetscreen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.splashThemeMode = ThemeMode.system});

  final ThemeMode splashThemeMode;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = 'assets/images/npslogo_navy_exact.png';

  late final AnimationController _entranceController;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  bool _navigationStarted = false;
  bool _logoSettled = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );
    _entranceController.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _logoSettled = true);
    });
    _entranceController.forward();
    _checkConnectivityAndNavigate();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivityAndNavigate() async {
    final connectivityController = Get.find<ConnectivityController>();

    await connectivityController.checkConnection();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (!connectivityController.isConnected.value) {
      Get.off(
        () => NoInternetScreen(
          onRetry: () async {
            await connectivityController.checkConnection();
          },
          onConnected: _navigateToNextScreen,
        ),
      );
    } else {
      await _navigateToNextScreen();
    }
  }

  Future<void> _navigateToNextScreen() async {
    if (_navigationStarted) return;
    _navigationStarted = true;
    try {
      final loggedIn = await NativeAuthSession.instance.isLoggedIn();
      if (loggedIn) {
        Get.offAll(const NewMainScreen());
      } else {
        Get.offAll(const AuthScreen());
      }
    } catch (_) {
      _navigationStarted = false;
      rethrow;
    }
  }

  bool _isDarkTheme(BuildContext context) {
    switch (widget.splashThemeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  double _screenScale(Size size) {
    final widthScale = size.width / 390;
    final heightScale = size.height / 844;
    return ((widthScale * 0.65) + (heightScale * 0.35)).clamp(0.78, 1.28);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final scale = _screenScale(mediaSize);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor:
            dark ? const Color(0xFF0B1B2F) : const Color(0xFFF8FAFC),
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SplashBackgroundPainter(dark: dark),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final widthScale = constraints.maxWidth / 390;
                  final heightScale = constraints.maxHeight / 844;
                  final layoutScale =
                      ((widthScale * 0.65) + (heightScale * 0.35))
                          .clamp(0.78, 1.28);
                  final s = (scale + layoutScale) / 2;
                  final logoSize = (164 * s)
                      .clamp(128.0, constraints.maxWidth * 0.46)
                      .toDouble();

                  final content = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: 'National Protective Service',
                        image: true,
                        child: Image.asset(
                          _logoAsset,
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      SizedBox(height: 20 * s),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 30 * s,
                            letterSpacing: -0.8 * s,
                            fontWeight: FontWeight.w800,
                            color: dark
                                ? const Color(0xFFF1F5FC)
                                : const Color(0xFF102541),
                          ),
                          children: [
                            const TextSpan(text: 'SmartNPS'),
                            TextSpan(
                              text: '360',
                              style: TextStyle(
                                color: dark
                                    ? const Color(0xFF4B8BFF)
                                    : const Color(0xFF0866FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 8 * s),
                        Text(
                        'Your Duty Companion',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2 * s,
                          color: dark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF778397),
                        ),
                      ),
                    ],
                  );

                  final child = reduceMotion || _logoSettled
                      ? content
                      : FadeTransition(
                          opacity: _logoOpacity,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: content,
                          ),
                        );

                  return Center(child: child);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashBackgroundPainter extends CustomPainter {
  const _SplashBackgroundPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [Color(0xFF14253D), Color(0xFF0B1B2F), Color(0xFF041221)]
            : const [Color(0xFFF8FAFC), Color(0xFFF1F5FC), Color(0xFFE3EDFC)],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, base);
  }

  @override
  bool shouldRepaint(covariant _SplashBackgroundPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
