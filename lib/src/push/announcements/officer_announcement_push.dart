import 'package:flutter/foundation.dart';

import '../../utilities/app_config.dart';

class OfficerAnnouncementPush {
  const OfficerAnnouncementPush({
    required this.recipientPublicId,
    this.destinationUrl,
  });

  final String recipientPublicId;
  final Uri? destinationUrl;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  static bool isUuid(String value) => _uuidPattern.hasMatch(value);

  static OfficerAnnouncementPush? tryParse(Map<String, dynamic> data) {
    final type = data['type']?.toString().trim();
    final notificationType = data['notification_type']?.toString().trim();
    final isAnnouncement =
        type == 'officer_announcement' ||
        notificationType == 'officer_announcement';
    if (!isAnnouncement) {
      return null;
    }

    final recipientPublicId =
        data['recipient_public_id']?.toString().trim() ?? '';
    if (recipientPublicId.isEmpty || !isUuid(recipientPublicId)) {
      if (kDebugMode) {
        debugPrint(
          '[SmartNPS360][Announcement] ignored malformed push '
          '(missing or invalid recipient_public_id)',
        );
      }
      return null;
    }

    return OfficerAnnouncementPush(
      recipientPublicId: recipientPublicId,
      destinationUrl: parseTrustedDestinationUrl(data['url']),
    );
  }

  static Uri? parseTrustedDestinationUrl(Object? raw) {
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (!AppConfig.isAllowedHost(uri.host)) return null;
    return uri;
  }

  static String redactRecipientPublicId(String recipientPublicId) {
    if (recipientPublicId.length < 13) return '…';
    return '${recipientPublicId.substring(0, 8)}…'
        '${recipientPublicId.substring(recipientPublicId.length - 4)}';
  }
}
