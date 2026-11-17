import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/widgets/dialogs/location_notice_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartnps360/src/screens/models/application_models.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/services/storage_service.dart';
import 'package:smartnps360/src/screens/main_screens/application_wizard_screen.dart';
import 'package:smartnps360/src/screens/new_screens/new_main_screen.dart';
import 'package:smartnps360/src/screens/widgets/auth_glass_popup.dart';

class AuthController extends GetxController {
  static const _rememberMeKey = 'portalRememberMe';
  static const _rememberEmailKey = 'portalEmail';
  static const _rememberPasswordKey = 'portalPassword';

  final isRegisterTab = false.obs;
  final message = ''.obs;
  final isSuccess = false.obs;
  final isPasswordFieldFocused = false.obs;
  final isInputFocused = false.obs;
  final shouldShowWelcome = true.obs;
  final isLoading = false.obs;
  final rememberMe = false.obs;

  // Form Controllers
  late TextEditingController regFirstNameController;
  late TextEditingController regLastNameController;
  late TextEditingController regEmailController;
  late TextEditingController regPhoneController;
  late TextEditingController regDobController;
  late TextEditingController regPasswordController;
  late TextEditingController regPassword2Controller;
  late TextEditingController loginEmailController;
  late TextEditingController loginPasswordController;

  // Form Keys
  final registerFormKey = GlobalKey<FormState>();
  final loginFormKey = GlobalKey<FormState>();

  // Services
  late StorageService storageService;

  // Lifecycle tracking
  bool _appInitialized = false;

  // Constants
  static const double customKeyboardHeight = 320.0;

  @override
  void onInit() {
    super.onInit();
    _initializeControllers();
    storageService = StorageService();
    loadSavedCredentials();
  }

  void setRememberMe(bool value) {
    rememberMe.value = value;
  }

  Future<void> loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (isClosed) return;
    final savedRememberMe = prefs.getBool(_rememberMeKey) ?? false;
    if (!savedRememberMe) return;

    final email = prefs.getString(_rememberEmailKey) ?? '';
    final password = prefs.getString(_rememberPasswordKey) ?? '';
    if (isClosed) return;

    rememberMe.value = true;
    loginEmailController.text = email;
    loginPasswordController.text = password;
    isRegisterTab.value = false;
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe.value) {
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(
        _rememberEmailKey,
        loginEmailController.text.trim(),
      );
      await prefs.setString(_rememberPasswordKey, loginPasswordController.text);
    } else {
      await prefs.remove(_rememberMeKey);
      await prefs.remove(_rememberEmailKey);
      await prefs.remove(_rememberPasswordKey);
    }
  }

  void _initializeControllers() {
    regFirstNameController = TextEditingController();
    regLastNameController = TextEditingController();
    regEmailController = TextEditingController();
    regPhoneController = TextEditingController();
    regDobController = TextEditingController();
    regPasswordController = TextEditingController();
    regPassword2Controller = TextEditingController();
    loginEmailController = TextEditingController();
    loginPasswordController = TextEditingController();
  }

  @override
  void onClose() {
    regFirstNameController.dispose();
    regLastNameController.dispose();
    regEmailController.dispose();
    regPhoneController.dispose();
    regDobController.dispose();
    regPasswordController.dispose();
    regPassword2Controller.dispose();
    loginEmailController.dispose();
    loginPasswordController.dispose();
    super.onClose();
  }

  Future<void> initializeApp({bool skipAutoLogin = false}) async {
    if (_appInitialized) return;
    _appInitialized = true;

    if (skipAutoLogin) {
      shouldShowWelcome.value = false;
      return;
    }

    try {
      final lastUserId = await storageService.getLastUserId();
      if (lastUserId != null && lastUserId.isNotEmpty) {
        final users = await storageService.loadUsers();
        final user = users[lastUserId];
        if (user != null) {
          shouldShowWelcome.value = false;
          _navigateToApp(user);
          return;
        }
      }
    } catch (e) {
      showMessagePopup(
        'Unable to open saved registration session. Please login again.',
        title: 'Session Error',
      );
      debugPrint('Auto-login error: $e');
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _validateRegisterFields() {
    final firstName = regFirstNameController.text.trim();
    final lastName = regLastNameController.text.trim();
    final email = regEmailController.text.trim();
    final phone = regPhoneController.text.trim();
    final dob = regDobController.text.trim();
    final password = regPasswordController.text;
    final confirm = regPassword2Controller.text;

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        dob.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      showMessagePopup(
        'Please fill in all fields to continue.',
        title: 'Missing Information',
      );
      return false;
    }
    if (!_isValidEmail(email)) {
      showMessagePopup(
        'Please enter a valid email address to continue.',
        title: 'Invalid Email',
      );
      return false;
    }
    if (password.length < 6) {
      showMessagePopup(
        'Password must be at least 6 characters.',
        title: 'Invalid Password',
      );
      return false;
    }
    if (password != confirm) {
      showMessagePopup(
        'Passwords do not match. Please try again.',
        title: 'Password Mismatch',
      );
      return false;
    }
    return true;
  }

  bool _validateLoginFields() {
    final email = loginEmailController.text.trim();
    final password = loginPasswordController.text;
    if (email.isEmpty || password.isEmpty) {
      showMessagePopup(
        'Please enter your email address and password to continue.',
        title: 'Missing Information',
      );
      return false;
    }
    if (!_isValidEmail(email)) {
      showMessagePopup(
        'Please enter a valid email address to continue.',
        title: 'Invalid Email',
      );
      return false;
    }
    return true;
  }

  Future<void> handleRegister() async {
    clearErrors();
    if (!_validateRegisterFields()) return;

    try {
      isLoading.value = true;
      final users = await storageService.loadUsers();
      final email = regEmailController.text.trim();

      final exists = users.values.any(
        (u) => u.email.toLowerCase() == email.toLowerCase(),
      );

      if (exists) {
        showMessagePopup(
          'That email is already registered on this device. Please login instead.',
          title: 'Account Exists',
        );
        return;
      }

      final userId = storageService.generateUserId();
      final profile = ProfileData(
        firstName: regFirstNameController.text.trim(),
        lastName: regLastNameController.text.trim(),
        phone: regPhoneController.text.trim(),
        email: email,
        dob: regDobController.text.trim(),
      );

      final user = UserAccount(
        id: userId,
        email: email,
        password: regPasswordController.text,
        firstName: profile.firstName,
        lastName: profile.lastName,
        phone: profile.phone,
        dob: profile.dob,
        createdAt: DateTime.now().toIso8601String(),
        application: ApplicationData.empty(profile: profile),
      );

      users[userId] = user;
      await storageService.saveUsers(users);
      await storageService.setLastUserId(userId);

      _navigateToApp(user);
    } catch (e) {
      showMessagePopup(
        'Registration failed: ${e.toString()}',
        title: 'Registration Failed',
      );
      debugPrint('Registration error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> handleLogin() async {
    clearErrors();
    if (!_validateLoginFields()) return;

    try {
      isLoading.value = true;
      await _saveCredentials();
      final email = loginEmailController.text.trim();
      await NativeAuthSession.instance.saveLocalSession(email: email);
      Get.offAll(
        () => const NewMainScreen(),
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 300),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final noticeContext = Get.context;
      if (noticeContext != null && noticeContext.mounted) {
        await LocationNoticeDialog.show(noticeContext);
      }
    } catch (e) {
      showMessagePopup('Login failed: ${e.toString()}', title: 'Login Failed');
      debugPrint('Login error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _navigateToApp(UserAccount user) {
    Get.off(
      () => ApplicationWizardScreen(user: user),
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 300),
    );
  }

  void updatePasswordFocusState(bool hasFocus) {
    isPasswordFieldFocused.value = hasFocus;
    if (hasFocus) isInputFocused.value = true;
  }

  void updateInputFocusState(bool hasFocus) {
    isInputFocused.value = hasFocus;
  }

  /// Switch between register and login tabs
  void switchTab(bool isRegister) {
    isRegisterTab.value = isRegister;
    message.value = '';
    clearErrors();
    if (isRegister && shouldShowWelcome.value) {
      _showWelcomeDialog();
    }
  }

  void clearErrors() {
    message.value = '';
    isSuccess.value = false;
  }

  void showMessagePopup(
    String text, {
    String title = 'Notice',
    bool success = false,
  }) {
    message.value = text;
    isSuccess.value = success;
    final context = Get.context;
    if (context == null || text.isEmpty) return;

    AuthGlassPopup.showMessage(
      context,
      title: title,
      message: text,
      success: success,
      onDismissed: clearErrors,
    );
  }

  void clearFormData() {
    regFirstNameController.clear();
    regLastNameController.clear();
    regEmailController.clear();
    regPhoneController.clear();
    regDobController.clear();
    regPasswordController.clear();
    regPassword2Controller.clear();
    loginEmailController.clear();
    loginPasswordController.clear();
  }

  void _showWelcomeDialog() {
    final context = Get.context;
    if (context == null) return;
    shouldShowWelcome.value = false;
    AuthGlassPopup.showWelcomeNotice(context);
  }
}
