import 'package:flutter/material.dart';

import '../utilities/app_config.dart';
import '../utilities/app_version_info.dart';

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({
    super.key,
    required this.onRetry,
    required this.isDark,
    this.isRetrying = false,
    this.statusMessage,
  });

  final VoidCallback onRetry;
  final bool isDark;
  final bool isRetrying;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    // Match splash / system chrome so offline UI tracks web light/dark theme.
    final background = isDark
        ? const Color(0xFF0F1724)
        : const Color(AppConfig.cSurface);
    final iconColor = isDark
        ? const Color(0xFF93C5FD)
        : const Color(AppConfig.cPrimary);
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF5D6168);
    final statusColor = isDark
        ? const Color(0xFFFBBF24)
        : const Color(0xFFB45309);
    final buttonBg = isDark ? Colors.white : const Color(AppConfig.cPrimary);
    final buttonFg = isDark ? const Color(0xFF111827) : Colors.white;
    final progressColor = isDark ? Colors.white : const Color(AppConfig.cPrimary);
    final versionColor = isDark
        ? Colors.white.withValues(alpha: 0.38)
        : const Color(0xFF9CA3AF);

    // Opaque Material so platform WebView error chrome never peeks through.
    return Material(
      color: background,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 52,
                          color: iconColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No internet connection',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isRetrying
                              ? 'Trying to reconnect…'
                              : 'Check your connection and try again.',
                          style: TextStyle(
                            color: bodyColor,
                            fontSize: 14,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (statusMessage != null &&
                            statusMessage!.trim().isNotEmpty &&
                            !isRetrying) ...[
                          const SizedBox(height: 12),
                          Text(
                            statusMessage!,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (isRetrying)
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: progressColor,
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: onRetry,
                            style: FilledButton.styleFrom(
                              backgroundColor: buttonBg,
                              foregroundColor: buttonFg,
                            ),
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'v${AppVersionInfo.version} (${AppVersionInfo.buildNumber})',
                style: TextStyle(
                  color: versionColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
