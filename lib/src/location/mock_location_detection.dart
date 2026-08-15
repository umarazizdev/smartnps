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
    return MockLocationFlags(
      isMocked: position.isMocked,
      isSimulatedBySoftware: isSimulatedBySoftware(position),
    );
  }

  static bool isDetected(Position position) => flagsFor(position).isDetected;
}
