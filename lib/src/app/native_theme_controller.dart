import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NativeThemeController extends GetxController {
  NativeThemeController._();

  static final NativeThemeController instance = NativeThemeController._();

  final Rx<ThemeMode> nativeThemeMode = ThemeMode.light.obs;

  bool get isDark => nativeThemeMode.value == ThemeMode.dark;

  void setDark(bool isDark) {
    final next = isDark ? ThemeMode.dark : ThemeMode.light;
    if (nativeThemeMode.value == next) return;
    nativeThemeMode.value = next;
  }
}
