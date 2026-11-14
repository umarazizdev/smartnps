import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool _isConnected = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isConnected => _isConnected;

  ConnectivityService() {
    _initialize();
  }

  void _initialize() {
    // Check initial connection status
    checkConnection();

    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        debugPrint('🌐 Connectivity changed: $results');
        _updateConnectionStatus(results);
      },
      onError: (error) {
        debugPrint('❌ Connectivity error: $error');
        _isConnected = false;
        _connectionStatusController.add(false);
      },
    );
  }

  Future<void> checkConnection() async {
    try {
      final List<ConnectivityResult> results = await _connectivity
          .checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      _isConnected = false;
      _connectionStatusController.add(false);
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    // Check if any result is not 'none'
    final hasConnection =
        results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);

    debugPrint('📡 Connection status: $hasConnection (from $results)');

    if (_isConnected != hasConnection) {
      _isConnected = hasConnection;
      _connectionStatusController.add(hasConnection);
      debugPrint('✅ Connection changed to: $hasConnection');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _connectionStatusController.close();
  }
}
