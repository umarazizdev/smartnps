import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_config.dart';

class DebugEnvScreen extends StatefulWidget {
  const DebugEnvScreen({super.key});

  @override
  State<DebugEnvScreen> createState() => _DebugEnvScreenState();
}

class _DebugEnvScreenState extends State<DebugEnvScreen> {
  late final TextEditingController _apiController;
  late final TextEditingController _webController;
  String? _apiError;
  String? _webError;
  bool _saving = false;
  bool _crashlyticsBusy = false;

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController();
    _webController = TextEditingController();
    unawaited(_loadEnv());
  }

  Future<void> _loadEnv() async {
    await DebugEnvConfig.instance.ensureReady();
    if (!mounted) return;
    final env = DebugEnvConfig.instance;
    setState(() {
      _apiController.text = env.apiOrigin;
      _webController.text = env.webBaseUrl;
    });
  }

  @override
  void dispose() {
    _apiController.dispose();
    _webController.dispose();
    super.dispose();
  }

  Future<void> _enableCrashlyticsForTest() async {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  }

  Future<void> _sendTestReport() async {
    if (_crashlyticsBusy) return;
    setState(() => _crashlyticsBusy = true);
    try {
      await _enableCrashlyticsForTest();
      await FirebaseCrashlytics.instance.log('manual_crashlytics_test');
      await FirebaseCrashlytics.instance.recordError(
        Exception('Crashlytics test report from DebugEnvScreen'),
        StackTrace.current,
        reason: 'manual_test',
        fatal: true,
      );
      // Force immediate upload while the app is still alive.
      await FirebaseCrashlytics.instance.sendUnsentReports();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Test report sent. Check Firebase Crashlytics in a few minutes.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send test report: $e')),
      );
    } finally {
      if (mounted) setState(() => _crashlyticsBusy = false);
    }
  }

  Future<void> _forceTestCrash() async {
    if (_crashlyticsBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force test crash?'),
        content: const Text(
          'The app will close. Reopen it once so Crashlytics can upload '
          'the crash, then check the Firebase console.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Crash now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _crashlyticsBusy = true);
    try {
      await _enableCrashlyticsForTest();
      await FirebaseCrashlytics.instance.log('manual_force_test_crash');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      FirebaseCrashlytics.instance.crash();
    } catch (e) {
      if (!mounted) return;
      setState(() => _crashlyticsBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to force crash: $e')),
      );
    }
  }

  Future<void> _save() async {
    final apiError = DebugEnvConfig.validateBaseUrl(_apiController.text);
    final webError = DebugEnvConfig.validateBaseUrl(_webController.text);
    setState(() {
      _apiError = apiError;
      _webError = webError;
    });
    if (apiError != null || webError != null) return;

    setState(() => _saving = true);
    try {
      await DebugEnvConfig.instance.save(
        apiOrigin: _apiController.text,
        webBaseUrl: _webController.text,
      );
      if (!mounted) return;
      await _promptRestart(
        title: 'URLs saved',
        message:
            'Restart the app so API calls and WebView load the new base URLs.\n\n'
            'API calls will use: '
            '${DebugEnvConfig.instance.apiBaseUrl}\n'
            'WebView will use: ${DebugEnvConfig.instance.webBaseUrl}',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    try {
      await DebugEnvConfig.instance.resetToProduction();
      if (!mounted) return;
      setState(() {
        _apiController.text = DebugEnvConfig.defaultApiOrigin;
        _webController.text = DebugEnvConfig.defaultWebBaseUrl;
        _apiError = null;
        _webError = null;
      });
      await _promptRestart(
        title: 'Reset to production',
        message:
            'Production URLs restored. Restart the app to apply '
            'smartnps360.com again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _promptRestart({
    required String title,
    required String message,
  }) async {
    final isDark = NativeThemeController.instance.isDark;
    final colors = _DebugEnvColors.of(isDark);
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.title,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  color: colors.subtitle,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(AppConfig.cPrimary),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Close app'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: colors.subtitle,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Later'),
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldExit == true) {
      if (Platform.isAndroid) {
        SystemNavigator.pop();
      } else {
        exit(0);
      }
    }
  }

  Widget _fieldLabel(String text, _DebugEnvColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: colors.label,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required _DebugEnvColors colors,
    String? errorText,
    Widget? suffix,
  }) {
    return InputDecoration(
      errorText: errorText,
      filled: true,
      fillColor: colors.fieldBg,
      errorStyle: TextStyle(
        color: colors.error,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(AppConfig.cPrimary),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final env = DebugEnvConfig.instance;
    final isDark = NativeThemeController.instance.isDark;
    final colors = _DebugEnvColors.of(isDark);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(AppConfig.cPrimary),
        foregroundColor: Colors.white,
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Debug environment',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                if (env.hasOverride) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.warningBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.warningBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: colors.warningFg,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Override active. App is not using production URLs.',
                            style: TextStyle(
                              color: colors.warningFg,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('API base URL', colors),
                      TextField(
                        controller: _apiController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        style: TextStyle(
                          color: colors.title,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: const Color(AppConfig.cPrimary),
                        decoration: _fieldDecoration(
                          colors: colors,
                          errorText: _apiError,
                          suffix: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.badgeBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '/api',
                                style: TextStyle(
                                  color: colors.badgeFg,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _fieldLabel('WebView base URL', colors),
                      TextField(
                        controller: _webController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        style: TextStyle(
                          color: colors.title,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: const Color(AppConfig.cPrimary),
                        decoration: _fieldDecoration(
                          colors: colors,
                          errorText: _webError,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crashlytics test',
                        style: TextStyle(
                          color: colors.title,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Send a report without killing the app, or force a '
                        'real crash. Reopen after a crash so it uploads.',
                        style: TextStyle(
                          color: colors.subtitle,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton(
                          onPressed: _crashlyticsBusy ? null : _sendTestReport,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: _crashlyticsBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Send test report'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton(
                          onPressed: _crashlyticsBusy ? null : _forceTestCrash,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.error,
                            side: BorderSide(color: colors.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Force test crash'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: BoxDecoration(
                color: colors.card,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(AppConfig.cPrimary),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(
                          AppConfig.cPrimary,
                        ).withValues(alpha: 0.55),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save URLs'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _reset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(AppConfig.cPrimary),
                        side: BorderSide(color: colors.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Reset to production'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugEnvColors {
  const _DebugEnvColors({
    required this.background,
    required this.card,
    required this.cardBorder,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.fieldBg,
    required this.border,
    required this.divider,
    required this.outline,
    required this.error,
    required this.warningBg,
    required this.warningBorder,
    required this.warningFg,
    required this.badgeBg,
    required this.badgeFg,
  });

  final Color background;
  final Color card;
  final Color cardBorder;
  final Color title;
  final Color subtitle;
  final Color label;
  final Color fieldBg;
  final Color border;
  final Color divider;
  final Color outline;
  final Color error;
  final Color warningBg;
  final Color warningBorder;
  final Color warningFg;
  final Color badgeBg;
  final Color badgeFg;

  static _DebugEnvColors of(bool isDark) {
    if (isDark) {
      return _DebugEnvColors(
        background: const Color(0xFF0F1724),
        card: const Color(AppConfig.cDarkCardColor),
        cardBorder: const Color(0xFF2A3548),
        title: Colors.white,
        subtitle: Colors.white.withValues(alpha: 0.65),
        label: Colors.white.withValues(alpha: 0.75),
        fieldBg: const Color(0xFF121A27),
        border: const Color(0xFF2A3548),
        divider: const Color(0xFF243044),
        outline: const Color(0xFF3B4A63),
        error: const Color(0xFFF87171),
        warningBg: const Color(0xFF2A2212),
        warningBorder: const Color(0xFF78520F),
        warningFg: const Color(0xFFFBBF24),
        badgeBg: const Color(0xFF1E3A5F),
        badgeFg: const Color(0xFF93C5FD),
      );
    }

    return const _DebugEnvColors(
      background: Color(0xFFF5F7FB),
      card: Color(0xFFFFFFFF),
      cardBorder: Color(0xFFE8ECF2),
      title: Color(0xFF0F172A),
      subtitle: Color(0xFF667085),
      label: Color(0xFF344054),
      fieldBg: Color(0xFFFFFFFF),
      border: Color(0xFFD0D5DD),
      divider: Color(0xFFEAECF0),
      outline: Color(0xFFD0D5DD),
      error: Color(0xFFDC2626),
      warningBg: Color(0xFFFFFBEB),
      warningBorder: Color(0xFFFDE68A),
      warningFg: Color(0xFF92400E),
      badgeBg: Color(0xFFEEF2FF),
      badgeFg: Color(0xFF1D4ED8),
    );
  }
}
