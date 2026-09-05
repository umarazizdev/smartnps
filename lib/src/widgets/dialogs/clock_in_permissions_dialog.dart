import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_navigator.dart';
import '../../app/native_theme_controller.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_version_info.dart';
import '../../utilities/overlay_prompt_guard.dart';
import 'clock_in_location_disclosure_dialog.dart';
import 'permission_blocker_chrome.dart';

class ClockInPermissionsDialog {
  ClockInPermissionsDialog._();

  static bool _visible = false;
  static Future<bool>? _activeShow;

  static bool get isVisible => _visible || _activeShow != null;

  static Future<bool> showUntilReadyOrCancelled() async {
    final existing = _activeShow;
    if (existing != null) return existing;

    final show = _presentUntilReadyOrCancelled();
    _activeShow = show;
    try {
      return await show;
    } finally {
      if (identical(_activeShow, show)) {
        _activeShow = null;
      }
    }
  }

  static Future<bool> _presentUntilReadyOrCancelled() async {
    _visible = true;
    try {
      final context = AppNavigator.key.currentContext;
      if (context == null || !context.mounted) return false;

      await OverlayPromptGuard.waitUntilReady();

      final readyContext = AppNavigator.key.currentContext;
      if (readyContext == null || !readyContext.mounted) return false;

      final gate = RequiredPermissionsGate.instance;
      final missing = await gate.missingClockInPermissionItems();
      if (missing.isEmpty) return true;

      OverlayPromptGuard.registerBlockingOverlay();
      try {
        final navigator = Navigator.of(readyContext, rootNavigator: true);
        final result = await navigator.push<bool>(
          PageRouteBuilder<bool>(
            opaque: true,
            barrierDismissible: false,
            transitionDuration: const Duration(milliseconds: 180),
            reverseTransitionDuration: const Duration(milliseconds: 150),
            pageBuilder: (context, animation, secondaryAnimation) {
              return const _ClockInPermissionsBlockerScreen();
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        );
        return result == true;
      } finally {
        OverlayPromptGuard.unregisterBlockingOverlay();
      }
    } finally {
      _visible = false;
    }
  }
}

class _ClockInPermissionsBlockerScreen extends StatefulWidget {
  const _ClockInPermissionsBlockerScreen();

  @override
  State<_ClockInPermissionsBlockerScreen> createState() =>
      _ClockInPermissionsBlockerScreenState();
}

class _ClockInPermissionsBlockerScreenState
    extends State<_ClockInPermissionsBlockerScreen>
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

  void _safePop(bool result) {
    if (_didPop || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    _didPop = true;
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  Future<void> _reload({bool closeIfReady = false}) async {
    final items = await _gate.buildClockInPermissionItems();
    final missing = items.where((e) => e.needsAction).toList(growable: false);
    if (!mounted || _didPop) return;

    if (closeIfReady && missing.isEmpty) {
      _safePop(true);
      return;
    }

    setState(() {
      _items = items;
      _loading = false;
    });

    if (!closeIfReady && missing.isEmpty) {
      _safePop(true);
    }
  }

  void _onClose() {
    _safePop(false);
  }

  Future<void> _onAction(RequiredPermissionItem item) async {
    if (_busyId != null || item.enabled || _didPop) return;
    setState(() => _busyId = item.id);
    try {
      if (kDebugMode) {
        debugPrint(
          '[ClockInPermissions] action id=${item.id} action=${item.action.name}',
        );
      }
      final accepted = await _showDisclosureFor(item);
      if (kDebugMode) {
        debugPrint(
          '[ClockInPermissions] disclosure id=${item.id} accepted=$accepted '
          'mounted=$mounted didPop=$_didPop',
        );
      }
      if (!accepted || !mounted || _didPop) return;

      await _gate.handleAction(item);
      if (kDebugMode) {
        debugPrint('[ClockInPermissions] handleAction done id=${item.id}');
      }
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
        return ClockInLocationDisclosureDialog.showForPermission(
          context,
          permissionId: item.id,
        );
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = PermissionBlockerColors.of(isDark);
    final versionColor = isDark
        ? Colors.white.withValues(alpha: 0.38)
        : const Color(0xFF9CA3AF);

    return Material(
      color: colors.background,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
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
                                    'These permissions are needed to clock in and '
                                    'track your shift.\n\n'
                                    'Location and motion are used only while you '
                                    'are on duty, and stop when your shift ends.',
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
                                  PermissionPrivacyBanner(colors: colors),
                                  const SizedBox(height: 16),
                                  if (_loading)
                                    const PermissionBlockerShimmerList()
                                  else
                                    for (var i = 0; i < _items.length; i++) ...[
                                      if (i > 0) const SizedBox(height: 10),
                                      PermissionBlockerRow(
                                        item: _items[i],
                                        colors: colors,
                                        busy: _busyId == _items[i].id,
                                        onAction: () => _onAction(_items[i]),
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
            ),
            Positioned(
              top: 8,
              right: 12,
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
                  onTap: _onClose,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
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
