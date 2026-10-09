import 'package:flutter/material.dart';

class VisitPatrolRoundColors {
  VisitPatrolRoundColors._();

  static const List<Color> _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFFDC2626),
    Color(0xFF0F766E),
    Color(0xFFEA580C),
    Color(0xFF4F46E5),
    Color(0xFF65A30D),
    Color(0xFFC026D3),
    Color(0xFF0284C7),
    Color(0xFFB45309),
    Color(0xFFBE123C),
    Color(0xFF4338CA),
  ];

  static Map<String, Color> mapForTags(Iterable<String> tags) {
    final unique = <String>[];
    final seen = <String>{};
    for (final raw in tags) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      final key = tag.toLowerCase();
      if (!seen.add(key)) continue;
      unique.add(tag);
    }

    final map = <String, Color>{};
    for (var i = 0; i < unique.length; i++) {
      map[unique[i].toLowerCase()] = colorForIndex(i);
    }
    return map;
  }

  static Color colorForIndex(int index) {
    if (_palette.isEmpty) return const Color(0xFF2563EB);
    final i = index < 0 ? 0 : index;
    return _palette[i % _palette.length];
  }

  static Color forTag(
    String? tag, {
    Map<String, Color>? palette,
    Iterable<String>? amongTags,
  }) {
    final key = tag?.trim().toLowerCase() ?? '';
    if (key.isEmpty) return _palette.first;

    final resolved = palette ??
        (amongTags == null ? null : mapForTags(amongTags));
    final fromMap = resolved?[key];
    if (fromMap != null) return fromMap;

    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }
}

class VisitPatrolRound {
  const VisitPatrolRound({
    required this.roundTag,
    this.sitePatrolWindowId,
    this.roundsRequired,
    this.timeStart,
    this.timeEnd,
  });

  final String roundTag;
  final int? sitePatrolWindowId;
  final int? roundsRequired;
  final String? timeStart;
  final String? timeEnd;

  String get label => roundTag;

  Color accentColor({
    Map<String, Color>? palette,
    Iterable<String>? amongTags,
  }) {
    return VisitPatrolRoundColors.forTag(
      roundTag,
      palette: palette,
      amongTags: amongTags,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'roundTag': roundTag,
      if (sitePatrolWindowId != null)
        'sitePatrolWindowId': sitePatrolWindowId,
      if (roundsRequired != null) 'roundsRequired': roundsRequired,
      if (timeStart != null) 'timeStart': timeStart,
      if (timeEnd != null) 'timeEnd': timeEnd,
    };
  }

  static VisitPatrolRound? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final tag = _string(json['roundTag'] ?? json['round_tag'] ?? json['tag']);
    if (tag == null) return null;
    return VisitPatrolRound(
      roundTag: tag,
      sitePatrolWindowId: _int(
        json['sitePatrolWindowId'] ??
            json['site_patrol_window_id'] ??
            json['windowId'] ??
            json['window_id'],
      ),
      roundsRequired: _int(
        json['roundsRequired'] ??
            json['rounds_required'] ??
            json['requiredRounds'] ??
            json['required_rounds'],
      ),
      timeStart: _string(
        json['timeStart'] ?? json['time_start'] ?? json['start'],
      ),
      timeEnd: _string(json['timeEnd'] ?? json['time_end'] ?? json['end']),
    );
  }

  static List<VisitPatrolRound> listFromPayload(Map<String, dynamic>? json) {
    if (json == null) return const <VisitPatrolRound>[];

    final nestedPatrol = _asMap(json['patrol']);
    final rawWindows =
        json['patrol_windows'] ??
        json['patrolWindows'] ??
        json['windows'] ??
        nestedPatrol?['patrol_windows'] ??
        nestedPatrol?['patrolWindows'];

    final rounds = <VisitPatrolRound>[];
    final seen = <String>{};

    void addRound(VisitPatrolRound? round) {
      if (round == null) return;
      final key = round.roundTag.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      rounds.add(round);
    }

    if (rawWindows is List) {
      for (final entry in rawWindows) {
        if (entry is Map) {
          addRound(fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    if (rounds.isEmpty) {
      final rootTag = _string(
        json['round_tag'] ??
            json['roundTag'] ??
            nestedPatrol?['round_tag'] ??
            nestedPatrol?['roundTag'],
      );
      if (rootTag != null) {
        addRound(
          VisitPatrolRound(
            roundTag: rootTag,
            sitePatrolWindowId: _int(
              json['site_patrol_window_id'] ??
                  json['sitePatrolWindowId'] ??
                  nestedPatrol?['site_patrol_window_id'],
            ),
            roundsRequired: _int(
              json['rounds_required'] ??
                  json['roundsRequired'] ??
                  nestedPatrol?['rounds_required'],
            ),
            timeStart: _string(
              json['time_start'] ??
                  json['timeStart'] ??
                  nestedPatrol?['time_start'],
            ),
            timeEnd: _string(
              json['time_end'] ?? json['timeEnd'] ?? nestedPatrol?['time_end'],
            ),
          ),
        );
      }
    }

    return List<VisitPatrolRound>.unmodifiable(rounds);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
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
}
