import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  static const _bgW = 853.0;
  static const _bgH = 1844.0;

  static const _lightIconBottomFrac = 0.408;
  static const _darkIconBottomFrac = 0.360;

  static const _lightTitle = Color(0xFF17213A);
  static const _lightAccent = Color(0xFF2964C9);
  static const _lightBody = Color(0xFF6B7280);
  static const _lightWarning = Color(0xFFE7A342);
  static const _lightCardBg = Color(0xFFFFFFFF);

  static const _darkTitle = Color(0xFFFFFFFF);
  static const _darkAccent = Color(0xFF5B8DEF);
  static const _darkBody = Color(0xFFA8B0BC);
  static const _darkWarning = Color(0xFFFDBA13);
  static const _darkHelpIcon = Color(0xFF4DA3FF);

  @override
  Widget build(BuildContext context) {
    final fallbackBg = isDark
        ? const Color(0xFF060F1E)
        : const Color(0xFFF6F9FE);
    final titlePrimary = isDark ? _darkTitle : _lightTitle;
    final titleAccent = isDark ? _darkAccent : _lightAccent;
    final bodyColor = isDark ? _darkBody : _lightBody;
    final versionColor = isDark
        ? Colors.white.withValues(alpha: 0.38)
        : const Color(0xFF9CA3AF);
    final helpTitleColor = isDark ? _darkTitle : _lightTitle;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final iconFrac = isDark ? _darkIconBottomFrac : _lightIconBottomFrac;

    return Material(
      color: fallbackBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          final scale = math.max(w / _bgW, h / _bgH);
          final paintedH = _bgH * scale;

          final topGap = (paintedH * iconFrac + 10).clamp(h * 0.28, h * 0.46);

          final textSidePad = (w * 0.08).clamp(20.0, 36.0);
          final actionSidePad = (w * 0.145).clamp(36.0, 56.0);
          final actionMaxW = math.min(w - actionSidePad * 2, 320.0);

          final content = Column(
            children: [
              SizedBox(height: topGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: textSidePad),
                child: Column(
                  children: [
                    SizedBox(height: isDark ? 20 : 0),

                    _Title(
                      primaryColor: titlePrimary,
                      accentColor: titleAccent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRetrying
                          ? 'Trying to reconnect…'
                          : 'We can\'t reach the server. Please check your '
                                'connection and try again.',
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: actionSidePad),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: actionMaxW),
                    child: Column(
                      children: [
                        _StatusCard(
                          message: statusMessage,
                          isDark: isDark,
                          isRetrying: isRetrying,
                        ),
                        const SizedBox(height: 14),
                        _RetryButton(
                          onPressed: isRetrying ? null : onRetry,
                          isRetrying: isRetrying,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: textSidePad),
                child: _HelpFooter(
                  titleColor: helpTitleColor,
                  bodyColor: bodyColor,
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 12),
            ],
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                isDark
                    ? 'assets/images/no-internet-dark-bg.png'
                    : 'assets/images/no-internet-light-bg.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
              Padding(
                padding: EdgeInsets.only(bottom: bottomInset + 6),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: content,
                      ),
                    ),
                    Text(
                      'v${AppVersionInfo.version} (${AppVersionInfo.buildNumber})',
                      style: TextStyle(
                        color: versionColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isDark ? bottomInset + 12 : 0),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.primaryColor, required this.accentColor});

  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'No internet ',
            style: TextStyle(
              color: primaryColor,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
          TextSpan(
            text: 'connection',
            style: TextStyle(
              color: accentColor,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.message,
    required this.isDark,
    required this.isRetrying,
  });

  final String? message;
  final bool isDark;
  final bool isRetrying;

  static const _defaultTitle = 'Still no internet connection.';
  static const _defaultBody = 'Please check your network and try again.';

  (String, String) _resolveCopy() {
    if (isRetrying) {
      return ('Reconnecting…', 'Please wait while we try again.');
    }
    final raw = message?.trim();
    if (raw == null || raw.isEmpty) {
      return (_defaultTitle, _defaultBody);
    }
    final idx = raw.indexOf('. ');
    if (idx > 0 && idx < raw.length - 2) {
      return (raw.substring(0, idx + 1), raw.substring(idx + 2));
    }
    return (raw, _defaultBody);
  }

  @override
  Widget build(BuildContext context) {
    final (title, body) = _resolveCopy();
    final titleColor = isDark
        ? OfflineScreen._darkWarning
        : OfflineScreen._lightWarning;
    final bodyColor = isDark
        ? const Color(0xFFB8C0CC)
        : const Color(0xFF6B7280);
    final cardBg = isDark
        ? const Color(0xFF0C1A2C).withValues(alpha: 0.78)
        : OfflineScreen._lightCardBg;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE8EDF4);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: isDark ? 14 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _WarningIcon(isDark: isDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningIcon extends StatelessWidget {
  const _WarningIcon({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final circleBg = isDark ? const Color(0xFF1A2436) : const Color(0xFFECF5FA);
    final iconColor = isDark
        ? OfflineScreen._darkWarning
        : OfflineScreen._lightWarning;

    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
            child: Icon(Icons.wifi_rounded, size: 18, color: iconColor),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF0A1220) : Colors.white,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                '!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.onPressed,
    required this.isRetrying,
    required this.isDark,
  });

  final VoidCallback? onPressed;
  final bool isRetrying;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [Color(0xFF59A3EE), Color(0xFF1E6BEF)]
          : const [Color(0xFF60A8FD), Color(0xFF256AEC)],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF3B82F6,
            ).withValues(alpha: isDark ? 0.42 : 0.30),
            blurRadius: isDark ? 18 : 14,
            offset: const Offset(0, 6),
            spreadRadius: isDark ? 0.5 : 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: Center(
              child: isRetrying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpFooter extends StatelessWidget {
  const _HelpFooter({
    required this.titleColor,
    required this.bodyColor,
    required this.isDark,
  });

  final Color titleColor;
  final Color bodyColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ringColor = isDark
        ? OfflineScreen._darkHelpIcon
        : const Color(0xFF1E3A5F);
    final markColor = isDark ? Colors.white : const Color(0xFF1E3A5F);
    final fillColor = isDark
        ? OfflineScreen._darkHelpIcon.withValues(alpha: 0.22)
        : const Color(0xFFEDF4FE);

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fillColor,
            border: Border.all(color: ringColor, width: 1.4),
          ),
          alignment: Alignment.center,
          child: Text(
            '?',
            style: TextStyle(
              color: markColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Need help?',
          style: TextStyle(
            color: titleColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Check your Wi-Fi or mobile data settings\nand try again.',
          style: TextStyle(
            color: bodyColor,
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
