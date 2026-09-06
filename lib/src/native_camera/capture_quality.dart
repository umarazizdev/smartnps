enum CaptureQuality {
  /// Highest practical still / video quality for evidence capture.
  maximum,

  /// Prefer quality but allow smaller files when the device struggles.
  balanced,
}

extension CaptureQualityCodec on CaptureQuality {
  String get wireName => switch (this) {
    CaptureQuality.maximum => 'maximum',
    CaptureQuality.balanced => 'balanced',
  };

  static CaptureQuality parse(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    return switch (value) {
      'balanced' => CaptureQuality.balanced,
      _ => CaptureQuality.maximum,
    };
  }
}
