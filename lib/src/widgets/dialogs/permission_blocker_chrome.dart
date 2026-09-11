import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/native_theme_controller.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_config.dart';

class PermissionBlockerColors {
  const PermissionBlockerColors({
    required this.background,
    required this.title,
    required this.subtitle,
    required this.divider,
    required this.cardBg,
    required this.cardShadow,
    required this.actionBg,
    required this.actionFg,
    required this.enabled,
    required this.privacyBg,
    required this.privacyIconBg,
    required this.privacyIcon,
    required this.privacyTitle,
    required this.privacyBody,
  });

  final Color background;
  final Color title;
  final Color subtitle;
  final Color divider;
  final Color cardBg;
  final Color cardShadow;
  final Color actionBg;
  final Color actionFg;
  final Color enabled;
  final Color privacyBg;
  final Color privacyIconBg;
  final Color privacyIcon;
  final Color privacyTitle;
  final Color privacyBody;

  static PermissionBlockerColors of(bool isDark) {
    if (isDark) {
      return PermissionBlockerColors(
        background: const Color(0xFF0F1724),
        title: Colors.white,
        subtitle: Colors.white.withValues(alpha: 0.68),
        divider: const Color(0xFF60A5FA),
        cardBg: const Color(AppConfig.cDarkCardColor),
        cardShadow: Colors.black.withValues(alpha: 0.35),
        actionBg: const Color(0xFF1E3A5F),
        actionFg: const Color(0xFF93C5FD),
        enabled: const Color(0xFF34D399),
        privacyBg: const Color(0xFF162033),
        privacyIconBg: const Color(0xFF1E3A5F),
        privacyIcon: const Color(0xFF93C5FD),
        privacyTitle: Colors.white,
        privacyBody: Colors.white.withValues(alpha: 0.68),
      );
    }

    return const PermissionBlockerColors(
      background: Color(0xFFFFFFFF),
      title: Color(0xFF022A67),
      subtitle: Color(0xFF667085),
      divider: Color(0xFF3B82F6),
      cardBg: Color(0xFFFFFFFF),
      cardShadow: Color(0x14000000),
      actionBg: Color(0xFFEEF2FF),
      actionFg: Color(0xFF3B82F6),
      enabled: Color(0xFF22C55E),
      privacyBg: Color(0xFFF0F4FF),
      privacyIconBg: Color(0xFFE0E7FF),
      privacyIcon: Color(0xFF3B82F6),
      privacyTitle: Color(0xFF022A67),
      privacyBody: Color(0xFF667085),
    );
  }
}

class PermissionBlockerAccent {
  const PermissionBlockerAccent({required this.icon, required this.iconBg});

  final Color icon;
  final Color iconBg;

  static PermissionBlockerAccent forItem(String id, bool isDark) {
    final isBlue = id == 'notifications' || id == 'push';
    if (isDark) {
      return PermissionBlockerAccent(
        icon: isBlue ? const Color(0xFF93C5FD) : const Color(0xFF34D399),
        iconBg: isBlue ? const Color(0xFF1E3A5F) : const Color(0xFF14532D),
      );
    }
    return PermissionBlockerAccent(
      icon: isBlue ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
      iconBg: isBlue ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
    );
  }
}

class PermissionBlockerRow extends StatelessWidget {
  const PermissionBlockerRow({
    super.key,
    required this.item,
    required this.colors,
    required this.busy,
    required this.onAction,
  });

  final RequiredPermissionItem item;
  final PermissionBlockerColors colors;
  final bool busy;
  final VoidCallback onAction;

  String get _buttonLabel {
    return switch (item.action) {
      RequiredPermissionAction.allow => 'Allow',
      RequiredPermissionAction.openSettings => 'Settings',
      RequiredPermissionAction.enable => 'Enable',
      RequiredPermissionAction.none => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final accent = PermissionBlockerAccent.forItem(item.id, isDark);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.iconBg,
                shape: BoxShape.circle,
              ),
              child: item.id == 'push'
                  ? Transform.rotate(
                      angle: -math.pi / 4,
                      child: Icon(item.icon, size: 18, color: accent.icon),
                    )
                  : Icon(item.icon, size: 18, color: accent.icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      color: colors.title,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: TextStyle(
                      color: colors.subtitle,
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (item.enabled)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 17, color: colors.enabled),
                  const SizedBox(width: 4),
                  Text(
                    'Enabled',
                    style: TextStyle(
                      color: colors.enabled,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                height: 32,
                child: TextButton(
                  onPressed: busy ? null : onAction,
                  style: TextButton.styleFrom(
                    backgroundColor: colors.actionBg,
                    foregroundColor: colors.actionFg,
                    disabledBackgroundColor: colors.actionBg.withValues(
                      alpha: 0.55,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.actionFg,
                          ),
                        )
                      : Text(
                          _buttonLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PermissionBlockerShimmerColors {
  const PermissionBlockerShimmerColors({
    required this.base,
    required this.highlight,
  });

  final Color base;
  final Color highlight;

  static PermissionBlockerShimmerColors of(bool isDark) {
    if (isDark) {
      return const PermissionBlockerShimmerColors(
        base: Color(0xFF243044),
        highlight: Color(0xFF3A4F6A),
      );
    }
    return const PermissionBlockerShimmerColors(
      base: Color(0xFFE5EBF5),
      highlight: Color(0xFFF7F9FC),
    );
  }
}

class PermissionBlockerShimmerList extends StatefulWidget {
  const PermissionBlockerShimmerList({
    super.key,
    this.itemCount = 4,
    this.compact = false,
  });

  final int itemCount;
  final bool compact;

  @override
  State<PermissionBlockerShimmerList> createState() =>
      _PermissionBlockerShimmerListState();
}

class _PermissionBlockerShimmerListState
    extends State<PermissionBlockerShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = PermissionBlockerColors.of(isDark);
    final shimmer = PermissionBlockerShimmerColors.of(isDark);
    final gap = widget.compact ? 8.0 : 10.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.itemCount; i++) ...[
              if (i > 0) SizedBox(height: gap),
              _PermissionBlockerShimmerRow(
                colors: colors,
                shimmer: shimmer,
                shimmerValue: _controller.value,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PermissionBlockerShimmerRow extends StatelessWidget {
  const _PermissionBlockerShimmerRow({
    required this.colors,
    required this.shimmer,
    required this.shimmerValue,
  });

  final PermissionBlockerColors colors;
  final PermissionBlockerShimmerColors shimmer;
  final double shimmerValue;

  Widget _bone({
    required double height,
    double? width,
    double widthFactor = 1,
    required double radius,
  }) {
    final bone = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-1.2 + shimmerValue * 2.4, 0),
          end: Alignment(-0.2 + shimmerValue * 2.4, 0),
          colors: [
            shimmer.base,
            shimmer.highlight,
            shimmer.base,
          ],
          stops: const [0.35, 0.5, 0.65],
        ),
      ),
    );

    if (width != null) return bone;
    return FractionallySizedBox(widthFactor: widthFactor, child: bone);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment(-1.2 + shimmerValue * 2.4, 0),
                  end: Alignment(-0.2 + shimmerValue * 2.4, 0),
                  colors: [
                    shimmer.base,
                    shimmer.highlight,
                    shimmer.base,
                  ],
                  stops: const [0.35, 0.5, 0.65],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bone(height: 12, radius: 6),
                  const SizedBox(height: 8),
                  _bone(height: 10, widthFactor: 0.72, radius: 5),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _bone(height: 28, width: 68, radius: 9),
          ],
        ),
      ),
    );
  }
}

class PermissionPrivacyBanner extends StatelessWidget {
  const PermissionPrivacyBanner({
    super.key,
    required this.colors,
    this.compact = false,
  });

  final PermissionBlockerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 32.0 : 40.0;
    final shieldSize = compact ? 18.0 : 22.0;
    final lockSize = compact ? 8.0 : 9.0;
    final pad = compact ? 10.0 : 14.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.privacyBg,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: colors.privacyIconBg,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: shieldSize,
                    color: colors.privacyIcon,
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: compact ? 3 : 4),
                    child: Icon(
                      Icons.lock_rounded,
                      size: lockSize,
                      color: colors.privacyIcon,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Privacy notice',
                    style: TextStyle(
                      color: colors.privacyTitle,
                      fontSize: compact ? 12.5 : 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 4),
                  Text(
                    'These permissions are used solely to verify attendance '
                    'during an active duty period. Collection stops when duty ends.',
                    style: TextStyle(
                      color: colors.privacyBody,
                      fontSize: compact ? 11.5 : 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
