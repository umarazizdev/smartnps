import 'package:flutter/material.dart';

// ===== Main Brand Colors =====
const Color cPrimary = Color(0xFF022A67);
const Color cPale = Color(0xFFF9F7F6);
const Color cOrange = Color(0xFFE48E15);
const Color cGreen = Color(0xFF16A34A);
const Color cRed = Color(0xFFDC2626);
const Color cWhite = Colors.white;
const Color cBlack = Colors.black;
final Color cMainBg = Color(0xFFF9FAFB);
// const Color cBackground = Color(0xFFF6F8FA);
const Color cBackground = Color(0xFFF9FAFC);
const Color cWhiteText = Color(0xFFF6F8FA);
const Color cText = Color(0xFF1E293B);
const Color cDarkText = Color(0xFF0D1A33);
const Color cDarkGreyclr = Color(0xFF475569);
const Color cSuccess = cGreen;
const Color cTransparent = Colors.transparent;
const Color cSurface = Color(0xFFFBFBFD);
const Color cBorder = Color(0xFFE5E7EB);
const Color cIconDefault = Color(0xFF6B7280);
const Color cIconActive = cPrimary;

// ===== Dark Mode Colors =====
const Color cDarkBackground = Color(0xFF0F1729);
// const Color cDarkPrimary = Color(0xFF3B82F6);
const Color cDarkCardColor = Color(0xFF1A2332);
const Color cDarkTextPrimary = Color(0xFFF1F5F9);
const Color cDarkTextSecondary = Color(0xFFCBD5E1);
const Color cDarkIconColor = Color(0xFF94A3B8);
const Color cDarkBorderColor = Color(0xFF334155);
const Color cDarkDividerColor = Color(0xFF1E293B);
const Color cDarkAppBarColor = Color(0xFF0F1729);
const Color cDarkInputFillColor = Color(0xFF1E293B);

// ===== Shadows =====
const BoxShadow cCardShadow = BoxShadow(
  color: Color.fromRGBO(0, 0, 0, 0.08),
  blurRadius: 4,
  offset: Offset(0, 1),
);

const LinearGradient cDiagonalSoftGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF1994C), Color(0xFF2E4F91), Color(0xFF022A67)],
  stops: [0.0, 0.5, 1.0],
);

final BoxDecoration cMainBoxDecoration = BoxDecoration(
  color: cSurface,
  borderRadius: BorderRadius.circular(12),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withAlpha(13),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ],
);

final TextStyle cSectionHeadingStyle = const TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.2,
  height: 1.2,
);

// Helper function to get theme-aware box decoration
BoxDecoration getCardDecoration(BuildContext context, {Color? customColor}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return BoxDecoration(
    color: customColor ?? (isDark ? const Color(0xFF182334) : cSurface),
    borderRadius: BorderRadius.circular(12),
    border: isDark
        ? Border.all(color: Colors.white.withAlpha(18), width: 1)
        : null,
    boxShadow: [
      BoxShadow(
        color: isDark ? Colors.black.withAlpha(45) : Colors.black.withAlpha(13),
        blurRadius: isDark ? 16 : 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

String normalizeStatus(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[_/,]'), ' ').trim();
}

Color getStatusBgColor(String status, {bool isDark = false}) {
  final s = normalizeStatus(status);

  if (s.contains('all good')) {
    return isDark ? const Color(0xFF123B2A) : const Color(0xFFE5F7EB);
  } else if (s.contains('moderate')) {
    return isDark ? const Color(0xFF3A2A12) : const Color(0xFFFFF7ED);
  } else if (s.contains('critical')) {
    return isDark ? const Color(0xFF3A1F1F) : const Color(0xFFFEE2E2);
  } else if (s.contains('incident')) {
    return isDark ? const Color(0xFF2A2F5A) : const Color(0xFFEDE9FE);
  }

  return isDark ? const Color(0xFF3A2A12) : const Color(0xFFFFF4E5);
}

Color getStatusTextColor(String status, {bool isDark = false}) {
  final s = normalizeStatus(status);

  if (s.contains('all good')) {
    return isDark ? const Color(0xFF4ADE80) : const Color(0xFF166534);
  } else if (s.contains('moderate')) {
    return isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
  } else if (s.contains('critical')) {
    return isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
  } else if (s.contains('incident')) {
    return isDark ? const Color(0xFFA5B4FC) : const Color(0xFF7C3AED);
  }

  return isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
}

Color getShiftStatusBgColor(String status, {bool isDark = false}) {
  final s = normalizeStatus(status);

  if (s.contains('permanent shift')) {
    return isDark ? const Color(0xFF183D2B) : const Color(0xFFE5F7EB);
  } else if (s.contains('extra coverage')) {
    return isDark ? const Color(0xFF4A2323) : const Color(0xFFFEE2E2);
  } else {
    return isDark ? const Color(0xFF363055) : const Color(0xFFEDE9FE);
  }
}

String formatHM(int lateMinutes) {
  if (lateMinutes <= 0) return 'On time';
  final h = lateMinutes ~/ 60;
  final m = lateMinutes % 60;
  if (h <= 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String formatMMSS(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0;
  final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String formatHHMMSS(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0;
  final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

DateTime? tryParseShiftDateTime(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

String formatStatusText(String value) {
  return value
      .replaceAll(RegExp(r'[_/,]'), ' ')
      .trim()
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}

Color getShiftStatusTextColor(String status, {bool isDark = false}) {
  final s = normalizeStatus(status);

  if (s.contains('permanent shift')) {
    return isDark ? const Color(0xFF95E8BE) : const Color(0xFF166534);
  } else if (s.contains('extra coverage')) {
    return isDark ? const Color(0xFFF7B0B0) : const Color(0xFFB91C1C);
  } else {
    return isDark ? const Color(0xFFD8BFD8) : const Color(0xFF7C3AED);
  }
}

String camelWorkStatus(String? raw) {
  if (raw == null) return '';
  final s = raw.trim();
  if (s.isEmpty) return '';

  return s
      .split('-')
      .map((part) {
        final p = part.trim();
        if (p.isEmpty) return p;
        return p[0].toUpperCase() + p.substring(1).toLowerCase();
      })
      .join('-');
}

String isScopeSelected = 'isScopeSelected';
String selectedShift = 'Shift';
String selectedRegion = 'Region';
String kIsScopeSelectedKey = 'isScopeSelected';
String kSelectedRegionKey = 'selectedRegion';
String kSelectedShiftKey = 'selectedShift';
String kSelectedSiteKey = 'selectedSite';
String appToken = 'appToken';
String isLogin = 'isLogin';
String role = 'role';
String onSiteOfficer = 'on-site';
String patrolOfficer = 'patrol';
String siteId = 'siteId';
String shiftId = 'shiftId';
String reigonId = 'reigonId';
const String contactNumberRaw = '+923216546423';

String get waPhone => contactNumberRaw.replaceAll('+', '').replaceAll(' ', '');
