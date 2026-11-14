import 'package:get/get.dart';

class PasswordVisibilityController extends GetxController {
  RxBool isVisible = false.obs;

  void toggleVisibility() {
    isVisible.value = !isVisible.value;
  }
}
