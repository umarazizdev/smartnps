import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_navigator.dart';
import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_config.dart';
import 'debug_env_screen.dart';

bool get isDebugEnvSupported =>
    !kIsWeb && Platform.isAndroid;

Future<void> openDebugEnvFromLogo(BuildContext context) async {
  if (!isDebugEnvSupported) return;
  final unlocked = await showDebugEnvPinDialog(context);
  if (!unlocked) return;
  final navContext = AppNavigator.key.currentContext;
  if (navContext == null || !navContext.mounted) return;
  await Navigator.of(navContext, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => const DebugEnvScreen()),
  );
}

Future<bool> showDebugEnvPinDialog(BuildContext context) async {
  if (!isDebugEnvSupported) return false;
  final navContext = AppNavigator.key.currentContext ?? context;
  if (!navContext.mounted) return false;
  final result = await showDialog<bool>(
    context: navContext,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    useRootNavigator: true,
    builder: (ctx) => const _DebugEnvPinDialog(),
  );
  return result == true;
}

class _DebugEnvPinDialog extends StatefulWidget {
  const _DebugEnvPinDialog();

  @override
  State<_DebugEnvPinDialog> createState() => _DebugEnvPinDialogState();
}

class _DebugEnvPinDialogState extends State<_DebugEnvPinDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _error = false;
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == DebugEnvConfig.accessPin) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _error = true);
    }
  }

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = _DebugPinColors.of(isDark);

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 26,
                  color: colors.iconFg,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Debug access',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.title,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter PIN to open environment settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.subtitle,
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                color: colors.title,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: _obscure ? 3 : 0.2,
              ),
              cursorColor: const Color(AppConfig.cPrimary),
              decoration: InputDecoration(
                labelText: 'PIN',
                labelStyle: TextStyle(
                  color: colors.subtitle,
                  fontWeight: FontWeight.w600,
                ),
                floatingLabelStyle: TextStyle(
                  color: _error
                      ? colors.error
                      : const Color(AppConfig.cPrimary),
                  fontWeight: FontWeight.w700,
                ),
                errorText: _error ? 'Incorrect PIN' : null,
                errorStyle: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
                filled: true,
                fillColor: colors.fieldBg,
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colors.subtitle,
                    size: 22,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _error
                        ? colors.error
                        : const Color(AppConfig.cPrimary),
                    width: 1.6,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.error),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.error, width: 1.6),
                ),
              ),
              onChanged: (_) {
                if (_error) setState(() => _error = false);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(AppConfig.cPrimary),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Unlock'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _cancel,
              style: TextButton.styleFrom(
                foregroundColor: colors.subtitle,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugPinColors {
  const _DebugPinColors({
    required this.surface,
    required this.title,
    required this.subtitle,
    required this.iconBg,
    required this.iconFg,
    required this.fieldBg,
    required this.border,
    required this.error,
  });

  final Color surface;
  final Color title;
  final Color subtitle;
  final Color iconBg;
  final Color iconFg;
  final Color fieldBg;
  final Color border;
  final Color error;

  static _DebugPinColors of(bool isDark) {
    if (isDark) {
      return _DebugPinColors(
        surface: const Color(AppConfig.cDarkCardColor),
        title: Colors.white,
        subtitle: Colors.white.withValues(alpha: 0.68),
        iconBg: const Color(0xFF1E3A5F),
        iconFg: const Color(0xFF93C5FD),
        fieldBg: const Color(0xFF121A27),
        border: const Color(0xFF2A3548),
        error: const Color(0xFFF87171),
      );
    }
    return const _DebugPinColors(
      surface: Color(0xFFFFFFFF),
      title: Color(0xFF022A67),
      subtitle: Color(0xFF667085),
      iconBg: Color(0xFFEEF2FF),
      iconFg: Color(0xFF3B82F6),
      fieldBg: Color(0xFFF8FAFC),
      border: Color(0xFFE4E7EC),
      error: Color(0xFFDC2626),
    );
  }
}
