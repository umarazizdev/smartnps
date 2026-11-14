// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:smartnps360/src/screens/main_screens/DARScreen/appoverlayfield.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'darcontroller.dart';
import 'package:smartnps360/src/screens/controllers/memory_storage_controller.dart';

class CreatDARScreen extends StatefulWidget {
  const CreatDARScreen({super.key});

  @override
  State<CreatDARScreen> createState() => _CreatDARScreenState();
}

class _CreatDARScreenState extends State<CreatDARScreen> {
  final DARController _darCtrl = Get.put(DARController());
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _policeReportController = TextEditingController();
  final TextEditingController _managerNameController = TextEditingController();
  final FocusNode _siteFocusNode = FocusNode();
  late final MemoryStorageController _mem;

  @override
  void initState() {
    super.initState();
    _mem = Get.isRegistered<MemoryStorageController>()
        ? Get.find<MemoryStorageController>()
        : Get.put(MemoryStorageController());
  }

  @override
  void dispose() {
    _policeReportController.dispose();
    _managerNameController.dispose();
    _siteFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = MediaQuery.of(context).size.width;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (FocusManager.instance.primaryFocus != null &&
            FocusManager.instance.primaryFocus!.hasFocus) {
          FocusManager.instance.primaryFocus?.unfocus();
        } else {
          Get.back();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? cDarkBackground : cMainBg,
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, w),
                    const SizedBox(height: 20),
                    _buildForm(context),
                  ],
                ),
              ),
              Obx(
                () => _darCtrl.isSubmitting.value
                    ? Container(
                        color: Colors.black.withAlpha(isDark ? 166 : 128),
                        child: const Center(child: CircularProgressIndicator()),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double w) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        InkWell(
          overlayColor: WidgetStatePropertyAll(cTransparent),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Get.back();
          },
          child: Container(
            padding: EdgeInsets.all(w * 0.03),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 51 : 26),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              color: isDark ? cDarkCardColor : cWhite,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back_ios_rounded,
              size: w * 0.06,
              color: isDark ? cDarkIconColor : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            "Create Daily Activity Report",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: isDark ? cDarkTextPrimary : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userRole = box.read('role');
    final isOnSiteOfficer =
        userRole != null && userRole is String && userRole == onSiteOfficer;

    return Stack(
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              if (isOnSiteOfficer)
                TextFormField(
                  controller: TextEditingController(text: _mem.getSiteName()),
                  readOnly: true,
                  style: TextStyle(
                    color: isDark ? cDarkTextPrimary : Colors.black87,
                  ),
                  decoration: _inputDecoration("Site"),
                ),
              const SizedBox(height: 18),
              InkWell(
                onTap: () => _pickReportDateTime(context),
                child: Obx(() {
                  return InputDecorator(
                    decoration: _inputDecoration("Report Time"),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Semantics(
                          label: "Report date and time",
                          child: Text(
                            DateFormat(
                              'MM/dd/yyyy hh:mm a',
                              Localizations.localeOf(context).toString(),
                            ).format(_darCtrl.reportDateTime.value),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? cDarkTextPrimary : Colors.black87,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: isDark ? cDarkIconColor : null,
                        ),
                      ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),

              Obx(() {
                const items = ["All Good", "Moderate", "Critical", "Incident"];
                final selected = _darCtrl.seriousness.value;

                final safeValue = items.contains(selected)
                    ? selected
                    : items.first;

                return AppOverlayDropdownFormField(
                  labelText: "Seriousness",
                  hintText: "Select level...",
                  items: items,
                  value: safeValue,
                  decoration: _inputDecoration(
                    "Seriousness",
                    "Select level...",
                  ),
                  onChanged: (v) {
                    if (v != null) _darCtrl.setSeriousness(v);
                  },

                  menuHorizontalMargin: 16,
                  maxMenuHeight: 220,
                );
              }),

              const SizedBox(height: 18),
              _buildIncidentReportSection(context),
              const SizedBox(height: 6),

              TextFormField(
                onChanged: _darCtrl.setReportDetails,
                maxLines: 4,
                style: TextStyle(
                  color: isDark ? cDarkTextPrimary : Colors.black87,
                ),
                decoration: _inputDecoration(
                  "Report Details",
                  "Write details here...",
                ),
              ),
              const SizedBox(height: 18),

              Obx(() {
                final isLoading = _darCtrl.isLoadingActivityTypes.value;
                final items = _darCtrl.activityTypes;
                final selected = _darCtrl.selectedActivityType.value;

                if (isLoading) {
                  return AppOverlayDropdownFormField(
                    labelText: "Activity Type",
                    hintText: "Loading...",
                    items: const [],
                    value: null,
                    isLoading: true,
                    enabled: false,
                    decoration: _inputDecoration("Activity Type", "Loading..."),
                    onChanged: (_) {},
                    menuHorizontalMargin: 16,
                  );
                }

                if (items.isEmpty) {
                  return AppOverlayDropdownFormField(
                    labelText: "Activity Type",
                    hintText: "No activity types available",
                    items: const [],
                    value: null,
                    enabled: false,
                    isEmptyAfterLoad: true,
                    decoration: _inputDecoration(
                      "Activity Type",
                      "No activity types available",
                    ),
                    onChanged: (_) {},
                    menuHorizontalMargin: 16,
                  );
                }

                final safeValue = items.contains(selected)
                    ? selected
                    : items.first;
                if (safeValue != selected) {
                  _darCtrl.selectedActivityType.value = safeValue;
                }

                return AppOverlayDropdownFormField(
                  labelText: "Activity Type",
                  hintText: "Select activity type...",
                  items: items,
                  value: safeValue,
                  decoration: _inputDecoration(
                    "Activity Type",
                    "Select activity type...",
                  ),
                  onChanged: (v) {
                    if (v != null) _darCtrl.setActivityType(v);
                  },
                  menuHorizontalMargin: 16,
                  maxMenuHeight: 260,
                );
              }),
              const SizedBox(height: 18),

              _buildPhotoSection(context),

              const SizedBox(height: 24),
              _buildSubmitButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Photos (unlimited)",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isDark ? cDarkTextPrimary : null,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => _darCtrl.openDARCamera(),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text("Upload Files"),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? cDarkInputFillColor
                    : const Color(0xFFF3F4F6),
                foregroundColor: isDark ? cDarkTextPrimary : Colors.black87,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Obx(
              () => Text(
                _darCtrl.photos.isEmpty
                    ? "No file chosen"
                    : "${_darCtrl.photos.length} file(s)",
                style: TextStyle(
                  color: isDark ? cDarkTextSecondary : Colors.black54,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Obx(() {
          if (_darCtrl.photos.isEmpty) return const SizedBox();
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(_darCtrl.photos.length, (index) {
              final photo = _darCtrl.photos[index];
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        barrierColor: Colors.black.withAlpha(
                          isDark ? 217 : 242,
                        ),
                        builder: (_) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: InteractiveViewer(
                              child: Image.file(photo, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        photo,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -10,
                    top: -10,
                    child: GestureDetector(
                      onTap: () => _darCtrl.removePhoto(index),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isDark ? cDarkDividerColor : Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          );
        }),
      ],
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        final ok = _formKey.currentState?.validate() ?? false;
        if (!ok) return;
        _darCtrl.submitDAR();
      },
      child: Container(
        height: 45,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3B82F6) : cPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            "Submit Report",
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, [String? hintText]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: isDark ? cDarkInputFillColor : cWhite,
      labelStyle: TextStyle(
        color: isDark ? cDarkTextPrimary : Colors.black87,
        fontSize: 13.5,
      ),
      hintStyle: TextStyle(
        color: isDark ? cDarkTextSecondary : Colors.black54,
        fontSize: 13.5,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? cDarkBorderColor : cBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? cDarkBorderColor : cBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF3B82F6) : cPrimary,
          width: 1.6,
        ),
      ),
    );
  }

  Future<void> _pickReportDateTime(BuildContext ctx) async {
    try {
      final initial = _darCtrl.reportDateTime.value;

      final minDate = DateTime(2020);
      final maxDate = DateTime(2100, 12, 31, 23, 59);

      final safeInitial = initial.isBefore(minDate)
          ? minDate
          : initial.isAfter(maxDate)
          ? maxDate
          : initial;

      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

      if (isIOS) {
        DateTime tempPicked = safeInitial;

        final DateTime? picked = await showCupertinoModalPopup<DateTime>(
          context: ctx,
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              height: 340,
              decoration: BoxDecoration(
                color: isDark ? cDarkCardColor : cWhite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: isDark
                                    ? cDarkTextSecondary
                                    : const Color(0xFF6B7280),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            'Report Date & Time',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? cDarkTextPrimary : cDarkText,
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context, tempPicked),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: cPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? cDarkBorderColor
                          : const Color(0xFFE5EAF1),
                    ),
                    Expanded(
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.dateAndTime,
                        initialDateTime: safeInitial,
                        minimumDate: minDate,
                        maximumDate: maxDate,
                        use24hFormat: false,
                        onDateTimeChanged: (DateTime value) {
                          tempPicked = value;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (picked == null) return;

        _darCtrl.setReportDateTime(
          DateTime(
            picked.year,
            picked.month,
            picked.day,
            picked.hour,
            picked.minute,
          ),
        );

        return;
      }

      final date = await showDatePicker(
        context: ctx,
        initialDate: safeInitial,
        firstDate: minDate,
        lastDate: maxDate,
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme:
                  (isDark
                          ? const ColorScheme.dark()
                          : const ColorScheme.light())
                      .copyWith(
                        primary: cPrimary,
                        surface: isDark ? cDarkCardColor : cWhite,
                        onSurface: isDark ? cDarkTextPrimary : cDarkText,
                      ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(foregroundColor: cPrimary),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: isDark ? cDarkCardColor : cWhite,
              ),
            ),
            child: child!,
          );
        },
      );

      if (date == null) return;

      final time = await showTimePicker(
        context: ctx,
        initialTime: TimeOfDay.fromDateTime(safeInitial),
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Theme(
            data: Theme.of(context).copyWith(
              timePickerTheme: TimePickerThemeData(
                dialHandColor: cPrimary,
                hourMinuteTextColor: WidgetStateColor.resolveWith(
                  (_) => isDark ? cDarkTextPrimary : Colors.black87,
                ),
                dayPeriodColor: cPrimary.withAlpha(26),
                backgroundColor: isDark ? cDarkCardColor : cWhite,
                dialBackgroundColor: isDark ? cDarkInputFillColor : null,
              ),
            ),
            child: child!,
          );
        },
      );

      if (time == null) return;

      _darCtrl.setReportDateTime(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    } catch (e) {
      debugPrint('Date/time picker error: $e');
    }
  }

  Widget _buildIncidentReportSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final enabled = _darCtrl.seriousness.value == "Incident";
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!enabled)
            const SizedBox.shrink()
          else ...[
            _buildYesNoRadioRow(
              title: "Police Notified",
              value: _darCtrl.policeNotified.value,
              onChanged: (v) {
                _darCtrl.setPoliceNotified(v);
                if (!v) _policeReportController.clear();
              },
            ),
            if (_darCtrl.policeNotified.value) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _policeReportController,
                onChanged: _darCtrl.setPoliceReportNumber,
                style: TextStyle(
                  color: isDark ? cDarkTextPrimary : Colors.black87,
                ),
                decoration: _inputDecoration(
                  "Police Report Number",
                  "Enter police report number...",
                ),
              ),
            ],

            const SizedBox(height: 14),

            _buildYesNoRadioRow(
              title: "Manager Notification",
              value: _darCtrl.managerNotified.value,
              onChanged: (v) {
                _darCtrl.setManagerNotified(v);
                if (!v) _managerNameController.clear();
              },
            ),
            if (_darCtrl.managerNotified.value) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _managerNameController,
                onChanged: _darCtrl.setManagerName,
                style: TextStyle(
                  color: isDark ? cDarkTextPrimary : Colors.black87,
                ),
                decoration: _inputDecoration(
                  "Manager Name",
                  "Enter manager name...",
                ),
              ),
            ],
          ],
          SizedBox(height: 12),
        ],
      );
    });
  }

  Widget _buildYesNoRadioRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: isDark ? cDarkTextPrimary : null,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _radioOption(
              label: "Yes",
              groupValue: value,
              radioValue: true,
              onChanged: (v) => onChanged(true),
            ),
            const SizedBox(width: 18),
            _radioOption(
              label: "No",
              groupValue: value,
              radioValue: false,
              onChanged: (v) => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _radioOption({
    required String label,
    required bool groupValue,
    required bool radioValue,
    required ValueChanged<bool?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      onTap: () => onChanged(radioValue),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<bool>(
            value: radioValue,
            groupValue: groupValue,
            onChanged: onChanged,
            activeColor: isDark ? const Color(0xFF3B82F6) : cPrimary,
            fillColor: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.selected)) {
                return isDark ? const Color(0xFF3B82F6) : cPrimary;
              }
              return isDark ? cDarkTextSecondary : cDarkGreyclr;
            }),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? cDarkTextSecondary : null,
            ),
          ),
        ],
      ),
    );
  }
}
