import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../utilities/app_config.dart';

class MockLocationFlags {
  const MockLocationFlags({
    required this.isMocked,
    required this.isSimulatedBySoftware,
  });

  final bool isMocked;
  final bool isSimulatedBySoftware;

  bool get isDetected => isMocked || isSimulatedBySoftware;
}

class MockLocationDetection {
  MockLocationDetection._();

  static bool? _isPhysicalDevice;

  /// Simulator / non-physical devices always report software-simulated GPS.
  static bool get ignoreSimulatedSoftwareFlag => _isPhysicalDevice == false;

  static Future<void> warmDeviceClass() async {
    if (_isPhysicalDevice != null) return;
    try {
      if (Platform.isIOS) {
        final ios = await DeviceInfoPlugin().iosInfo;
        _isPhysicalDevice = ios.isPhysicalDevice;
      } else if (Platform.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        _isPhysicalDevice = android.isPhysicalDevice;
      } else {
        _isPhysicalDevice = true;
      }
    } catch (_) {
      _isPhysicalDevice = true;
    }
  }

  static bool isSimulatedBySoftware(Position position) {
    if (!AppConfig.enableMockLocationDetection) return false;
    try {
      final dynamic p = position;
      final dynamic sourceInformation = p.sourceInformation;
      return sourceInformation?.isSimulatedBySoftware == true;
    } catch (_) {
      return false;
    }
  }

  static MockLocationFlags flagsFor(Position position) {
    if (!AppConfig.enableMockLocationDetection) {
      return const MockLocationFlags(
        isMocked: false,
        isSimulatedBySoftware: false,
      );
    }

    final mocked = position.isMocked;
    var simulated = isSimulatedBySoftware(position);

    // iOS Simulator / Xcode GPX always reports simulated software locations.
    // Only treat that flag as a block on physical devices.
    if (simulated && ignoreSimulatedSoftwareFlag) {
      simulated = false;
    }

    return MockLocationFlags(
      isMocked: mocked,
      isSimulatedBySoftware: simulated,
    );
  }

  static bool isDetected(Position position) => flagsFor(position).isDetected;
}
