import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_config.dart';
import 'debug_env_theme.dart';

/// Override API and WebView base URLs for local / staging hosts.
class DebugEnvUrlsScreen extends StatefulWidget {
  const DebugEnvUrlsScreen({super.key});

  @override
  State<DebugEnvUrlsScreen> createState() => _DebugEnvUrlsScreenState();
}

class _DebugEnvUrlsScreenState extends State<DebugEnvUrlsScreen> {
  late final TextEditingController _apiController;
  late final TextEditingController _webController;
  String? _apiError;
  String? _webError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController();
    _webController = TextEditingController();
    _loadEnv();
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
        title: 'Endpoints saved',
        message:
            'Restart the app so API calls and WebView use the new base URLs.\n\n'
            'API: ${DebugEnvConfig.instance.apiBaseUrl}\n'
            'WebView: ${DebugEnvConfig.instance.webBaseUrl}',
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
        title: 'Production restored',
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
    final colors = DebugEnvColors.of(isDark);
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

  Widget _fieldLabel(String text, DebugEnvColors colors) {
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
    required DebugEnvColors colors,
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
    final colors = DebugEnvColors.of(isDark);

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
          'Environment endpoints',
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
                        Icon(Icons.circle, size: 8, color: colors.warningFg),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Override active',
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
                          : const Text('Save endpoints'),
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
