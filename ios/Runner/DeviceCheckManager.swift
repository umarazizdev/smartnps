import DeviceCheck
import Flutter
import Foundation

/// Generates Apple DeviceCheck tokens for backend fraud / device-block validation.
final class DeviceCheckManager {
  static let methodChannelName = "com.smartnps360.app/device_check"

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(DCDevice.current.isSupported)
    case "generateToken":
      generateToken(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func generateToken(result: @escaping FlutterResult) {
    guard DCDevice.current.isSupported else {
      result(
        FlutterError(
          code: "unsupported",
          message: "DeviceCheck is not supported on this device",
          details: nil
        )
      )
      return
    }

    DCDevice.current.generateToken { data, error in
      if let error = error {
        result(
          FlutterError(
            code: "token_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
        return
      }

      guard let data = data, !data.isEmpty else {
        result(
          FlutterError(
            code: "token_empty",
            message: "DeviceCheck returned an empty token",
            details: nil
          )
        )
        return
      }

      result(data.base64EncodedString())
    }
  }
}
