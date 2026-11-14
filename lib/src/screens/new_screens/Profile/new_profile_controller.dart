import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NewProfileController extends GetxController {
  final name = 'Hamid Khan'.obs;
  final role = 'Security Officer'.obs;
  final phone = '+1 555 0100'.obs;
  final email = 'hamid.khan@smartnps360.com'.obs;
  final active = true.obs;

  final nameCtrl = TextEditingController(text: 'Hamid Khan');
  final phoneCtrl = TextEditingController(text: '+1 555 0100');
  final emailCtrl = TextEditingController(text: 'hamid.khan@smartnps360.com');

  String get initials => name.value.split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase();

  @override
  void onClose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    super.onClose();
  }

  void saveProfile() {
    final n = nameCtrl.text.trim();
    if (n.isNotEmpty) name.value = n;
    phone.value = phoneCtrl.text.trim();
    email.value = emailCtrl.text.trim();
    Get.back();
  }

  void openEditDialog() {
    nameCtrl.text = name.value;
    phoneCtrl.text = phone.value;
    emailCtrl.text = email.value;
  }
}
