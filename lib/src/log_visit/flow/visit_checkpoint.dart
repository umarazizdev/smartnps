import '../../app/app_routes.dart';

class VisitCheckpoint {
  const VisitCheckpoint({
    required this.id,
    required this.name,
    this.siteId,
    this.description,
    this.photoUrl,
    this.photoPath,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.sortOrder = 0,
    this.isActive = true,
    this.timeBound = false,
    this.timeMode,
    this.specificTime,
    this.windowStart,
    this.windowEnd,
  });

  final int id;
  final int? siteId;
  final String name;
  final String? description;
  final String? photoUrl;
  final String? photoPath;
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;
  final int sortOrder;
  final bool isActive;
  final bool timeBound;
  final String? timeMode;
  final String? specificTime;
  final String? windowStart;
  final String? windowEnd;

  bool get hasReferencePhoto {
    final url = photoUrl?.trim();
    return url != null && url.isNotEmpty;
  }

  bool get hasCoordinates => latitude != null && longitude != null;

  String get subtitle {
    final desc = description?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    if (radiusMeters != null) {
      return 'Within ${radiusMeters!.round()}m of checkpoint';
    }
    return 'Capture a clear photo at this checkpoint';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'siteId': siteId,
      'name': name,
      'description': description,
      'photoUrl': photoUrl,
      'photoPath': photoPath,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'sortOrder': sortOrder,
      'isActive': isActive,
      'timeBound': timeBound,
      'timeMode': timeMode,
      'specificTime': specificTime,
      'windowStart': windowStart,
      'windowEnd': windowEnd,
    };
  }

  static VisitCheckpoint? fromJson(
    Map<String, dynamic>? json, {
    String? baseUrl,
  }) {
    if (json == null) return null;
    final id = _int(
      json['site_checkpoint_id'] ??
          json['siteCheckpointId'] ??
          json['checkpoint_id'] ??
          json['checkpointId'] ??
          json['id'],
    );
    if (id == null) return null;

    final name = _string(json['name']) ?? 'Checkpoint $id';
    final photoPath = _extractPhotoPath(json);
    final rawPhotoUrl = _extractPhotoUrl(json);

    return VisitCheckpoint(
      id: id,
      siteId: _int(json['site_id'] ?? json['siteId']),
      name: name,
      description: _string(json['description']),
      photoUrl: resolvePhotoUrl(
        photoUrl: rawPhotoUrl,
        photoPath: photoPath,
        baseUrl: baseUrl,
      ),
      photoPath: photoPath,
      latitude: _double(json['latitude'] ?? json['lat']),
      longitude: _double(json['longitude'] ?? json['lng'] ?? json['lon']),
      radiusMeters: _double(
        json['radius_meters'] ?? json['radiusMeters'] ?? json['radius'],
      ),
      sortOrder: _int(json['sort_order'] ?? json['sortOrder']) ?? 0,
      isActive: json['is_active'] != false && json['isActive'] != false,
      timeBound: json['time_bound'] == true || json['timeBound'] == true,
      timeMode: _string(json['time_mode'] ?? json['timeMode']),
      specificTime: _string(json['specific_time'] ?? json['specificTime']),
      windowStart: _string(json['window_start'] ?? json['windowStart']),
      windowEnd: _string(json['window_end'] ?? json['windowEnd']),
    );
  }

  static List<VisitCheckpoint> listFromJson(
    dynamic raw, {
    String? baseUrl,
  }) {
    if (raw is! List) return const <VisitCheckpoint>[];
    final out = <VisitCheckpoint>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final checkpoint = fromJson(
        Map<String, dynamic>.from(entry),
        baseUrl: baseUrl,
      );
      if (checkpoint == null) continue;
      if (!checkpoint.isActive) continue;
      out.add(checkpoint);
    }
    out.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.id.compareTo(b.id);
    });
    return out;
  }

  static String? _extractPhotoUrl(Map<String, dynamic> json) {
    for (final key in const [
      'photo_url',
      'photoUrl',
      'image_url',
      'imageUrl',
      'thumbnail_url',
      'thumbnailUrl',
      'reference_photo_url',
      'referencePhotoUrl',
      'file_url',
      'fileUrl',
      'src',
      'url',
    ]) {
      final value = _string(json[key]);
      if (value != null) return value;
    }

    for (final key in const [
      'photo',
      'image',
      'media',
      'thumbnail',
      'file',
      'attachment',
      'reference_photo',
      'referencePhoto',
    ]) {
      final nested = json[key];
      if (nested is Map) {
        final map = Map<String, dynamic>.from(nested);
        final nestedUrl = _string(
          map['url'] ??
              map['photo_url'] ??
              map['photoUrl'] ??
              map['image_url'] ??
              map['imageUrl'] ??
              map['src'] ??
              map['uri'] ??
              map['path'] ??
              map['photo_path'] ??
              map['photoPath'],
        );
        if (nestedUrl != null) return nestedUrl;
      } else {
        final value = _string(nested);
        if (value != null &&
            (_isAbsoluteUrl(value) ||
                value.contains('/') ||
                value.contains('.'))) {
          return value;
        }
      }
    }

    // Last resort: any absolute image-looking string on the checkpoint.
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is! String) continue;
      final text = value.trim();
      if (!_isAbsoluteUrl(text)) continue;
      final lower = text.toLowerCase();
      if (lower.contains('.jpg') ||
          lower.contains('.jpeg') ||
          lower.contains('.png') ||
          lower.contains('.webp') ||
          lower.contains('.gif') ||
          lower.contains('/storage/') ||
          lower.contains('/media/') ||
          lower.contains('/uploads/') ||
          lower.contains('/checkpoints/')) {
        return text;
      }
    }
    return null;
  }

  static String? _extractPhotoPath(Map<String, dynamic> json) {
    for (final key in const [
      'photo_path',
      'photoPath',
      'image_path',
      'imagePath',
      'file_path',
      'filePath',
    ]) {
      final value = _string(json[key]);
      if (value != null && !_isAbsoluteUrl(value)) return value;
    }

    for (final key in const [
      'photo',
      'image',
      'media',
      'file',
      'attachment',
      'reference_photo',
      'referencePhoto',
    ]) {
      final nested = json[key];
      if (nested is! Map) continue;
      final map = Map<String, dynamic>.from(nested);
      final nestedPath = _string(
        map['path'] ??
            map['photo_path'] ??
            map['photoPath'] ??
            map['image_path'] ??
            map['imagePath'],
      );
      if (nestedPath != null && !_isAbsoluteUrl(nestedPath)) return nestedPath;
    }
    return null;
  }

  /// Builds an absolute image URL from bridge `photo_url` / `photo_path`.
  static String? resolvePhotoUrl({
    String? photoUrl,
    String? photoPath,
    String? baseUrl,
  }) {
    final direct = photoUrl?.trim();
    if (direct != null && direct.isNotEmpty) {
      if (_isAbsoluteUrl(direct)) return direct;
      return _joinOriginPath(baseUrl, direct);
    }

    final path = photoPath?.trim();
    if (path == null || path.isEmpty) return null;
    if (_isAbsoluteUrl(path)) return path;
    return _joinStoragePath(baseUrl, path);
  }

  static bool _isAbsoluteUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static String? _originFrom(String? baseUrl) {
    final raw = (baseUrl ?? AppRoutes.webBaseUrl).trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    return '$scheme://${uri.host}';
  }

  static String? _joinOriginPath(String? baseUrl, String path) {
    final origin = _originFrom(baseUrl);
    if (origin == null) return path.startsWith('/') ? path : '/$path';
    final clean = path.startsWith('/') ? path : '/$path';
    return '$origin$clean';
  }

  static String? _joinStoragePath(String? baseUrl, String path) {
    final origin = _originFrom(baseUrl);
    if (origin == null) return null;
    var clean = path.startsWith('/') ? path.substring(1) : path;
    if (clean.startsWith('storage/')) {
      return '$origin/$clean';
    }
    return '$origin/storage/$clean';
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    if (value is Map || value is List) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static double? _double(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }
}
