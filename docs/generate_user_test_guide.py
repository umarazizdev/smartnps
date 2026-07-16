#!/usr/bin/env python3
"""User-facing SmartNPS360 testing checklist — matches real app flows."""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch, mm
from reportlab.platypus import (
    HRFlowable,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

OUT = Path(__file__).resolve().parent / "SmartNPS360_Simple_Tester_Guide.pdf"

NAVY = colors.HexColor("#022A67")
HEADER_BG = colors.HexColor("#022A67")
ROW_ALT = colors.HexColor("#F5F8FC")
BORDER = colors.HexColor("#C5D0E0")
NOTE_BG = colors.HexColor("#FFFBF0")
LIGHT_LINE = colors.HexColor("#E2E8F0")


def styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=18,
            textColor=NAVY,
            alignment=TA_CENTER,
            spaceAfter=2,
            leading=22,
        ),
        "sub": ParagraphStyle(
            "sub",
            parent=base["Normal"],
            fontSize=10,
            textColor=colors.HexColor("#64748B"),
            alignment=TA_CENTER,
            spaceAfter=8,
            leading=13,
        ),
        "h": ParagraphStyle(
            "h",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=11,
            textColor=NAVY,
            spaceBefore=11,
            spaceAfter=5,
            leading=14,
        ),
        "body": ParagraphStyle(
            "body",
            parent=base["Normal"],
            fontSize=8.5,
            leading=11.5,
            textColor=colors.HexColor("#334155"),
            spaceAfter=4,
        ),
        "cell": ParagraphStyle(
            "cell",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=10.5,
            textColor=colors.HexColor("#1E293B"),
            alignment=TA_LEFT,
        ),
        # CRITICAL: header text must be white inside Paragraph (table TEXTCOLOR is ignored)
        "header": ParagraphStyle(
            "header",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=11,
            textColor=colors.white,
            alignment=TA_CENTER,
        ),
        "tip": ParagraphStyle(
            "tip",
            parent=base["Normal"],
            fontSize=8,
            leading=11,
            textColor=colors.HexColor("#475569"),
            spaceAfter=5,
        ),
    }


def P(text, style):
    return Paragraph(str(text), style)


def checklist(st, rows):
    """rows: (what, expected)"""
    data = [[
        P("Done", st["header"]),
        P("What to test", st["header"]),
        P("Expected result", st["header"]),
        P("Notes", st["header"]),
    ]]
    for what, expected in rows:
        data.append([
            P("☐", st["cell"]),
            P(what, st["cell"]),
            P(expected, st["cell"]),
            P("", st["cell"]),
        ])

    t = Table(
        data,
        colWidths=[0.48 * inch, 2.2 * inch, 2.55 * inch, 1.52 * inch],
        repeatRows=1,
    )
    cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), HEADER_BG),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("BACKGROUND", (3, 1), (3, -1), NOTE_BG),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            cmds.append(("BACKGROUND", (0, i), (2, i), ROW_ALT))
    t.setStyle(TableStyle(cmds))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LIGHT_LINE)
    canvas.setLineWidth(0.6)
    canvas.line(12 * mm, 11 * mm, A4[0] - 12 * mm, 11 * mm)
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.HexColor("#94A3B8"))
    canvas.drawString(12 * mm, 7 * mm, "SmartNPS360 App Testing Checklist")
    canvas.drawRightString(A4[0] - 12 * mm, 7 * mm, f"Page {doc.page}")
    canvas.restoreState()


def build():
    st = styles()
    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=11 * mm,
        rightMargin=11 * mm,
        topMargin=12 * mm,
        bottomMargin=14 * mm,
        title="SmartNPS360 App Testing Checklist",
        author="SmartNPS360",
    )
    story = []

    story.append(P("SmartNPS360", st["title"]))
    story.append(P("App Testing Checklist", st["sub"]))
    story.append(
        HRFlowable(width="100%", thickness=1.2, color=NAVY, spaceAfter=8)
    )
    story.append(
        P(
            "Use this list while testing the SmartNPS360 app on your phone. "
            "Tick <b>Done</b> when finished. In the yellow <b>Notes</b> column write "
            "<b>Pass</b> or <b>Fail</b>. If something fails, write what you saw.",
            st["body"],
        )
    )

    # 1. Open & internet — OfflineScreen: "No internet connection", "Retry"
    story.append(P("1. Open the app & internet", st["h"]))
    story.append(checklist(st, [
        (
            "Open SmartNPS360 from your phone",
            "App opens and shows the SmartNPS360 website (login or home).",
        ),
        (
            "Turn on Airplane Mode, then open or reload the app",
            "You see “No internet connection” and a Retry button.",
        ),
        (
            "Turn internet back on and tap Retry",
            "The page loads again.",
        ),
    ]))

    # 2. Login / logout — real auth routes + logout_blocked_on_duty
    story.append(P("2. Login & logout", st["h"]))
    story.append(checklist(st, [
        (
            "On the login page, enter a wrong password and submit",
            "Login fails. You stay on the login page.",
        ),
        (
            "Log in with a correct account",
            "You enter the officer area of the app.",
        ),
        (
            "Fully close the app, then open it again (while still logged in)",
            "You can continue without problems (session still works).",
        ),
        (
            "While your shift has ended (off duty): log out",
            "You return to the login page.",
        ),
        (
            "While still on shift (on duty): try to log out",
            "Logout is blocked. Message says you must end your shift first.",
        ),
    ]))

    # 3. Bottom bar — exact labels Dashboard, TimeSheet, Profile
    story.append(P("3. Bottom menu (after login)", st["h"]))
    story.append(
        P(
            "The bottom menu shows only on the main Dashboard, TimeSheet, and Profile pages.",
            st["tip"],
        )
    )
    story.append(checklist(st, [
        (
            "Tap Dashboard",
            "Dashboard page opens. Menu item looks selected.",
        ),
        (
            "Tap TimeSheet",
            "Monthly timesheet page opens.",
        ),
        (
            "Tap Profile",
            "Profile page opens.",
        ),
    ]))

    # 4. Clock-in — Continue / Cancel disclosure, Open Settings, Always location
    story.append(P("4. Clock in / shift attendance", st["h"]))
    story.append(
        P(
            "Phone Location must be on. The app may show "
            "“Location required for shift attendance” with buttons "
            "<b>Cancel</b> and <b>Continue</b>. You may need location set to "
            "<b>Always</b> / <b>Allow all the time</b>.",
            st["tip"],
        )
    )
    story.append(checklist(st, [
        (
            "Start clock-in / shift attendance from the app",
            "If a location message appears, title is about location for shift attendance.",
        ),
        (
            "On that message, tap Continue (then allow location when the phone asks)",
            "You can move to the next location step.",
        ),
        (
            "If asked, set location to Always / Allow all the time",
            "Clock-in can complete.",
        ),
        (
            "Clock in outdoors or near a window (good GPS)",
            "Attendance / clock-in succeeds.",
        ),
        (
            "On the location message, tap Cancel",
            "Clock-in stops. You are not forced to continue.",
        ),
        (
            "Turn Location off on the phone, then try clock-in",
            "You may see “Turn on location services” or Open Settings / Cancel.",
        ),
        (
            "If Open Settings is shown: open Settings, fix location, return to the app, try again",
            "Clock-in works after location is fixed.",
        ),
        (
            "If the phone uses fake/mock GPS, try clock-in",
            "You see “Mock location detected” and an OK button. Clock-in does not succeed until mock GPS is off.",
        ),
    ]))

    # 5. On duty — banner Enable Location, Android FGS "Sharing live location"
    story.append(P("5. During your shift (on duty)", st["h"]))
    story.append(checklist(st, [
        (
            "Start / stay on duty with location fully allowed",
            "Shift stays active. On Android you may see a notification: “Sharing live location”.",
        ),
        (
            "Leave the app for a few minutes while still on duty (open another app)",
            "App does not crash. You can return and continue.",
        ),
        (
            "If a top banner asks for location (button like Enable Location / Allow Location)",
            "Tapping the button helps you fix location settings.",
        ),
        (
            "End your shift (go off duty)",
            "Location sharing stops. You can log out after this.",
        ),
    ]))

    # 6. Camera / photos — real JS bridge, Info.plist purposes
    story.append(P("6. Camera & photos", st["h"]))
    story.append(
        P(
            "These appear when a page asks for a photo (for example reports, visits, or profile / ID).",
            st["tip"],
        )
    )
    story.append(checklist(st, [
        (
            "When asked for a photo, allow Camera and take a picture",
            "Camera opens. Photo can be attached.",
        ),
        (
            "Cancel without taking a photo",
            "You return safely. App still works.",
        ),
        (
            "Choose a photo from your gallery when asked",
            "You can pick an image and attach it.",
        ),
        (
            "Deny Camera permission, then try to take a photo again",
            "Photo does not work. App shows that permission was denied.",
        ),
    ]))

    # 7. Notifications — real FCM flow
    story.append(P("7. Notifications", st["h"]))
    story.append(checklist(st, [
        (
            "Allow notifications when the phone or app asks",
            "Notifications are allowed.",
        ),
        (
            "Ask your team to send a test alert while the app is open",
            "You see the notification (sound if the phone is not silent).",
        ),
        (
            "Receive an alert with the app closed, then tap the notification",
            "App opens to a SmartNPS360 page (often Dashboard).",
        ),
        (
            "Turn off notifications for SmartNPS360 in phone Settings",
            "Alerts stop until you turn them on again.",
        ),
    ]))

    # 8. Other real bridges — share, download, theme, profile tab
    story.append(P("8. Other actions", st["h"]))
    story.append(checklist(st, [
        (
            "On Profile, update your details and save (if the page allows)",
            "Changes are saved.",
        ),
        (
            "If a page offers Share, tap it",
            "Phone share options open.",
        ),
        (
            "If a page offers Download, download a file",
            "Download completes. App does not crash.",
        ),
        (
            "If the website has light / dark mode, switch it",
            "App look updates to match.",
        ),
    ]))

    # 9. Full use cases — success + every clock-in failure path in the app
    story.append(P("9. Full use cases", st["h"]))
    story.append(
        P(
            "Do these end-to-end. For clock-in, test both <b>success</b> and every way "
            "clock-in can fail (location off, permission denied, Always missing, Cancel, "
            "mock GPS, poor GPS). After each failure, fix the setting and confirm clock-in works again.",
            st["tip"],
        )
    )
    story.append(checklist(st, [
        # --- General ---
        (
            "Open app → log in → tap Dashboard, TimeSheet, and Profile",
            "All three pages open. No freeze.",
        ),
        (
            "Wrong password, then correct password",
            "Fails first, then successful login.",
        ),
        (
            "Get a notification → tap it",
            "App opens to the related SmartNPS360 page.",
        ),
        (
            "On a page that needs a photo: allow Camera → take photo → attach → save / submit",
            "Photo is attached and saved.",
        ),
        (
            "On a photo page: deny Camera → try again → allow Camera → take photo",
            "Blocked while denied; works after Camera is allowed.",
        ),
        # --- Clock-in SUCCESS ---
        (
            "SUCCESS: Log in → clock in → on location message tap Continue → allow location → set Always / Allow all the time → finish clock-in outdoors",
            "Clock-in succeeds. You are on shift.",
        ),
        (
            "SUCCESS: Stay on duty a few minutes → leave the app briefly → return → end shift → log out",
            "Full day path works. Logout works only after the shift ends.",
        ),
        # --- Clock-in FAILURES then recover ---
        (
            "FAIL: Turn Location / Location Services OFF on the phone → try clock-in",
            "Unable to clock in. You see “Turn on location services” (or Open Settings / Cancel). Clock-in does not complete.",
        ),
        (
            "RECOVER: Turn Location back ON → try clock-in again (with Always allowed)",
            "Clock-in succeeds.",
        ),
        (
            "FAIL: On “Location required for shift attendance”, tap Cancel",
            "Unable to clock in. Flow stops. You are not forced to continue.",
        ),
        (
            "RECOVER: Start clock-in again → tap Continue → allow what is needed → finish",
            "Clock-in succeeds.",
        ),
        (
            "FAIL: When the phone asks for location, tap Don’t Allow / Deny",
            "Unable to clock in. App asks you to open Settings or shows location is needed.",
        ),
        (
            "RECOVER: Open Settings from the app (or phone Settings) → allow location → return → clock in again",
            "Clock-in succeeds.",
        ),
        (
            "FAIL: Allow location only While Using / only this time (not Always / All the time) → try clock-in",
            "Unable to clock in. App asks for background / Always location (Open Settings / Cancel).",
        ),
        (
            "RECOVER: In Settings set SmartNPS360 location to Always / Allow all the time → return → clock in",
            "Clock-in succeeds.",
        ),
        (
            "FAIL: On Open Settings message, tap Cancel (do not open Settings)",
            "Unable to clock in. Attendance is not completed.",
        ),
        (
            "FAIL: Tap Open Settings but leave location wrong → return to the app",
            "Unable to clock in. You may see “Unable to verify attendance”.",
        ),
        (
            "RECOVER: Set location correctly to Always → return → clock in again",
            "Clock-in succeeds.",
        ),
        (
            "FAIL: Turn on fake / mock GPS on the phone → try clock-in (with Always already allowed)",
            "Unable to clock in. You see “Mock location detected” and OK.",
        ),
        (
            "RECOVER: Turn mock GPS off → try clock-in again",
            "Clock-in succeeds.",
        ),
        (
            "FAIL: Try clock-in indoors with very poor GPS / weak signal (Always already allowed)",
            "Clock-in may fail or take long if GPS is not accurate enough. Retry outdoors or near a window.",
        ),
        (
            "RECOVER: Move outdoors / near a window → clock in again",
            "Clock-in succeeds with a good GPS fix.",
        ),
        (
            "FAIL: Double-tap clock-in quickly while the first permission step is still running",
            "Second try may say to wait until the location step finishes. First flow continues.",
        ),
        (
            "COMBINED: Location OFF + no Always permission → try clock-in → fix Location ON → still only While Using → try again → set Always → clock in",
            "Blocked at each wrong step. Succeeds only when Location is on and Always is set.",
        ),
    ]))

    story.append(Spacer(1, 10))
    story.append(P("Sign-off", st["h"]))
    sign = [
        [
            P("<font color='#022A67'><b>Your name</b></font>", st["cell"]),
            P("", st["cell"]),
            P("<font color='#022A67'><b>Phone</b></font>", st["cell"]),
            P("", st["cell"]),
        ],
        [
            P("<font color='#022A67'><b>Date</b></font>", st["cell"]),
            P("", st["cell"]),
            P("<font color='#022A67'><b>Overall (Pass / Fail)</b></font>", st["cell"]),
            P("", st["cell"]),
        ],
        [
            P("<font color='#022A67'><b>Problems found</b></font>", st["cell"]),
            P("", st["cell"]),
            P("", st["cell"]),
            P("", st["cell"]),
        ],
    ]
    t = Table(sign, colWidths=[1.4 * inch, 2.0 * inch, 1.55 * inch, 1.8 * inch])
    t.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, BORDER),
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#EEF2F7")),
                ("BACKGROUND", (2, 0), (2, 1), colors.HexColor("#EEF2F7")),
                ("SPAN", (1, 2), (-1, 2)),
                ("BACKGROUND", (1, 0), (1, -1), NOTE_BG),
                ("BACKGROUND", (3, 0), (3, 1), NOTE_BG),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
            ]
        )
    )
    story.append(t)

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    build()
