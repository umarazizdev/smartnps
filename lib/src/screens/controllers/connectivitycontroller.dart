import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/services/connectivityservice.dart';

class ConnectivityController extends GetxController {
  final ConnectivityService _connectivityService = ConnectivityService();

  final RxBool isConnected = true.obs;
  StreamSubscription<bool>? _statusSubscription;

  @override
  void onInit() {
    super.onInit();
    // Initialize with current connection status
    isConnected.value = _connectivityService.isConnected;
    debugPrint('🎯 Initial connection: ${isConnected.value}');

    // Listen to connection changes
    _statusSubscription = _connectivityService.connectionStatus.listen((
      status,
    ) {
      debugPrint('🔄 Connection update in controller: $status');
      isConnected.value = status;
    });
  }

  Future<void> checkConnection() async {
    debugPrint('🔍 Manual connection check triggered');
    await _connectivityService.checkConnection();
    isConnected.value = _connectivityService.isConnected;
    debugPrint('✨ Connection status after check: ${isConnected.value}');
  }

  @override
  void onClose() {
    _statusSubscription?.cancel();
    _connectivityService.dispose();
    super.onClose();
  }
}
