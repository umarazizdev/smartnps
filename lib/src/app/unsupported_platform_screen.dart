import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class UnsupportedPlatformScreen extends StatelessWidget {
  const UnsupportedPlatformScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = kIsWeb ? 'Web' : defaultTargetPlatform.name;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF0F1724)
        : Theme.of(context).colorScheme.surface;
    return Scaffold(
      backgroundColor: background,
      body: ColoredBox(
        color: background,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_iphone_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This app is mobile-only',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You are running on $platform. SmartNPS360 is configured to run on Android and iOS only (WebView wrapper).',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Run: flutter run -d android  (or)  flutter run -d ios',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

