enum CaptureType {
  photo,
  video,
}

extension CaptureTypeCodec on CaptureType {
  String get wireName => switch (this) {
    CaptureType.photo => 'photo',
    CaptureType.video => 'video',
  };

  static CaptureType? tryParse(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    return switch (value) {
      'photo' => CaptureType.photo,
      'video' => CaptureType.video,
      _ => null,
    };
  }
}
