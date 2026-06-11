import 'package:geolocator/geolocator.dart';

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
    try {
      final dynamic p = position;
      final dynamic sourceInformation = p.sourceInformation;
      return sourceInformation?.isSimulatedBySoftware == true;
    } catch (_) {
      return false;
    }
  }

  static MockLocationFlags flagsFor(Position position) {
    return MockLocationFlags(
      isMocked: position.isMocked,
      isSimulatedBySoftware: isSimulatedBySoftware(position),
    );
  }

  static bool isDetected(Position position) => flagsFor(position).isDetected;
}
