import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_navigator.dart';
import '../../app/native_theme_controller.dart';
import '../../background/duty/off_duty_push_prompt_service.dart';
import '../../permissions/required_permissions_gate.dart';
import '../../utilities/app_config.dart';
import '../../utilities/overlay_prompt_guard.dart';
import 'permission_blocker_chrome.dart';

class OffDutyPushPermissionsDialog {
  OffDutyPushPermissionsDialog._();

  static bool _visible = false;

  static bool get isVisible => _visible;

  static Future<bool> showIfNeeded() async {
    if (_visible) return false;
    if (RequiredPermissionsGate.isPrivacyNoticeVisible) return false;
    final uri = OffDutyPushPromptService.currentUriChecker?.call();
    if (uri != null && AppConfig.isAuthEntryRoute(uri)) return false;

    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return false;

    await OverlayPromptGuard.waitUntilReady();

    final readyContext = AppNavigator.key.currentContext;
    if (readyContext == null || !readyContext.mounted) return false;

    final gate = RequiredPermissionsGate.instance;
    final missing = await gate.missingOffDutyPushPermissionItems();
    if (missing.isEmpty) return false;

    _visible = true;
    OverlayPromptGuard.registerBlockingOverlay();
    try {
      await showDialog<void>(
        context: readyContext,
        useRootNavigator: true,
        barrierDismissible: true,
        builder: (_) => const _OffDutyPushPermissionsDialogPanel(),
      );
      return true;
    } finally {
      OverlayPromptGuard.unregisterBlockingOverlay();
      _visible = false;
    }
  }
}

class _OffDutyPushPermissionsDialogPanel extends StatefulWidget {
  const _OffDutyPushPermissionsDialogPanel();

  @override
  State<_OffDutyPushPermissionsDialogPanel> createState() =>
      _OffDutyPushPermissionsDialogPanelState();
}

class _OffDutyPushPermissionsDialogPanelState
    extends State<_OffDutyPushPermissionsDialogPanel>
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

  Future<void> _reload({bool closeIfReady = false}) async {
    final items = await _gate.buildOffDutyPushPermissionItems();
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
      await _gate.handleAction(item);
      if (!mounted || _didPop) return;
      await _reload(closeIfReady: true);
    } finally {
      if (mounted && !_didPop) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = PermissionBlockerColors.of(isDark);
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.72;

    return Dialog(
      backgroundColor: colors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/npslogo.png',
                    height: 64,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enable push alerts',
                    style: TextStyle(
                      color: colors.title,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable notifications to receive shift alerts, assignments, '
                    'and other important updates from SmartNPS360.',
                    style: TextStyle(
                      color: colors.subtitle,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
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
