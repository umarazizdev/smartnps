/**
 * WEB APP — REQUIRED clock-in integration for native app (iOS/Android)
 *
 * ROOT CAUSE if clock-in works after foreground-only OS permission:
 * The web is calling clock-in (or geolocation) WITHOUT awaiting ensureCanClockIn.
 *
 * Native app now blocks GPS until OS reports background location (Always /
 * Allow all the time). Clock-in API calls that do not use GPS can still succeed
 * if the web submits the API directly — that MUST be fixed on the web side.
 *
 * After a successful clock-in API, notify native with clock_in_success so it can
 * burst-poll heartbeat and start duty tracking quickly.
 */

// ---------------------------------------------------------------------------
// REQUIRED: bind clock-in button — do not use a raw click handler
// ---------------------------------------------------------------------------

function initSmartNpsClockInGate() {
  var clockInBtn = document.querySelector('#clock-in-btn');

  if (!clockInBtn || !window.SmartNPS360) return;

  window.SmartNPS360.bindClockInGate(
    clockInBtn,
    function onAllowed() {
      // ONLY runs after native OS confirms background location.
      submitClockIn();
    },
    function onBlocked(gate) {
      showToast(gate.title, gate.message);
    }
  );
}

// ---------------------------------------------------------------------------
// REQUIRED: submitClockIn must NOT run on button click directly
// ---------------------------------------------------------------------------

async function submitClockIn() {
  // If you use geolocation here, it is blocked until background is enabled.
  // await new Promise((resolve, reject) => {
  //   navigator.geolocation.getCurrentPosition(resolve, reject);
  // });

  const res = await fetch('/api/attendance/clock-in', {
    method: 'POST',
    // headers / body as needed
  });

  const clockInSuccess = res.ok;

  // REQUIRED in native WebView: notify after clock-in attempt result
  if (
    window.flutter_inappwebview &&
    typeof window.flutter_inappwebview.callHandler === 'function'
  ) {
    window.flutter_inappwebview.callHandler('clock_in_success', {
      action: 'clock_in_success',
      clock_in_success: clockInSuccess,
      ok: clockInSuccess,
      source: 'officer_dashboard_time_tracker',
      occurred_at: new Date().toISOString(),
    });
  }
}

// ---------------------------------------------------------------------------
// WRONG — causes clock-in before background permission:
//
// clockInBtn.addEventListener('click', submitClockIn);
//
// navigator.permissions.query({ name: 'geolocation' }).then((s) => {
//   s.onchange = () => submitClockIn(); // fires after foreground OS grant
// });
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// ALTERNATIVE (no bindClockInGate): await gate before anything else
// ---------------------------------------------------------------------------

/*
async function handleClockInClick() {
  if (window.SmartNPS360 && window.SmartNPS360.isNativeApp()) {
    const gate = await window.SmartNPS360.ensureCanClockIn();
    if (!gate.ok) {
      showToast(gate.title, gate.message);
      return;
    }
  }
  await submitClockIn();
}
*/
