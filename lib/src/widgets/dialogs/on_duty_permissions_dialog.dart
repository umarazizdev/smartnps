import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_navigator.dart';
import '../../app/native_theme_controller.dart';
import '../../debug/debug_env_pin_dialog.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_version_info.dart';
import '../../utilities/overlay_prompt_guard.dart';
import 'clock_in_location_disclosure_dialog.dart';
import 'permission_blocker_chrome.dart';

class OnDutyPermissionsDialog {
  OnDutyPermissionsDialog._();

  static bool _visible = false;
  static Future<bool>? _activeShow;

  static bool get isVisible => _visible || _activeShow != null;

  static Future<bool> showIfNeeded() async {
    final existing = _activeShow;
    if (existing != null) return existing;

    final show = _presentIfNeeded();
    _activeShow = show;
    try {
      return await show;
    } finally {
      if (identical(_activeShow, show)) {
        _activeShow = null;
      }
    }
  }

  static Future<bool> _presentIfNeeded() async {
    if (_visible) return false;
    if (RequiredPermissionsGate.isPrivacyNoticeVisible) return false;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return false;

    _visible = true;
    OverlayPromptGuard.registerBlockingOverlay();
    try {
      await OverlayPromptGuard.waitUntilReady();

      final readyContext = AppNavigator.key.currentContext;
      if (readyContext == null || !readyContext.mounted) return false;

      final gate = RequiredPermissionsGate.instance;
      final missing = await gate.missingOnDutyPermissionItems();
      if (missing.isEmpty) return false;

      await showDialog<void>(
        context: readyContext,
        useRootNavigator: true,
        barrierDismissible: true,
        builder: (dialogContext) {
          return const _OnDutyPermissionsDialogPanel();
        },
      );
      return true;
    } finally {
      OverlayPromptGuard.unregisterBlockingOverlay();
      _visible = false;
    }
  }
}

class _OnDutyPermissionsDialogPanel extends StatefulWidget {
  const _OnDutyPermissionsDialogPanel();

  @override
  State<_OnDutyPermissionsDialogPanel> createState() =>
      _OnDutyPermissionsDialogPanelState();
}

class _OnDutyPermissionsDialogPanelState
    extends State<_OnDutyPermissionsDialogPanel>
    with WidgetsBindingObserver {
  final RequiredPermissionsGate _gate = RequiredPermissionsGate.instance;
  List<RequiredPermissionItem> _items = const [];
  String? _busyId;
  bool _loading = true;
  bool _didPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_busyId != null || _didPop) return;
      unawaited(_reload(closeIfReady: true));
    }
  }

  void _safePop() {
    if (_didPop || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    _didPop = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  List<RequiredPermissionItem> get _missingItems =>
      _items.where((e) => e.needsAction).toList(growable: false);

  bool get _onlyAlertsMissing {
    final missing = _missingItems;
    if (missing.isEmpty) return false;
    return missing.every((e) => e.id == 'notifications' || e.id == 'push');
  }

  bool get _onlyMotionMissing {
    final missing = _missingItems;
    if (missing.isEmpty) return false;
    return missing.every((e) => e.id == 'motionActivity');
  }

  bool get _onlyLocationMissing {
    final missing = _missingItems;
    if (missing.isEmpty) return false;
    const locationIds = {
      'locationServices',
      'foregroundLocation',
      'backgroundLocation',
      'preciseLocation',
    };
    return missing.every((e) => locationIds.contains(e.id));
  }

  bool get _onlyTrackingMissing {
    final missing = _missingItems;
    if (missing.isEmpty) return false;
    const trackingIds = {
      'locationServices',
      'foregroundLocation',
      'backgroundLocation',
      'preciseLocation',
      'motionActivity',
      'backgroundAppRefresh',
    };
    return missing.every((e) => trackingIds.contains(e.id));
  }

  String get _titleText {
    if (_onlyAlertsMissing) return 'Notifications are off';
    if (_onlyMotionMissing) {
      return Platform.isAndroid
          ? 'Physical activity required'
          : 'Motion & Fitness required';
    }
    if (_onlyLocationMissing) return 'Location permissions unavailable';
    if (_onlyTrackingMissing) return 'Tracking permissions unavailable';
    return 'Required permissions unavailable';
  }

  String get _subtitleText {
    if (_onlyAlertsMissing) {
      return 'Enable notifications to receive shift alerts, assignments, '
          'and other important updates from SmartNPS360.';
    }
    if (_onlyMotionMissing) {
      return Platform.isAndroid
          ? 'Physical activity access is needed so movement during your shift '
              'can be recorded accurately for attendance verification.'
          : 'Motion & Fitness access is needed so movement during your shift '
              'can be recorded accurately for attendance verification.';
    }
    if (_onlyLocationMissing) {
      return 'Location access is needed to verify attendance and continue '
          'live tracking during your shift. Tracking stops when you clock out.';
    }
    if (_onlyTrackingMissing) {
      return 'Location and related tracking permissions are needed to verify '
          'attendance during your shift. Tracking stops when you clock out.';
    }
    return 'Some permissions required by SmartNPS360 are turned off. Restore '
        'them so attendance tracking and notifications work as expected.';
  }

  Future<void> _reload({bool closeIfReady = false}) async {
    final items = await _gate.buildOnDutyPermissionItems();
    final missing = items.where((e) => e.needsAction).toList(growable: false);
    if (!mounted || _didPop) return;

    if (closeIfReady && missing.isEmpty) {
      _safePop();
      return;
    }

    setState(() {
      _items = items;
      _loading = false;
    });

    if (!closeIfReady && missing.isEmpty) {
      _safePop();
    }
  }

  Future<void> _onAction(RequiredPermissionItem item) async {
    if (_busyId != null || item.enabled || _didPop) return;
    setState(() => _busyId = item.id);
    try {
      final accepted = await _showDisclosureFor(item);
      if (!accepted || !mounted || _didPop) return;
      await _gate.handleAction(item);
      if (!mounted || _didPop) return;
      await _reload(closeIfReady: true);
    } finally {
      if (mounted && !_didPop) setState(() => _busyId = null);
    }
  }

  Future<bool> _showDisclosureFor(RequiredPermissionItem item) async {
    if (!mounted) return false;

    if (Platform.isAndroid && item.id != 'backgroundLocation') {
      return true;
    }

    switch (item.id) {
      case 'locationServices':
      case 'preciseLocation':
      case 'motionActivity':
      case 'foregroundLocation':
      case 'backgroundLocation':
      case 'backgroundAppRefresh':
        return ClockInLocationDisclosureDialog.showForPermission(
          context,
          permissionId: item.id,
        );
      case 'notifications':
      case 'push':
        return true;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = PermissionBlockerColors.of(isDark);
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88;
    final versionColor = isDark
        ? Colors.white.withValues(alpha: 0.38)
        : const Color(0xFF9CA3AF);

    final orderedItems = [
      ..._items.where((e) => e.needsAction),
      ..._items.where((e) => !e.needsAction),
    ];

    return Dialog(
      backgroundColor: colors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: maxHeight,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onLongPress: isDebugEnvSupported
                            ? () {
                                final navContext =
                                    AppNavigator.key.currentContext ?? context;
                                unawaited(openDebugEnvFromLogo(navContext));
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          child: Image.asset(
                            'assets/npslogo.png',
                            height: 72,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _titleText,
                    style: TextStyle(
                      color: colors.title,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _subtitleText,
                    style: TextStyle(
                      color: colors.subtitle,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  PermissionPrivacyBanner(colors: colors, compact: true),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _loading
                        ? const SingleChildScrollView(
                            child: PermissionBlockerShimmerList(
                              itemCount: 5,
                              compact: true,
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: orderedItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = orderedItems[index];
                              return PermissionBlockerRow(
                                item: item,
                                colors: colors,
                                busy: _busyId == item.id,
                                onAction: () => _onAction(item),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'v${AppVersionInfo.version} '
                    '(${AppVersionInfo.buildNumber})',
                    style: TextStyle(
                      color: versionColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white,
                shape: CircleBorder(
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                elevation: isDark ? 0 : 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _safePop,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.88)
                          : const Color(0xFF111827),
                    ),
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
