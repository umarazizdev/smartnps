/**
 * WEB APP CHANGES — paste into your attendance / clock-in page.
 *
 * The native Flutter app injects SmartNPS360.bindClockInGate automatically.
 * You only need the code below on smartnps360.com (no extra JS file to host).
 */

// ---------------------------------------------------------------------------
// 1) Add this once when the clock-in page loads (DOMContentLoaded or your SPA mount)
// ---------------------------------------------------------------------------

function initSmartNpsClockInGate() {
  var clockInBtn = document.querySelector('#clock-in-btn'); // your button selector

  if (!clockInBtn || !window.SmartNPS360) return;

  window.SmartNPS360.bindClockInGate(
    clockInBtn,
    function onAllowed() {
      // Called ONLY when background location is ready (native app).
      // Put your existing clock-in logic here:
      submitClockIn();
    },
    function onBlocked(gate) {
      // Optional: replace alert with your toast/modal component
      showToast(gate.title, gate.message);
      // gate.reason examples:
      //   location_background  (Android — need "Allow all the time")
      //   location_always      (iOS — need "Always")
      //   location_foreground  (need basic location first)
      //   location_services_disabled
    }
  );
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initSmartNpsClockInGate);
} else {
  initSmartNpsClockInGate();
}

// ---------------------------------------------------------------------------
// 2) Your existing clock-in function (unchanged except it is called from above)
// ---------------------------------------------------------------------------

async function submitClockIn() {
  // e.g. get GPS, then POST to your clock-in API
  // const location = await getCurrentLocation();
  // await fetch('/api/attendance/clock-in', { method: 'POST', body: ... });
}

// ---------------------------------------------------------------------------
// 3) Optional CSS — dim blocked button in native app
// ---------------------------------------------------------------------------

/*
.smartnps-clockin-blocked {
  opacity: 0.55;
  cursor: not-allowed;
}
*/

// ---------------------------------------------------------------------------
// ALTERNATIVE — if you use a form submit instead of a button click handler:
// call ensureCanClockIn() at the start of your handler
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
