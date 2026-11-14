import 'package:get/get.dart';

class NoShiftSessionController extends GetxController {
  final RxBool noShiftDialogShown = false.obs;

  bool markNoShiftShown() {
    if (noShiftDialogShown.value) return false;
    noShiftDialogShown.value = true;
    return true;
  }

  void reset() {
    noShiftDialogShown.value = false;
  }
}
