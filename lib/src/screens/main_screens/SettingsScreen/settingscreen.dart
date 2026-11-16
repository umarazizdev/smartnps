import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';
import 'package:smartnps360/src/screens/main_screens/main_controller.dart';
import 'package:smartnps360/src/screens/main_screens/SettingsScreen/settingscontroller.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_controller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/widgets/bottomsheet.dart';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({
    super.key,
    required this.parentContext,
    required this.isAppleStyle,
  });

  final BuildContext parentContext;
  final bool isAppleStyle;

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet>
    with WidgetsBindingObserver {
  final MemoryStorageController _mem =
      Get.isRegistered<MemoryStorageController>()
      ? Get.find<MemoryStorageController>()
      : Get.put(MemoryStorageController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        Get.isRegistered<SettingsController>()) {
      Get.find<SettingsController>().refreshPermissionState();
    }
  }

  Future<void> _performLogout(SettingsController controller) async {
    _mem.setRegionId(null);
    _mem.setShiftId(null);
    _mem.setSiteId(null);
    _mem.setSeriesId(null);
    _mem.setRegionName('');
    _mem.setShiftName('');
    _mem.setSiteName('');
    _mem.setIsScopeSelected(false);
    _mem.setShiftStartTime(null);
    _mem.setShiftEndTime(null);
    await controller.handleLogout(widget.parentContext);
  }

  Future<void> _showIOSLogoutActionSheet(SettingsController controller) async {
    await showCupertinoModalPopup<void>(
      context: widget.parentContext,
      useRootNavigator: true,
      barrierColor: Colors.black.withAlpha(70),
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text(
            'Log Out',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          message: const Text(
            'Are you sure you want to log out of this account?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.of(context, rootNavigator: true).pop();
                await _performLogout(controller);
              },
              child: const Text(
                'Log Out',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  void _handleLogoutTap(SettingsController controller) {
    Navigator.of(context).pop();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isAppleStyle) {
        _showIOSLogoutActionSheet(controller);
      } else {
        ShowBottomSheet.show(
          context: widget.parentContext,
          onTap: () async => _performLogout(controller),
          title: 'Log Out',
          buttonTitle: 'Log Out',
          buttonColor: cPrimary,
          description: 'Are you sure you want to log out of this account?',
          iconAssetPath: 'assets/Icons/logouticon.png',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SettingsController());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final sheetRadius = widget.isAppleStyle ? 30.0 : 28.0;
    final blurSigma = widget.isAppleStyle ? 18.0 : 14.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            width: double.infinity,
            decoration: _sheetDecoration(isDark, sheetRadius),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  10,
                  18,
                  bottomInset > 0 ? 12 : 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _DragHandle(isDark: isDark)),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: widget.isAppleStyle ? 28 : 27,
                              height: 1.05,
                              letterSpacing: -0.55,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        _CloseButton(isDark: isDark),
                      ],
                    ),

                    const SizedBox(height: 26),
                    _SectionLabel(title: 'PREFERENCES', isDark: isDark),
                    const SizedBox(height: 10),

                    _GlassGroup(
                      isDark: isDark,
                      children: [
                        Obx(
                          () => _SettingsSwitchTile(
                            icon: CupertinoIcons.moon_fill,
                            title: 'Dark Mode',
                            isOn: controller.isDarkMode.value,
                            iconColor: const Color(0xFF5B5BE8),
                            iconBgColor: const Color(0xFFE8E7FF),
                            onChange: controller.toggleDarkMode,
                            isDark: isDark,
                          ),
                        ),
                        _TileDivider(isDark: isDark),
                        Obx(
                          () => AbsorbPointer(
                            absorbing:
                                controller.isUpdatingNotificationToggle.value,
                            child: _SettingsSwitchTile(
                              icon: CupertinoIcons.bell_fill,
                              title: 'Notifications',
                              isOn: controller.notificationsEnabled.value,
                              iconColor: const Color(0xFF0A84FF),
                              iconBgColor: const Color(0xFFDDEEFF),
                              onChange: controller.toggleNotifications,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),
                    _SectionLabel(title: 'ACCOUNT', isDark: isDark),
                    const SizedBox(height: 10),

                    _GlassGroup(
                      isDark: isDark,
                      children: [
                        _SettingsNavigationTile(
                          icon: CupertinoIcons.square_arrow_right,
                          title: 'Log Out',
                          iconColor: const Color(0xFFEF4444),
                          iconBgColor: const Color(0xFFFFE8E8),
                          isDark: isDark,
                          onTap: () => _handleLogoutTap(controller),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _sheetDecoration(bool isDark, double radius) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: isDark
            ? [
                const Color(0xFF1E293B).withAlpha(224),
                const Color(0xFF0F172A).withAlpha(212),
              ]
            : [
                Colors.white.withAlpha(236),
                const Color(0xFFF4F8FD).withAlpha(220),
              ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      border: Border.all(
        color: isDark
            ? Colors.white.withAlpha(26)
            : Colors.white.withAlpha(175),
        width: 1.1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 128 : 34),
          blurRadius: 34,
          offset: const Offset(0, -10),
        ),
      ],
    );
  }
}

void showSettingsBottomSheet(BuildContext context) {
  final mainController = Get.isRegistered<MainController>()
      ? Get.find<MainController>()
      : null;
  final newMainController = Get.isRegistered<NewMainController>()
      ? Get.find<NewMainController>()
      : null;
  mainController?.hideBottomBar();
  newMainController?.hideBottomBar();

  final isApplePlatform =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  if (isApplePlatform) {
    showCupertinoModalPopup<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withAlpha(62),
      builder: (popupContext) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                  child: Container(color: Colors.transparent),
                ),
              ),
              SettingsBottomSheet(parentContext: context, isAppleStyle: true),
            ],
          ),
        );
      },
    ).whenComplete(() {
      mainController?.showBottomBar();
      newMainController?.showBottomBar();
    });

    return;
  }

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(72),
    isScrollControlled: true,
    useSafeArea: false,
    builder: (_) =>
        SettingsBottomSheet(parentContext: context, isAppleStyle: false),
  ).whenComplete(() {
    mainController?.showBottomBar();
    newMainController?.showBottomBar();
  });
}

class _DragHandle extends StatelessWidget {
  final bool isDark;

  const _DragHandle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(70)
            : const Color(0xFFB8BEC8).withAlpha(210),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final bool isDark;

  const _CloseButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withAlpha(24)
              : Colors.white.withAlpha(170),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(28)
                : Colors.white.withAlpha(210),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.xmark,
          size: 22,
          color: isDark ? Colors.white.withAlpha(225) : const Color(0xFF111827),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionLabel({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        height: 1,
        letterSpacing: 0.95,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white.withAlpha(126) : const Color(0xFF748093),
      ),
    );
  }
}

class _GlassGroup extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _GlassGroup({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withAlpha(18)
                : Colors.white.withAlpha(142),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(24)
                  : Colors.white.withAlpha(175),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 38 : 10),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _TileDivider extends StatelessWidget {
  final bool isDark;

  const _TileDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 74, right: 18),
      child: Container(
        height: 0.7,
        color: isDark
            ? Colors.white.withAlpha(18)
            : const Color(0xFFDCE3EC).withAlpha(190),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isOn;
  final Color iconColor;
  final Color iconBgColor;
  final ValueChanged<bool> onChange;
  final bool isDark;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.isOn,
    required this.iconColor,
    required this.iconBgColor,
    required this.onChange,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            _SettingsIconBox(
              icon: icon,
              iconColor: iconColor,
              iconBgColor: iconBgColor,
              isDark: isDark,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.1,
                  letterSpacing: -0.15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            Transform.scale(
              scale: 0.88,
              child: CupertinoSwitch(
                value: isOn,
                onChanged: onChange,
                activeTrackColor: cPrimary,
                inactiveTrackColor: isDark
                    ? Colors.white.withAlpha(40)
                    : const Color(0xFFD8DDE5),
                thumbColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsNavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;
  final Color iconBgColor;
  final bool isDark;
  final VoidCallback onTap;

  const _SettingsNavigationTile({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.iconBgColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              _SettingsIconBox(
                icon: icon,
                iconColor: iconColor,
                iconBgColor: iconBgColor,
                isDark: isDark,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.1,
                    letterSpacing: -0.15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 22,
                color: isDark
                    ? Colors.white.withAlpha(112)
                    : const Color(0xFF8B95A5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsIconBox extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final bool isDark;

  const _SettingsIconBox({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white.withAlpha(20) : iconBgColor,
        border: Border.all(
          color: isDark
              ? Colors.white.withAlpha(22)
              : Colors.white.withAlpha(90),
          width: 1,
        ),
      ),
      child: Icon(
        icon,
        size: 21,
        color: isDark ? Colors.white.withAlpha(214) : iconColor,
      ),
    );
  }
}
