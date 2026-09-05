package com.smartnps360.app.duty

import android.os.SystemClock

object AndroidDutyUiState {
  @Volatile
  var resumedCount: Int = 0

  @Volatile
  private var lastBecamePausedAtElapsedMs: Long = 0L

  val isUiResumed: Boolean
    get() = resumedCount > 0

  fun noteResumed() {
    resumedCount += 1
  }

  fun notePaused() {
    if (resumedCount > 0) {
      resumedCount -= 1
    }
    if (resumedCount == 0) {
      lastBecamePausedAtElapsedMs = SystemClock.elapsedRealtime()
    }
  }

  /**
   * True when the activity has been away long enough that this is likely a
   * real swipe-kill / long background — not a brief Settings permission jump.
   */
  fun isAwayLongEnoughForNativeFgs(minAwayMs: Long = 45_000L): Boolean {
    if (isUiResumed) return false
    val pausedAt = lastBecamePausedAtElapsedMs
    if (pausedAt <= 0L) {
      // Process restarted with no UI (or never resumed) — treat as killed.
      return true
    }
    return SystemClock.elapsedRealtime() - pausedAt >= minAwayMs
  }
}
