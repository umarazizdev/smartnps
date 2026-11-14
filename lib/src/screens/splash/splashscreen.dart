import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/connectivitycontroller.dart';
import 'package:smartnps360/src/screens/main_screens/auth_screen.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_screen.dart';
import 'package:smartnps360/src/screens/widgets/nointernetscreen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.splashThemeMode = ThemeMode.dark});

  final ThemeMode splashThemeMode;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = 'assets/images/npslogo.png';

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
      duration: const Duration(milliseconds: 800),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOut),
      ),
    );
    _logoScale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
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

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: dark
            ? const Color(0xFF0B192D)
            : const Color(0xFFF4F8FD),
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
                  final logoSize = constraints.maxWidth * 0.7;

                  final logo = Semantics(
                    label: 'National Protective Service',
                    image: true,
                    child: Image.asset(
                      _logoAsset,
                      width: logoSize,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  );

                  return Center(
                    child: reduceMotion || _logoSettled
                        ? logo
                        : FadeTransition(
                            opacity: _logoOpacity,
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: logo,
                            ),
                          ),
                  );
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
            ? const [Color(0xFF10233C), Color(0xFF0B192D), Color(0xFF071222)]
            : const [Color(0xFFF9FBFF), Color(0xFFF4F8FD), Color(0xFFEBF2FB)],
        stops: const [0.0, 0.40, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    if (dark) {
      final subtleTopTint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -1.15),
          radius: 1.35,
          colors: [
            const Color(0xFF315478).withValues(alpha: 0.25),
            const Color(0xFF315478).withValues(alpha: 0.07),
            Colors.transparent,
          ],
          stops: const [0.0, 0.28, 0.62],
        ).createShader(rect);
      canvas.drawRect(rect, subtleTopTint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashBackgroundPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
