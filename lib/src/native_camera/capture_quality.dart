enum CaptureQuality {

  maximum,

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
