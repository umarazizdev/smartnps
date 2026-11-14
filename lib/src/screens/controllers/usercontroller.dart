import 'dart:developer' as developer;
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/app_storage.dart';
import 'package:smartnps360/src/screens/models/user_model.dart';
import 'package:smartnps360/src/screens/native_auth_session.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';

class UserController extends GetxController {
  final ApiService _apiService = ApiService();

  final user = Rx<UserModel?>(null);
  final profileData = Rx<Map<String, dynamic>?>(null);
  final isLoading = false.obs;
  final errorMessage = Rx<String?>(null);

  bool _hasFetched = false;
  Future<void>? _fetchFuture;

  bool get _hasValidSession {
    return NativeAuthSession.instance.hasValidSessionSync;
  }

  @override
  void onInit() {
    super.onInit();
    _loadStoredUser();
  }

  void _loadStoredUser() {
    final storedUser = box.read('userInfo');
    if (storedUser is Map) {
      final parsed = UserModel.fromJson(Map<String, dynamic>.from(storedUser));
      _setUser(parsed, saveToStorage: false);
    }
  }

  UserModel? _parseProfileData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return UserModel.fromJson(data);
    }

    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        return UserModel.fromJson(first);
      }
    }

    errorMessage.value = 'Invalid profile data format';
    developer.log(
      'Unexpected profile data type: ${data.runtimeType}',
      name: 'UserController',
    );
    return null;
  }

  void _setUser(UserModel parsed, {required bool saveToStorage}) {
    user.value = parsed;
    profileData.value = parsed.toProfileMap();
    _hasFetched = true;
    errorMessage.value = null;

    if (saveToStorage) {
      box.write('userId', parsed.id);
      box.write('userInfo', parsed.toJson());
      box.write('profileData', parsed.toProfileMap());
    }
  }

  void setProfileFromLoginResponse(Map<String, dynamic> userData) {
    final parsed = UserModel.fromJson(userData);
    _setUser(parsed, saveToStorage: true);
  }

  Future<void> fetchProfileData({
    bool forceRefresh = false,
    bool enableLoading = true,
    bool showEasyLoading = false,
  }) async {
    if (!_hasValidSession) return;

    if (!forceRefresh && _hasFetched) return;

    if (_fetchFuture != null) {
      if (!forceRefresh) return _fetchFuture!;
      await _fetchFuture;
    }

    errorMessage.value = null;

    _fetchFuture = (() async {
      try {
        if (enableLoading) isLoading.value = true;
        if (showEasyLoading) EasyLoading.show();

        final data = await _apiService.getData(
          'users/profile',
          requiresAuth: true,
        );

        final parsed = _parseProfileData(data);

        if (parsed != null) {
          _setUser(parsed, saveToStorage: true);
          developer.log('Profile data fetched', name: 'UserController');
        }
      } catch (e, stackTrace) {
        errorMessage.value = 'Failed to fetch profile: $e';
        developer.log(
          errorMessage.value!,
          name: 'UserController',
          error: e,
          stackTrace: stackTrace,
        );
      } finally {
        if (showEasyLoading) EasyLoading.dismiss();
        if (enableLoading) isLoading.value = false;
      }
    })();

    try {
      await _fetchFuture;
    } finally {
      _fetchFuture = null;
    }
  }

  Future<void> fetchProfileDataAfterLogin() async {
    await fetchProfileData(
      forceRefresh: true,
      enableLoading: true,
      showEasyLoading: false,
    );
  }

  void clearProfile() {
    user.value = null;
    profileData.value = null;
    _hasFetched = false;
    errorMessage.value = null;
  }
}
