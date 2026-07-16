#!/usr/bin/env python3
"""Generate SmartNPS360 functional test plan PDF from codebase analysis."""

from datetime import date
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch, mm
from reportlab.platypus import (
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

OUT = Path(__file__).resolve().parent / "SmartNPS360_Functional_Test_Plan.pdf"
APP_VERSION = "1.0.0+44"
ANALYSIS_DATE = date.today().isoformat()
NT = "Not Tested"

PRIMARY = colors.HexColor("#022A67")
ACCENT = colors.HexColor("#2563EB")
LIGHT = colors.HexColor("#F0F4FA")
HEADER_BG = colors.HexColor("#022A67")
ALT_ROW = colors.HexColor("#F7F9FC")
BORDER = colors.HexColor("#D0D7E2")


def styles():
    base = getSampleStyleSheet()
    s = {
        "cover_title": ParagraphStyle(
            "cover_title",
            parent=base["Title"],
            fontSize=26,
            textColor=PRIMARY,
            spaceAfter=8,
            alignment=TA_CENTER,
            leading=32,
        ),
        "cover_sub": ParagraphStyle(
            "cover_sub",
            parent=base["Normal"],
            fontSize=12,
            textColor=colors.HexColor("#334155"),
            alignment=TA_CENTER,
            spaceAfter=6,
            leading=16,
        ),
        "h1": ParagraphStyle(
            "h1",
            parent=base["Heading1"],
            fontSize=16,
            textColor=PRIMARY,
            spaceBefore=14,
            spaceAfter=8,
            leading=20,
        ),
        "h2": ParagraphStyle(
            "h2",
            parent=base["Heading2"],
            fontSize=12,
            textColor=ACCENT,
            spaceBefore=10,
            spaceAfter=6,
            leading=15,
        ),
        "h3": ParagraphStyle(
            "h3",
            parent=base["Heading3"],
            fontSize=10.5,
            textColor=PRIMARY,
            spaceBefore=8,
            spaceAfter=4,
            leading=13,
        ),
        "body": ParagraphStyle(
            "body",
            parent=base["Normal"],
            fontSize=9,
            leading=12,
            alignment=TA_JUSTIFY,
            spaceAfter=4,
        ),
        "small": ParagraphStyle(
            "small",
            parent=base["Normal"],
            fontSize=8,
            leading=10,
            textColor=colors.HexColor("#475569"),
            spaceAfter=3,
        ),
        "cell": ParagraphStyle(
            "cell",
            parent=base["Normal"],
            fontSize=7.5,
            leading=9.5,
            alignment=TA_LEFT,
        ),
        "cell_center": ParagraphStyle(
            "cell_center",
            parent=base["Normal"],
            fontSize=7.5,
            leading=9.5,
            alignment=TA_CENTER,
        ),
        "toc": ParagraphStyle(
            "toc",
            parent=base["Normal"],
            fontSize=10,
            leading=16,
            leftIndent=8,
        ),
        "footer": ParagraphStyle(
            "footer",
            parent=base["Normal"],
            fontSize=7.5,
            textColor=colors.HexColor("#64748B"),
            alignment=TA_CENTER,
        ),
    }
    return s


def p(text, style):
    return Paragraph(str(text).replace("\n", "<br/>"), style)


def bullet_list(items, style):
    return ListFlowable(
        [ListItem(Paragraph(i, style), leftIndent=12, bulletColor=PRIMARY) for i in items],
        bulletType="bullet",
        start="•",
        leftIndent=18,
        bulletFontSize=8,
    )


def section_table(headers, rows, col_widths, st):
    data = [[p(h, st["cell_center"]) for h in headers]]
    for row in rows:
        data.append([p(c, st["cell"]) for c in row])
    t = Table(data, colWidths=col_widths, repeatRows=1)
    style_cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), HEADER_BG),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 7.5),
        ("ALIGN", (0, 0), (-1, 0), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, BORDER),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            style_cmds.append(("BACKGROUND", (0, i), (-1, i), ALT_ROW))
    t.setStyle(TableStyle(style_cmds))
    return t


def tc_block(st, tc):
    """Render one test case as a compact table."""
    rows = [
        ["Test Case ID", tc["id"]],
        ["Detected Feature / Integration / Permission", tc["feature"]],
        ["Source Code Reference", tc["src"]],
        ["User Role", tc["role"]],
        ["Preconditions", tc["pre"]],
        ["Test Steps", tc["steps"]],
        ["Expected Result", tc["exp"]],
        ["Test Status", tc.get("status", NT)],
        ["Notes", tc.get("notes", "")],
    ]
    data = [[p(a, st["cell"]), p(b, st["cell"])] for a, b in rows]
    t = Table(data, colWidths=[1.55 * inch, 5.2 * inch])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), LIGHT),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EEF8")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.35, BORDER),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
            ]
        )
    )
    return KeepTogether([t, Spacer(1, 8)])


def add_header_footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(PRIMARY)
    canvas.setLineWidth(0.8)
    canvas.line(18 * mm, A4[1] - 12 * mm, A4[0] - 18 * mm, A4[1] - 12 * mm)
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.HexColor("#64748B"))
    canvas.drawString(18 * mm, A4[1] - 10 * mm, "SmartNPS360 — Functional Test Plan (Code-Derived)")
    canvas.drawRightString(A4[0] - 18 * mm, A4[1] - 10 * mm, f"v{APP_VERSION}")
    canvas.line(18 * mm, 12 * mm, A4[0] - 18 * mm, 12 * mm)
    canvas.drawCentredString(A4[0] / 2, 8 * mm, f"Page {doc.page}  |  Production/Release focus  |  Generated {ANALYSIS_DATE}")
    canvas.restoreState()


def inventory_features():
    return [
        ["F-01", "WebView application shell", "Loads https://smartnps360.com in InAppWebView; splash, progress, pull-to-refresh", "lib/src/webview/webview_shell.dart"],
        ["F-02", "Officer bottom navigation", "Dashboard / TimeSheet / Profile tabs (exact path match)", "webview_shell.dart (_BottomItem)"],
        ["F-03", "Officer login (web + Sanctum)", "Web login routes + loginWithSanctum native API", "auth_session_manager.dart, webview_shell.dart"],
        ["F-04", "Officer registration/sign-up", "Detected login-route paths for register/sign-up", "auth_session_manager.dart"],
        ["F-05", "Auth event bridge (login/logout)", "authEvent JS handler; session persist; logout blocked on duty", "webview_shell.dart, AuthRepository"],
        ["F-06", "Token refresh / session continuity", "POST /api/auth/refresh; Dio 401 retry interceptor", "auth_repository.dart, api_client.dart"],
        ["F-07", "Clock-in / shift attendance gate", "prepareClockIn disclosure → permissions → mock check → GPS", "clock_in_gate_service.dart, js_bridge.dart"],
        ["F-08", "Foreground GPS for web", "getCurrentLocation / location watch with accuracy gate", "js_bridge.dart, webview_shell.dart"],
        ["F-09", "On-duty background location tracking", "Heartbeat on_duty starts BG GPS + uploads", "duty_heartbeat_service.dart, background_location_*"],
        ["F-10", "Off-duty location stop", "Heartbeat off_duty stops tracking and drains queue", "duty_heartbeat_service.dart"],
        ["F-11", "GPS ping & batch upload", "POST /api/gps/ping and /api/gps/batch with Hive queue", "background_location_uploader.dart"],
        ["F-12", "Speed-adaptive GPS policy", "Adjusts keep/upload frequency by speed band", "speed_adaptive_gps_policy.dart"],
        ["F-13", "Batch displacement gate", "Skips near-duplicate points for batch upload", "batch_displacement_gate.dart"],
        ["F-14", "Mock / fake GPS detection", "Blocks clock-in; dialog during duty tracking", "mock_location_guard.dart, detection"],
        ["F-15", "Location disclosure consent", "Store-safe disclosure before OS permission prompts", "location_disclosure_consent.dart, dialogs"],
        ["F-16", "Background location required banner", "On-duty UI banner when Always/BG location missing", "background_location_required_banner.dart"],
        ["F-17", "Camera capture (takePhoto)", "JS bridge → ImagePicker camera for reports/attachments", "js_bridge.dart (Info.plist: DAR/visits/ID)"],
        ["F-18", "Gallery image pick", "pickImage with photos permission", "js_bridge.dart"],
        ["F-19", "File picker", "pickFile for attachments", "js_bridge.dart"],
        ["F-20", "Share content", "share_plus via shareContent handler", "js_bridge.dart"],
        ["F-21", "External URL open", "url_launcher external application", "js_bridge.dart"],
        ["F-22", "File download", "downloadFile handler via shell download path", "js_bridge.dart, webview_shell.dart"],
        ["F-23", "Device info bridge", "getDeviceInfo (brand/model/OS)", "js_bridge.dart"],
        ["F-24", "Push notifications (FCM)", "Firebase Messaging + local notifications + sound", "push_notification_service.dart"],
        ["F-25", "Push token register/delete", "POST/DELETE /api/push-token", "push_notification_service.dart"],
        ["F-26", "In-app push enable/disable", "setPushNotificationsEnabled + prefs + permission-status sync", "push_notification_preferences.dart"],
        ["F-27", "Officer announcement push", "type=officer_announcement → WebView recipient UUID", "officer_announcement_*.dart"],
        ["F-28", "Notification tap deep link", "Opens trusted smartnps360 URL (default officer/dashboard)", "push_notification_service.dart"],
        ["F-29", "Native permission status sync", "POST /api/native-app/permission-status (location, push, battery)", "native_permission_status_service.dart"],
        ["F-30", "Battery monitoring upload", "Periodic battery % + low power mode while logged in", "native_permission_status_service.dart"],
        ["F-31", "Theme sync (light/dark)", "themeChanged JS → NativeThemeController", "native_theme_controller.dart"],
        ["F-32", "Offline / connectivity handling", "OfflineScreen + Retry when no network", "offline_screen.dart, webview_shell.dart"],
        ["F-33", "Unsupported platform screen", "Non Android/iOS shows mobile-only message", "unsupported_platform_screen.dart"],
        ["F-34", "Host allowlist & trusted maps CDN", "Blocks untrusted nav; allows Google Maps/Fonts subresources", "app_config.dart, webview_shell.dart"],
        ["F-35", "App upgrade reconcile", "Clears stale duty/disclosure state after version change", "app_upgrade_reconciler.dart"],
        ["F-36", "Open Settings helpers", "App settings / location permission settings MethodChannel", "permission_settings_helper.dart, MainActivity.kt"],
        ["F-37", "iOS significant location change", "Native SLC channel for background duty resilience", "ios_significant_location_change_service.dart, AppDelegate.swift"],
        ["F-38", "iOS duty location pinger", "Foreground/background position stream for iOS duty", "ios_duty_location_pinger.dart"],
        ["F-39", "Logout while on duty blocked", "authEvent logout returns logout_blocked_on_duty", "webview_shell.dart, duty_heartbeat_service.dart"],
        ["F-40", "Secure credential storage", "flutter_secure_storage for tokens/user JSON", "auth_repository.dart"],
    ]


def inventory_permissions():
    return [
        ["P-01", "INTERNET / NETWORK_STATE", "Android Manifest", "WebView + all API calls", "Always required"],
        ["P-02", "ACCESS_FINE/COARSE_LOCATION", "Android Manifest + runtime", "Clock-in GPS, duty tracking, web GPS", "Foreground location"],
        ["P-03", "ACCESS_BACKGROUND_LOCATION", "Android Q+ runtime", "Clock-in gate, on-duty BG tracking", "Always allow / all the time"],
        ["P-04", "FOREGROUND_SERVICE_LOCATION", "Android Manifest + FGS", "BackgroundLocationService notification", "On duty"],
        ["P-05", "CAMERA", "Android + NSCameraUsageDescription", "takePhoto / DAR / visits / ID", "When capturing"],
        ["P-06", "RECORD_AUDIO", "Android Manifest", "WebView media (if used by site)", "If web requests mic"],
        ["P-07", "READ_MEDIA_* / storage", "Android 13+ / legacy storage", "pickImage / attachments", "Gallery pick"],
        ["P-08", "POST_NOTIFICATIONS", "Android 13+ runtime", "FCM / local notifications", "Push features"],
        ["P-09", "NSLocationWhenInUse", "iOS Info.plist", "Foreground GPS", "While Using"],
        ["P-10", "NSLocationAlwaysAndWhenInUse", "iOS Info.plist", "Duty BG tracking / clock-in Always", "Always"],
        ["P-11", "NSPhotoLibrary", "iOS Info.plist", "pickImage / registration images", "Photos"],
        ["P-12", "NSUserNotifications", "iOS Info.plist + FCM", "Push alerts", "Notifications"],
        ["P-13", "Battery optimization exemption", "Android MethodChannel status", "Reported to permission-status API", "OEM battery"],
        ["P-14", "Low Power / Battery Saver", "Android/iOS power status", "Synced to backend", "System power mode"],
    ]


def inventory_integrations():
    return [
        ["N-01", "InAppWebView (flutter_inappwebview)", "Primary UI host for smartnps360.com"],
        ["N-02", "Firebase Core + Messaging", "Push init, background handler, FCM token"],
        ["N-03", "flutter_local_notifications", "Foreground/data push display + custom sound"],
        ["N-04", "Geolocator", "GPS stream, permission checks, accuracy"],
        ["N-05", "flutter_background_service", "Android FGS location isolate"],
        ["N-06", "permission_handler", "Runtime camera/photos/location/notification"],
        ["N-07", "Dio HTTP client", "Native APIs with Bearer + refresh retry"],
        ["N-08", "Hive local queue", "Offline GPS batch persistence"],
        ["N-09", "flutter_secure_storage", "Access/refresh tokens, user, consent keys"],
        ["N-10", "shared_preferences", "Push toggle, permission history flags, duty prefs"],
        ["N-11", "image_picker / file_picker", "Camera, gallery, files"],
        ["N-12", "share_plus / url_launcher", "Share sheet / external browser"],
        ["N-13", "connectivity_plus", "Offline detection"],
        ["N-14", "device_info_plus / package_info_plus", "Device + app version metadata"],
        ["N-15", "battery_plus", "Battery percentage for permission-status"],
        ["N-16", "cupertino_native", "iOS native tab bar"],
        ["N-17", "MethodChannel settings", "com.smartnps360.app/settings (Android/iOS)"],
        ["N-18", "iOS SLC channels", "com.smartnps360.app/ios_slc (+ events)"],
        ["N-19", "Google Maps/Fonts CDN allowlist", "Trusted subresource hosts for embedded maps"],
        ["N-20", "Laravel Sanctum APIs", "login, refresh, heartbeat, gps, push-token, permission-status"],
    ]


def inventory_roles():
    return [
        ["R-01", "Unauthenticated visitor", "Login/register routes; no duty tracking; push prompts deferred on login", "auth_session_manager.isLoginRoute"],
        ["R-02", "Officer (authenticated)", "Primary native role: dashboard/timesheet/profile, clock-in, duty GPS, push, permission sync", "AuthRepository officer_logged_in; /officer/*"],
        ["R-03", "Officer on duty", "Heartbeat on_duty; BG location active; logout blocked until off duty", "DutyHeartbeatService"],
        ["R-04", "Officer off duty", "Tracking stopped; can logout; GPS upload drained", "DutyHeartbeatService.off_duty"],
        ["R-05", "Web admin (if present on site)", "Not specially instrumented in native shell; host allowlist only. Verify via web UI if role exists server-side.", "No native admin branch"],
    ]


def all_test_cases():
    """Comprehensive functional test cases derived from code."""
    cases = []

    def add(**kwargs):
        cases.append(kwargs)

    # --- Shell / Navigation ---
    add(
        id="TC-NAV-001",
        feature="F-01 WebView shell — cold start (release)",
        src="main.dart; smart_nps_app.dart; webview_shell.dart",
        role="Any (Officer device)",
        pre="Release/production build installed; network available; device Android or iOS.",
        steps="1. Launch app from home screen.\n2. Observe splash/logo overlay.\n3. Wait for WebView to load https://smartnps360.com/.",
        exp="App initializes Firebase, auth cache, push; splash dismisses; home/login web page loads successfully without debug banners.",
        notes="Run release: flutter build apk --release / IPA Archive. Debug banner must be absent.",
    )
    add(
        id="TC-NAV-002",
        feature="F-02 Bottom navigation — Dashboard",
        src="webview_shell.dart _BottomItem.dashboard",
        role="Officer",
        pre="Officer logged in; URL on an officer surface that shows bottom bar.",
        steps="1. Tap Dashboard tab.\n2. Confirm navigation to /officer/dashboard.\n3. Tap Dashboard again (same tab).",
        exp="WebView loads dashboard; tab highlights; re-tap does not restart unnecessary navigation when already selected.",
    )
    add(
        id="TC-NAV-003",
        feature="F-02 Bottom navigation — TimeSheet",
        src="_BottomItem.timesheet → /officer/timesheet/monthly",
        role="Officer",
        pre="Officer logged in; bottom bar visible.",
        steps="1. Tap TimeSheet.\n2. Verify monthly timesheet page.",
        exp="Exact path /officer/timesheet/monthly loads; tab selected.",
    )
    add(
        id="TC-NAV-004",
        feature="F-02 Bottom navigation — Profile",
        src="_BottomItem.profile → /officer/profile",
        role="Officer",
        pre="Officer logged in.",
        steps="1. Tap Profile.\n2. Verify profile page content.",
        exp="Profile URL loads; bottom bar remains correct.",
    )
    add(
        id="TC-NAV-005",
        feature="F-02 Bottom bar hidden on sub-routes",
        src="_BottomItem.indexForUri exact match only",
        role="Officer",
        pre="On dashboard; navigate into a nested officer sub-page (not exact tab URL).",
        steps="1. Open a nested page from dashboard.\n2. Observe bottom bar visibility.",
        exp="Bottom bar only on exact tab landing URLs — not sibling/subpath pages.",
    )
    add(
        id="TC-NAV-006",
        feature="F-34 Untrusted host blocked",
        src="app_config.isAllowedHost; webview_shell navigation",
        role="Officer",
        pre="App running.",
        steps="1. Attempt navigation to non-allowed host (via web link if present).\n2. Attempt Google Maps tiles/iframe on allowed page.",
        exp="Untrusted hosts do not replace shell; trusted Google CDN subresources allowed for maps.",
    )
    add(
        id="TC-NAV-007",
        feature="F-32 Offline screen",
        src="offline_screen.dart; connectivity_plus",
        role="Any",
        pre="App open.",
        steps="1. Enable airplane mode / disable network.\n2. Trigger load/navigation.\n3. Tap Retry after restoring network.",
        exp="OfflineScreen shows 'No internet connection' + Retry; Retry reloads when online.",
    )
    add(
        id="TC-NAV-008",
        feature="F-33 Unsupported platform",
        src="unsupported_platform_screen.dart",
        role="N/A",
        pre="Run on web/desktop if available.",
        steps="1. Launch on non-mobile platform.",
        exp="Shows 'This app is mobile-only' message.",
        notes="Optional; primary platforms are Android/iOS.",
    )

    # --- Auth ---
    add(
        id="TC-AUTH-001",
        feature="F-03 Officer web login — valid credentials",
        src="auth_session_manager login routes; authEvent; AuthRepository.saveLogin",
        role="Officer",
        pre="Valid officer credentials; on login page.",
        steps="1. Enter valid username/password on web form.\n2. Submit login.\n3. Observe navigation to officer surface.",
        exp="Native stores tokens/user; officerLoggedIn=true; dashboard accessible; push/permission sync may start.",
    )
    add(
        id="TC-AUTH-002",
        feature="F-03 Login — invalid credentials",
        src="Web form + optional loginWithSanctum",
        role="Unauthenticated",
        pre="On login page.",
        steps="1. Enter invalid password.\n2. Submit.",
        exp="Login fails with web/native error; no durable officer session; tokens not treated as logged-in.",
    )
    add(
        id="TC-AUTH-003",
        feature="F-03 Native Sanctum login bridge",
        src="loginWithSanctum handler → POST /api/auth/login",
        role="Officer",
        pre="Trusted host; web triggers flutter_inappwebview.callHandler('loginWithSanctum', {username,password}).",
        steps="1. Trigger Sanctum login with valid creds.\n2. Inspect response {ok:true,hasToken:true}.",
        exp="Access/refresh tokens saved; untrusted origin denied.",
    )
    add(
        id="TC-AUTH-004",
        feature="F-04 Registration / sign-up routes",
        src="isLoginRoute paths officer/register, sign-up, signup",
        role="Unauthenticated",
        pre="Navigate to registration URL on smartnps360.com.",
        steps="1. Open register/sign-up.\n2. Complete registration form fields required by web.\n3. Submit.",
        exp="Registration workflow completes per web app; treated as auth route (push prompts deferred).",
        notes="Form fields are web-owned; native treats path as login-family route.",
    )
    add(
        id="TC-AUTH-005",
        feature="F-05 / F-39 Logout when off duty",
        src="authEvent logout; AuthSessionManager.clearNativeSession",
        role="Officer off duty",
        pre="Logged in; heartbeat off_duty.",
        steps="1. Logout from web/profile.\n2. Observe native teardown phases.",
        exp="Tracking stopped; GPS queue drained; FCM token deleted; secure storage cleared; returns to login.",
    )
    add(
        id="TC-AUTH-006",
        feature="F-39 Logout blocked while on duty",
        src="webview_shell authEvent logout_blocked_on_duty",
        role="Officer on duty",
        pre="Heartbeat reports on_duty; tracking active.",
        steps="1. Attempt logout.",
        exp="Logout rejected with code logout_blocked_on_duty and message to end shift first; session remains.",
    )
    add(
        id="TC-AUTH-007",
        feature="F-06 Access token refresh",
        src="AuthRepository.refreshAccessToken; ApiClient 401 retry",
        role="Officer",
        pre="Logged in with refresh token; wait for access expiry or force 401 native call.",
        steps="1. Trigger native API after access token expiry (heartbeat/GPS/push).\n2. Observe silent refresh.",
        exp="POST /api/auth/refresh succeeds; request retried with new Bearer; session continues. Failed refresh clears session.",
    )
    add(
        id="TC-AUTH-008",
        feature="F-40 Session persistence across kill",
        src="flutter_secure_storage; warmAccessTokenCache",
        role="Officer",
        pre="Logged in; force-quit app.",
        steps="1. Relaunch app.\n2. Check if officer session restored without re-login (per web cookie + native tokens).",
        exp="Native tokens warm from secure storage; authenticated APIs work; web session behavior matches product expectation.",
    )

    # --- Clock-in / Location ---
    add(
        id="TC-CLK-001",
        feature="F-07 / F-15 Clock-in happy path (permissions granted)",
        src="prepareClockIn; ClockInGateService; getCurrentLocation for_clock_in",
        role="Officer",
        pre="Release build; location services ON; Always/background location already granted; disclosure accepted; no mock GPS.",
        steps="1. From web, start clock-in / shift attendance.\n2. Native prepareClockIn runs.\n3. GPS returns accurate fix ≤ required meters.",
        exp="canClockIn=true; location payload returned; attendance verification succeeds on web.",
    )
    add(
        id="TC-CLK-002",
        feature="F-07 Clock-in — disclosure cancel",
        src="ClockInLocationDisclosureDialog; prepareClockIn",
        role="Officer",
        pre="Disclosure not accepted; background not ready.",
        steps="1. Start clock-in.\n2. Cancel disclosure dialog.",
        exp="Clock-in cancelled; canClockIn false; reason clock_in_cancelled / disclosure cancelled.",
    )
    add(
        id="TC-CLK-003",
        feature="F-07 Clock-in — location services disabled",
        src="Geolocator.isLocationServiceEnabled",
        role="Officer",
        pre="Disable device Location Services.",
        steps="1. Start clock-in.",
        exp="Blocked with location_services_disabled; Open Settings prompt available.",
    )
    add(
        id="TC-CLK-004",
        feature="F-14 Clock-in blocked by mock location",
        src="MockLocationGuard.ensureClearForClockIn",
        role="Officer",
        pre="Enable mock/fake GPS (developer options).",
        steps="1. Grant Always location.\n2. Attempt clock-in.",
        exp="Mock location dialog; canClockIn false with reason mock_location until mock disabled.",
    )
    add(
        id="TC-CLK-005",
        feature="F-08 getCurrentLocation accuracy timeout",
        src="js_bridge.getCurrentLocation",
        role="Officer",
        pre="Indoors / poor GPS; required_accuracy_meters tight.",
        steps="1. Request location with high accuracy requirement.\n2. Wait for timeout.",
        exp="Error fresh_location_unavailable; may include bestAccuracySeenMeters.",
    )
    add(
        id="TC-CLK-006",
        feature="F-08 Location watch start/clear",
        src="startLocationWatch / clearLocationWatch handlers",
        role="Officer",
        pre="Foreground location granted; disclosure accepted.",
        steps="1. Web starts location watch.\n2. Move device; observe updates.\n3. Clear watch.",
        exp="Continuous updates while active; clear stops stream.",
    )

    # --- Duty / Background ---
    add(
        id="TC-DUTY-001",
        feature="F-09 On-duty tracking start",
        src="DutyHeartbeatService; POST /api/heartbeat; BackgroundLocationController",
        role="Officer on duty",
        pre="Logged in; Always location; disclosure accepted.",
        steps="1. Clock in / set on duty on server so heartbeat returns on_duty.\n2. Background the app.\n3. Verify location notification (Android FGS) / iOS indicator.",
        exp="Tracking starts; points queued/uploaded; permission-status reflects granted BG location.",
    )
    add(
        id="TC-DUTY-002",
        feature="F-10 Off-duty stop",
        src="DutyHeartbeatService off_duty stop",
        role="Officer",
        pre="Currently on duty with tracking.",
        steps="1. Clock out / end shift so heartbeat returns off_duty.\n2. Observe FGS/notification stop.",
        exp="Tracking stops; pending batches flush/drain; banner clears.",
    )
    add(
        id="TC-DUTY-003",
        feature="F-11 GPS ping & batch APIs",
        src="background_location_uploader.dart; AppConfig gps paths",
        role="Officer on duty",
        pre="On duty outdoors with movement.",
        steps="1. Remain on duty for several minutes with movement.\n2. Optionally go offline then online.",
        exp="POST /api/gps/ping and/or /api/gps/batch succeed (200); Hive queue drains after reconnect.",
    )
    add(
        id="TC-DUTY-004",
        feature="F-12 / F-13 Adaptive keep + displacement",
        src="speed_adaptive_gps_policy.dart; batch_displacement_gate.dart",
        role="Officer on duty",
        pre="On duty; walk then ride/drive if safe.",
        steps="1. Stationary period.\n2. Move slowly then faster.",
        exp="Fewer uploads when stationary/near-duplicate; denser keep when moving per policy (backend receives sensible density).",
    )
    add(
        id="TC-DUTY-005",
        feature="F-16 Background location banner",
        src="background_location_required_banner.dart",
        role="Officer on duty",
        pre="On duty but Only While Using / no Always.",
        steps="1. Enter on_duty without Always permission.\n2. Tap Enable Location on banner.",
        exp="Banner visible; tapping guides disclosure/settings flow; tracking does not falsely claim ready.",
    )
    add(
        id="TC-DUTY-006",
        feature="F-37 / F-38 iOS SLC + duty pinger",
        src="ios_significant_location_change_service.dart; ios_duty_location_pinger.dart; AppDelegate.swift",
        role="Officer on duty (iOS)",
        pre="iOS Always location; release build; on duty.",
        steps="1. Background app for extended period.\n2. Travel enough for SLC if applicable.\n3. Return to foreground.",
        exp="Location continues best-effort; pinger/SLC channels operate without crash; uploads resume.",
        notes="iOS BG is best-effort per code comments — verify production behavior on real device.",
    )

    # --- Media / Files ---
    add(
        id="TC-MED-001",
        feature="F-17 takePhoto — permission granted",
        src="js_bridge.takePhoto; Permission.camera",
        role="Officer",
        pre="Camera permission allowed.",
        steps="1. From web feature needing photo (DAR/visit/ID).\n2. Capture photo.\n3. Confirm.\n4. Cancel once.",
        exp="ok with photo path/name; cancel returns canceled:true.",
    )
    add(
        id="TC-MED-002",
        feature="F-18 pickImage — gallery",
        src="js_bridge.pickImage",
        role="Officer",
        pre="Photos/media permission as required by OS.",
        steps="1. Pick image from gallery.\n2. Cancel picker.",
        exp="Selected image returned; cancel handled; iOS denial returns permission_denied.",
    )
    add(
        id="TC-MED-003",
        feature="F-19 pickFile",
        src="js_bridge.pickFile",
        role="Officer",
        pre="Trusted host.",
        steps="1. Trigger file pick.\n2. Select a file / cancel.",
        exp="File metadata returned or canceled:true.",
    )
    add(
        id="TC-MED-004",
        feature="F-20 shareContent",
        src="js_bridge.shareContent",
        role="Officer",
        pre="Trusted host.",
        steps="1. Trigger share with text.\n2. Complete or dismiss share sheet.",
        exp="Share sheet opens; ok:true on success.",
    )
    add(
        id="TC-MED-005",
        feature="F-21 openExternalUrl",
        src="js_bridge.openExternalUrl",
        role="Officer",
        pre="Trusted host.",
        steps="1. Open an https URL externally.",
        exp="launched:true opens in external browser/app.",
    )
    add(
        id="TC-MED-006",
        feature="F-22 downloadFile",
        src="downloadFile handler",
        role="Officer",
        pre="Authenticated; file URL on allowed host if required.",
        steps="1. Download a report/attachment from web via bridge.",
        exp="Download completes with ok result; file accessible per platform behavior.",
    )
    add(
        id="TC-MED-007",
        feature="F-23 getDeviceInfo",
        src="js_bridge.getDeviceInfo",
        role="Officer",
        pre="Trusted host.",
        steps="1. Call getDeviceInfo from web.",
        exp="Returns platform + device model/SDK or iOS system fields.",
    )

    # --- Push ---
    add(
        id="TC-PUSH-001",
        feature="F-24 / F-25 Push receive foreground",
        src="push_notification_service.dart; MainActivity channel smartnps360_default",
        role="Officer",
        pre="Logged in; notification permission granted; push enabled; token uploaded.",
        steps="1. Send test FCM from backend while app foregrounded.\n2. Observe local notification + sound (alert_sound).",
        exp="Notification displayed with title/body; custom sound where channel allows.",
    )
    add(
        id="TC-PUSH-002",
        feature="F-24 Push receive background/killed",
        src="firebaseMessagingBackgroundHandler",
        role="Officer",
        pre="App backgrounded or killed; permission granted.",
        steps="1. Send FCM.\n2. Tap notification.",
        exp="OS/local notification appears; tap opens trusted URL (default /officer/dashboard).",
    )
    add(
        id="TC-PUSH-003",
        feature="F-26 Toggle push off/on",
        src="setPushNotificationsEnabled; PushNotificationPreferences",
        role="Officer",
        pre="Logged in.",
        steps="1. Disable push via web bridge.\n2. Send FCM.\n3. Re-enable.",
        exp="Preference persists; permission-status push field updates; enabled state restores token registration behavior.",
    )
    add(
        id="TC-PUSH-004",
        feature="F-27 Officer announcement push",
        src="officer_announcement_push.dart; coordinator",
        role="Officer",
        pre="Valid recipient_public_id UUID for logged-in officer.",
        steps="1. Send type=officer_announcement with recipient_public_id.\n2. Optional trusted url.",
        exp="Coordinator forwards UUID to WebView; malformed UUID ignored; untrusted url rejected.",
        notes="Unit tests exist in test/officer_announcement_*_test.dart",
    )
    add(
        id="TC-PUSH-005",
        feature="F-28 Notification deep link allowlist",
        src="parseTrustedDestinationUrl / tap handler",
        role="Officer",
        pre="Push with url payload.",
        steps="1. Send push with https://smartnps360.com/... url.\n2. Send push with evil.com url.",
        exp="Trusted URL opens in WebView; untrusted falls back to defaultPushUrl.",
    )

    # --- Permission status / battery ---
    add(
        id="TC-PERMAPI-001",
        feature="F-29 Permission-status sync after login",
        src="NativePermissionStatusService → POST /api/native-app/permission-status",
        role="Officer",
        pre="Native auth session present.",
        steps="1. Login.\n2. Grant/deny permissions.\n3. Resume app from Settings.",
        exp="Payload includes platform, deviceId, appVersion, build, battery, permissions map, checkedAt; backend receives updates.",
    )
    add(
        id="TC-PERMAPI-002",
        feature="F-30 Battery monitoring",
        src="startBatteryMonitoring every 5 minutes",
        role="Officer",
        pre="Logged in; app active.",
        steps="1. Keep app open >5 minutes.\n2. Change battery level (or wait).",
        exp="Battery percentage uploaded when changed; stops after logout.",
    )
    add(
        id="TC-THEME-001",
        feature="F-31 Theme sync",
        src="themeChanged handler; NativeThemeController",
        role="Officer",
        pre="Web supports theme toggle.",
        steps="1. Toggle dark/light in web.\n2. Observe native dialogs/scaffold theme.",
        exp="Native ThemeMode updates; ok:true with isDark.",
    )
    add(
        id="TC-UPG-001",
        feature="F-35 App upgrade reconcile",
        src="app_upgrade_reconciler.dart",
        role="Officer",
        pre="Install prior build with duty flags; upgrade to +44.",
        steps="1. Upgrade app.\n2. Launch.",
        exp="Stale duty/disclosure/geo unlock cleared safely; no crash before MainActivity channel ready.",
    )

    # --- Permission state matrix cases ---
    perm_matrix = [
        ("P-02", "Foreground location", "Clock-in / web GPS / duty", "Permission.location / Geolocator"),
        ("P-03", "Background / Always location", "Clock-in gate + on-duty BG tracking", "ACCESS_BACKGROUND_LOCATION / Always"),
        ("P-05", "Camera", "takePhoto", "Permission.camera"),
        ("P-07", "Photos / media", "pickImage", "Permission.photos / READ_MEDIA_*"),
        ("P-08", "Notifications", "FCM display + prompt", "POST_NOTIFICATIONS / FCM auth"),
    ]
    for code, name, feature, src in perm_matrix:
        add(
            id=f"TC-PERM-{code}-G",
            feature=f"{code} {name} — GRANTED",
            src=src,
            role="Officer",
            pre=f"{name} granted in OS Settings; location services on if location.",
            steps=f"1. Exercise dependent feature: {feature}.\n2. Confirm success path.",
            exp="Feature completes successfully; permission-status reports granted (or lasting While Using rules for iOS FG).",
        )
        add(
            id=f"TC-PERM-{code}-D",
            feature=f"{code} {name} — DENIED (OS prompt Don't Allow)",
            src=src,
            role="Officer",
            pre="Fresh or reset permission; trigger request.",
            steps="1. Trigger feature.\n2. Deny OS permission prompt.",
            exp="Feature returns permission_denied (or equivalent); Open Settings education may appear; API may report denied/unknown per history rules.",
        )
        add(
            id=f"TC-PERM-{code}-S",
            feature=f"{code} {name} — DISABLED from Settings",
            src="PermissionSettingsHelper + Settings",
            role="Officer",
            pre="Permission previously granted.",
            steps="1. Open Settings and disable permission.\n2. Return to app.\n3. Retry feature.",
            exp="Feature blocked; settings prompt / banner as designed; permission-status sync updates on resume.",
        )
        add(
            id=f"TC-PERM-{code}-R",
            feature=f"{code} {name} — RE-GRANTED after deny/disable",
            src="recheckAfterAppResume; syncLocationPermissionsOnResume",
            role="Officer",
            pre="Permission currently denied/disabled.",
            steps="1. Open Settings from in-app prompt.\n2. Grant permission.\n3. Return to app.\n4. Retry feature.",
            exp="App detects new grant; clock-in/duty/push proceeds; failure dialog not shown if now ready.",
        )

    # Android one-time location special
    add(
        id="TC-PERM-P02-ONETIME",
        feature="P-02 Android 'Allow only this time' treated insufficient",
        src="MainActivity.hasOneTimeLocationPermission; NativePermissionStatusService",
        role="Officer (Android)",
        pre="Android 11+.",
        steps="1. Choose Allow only this time for location.\n2. Attempt clock-in / check permission-status.",
        exp="Clock-in requires lasting background readiness; API may report foregroundLocation denied for one-time; user guided to lasting Always.",
    )

    # Native integration release checks
    add(
        id="TC-NAT-001",
        feature="N-17 MethodChannel openAppSettings / location settings",
        src="MainActivity.kt; permission_settings_helper.dart",
        role="Officer",
        pre="Release build on Android.",
        steps="1. Trigger Open Settings from clock-in dialog.\n2. Confirm correct Settings screen.\n3. Return via back.",
        exp="Settings opens without crash; resume recheck runs.",
    )
    add(
        id="TC-NAT-002",
        feature="N-02/N-03 Firebase + local notifications release",
        src="main.dart Firebase.initializeApp; google-services",
        role="Officer",
        pre="Production Firebase project config in release build.",
        steps="1. Confirm FCM token obtained.\n2. Receive production push.",
        exp="Token uploaded; notification channel smartnps360_default exists; sound works.",
    )
    add(
        id="TC-NAT-003",
        feature="N-05 Android foreground service location",
        src="AndroidManifest BackgroundService; BackgroundLocationService",
        role="Officer on duty",
        pre="On duty; Always location.",
        steps="1. Background app.\n2. Check ongoing 'Sharing live location' notification.",
        exp="FGS notification present (channel smartnps360_location); tracking continues.",
    )
    add(
        id="TC-NAT-004",
        feature="N-08 Hive GPS queue survives process death",
        src="background_location_uploader.dart",
        role="Officer on duty",
        pre="On duty; briefly kill network then force-stop carefully.",
        steps="1. Generate points offline.\n2. Restore network and relaunch.",
        exp="Queued batches upload when possible; no silent permanent loss without drain/discard rules.",
    )
    add(
        id="TC-NAT-005",
        feature="N-18 iOS significant location change channel",
        src="AppDelegate.swift ios_slc",
        role="Officer on duty (iOS)",
        pre="Always location; release IPA.",
        steps="1. Enable duty tracking.\n2. Background and move.",
        exp="SLC monitoring registers without Flutter crash; events delivered when OS wakes app.",
    )
    add(
        id="TC-NAT-006",
        feature="N-14 Low power mode change event",
        src="MainActivity lowPowerModeChanged; AppDelegate",
        role="Officer",
        pre="Logged in.",
        steps="1. Toggle Battery Saver / Low Power Mode.\n2. Observe permission-status sync.",
        exp="low_power_mode field updates to enabled/disabled.",
    )

    # E2E workflows
    add(
        id="TC-E2E-001",
        feature="E2E Officer day: login → clock-in → duty track → clock-out → logout",
        src="Multiple modules (auth, clock-in, heartbeat, GPS, logout)",
        role="Officer",
        pre="Release build; Always location; notifications; production backend.",
        steps="1. Login.\n2. PrepareClockIn + clock in.\n3. Work shift with app backgrounded.\n4. Clock out.\n5. Logout.",
        exp="Each phase succeeds; GPS visible server-side; logout allowed only after off duty; tokens cleared.",
    )
    add(
        id="TC-E2E-002",
        feature="E2E Push announcement while on duty",
        src="push + announcement coordinator + webview",
        role="Officer on duty",
        pre="On duty; push granted.",
        steps="1. Send officer_announcement.\n2. Tap notification.\n3. Confirm WebView receives recipient id / navigates.",
        exp="Announcement handled without stopping duty tracking.",
    )
    add(
        id="TC-E2E-003",
        feature="E2E Media attachment on report while authenticated",
        src="takePhoto/pickImage + web upload",
        role="Officer",
        pre="Camera/photos granted.",
        steps="1. Open Daily Activity Report or visit evidence flow on web.\n2. Capture/attach photo.\n3. Submit form.",
        exp="Native picker returns path; web upload succeeds; record visible.",
        notes="Web form fields are server-rendered; native provides capture bridge only.",
    )
    add(
        id="TC-E2E-004",
        feature="E2E Timesheet monthly review",
        src="Bottom tab timesheet URL",
        role="Officer",
        pre="Logged in; has historical attendance.",
        steps="1. Open TimeSheet tab.\n2. Review monthly entries.\n3. Navigate back to Dashboard.",
        exp="Timesheet loads; navigation stable; no auth loss.",
    )
    add(
        id="TC-E2E-005",
        feature="E2E Profile update with image",
        src="/officer/profile + pickImage",
        role="Officer",
        pre="Photos permission.",
        steps="1. Open Profile.\n2. Update fields / attach profile or ID image.\n3. Save.",
        exp="Profile updates persist; image pick works.",
    )

    # Web CRUD implied (document as web-backed via shell)
    add(
        id="TC-CRUD-001",
        feature="Web CRUD via shell — create attendance/visit/report records",
        src="Web app at smartnps360.com (hosted) + native bridges",
        role="Officer",
        pre="Authenticated.",
        steps="1. Create a new report/visit/attendance as provided by web UI.\n2. Read/list it.\n3. Update if UI allows.\n4. Delete/cancel if UI allows.",
        exp="CRUD completes through WebView; native GPS/camera used where required.",
        notes="Native repo does not implement server CRUD UI; verify against production web modules.",
    )

    return cases


def build():
    st = styles()
    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title="SmartNPS360 Functional Test Plan",
        author="Auto — Code-derived QA inventory",
    )
    story = []

    # Cover
    story.append(Spacer(1, 40))
    story.append(p("SmartNPS360", st["cover_title"]))
    story.append(p("Complete Functional Test Plan & Feature Inventory", st["cover_sub"]))
    story.append(p("Automatically derived from Flutter native shell source code", st["cover_sub"]))
    story.append(Spacer(1, 20))
    meta = [
        ["Document type", "Functional verification test plan (production/release)"],
        ["Application", "SmartNPS360 (WebView shell + native bridges)"],
        ["App version analyzed", APP_VERSION],
        ["Production host", "https://smartnps360.com/"],
        ["Analysis date", ANALYSIS_DATE],
        ["Primary platforms", "Android & iOS (release builds)"],
        ["Execution status baseline", "All cases marked Not Tested pending device execution"],
        ["Architecture note", "Flutter hosts InAppWebView; business UI largely web; native owns GPS, auth tokens, push, permissions, media"],
    ]
    story.append(section_table(["Field", "Value"], meta, [2.2 * inch, 4.55 * inch], st))
    story.append(Spacer(1, 16))
    story.append(
        p(
            "<b>Objective:</b> Verify every feature, permission-dependent behavior, native integration, "
            "user role workflow, and end-to-end path discovered in the codebase works as intended in a "
            "production/release environment. Focus is functional correctness, not exploratory bug hunting.",
            st["body"],
        )
    )
    story.append(PageBreak())

    # TOC
    story.append(p("1. Table of Contents", st["h1"]))
    toc_items = [
        "2. Analysis methodology & architecture summary",
        "3. Automatically detected feature inventory",
        "4. Automatically detected permissions & dependent features",
        "5. Automatically detected native integrations & SDKs",
        "6. Automatically detected user roles & workflows",
        "7. Detected screens, routes, JS bridges & APIs",
        "8. Complete functional test cases",
        "9. Permission-state testing matrix",
        "10. Native integration testing checklist",
        "11. End-to-end workflow testing checklist",
        "12. Production/release testing checklist",
        "13. Test execution summary",
    ]
    for t in toc_items:
        story.append(p(t, st["toc"]))
    story.append(PageBreak())

    # Methodology
    story.append(p("2. Analysis Methodology & Architecture Summary", st["h1"]))
    story.append(
        p(
            "This inventory was produced by static analysis of the repository at "
            "<b>lib/</b>, <b>android/</b>, <b>ios/</b>, and <b>pubspec.yaml</b>. Features were inferred from "
            "Dart classes, JS bridge handlers, MethodChannels, AndroidManifest/Info.plist permissions, "
            "API URL constants in <b>AppConfig</b>, and UI widgets/dialogs. No manual feature list was supplied.",
            st["body"],
        )
    )
    story.append(p("Architecture (as coded)", st["h2"]))
    story.append(
        bullet_list(
            [
                "SmartNpsApp → WebViewShell on Android/iOS; UnsupportedPlatformScreen elsewhere.",
                "Web content: https://smartnps360.com with UA signature SmartNPS360App.",
                "Native JS bridge (trusted host only) for media, GPS, push, clock-in, auth, theme, share, download.",
                "Officer session via Sanctum login/refresh + secure storage; web authEvent for login/logout.",
                "Duty mode driven by polling POST /api/heartbeat (on_duty / off_duty).",
                "Background GPS via flutter_background_service (Android FGS) and iOS pinger/SLC.",
                "Firebase Cloud Messaging + local notifications with custom alert sound.",
            ],
            st["body"],
        )
    )
    story.append(PageBreak())

    # Feature inventory
    story.append(p("3. Automatically Detected Feature Inventory", st["h1"]))
    story.append(
        p(
            "Features below are implemented or enabled in the native shell and/or clearly described by native usage strings "
            "(e.g., Daily Activity Reports, visits, profile/ID). Web-only CRUD modules load inside the WebView.",
            st["body"],
        )
    )
    story.append(
        section_table(
            ["ID", "Feature", "Intended behavior (from code)", "Source"],
            inventory_features(),
            [0.55 * inch, 1.55 * inch, 2.7 * inch, 1.95 * inch],
            st,
        )
    )
    story.append(PageBreak())

    # Permissions
    story.append(p("4. Automatically Detected Permissions & Dependent Features", st["h1"]))
    story.append(
        section_table(
            ["ID", "Permission", "Declared in", "Dependent features", "When used"],
            inventory_permissions(),
            [0.55 * inch, 1.6 * inch, 1.5 * inch, 1.8 * inch, 1.3 * inch],
            st,
        )
    )
    story.append(p("Permission-status API fields (synced to backend)", st["h2"]))
    story.append(
        p(
            "NativePermissionStatusService reports: <b>foregroundLocation</b>, <b>backgroundLocation</b>, "
            "<b>preciseLocation</b>, <b>notifications</b>, <b>batteryOptimization</b>, <b>push</b> (in-app toggle), "
            "plus battery_percentage and low_power_mode.",
            st["body"],
        )
    )
    story.append(PageBreak())

    # Native integrations
    story.append(p("5. Automatically Detected Native Integrations & Packages", st["h1"]))
    story.append(
        section_table(
            ["ID", "Integration / SDK", "Functional role"],
            inventory_integrations(),
            [0.6 * inch, 2.4 * inch, 3.75 * inch],
            st,
        )
    )
    story.append(p("Native API endpoints (AppConfig)", st["h2"]))
    story.append(
        bullet_list(
            [
                "POST https://smartnps360.com/api/auth/login",
                "POST https://smartnps360.com/api/auth/refresh",
                "GET/POST https://smartnps360.com/api/heartbeat",
                "POST https://smartnps360.com/api/gps/point|ping|batch",
                "POST/DELETE https://smartnps360.com/api/push-token",
                "POST https://smartnps360.com/api/native-app/permission-status",
            ],
            st["body"],
        )
    )
    story.append(PageBreak())

    # Roles
    story.append(p("6. Automatically Detected User Roles & Workflows", st["h1"]))
    story.append(
        p(
            "Native code centers on the <b>Officer</b> role (officer_logged_in flag, /officer/* routes, "
            "officer announcement pushes). Admin/other web roles are not branched in Flutter; test them only if "
            "the production website exposes them through the same WebView.",
            st["body"],
        )
    )
    story.append(
        section_table(
            ["ID", "Role / state", "Workflows available", "Source"],
            inventory_roles(),
            [0.55 * inch, 1.5 * inch, 2.9 * inch, 1.8 * inch],
            st,
        )
    )
    story.append(p("Primary officer workflow (code-derived)", st["h2"]))
    story.append(
        bullet_list(
            [
                "Open app → WebView loads → Login/Register (auth routes).",
                "Native Sanctum or authEvent persists session tokens.",
                "Bottom bar: Dashboard ↔ TimeSheet ↔ Profile.",
                "prepareClockIn → disclosure → location permissions → mock check → GPS → web attendance.",
                "Heartbeat on_duty → background location upload → optional banner if Always missing.",
                "Heartbeat off_duty → stop tracking → allow logout.",
                "Push: register token, receive alerts/announcements, tap to navigate.",
                "Logout: blocked if on duty; otherwise clear session + delete push token + drain GPS.",
            ],
            st["body"],
        )
    )
    story.append(PageBreak())

    # Screens / routes / bridges
    story.append(p("7. Detected Screens, Routes, JS Bridges & Forms", st["h1"]))
    story.append(p("Native Flutter screens / overlays", st["h2"]))
    story.append(
        bullet_list(
            [
                "WebViewShell (primary)",
                "OfflineScreen (Retry)",
                "UnsupportedPlatformScreen",
                "Splash overlay (_SplashOverlay)",
                "Clock-in location disclosure dialog",
                "Clock-in blocked / Open Settings dialogs (GlassActionDialog)",
                "Mock location dialog",
                "Background location required banner",
                "Platform bottom bar (Dashboard / TimeSheet / Profile)",
            ],
            st["body"],
        )
    )
    story.append(p("Web routes recognized natively", st["h2"]))
    story.append(
        bullet_list(
            [
                "Auth: /, /officer/login, sign-in, register/sign-up variants",
                "Logout: /officer/logout or path ending /logout",
                "Tabs: /officer/dashboard, /officer/timesheet/monthly, /officer/profile",
                "Generic officer surface: any allowed-host path containing /officer",
                "Default push destination: /officer/dashboard",
            ],
            st["body"],
        )
    )
    story.append(p("JavaScript bridge handlers (trusted host only)", st["h2"]))
    story.append(
        bullet_list(
            [
                "pickFile, pickImage, takePhoto",
                "getCurrentLocation, startLocationWatch, clearLocationWatch",
                "getDeviceInfo, openExternalUrl, shareContent, downloadFile",
                "getPushNotificationToken, getPushNotificationStatus, setPushNotificationsEnabled",
                "getBackgroundLocationStatus, prepareClockIn",
                "themeChanged, loginWithSanctum, authEvent",
                "iosPopoverFixDebug (iOS diagnostic)",
            ],
            st["body"],
        )
    )
    story.append(p("Forms & inputs", st["h2"]))
    story.append(
        p(
            "Native shell does not define Material text forms for business data. Detected inputs: "
            "<b>loginWithSanctum username/password</b>; web login/registration/profile/report forms inside WebView; "
            "OS permission dialogs; disclosure Accept/Cancel; Open Settings / Cancel on glass dialogs; Offline Retry.",
            st["body"],
        )
    )
    story.append(PageBreak())

    # Test cases
    story.append(p("8. Complete Functional Test Cases", st["h1"]))
    story.append(
        p(
            "Each case uses the required fields: ID, detected feature, source reference, role, preconditions, "
            "steps, expected result, status, notes. Status defaults to <b>Not Tested</b> for device execution tracking.",
            st["body"],
        )
    )
    cases = all_test_cases()
    story.append(p(f"Total automatically generated test cases: <b>{len(cases)}</b>", st["body"]))
    story.append(Spacer(1, 6))
    for tc in cases:
        story.append(tc_block(st, tc))
    story.append(PageBreak())

    # Permission matrix
    story.append(p("9. Permission-State Testing Matrix", st["h1"]))
    story.append(
        p(
            "For each permission, verify dependent feature behavior across four states. "
            "Detailed steps are in TC-PERM-* cases above; this matrix is the execution tracker.",
            st["body"],
        )
    )
    matrix_rows = []
    for code, perm, feature in [
        ("P-02", "Foreground location", "GPS / clock-in / duty FG"),
        ("P-03", "Background/Always location", "Clock-in + BG duty tracking"),
        ("P-05", "Camera", "takePhoto / evidence"),
        ("P-07", "Photos/media", "pickImage / attachments"),
        ("P-08", "Notifications", "FCM alerts"),
        ("P-13", "Battery optimization (Android)", "Reported status / tracking resilience"),
    ]:
        for state, expect in [
            ("Granted/Enabled", "Feature succeeds; API granted/enabled as applicable"),
            ("Denied on prompt", "Feature errors; settings education may show"),
            ("Disabled in Settings", "Feature blocked; resume sync updates API"),
            ("Re-granted after deny", "Feature recovers without requiring reinstall"),
        ]:
            matrix_rows.append([code, perm, feature, state, expect, NT])
    story.append(
        section_table(
            ["Perm", "Permission", "Feature", "State", "Expected behavior", "Status"],
            matrix_rows,
            [0.5 * inch, 1.15 * inch, 1.2 * inch, 1.15 * inch, 1.85 * inch, 0.7 * inch],
            st,
        )
    )
    story.append(PageBreak())

    # Native checklist
    story.append(p("10. Native Integration Testing Checklist", st["h1"]))
    native_checks = [
        ["☐", "N-01", "InAppWebView loads production site; pull-to-refresh works"],
        ["☐", "N-02", "Firebase initializes in release; FCM token obtained"],
        ["☐", "N-03", "Local notifications + alert_sound channel"],
        ["☐", "N-04", "Geolocator accuracy gating for clock-in"],
        ["☐", "N-05", "Android FGS 'Sharing live location' while on duty"],
        ["☐", "N-06", "Runtime permission prompts appear only after disclosure"],
        ["☐", "N-07", "Dio Bearer + 401 refresh retry on native APIs"],
        ["☐", "N-08", "Hive GPS queue flush after offline"],
        ["☐", "N-09", "Secure storage survives app restart"],
        ["☐", "N-10", "SharedPreferences push/permission history"],
        ["☐", "N-11", "Camera / gallery / file pickers"],
        ["☐", "N-12", "Share sheet / external URL"],
        ["☐", "N-13", "OfflineScreen on connectivity loss"],
        ["☐", "N-14/15", "Device id + battery in permission-status"],
        ["☐", "N-16", "iOS Cupertino tab bar"],
        ["☐", "N-17", "Settings MethodChannel opens correct screens"],
        ["☐", "N-18", "iOS SLC channels under Always location"],
        ["☐", "N-19", "Embedded Google Maps render in WebView"],
        ["☐", "N-20", "All AppConfig API endpoints reachable with prod auth"],
    ]
    story.append(
        section_table(
            ["Done", "ID", "Release verification item"],
            native_checks,
            [0.55 * inch, 0.7 * inch, 5.5 * inch],
            st,
        )
    )
    story.append(PageBreak())

    # E2E checklist
    story.append(p("11. End-to-End Workflow Testing Checklist", st["h1"]))
    e2e = [
        ["☐", "E2E-01", "Fresh install → login → dashboard"],
        ["☐", "E2E-02", "Register/sign-up path (if enabled in prod)"],
        ["☐", "E2E-03", "Clock-in with full permission ladder (disclosure→FG→Always)"],
        ["☐", "E2E-04", "On-duty background tracking for ≥15 minutes"],
        ["☐", "E2E-05", "Offline duty → reconnect → batch upload"],
        ["☐", "E2E-06", "Mock GPS blocked during clock-in"],
        ["☐", "E2E-07", "Logout blocked while on duty; allowed after off duty"],
        ["☐", "E2E-08", "Push receive (FG/BG/killed) + tap navigation"],
        ["☐", "E2E-09", "Officer announcement push with valid UUID"],
        ["☐", "E2E-10", "Camera evidence attach + submit web form"],
        ["☐", "E2E-11", "Gallery attach for profile/ID"],
        ["☐", "E2E-12", "Timesheet monthly review via bottom tab"],
        ["☐", "E2E-13", "Profile update + theme toggle"],
        ["☐", "E2E-14", "Token refresh during long duty session"],
        ["☐", "E2E-15", "App upgrade reconcile from previous build"],
        ["☐", "E2E-16", "Permission revoke mid-duty → banner → re-grant → recover"],
    ]
    story.append(
        section_table(
            ["Done", "ID", "Workflow"],
            e2e,
            [0.55 * inch, 0.8 * inch, 5.4 * inch],
            st,
        )
    )
    story.append(PageBreak())

    # Production checklist
    story.append(p("12. Production / Release Testing Checklist", st["h1"]))
    prod = [
        ["☐", "Build release APK/AAB and App Store IPA (not debug)"],
        ["☐", "Confirm ProGuard/R8 does not break MethodChannels or Firebase"],
        ["☐", "Verify production Firebase options / GoogleService-Info.plist"],
        ["☐", "Verify deep links / notification channel IDs match prod"],
        ["☐", "Test on low-end Android + recent Pixel/Samsung; iPhone + recent iOS"],
        ["☐", "Test OEM battery restrictions (Xiaomi/Vivo/etc.) with Always location"],
        ["☐", "Confirm UA contains SmartNPS360App for web detection"],
        ["☐", "Confirm allowedHosts only smartnps360.com / www"],
        ["☐", "Confirm no debug logging of tokens in release"],
        ["☐", "Validate Info.plist / Play Store disclosure strings match actual BG location use"],
        ["☐", "Regression after force-stop, reboot, airplane mode"],
        ["☐", "Confirm version 1.0.0+44 (or release candidate) reported in permission-status"],
    ]
    story.append(
        section_table(
            ["Done", "Production gate"],
            prod,
            [0.55 * inch, 6.2 * inch],
            st,
        )
    )
    story.append(PageBreak())

    # Summary
    story.append(p("13. Test Execution Summary", st["h1"]))
    n = len(cases)
    summary = [
        ["Features inventoried", str(len(inventory_features()))],
        ["Permissions inventoried", str(len(inventory_permissions()))],
        ["Native integrations inventoried", str(len(inventory_integrations()))],
        ["Roles / duty states inventoried", str(len(inventory_roles()))],
        ["Functional test cases generated", str(n)],
        ["Passed", "0 (pending execution)"],
        ["Failed", "0 (pending execution)"],
        ["Not Tested", str(n)],
        ["Blocked", "0"],
        ["Environment for execution", "Production/release Android + iOS devices against smartnps360.com"],
        ["Automated unit tests present", "officer_announcement_push_test.dart, officer_announcement_coordinator_test.dart"],
        ["Overall readiness", "Inventory & plan complete — execute TC-* on release builds and update Status column"],
    ]
    story.append(section_table(["Metric", "Value"], summary, [2.6 * inch, 4.15 * inch], st))
    story.append(Spacer(1, 12))
    story.append(p("Sign-off", st["h2"]))
    sign = [
        ["Prepared by (analysis)", "Automated code analysis — Cursor Agent"],
        ["QA executor", "______________________________"],
        ["Date executed", "______________________________"],
        ["Android build / device", "______________________________"],
        ["iOS build / device", "______________________________"],
        ["Result approval", "______________________________"],
    ]
    story.append(section_table(["Role", "Signature / notes"], sign, [2.2 * inch, 4.55 * inch], st))
    story.append(Spacer(1, 16))
    story.append(
        p(
            "<i>End of document. Update each test case Status field to Pass/Fail during execution. "
            "Re-generate or annotate this PDF as the living QA record for SmartNPS360 native shell releases.</i>",
            st["small"],
        )
    )

    doc.build(story, onFirstPage=add_header_footer, onLaterPages=add_header_footer)
    return n


if __name__ == "__main__":
    count = build()
    print(f"Wrote {OUT} with {count} test cases")
