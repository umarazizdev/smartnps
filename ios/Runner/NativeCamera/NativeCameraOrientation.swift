import AVFoundation
import ImageIO
import UIKit

/// Landscape validation and EXIF / CGImage orientation helpers for visit captures.
enum NativeCameraOrientation {
  static let logPrefix = "[SmartNPS360Camera]"

  /// Degrees clockwise from upright portrait (0 / 90 / 180 / 270).
  static func degrees(from cgOrientation: CGImagePropertyOrientation) -> Int {
    switch cgOrientation {
    case .up, .upMirrored:
      return 0
    case .right, .rightMirrored:
      return 90
    case .down, .downMirrored:
      return 180
    case .left, .leftMirrored:
      return 270
    }
  }

  static func cgOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch uiOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }

  static func cgOrientation(from captureOrientation: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
    switch captureOrientation {
    case .portrait:
      return .right
    case .portraitUpsideDown:
      return .left
    case .landscapeRight:
      // Device home button / Dynamic Island on the right → landscape left content.
      return .down
    case .landscapeLeft:
      return .up
    @unknown default:
      return .up
    }
  }

  /// Maps interface orientation to the capture connection orientation.
  static func videoOrientation(
    from interfaceOrientation: UIInterfaceOrientation
  ) -> AVCaptureVideoOrientation {
    switch interfaceOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    case .unknown:
      return .landscapeRight
    @unknown default:
      return .landscapeRight
    }
  }

  static func currentInterfaceOrientation() -> UIInterfaceOrientation {
    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      if let orientation = scenes.first(where: { $0.activationState == .foregroundActive })?
        .interfaceOrientation
      {
        return orientation
      }
      if let orientation = scenes.first?.interfaceOrientation {
        return orientation
      }
    }
    return .landscapeRight
  }

  static func isInterfaceLandscape(_ orientation: UIInterfaceOrientation) -> Bool {
    orientation == .landscapeLeft || orientation == .landscapeRight
  }

  /// Effective display size after applying EXIF orientation metadata.
  static func orientedSize(pixelWidth: Int, pixelHeight: Int, orientationDegrees: Int) -> CGSize {
    let rotated = orientationDegrees == 90 || orientationDegrees == 270
    if rotated {
      return CGSize(width: pixelHeight, height: pixelWidth)
    }
    return CGSize(width: pixelWidth, height: pixelHeight)
  }

  static func isLandscapeSize(_ size: CGSize) -> Bool {
    size.width > size.height
  }

  /// Reads EXIF orientation and pixel dimensions from still-image file data.
  static func readPhotoMetadata(at url: URL) -> (width: Int, height: Int, degrees: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
      return nil
    }

    let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let rawOrientation =
      (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
      ?? CGImagePropertyOrientation.up.rawValue
    let cgOrientation =
      CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
    let degrees = degrees(from: cgOrientation)
    guard width > 0, height > 0 else { return nil }
    return (width, height, degrees)
  }

  /// Validates that a saved photo is landscape after EXIF rotation.
  /// FAIL CLOSED: missing metadata rejects the capture.
  static func isLandscapePhoto(at url: URL) -> Bool {
    guard let meta = readPhotoMetadata(at: url) else {
      NSLog("\(logPrefix) photo metadata unavailable; fail-closed landscape")
      return false
    }
    let size = orientedSize(
      pixelWidth: meta.width,
      pixelHeight: meta.height,
      orientationDegrees: meta.degrees
    )
    let landscape = isLandscapeSize(size)
    NSLog(
      "\(logPrefix) photo landscape check "
        + "px=\(meta.width)x\(meta.height) deg=\(meta.degrees) "
        + "display=\(Int(size.width))x\(Int(size.height)) ok=\(landscape)"
    )
    return landscape
  }

  /// Validates video track preferred transform + natural size produce landscape.
  /// FAIL CLOSED: missing track rejects the capture.
  static func isLandscapeVideo(at url: URL) -> Bool {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
      NSLog("\(logPrefix) video track missing; fail-closed landscape")
      return false
    }
    let size = track.naturalSize.applying(track.preferredTransform)
    let width = abs(size.width)
    let height = abs(size.height)
    let landscape = width > height
    NSLog(
      "\(logPrefix) video landscape check "
        + "display=\(Int(width))x\(Int(height)) ok=\(landscape)"
    )
    return landscape
  }

  static func videoOrientationDegrees(at url: URL) -> Int {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else { return 0 }
    let transform = track.preferredTransform
    if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
      return 90
    }
    if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
      return 270
    }
    if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
      return 180
    }
    return 0
  }

  static func videoDisplaySize(at url: URL) -> (width: Int, height: Int)? {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else { return nil }
    let size = track.naturalSize.applying(track.preferredTransform)
    let width = Int(abs(size.width).rounded())
    let height = Int(abs(size.height).rounded())
    guard width > 0, height > 0 else { return nil }
    return (width, height)
  }

  static func videoDurationMs(at url: URL) -> Int {
    let asset = AVURLAsset(url: url)
    let seconds = CMTimeGetSeconds(asset.duration)
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return Int((seconds * 1000).rounded())
  }
}
