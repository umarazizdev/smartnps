import 'dart:async';
import 'package:get/get.dart';
import '../new_models.dart';
import 'new_dashboard_controller.dart';

class NewDashboardDialController extends GetxController {
  final title = 'Upcoming Shift'.obs;
  final subtitle = 'BayCrest'.obs;
  final fading = false.obs;

  Timer? _timer;
  int _state = 1;
  Worker? _statusWorker;
  late final NewDashboardController dashboard;

  @override
  void onInit() {
    super.onInit();
    dashboard = Get.find<NewDashboardController>();
    _applyState();
    _statusWorker = ever<NewOfficerStatus>(dashboard.status, (_) => _applyState());
    _timer = Timer.periodic(const Duration(milliseconds: 4500), (_) => _rotate());
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
    if (_state == 0) {
      title.value = dashboard.status.value == NewOfficerStatus.standby ? 'Upcoming Shift' : 'Current Shift';
      subtitle.value = dashboard.selectedSite.value;
      return;
    }
    if (_state == 1) {
      title.value = 'Schedule';
      subtitle.value = '9 AM – 5 PM · 8hr';
      return;
    }
    title.value = 'Tuesday';
    subtitle.value = 'May 19, 2026';
  }
}
