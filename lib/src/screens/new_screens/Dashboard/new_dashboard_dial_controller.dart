import 'dart:async';
import 'package:get/get.dart';
import '../new_models.dart';
import 'new_dashboard_controller.dart';

class NewDashboardDialController extends GetxController {
  final title = 'Upcoming Shift'.obs;
  final subtitle = 'BayCrest'.obs;
  final fading = false.obs;

  Timer? _timer;
  int _state = 0;
  Worker? _statusWorker;
  late final NewDashboardController dashboard;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void onInit() {
    super.onInit();
    dashboard = Get.find<NewDashboardController>();
    _applyState();
    _statusWorker =
        ever<NewOfficerStatus>(dashboard.status, (_) => _applyState());
    _timer =
        Timer.periodic(const Duration(milliseconds: 4500), (_) => _rotate());
  }

  @override
  void onClose() {
    _timer?.cancel();
    _statusWorker?.dispose();
    super.onClose();
  }

  void _rotate() {
    fading.value = true;
    Future.delayed(const Duration(milliseconds: 620), () {
      if (isClosed) return;
      _state = (_state + 1) % 3;
      _applyState();
      fading.value = false;
    });
  }

  void _applyState() {
    final start = dashboard.scheduledShiftStart;
    if (_state == 0) {
      title.value =
          dashboard.hasActiveDuty && dashboard.status.value != NewOfficerStatus.standby
              ? 'Current Shift'
              : 'Upcoming Shift';
      subtitle.value = dashboard.selectedSite.value;
      return;
    }
    if (_state == 1) {
      title.value = 'Schedule';
      subtitle.value = dashboard.selectedShift.value;
      return;
    }
    title.value = _weekdays[start.weekday - 1];
    subtitle.value =
        '${_months[start.month - 1]} ${start.day}, ${start.year}';
  }
}
