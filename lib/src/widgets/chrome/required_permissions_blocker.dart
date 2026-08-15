import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/native_theme_controller.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_config.dart';
import '../../utilities/app_version_info.dart';

class RequiredPermissionsBlocker extends StatefulWidget {
  const RequiredPermissionsBlocker({super.key});

  @override
  State<RequiredPermissionsBlocker> createState() =>
      _RequiredPermissionsBlockerState();
}

class _RequiredPermissionsBlockerState extends State<RequiredPermissionsBlocker>
    with WidgetsBindingObserver {
  final RequiredPermissionsGate _gate = RequiredPermissionsGate.instance;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(() async {
      await _gate.refresh(force: true);
      await _gate.requestPendingAllowPermissionsAutomatically();
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_gate.refresh(force: true));
    }
  }

  Future<void> _onAction(RequiredPermissionItem item) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.id);
    try {
      await _gate.handleAction(item);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = _PermissionBlockerColors.of(isDark);
    final versionColor = isDark
        ? Colors.white.withValues(alpha: 0.38)
        : const Color(0xFF9CA3AF);

    return Material(
      color: colors.background,
      child: SafeArea(
        child: ValueListenableBuilder<List<RequiredPermissionItem>>(
          valueListenable: _gate.items,
          builder: (context, items, _) {
            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 28,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Image.asset(
                                    'assets/npslogo.png',
                                    height: 88,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Permissions required',
                                    style: TextStyle(
                                      color: colors.title,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                      height: 1.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'SmartNPS360 needs these permissions to run properly.\n\n'
                                    'Location is used only while you are on duty, and stops '
                                    'when your shift ends.',
                                    style: TextStyle(
                                      color: colors.subtitle,
                                      fontSize: 13.5,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 14),
                                  Center(
                                    child: Container(
                                      width: 44,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: colors.divider,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _PrivacyBanner(colors: colors),
                                  const SizedBox(height: 16),
                                  for (var i = 0; i < items.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 10),
                                    _PermissionRow(
                                      item: items[i],
                                      colors: colors,
                                      busy: _busyId == items[i].id,
                                      onAction: () => _onAction(items[i]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
            );
          },
        ),
      ),
    );
  }
}

class _PermissionBlockerColors {
  const _PermissionBlockerColors({
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

  static _PermissionBlockerColors of(bool isDark) {
    if (isDark) {
      return _PermissionBlockerColors(
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

    return const _PermissionBlockerColors(
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

class _PermissionAccent {
  const _PermissionAccent({required this.icon, required this.iconBg});

  final Color icon;
  final Color iconBg;

  static _PermissionAccent forItem(String id, bool isDark) {
    final isBlue = id == 'notifications' || id == 'push';
    if (isDark) {
      return _PermissionAccent(
        icon: isBlue ? const Color(0xFF93C5FD) : const Color(0xFF34D399),
        iconBg: isBlue ? const Color(0xFF1E3A5F) : const Color(0xFF14532D),
      );
    }
    return _PermissionAccent(
      icon: isBlue ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
      iconBg: isBlue ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.item,
    required this.colors,
    required this.busy,
    required this.onAction,
  });

  final RequiredPermissionItem item;
  final _PermissionBlockerColors colors;
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
    final accent = _PermissionAccent.forItem(item.id, isDark);

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
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.iconBg,
                shape: BoxShape.circle,
              ),
              child: item.id == 'push'
                  ? Transform.rotate(
                      angle: -math.pi / 4,
                      child: Icon(item.icon, size: 20, color: accent.icon),
                    )
                  : Icon(item.icon, size: 20, color: accent.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      color: colors.title,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    style: TextStyle(
                      color: colors.subtitle,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.enabled)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 18, color: colors.enabled),
                  const SizedBox(width: 5),
                  Text(
                    'Enabled',
                    style: TextStyle(
                      color: colors.enabled,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                height: 34,
                child: TextButton(
                  onPressed: busy ? null : onAction,
                  style: TextButton.styleFrom(
                    backgroundColor: colors.actionBg,
                    foregroundColor: colors.actionFg,
                    disabledBackgroundColor: colors.actionBg.withValues(
                      alpha: 0.55,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
                            fontSize: 13,
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

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.colors});

  final _PermissionBlockerColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.privacyBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.privacyIconBg,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 22,
                    color: colors.privacyIcon,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 9,
                      color: colors.privacyIcon,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your privacy and security are our priority.',
                    style: TextStyle(
                      color: colors.privacyTitle,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'We only use these permissions for core app features.',
                    style: TextStyle(
                      color: colors.privacyBody,
                      fontSize: 12,
                      height: 1.4,
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
