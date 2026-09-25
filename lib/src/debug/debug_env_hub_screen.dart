import 'package:flutter/material.dart';

import '../app/native_theme_controller.dart';
import '../utilities/app_config.dart';
import 'debug_env_logs_screen.dart';
import 'debug_env_theme.dart';
import 'debug_env_urls_screen.dart';

/// Post-PIN landing: choose Diagnostic Logging or Environment Endpoints.
class DebugEnvHubScreen extends StatelessWidget {
  const DebugEnvHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Developer tools',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          _HubCard(
            colors: colors,
            icon: Icons.terminal_rounded,
            title: 'Diagnostic logging',
            onTap: () => _open(context, const DebugEnvLogsScreen()),
          ),
          const SizedBox(height: 14),
          _HubCard(
            colors: colors,
            icon: Icons.language_rounded,
            title: 'Environment endpoints',
            onTap: () => _open(context, const DebugEnvUrlsScreen()),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final DebugEnvColors colors;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(
                    AppConfig.cPrimary,
                  ).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: const Color(AppConfig.cPrimary),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.subtitle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
