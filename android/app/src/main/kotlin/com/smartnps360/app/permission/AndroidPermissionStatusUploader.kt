package com.smartnps360.app.permission

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object AndroidPermissionStatusUploader {
  private const val TAG = "AndroidPermStatus"

  data class Snapshot(
    val payload: JSONObject,
    val fingerprint: String,
  )

  fun buildSnapshot(context: Context): Snapshot {
    val permissions = AndroidPermissionStatusReader.buildPermissionsJson(
      context,
      AndroidPermissionStatusStore.pushStatus(context),
    )
    val battery = AndroidPermissionStatusReader.batteryPercentage(context)
    val payload = JSONObject()
      .put("platform", "android")
      .put("deviceId", AndroidPermissionStatusStore.deviceId(context))
      .put("appVersion", AndroidPermissionStatusStore.appVersion(context))
      .put("build", AndroidPermissionStatusStore.build(context))
      .put("low_power_mode", AndroidPermissionStatusReader.lowPowerModeStatus(context))
      .put("permissions", permissions)
      .put("checkedAt", utcNow())
      .put("app_cycle", "killed")
    AndroidPermissionStatusStore.deviceName(context)?.let {
      payload.put("deviceName", it)
    }
    if (battery in 0..100) {
      payload.put("battery_percentage", battery)
    }

    val fingerprint = fingerprintOf(payload)
    return Snapshot(payload = payload, fingerprint = fingerprint)
  }

  fun fingerprintOf(payload: JSONObject): String {
    val copy = JSONObject(payload.toString())
    copy.remove("app_cycle")
    copy.remove("battery_percentage")
    copy.remove("checkedAt")
    copy.remove("killed_at")
    copy.remove("opened_at")
    // Stable key order for permissions sub-object.
    val perms = copy.optJSONObject("permissions")
    if (perms != null) {
      val ordered = JSONObject()
      for (key in listOf(
        "foregroundLocation",
        "backgroundLocation",
        "preciseLocation",
        "notifications",
        "motionActivity",
        "batteryOptimization",
        "backgroundAppRefresh",
        "push",
      )) {
        if (perms.has(key)) ordered.put(key, perms.get(key))
      }
      copy.put("permissions", ordered)
    }
    return copy.toString()
  }

  fun uploadIfChanged(context: Context): Boolean {
    val snapshot = buildSnapshot(context)
    val last = AndroidPermissionStatusStore.lastFingerprint(context)
    if (last != null && last == snapshot.fingerprint) {
      Log.i(TAG, "skip upload; permissions unchanged")
      return false
    }

    var result = postPermissionStatus(context, snapshot.payload)
    if (result.code == 401 || result.code == 403) {
      if (refreshAccessToken(context)) {
        result = postPermissionStatus(context, snapshot.payload)
      }
    }
    if (result.code in 200..299) {
      AndroidPermissionStatusStore.writeFingerprint(context, snapshot.fingerprint)
      Log.i(TAG, "uploaded permission-status (changed)")
      return true
    }
    Log.w(TAG, "upload failed code=${result.code}")
    return false
  }

  /**
   * Explicit app_cycle timeline upload (killed / kill+open).
   * Always POSTs; does not use permission fingerprint skip.
   */
  fun uploadAppCycleEvent(
    context: Context,
    appCycle: String,
    killedAt: String?,
    openedAt: String?,
    connectTimeoutMs: Int = 12_000,
    readTimeoutMs: Int = 12_000,
    lightweight: Boolean = false,
  ): Boolean {
    seedAuthAndApiBase(context)
    val token = AndroidPermissionStatusStore.accessToken(context)
    if (token.isNullOrEmpty()) {
      Log.w(TAG, "app_cycle=$appCycle skipped; no access token")
      return false
    }
    val base = resolveApiBaseUrl(context)
    Log.i(TAG, "app_cycle=$appCycle POST $base/native-app/permission-status lightweight=$lightweight")

    val payload = if (lightweight) {
      buildLightweightPayload(context, appCycle, killedAt, openedAt)
    } else {
      val snapshot = buildSnapshot(context)
      val full = snapshot.payload
      full.put("app_cycle", appCycle)
      full.put("checkedAt", utcNow())
      if (!killedAt.isNullOrEmpty()) {
        full.put("killed_at", killedAt)
      }
      if (!openedAt.isNullOrEmpty()) {
        full.put("opened_at", openedAt)
      }
      full
    }

    var result = postPermissionStatus(
      context,
      payload,
      connectTimeoutMs = connectTimeoutMs,
      readTimeoutMs = readTimeoutMs,
    )
    if (result.code == 401 || result.code == 403) {
      Log.w(TAG, "app_cycle=$appCycle unauthorized; refreshing token")
      if (refreshAccessToken(context)) {
        result = postPermissionStatus(
          context,
          payload,
          connectTimeoutMs = connectTimeoutMs,
          readTimeoutMs = readTimeoutMs,
        )
      }
    }
    val ok = result.code in 200..299
    if (!ok) {
      Log.w(
        TAG,
        "app_cycle=$appCycle failed status=${result.code} body=${result.body?.take(200)}",
      )
    } else {
      Log.i(TAG, "app_cycle=$appCycle status=${result.code}")
    }
    return ok
  }

  /** Minimal payload for kill/wake — reuse last full Flutter snapshot when present. */
  private fun buildLightweightPayload(
    context: Context,
    appCycle: String,
    killedAt: String?,
    openedAt: String?,
  ): JSONObject {
    val push = AndroidPermissionStatusStore.pushStatus(context).let {
      if (it == "disabled") "disabled" else "enabled"
    }
    val cached = AndroidPermissionStatusStore.readFullPermissionsCache(context)
    val permissions = JSONObject()
    if (cached != null) {
      for ((key, value) in cached) {
        permissions.put(key, value)
      }
      if (!permissions.has("push")) {
        permissions.put("push", push)
      }
    } else {
      permissions
        .put("foregroundLocation", "unknown")
        .put("backgroundLocation", "unknown")
        .put("preciseLocation", "unknown")
        .put("notifications", "unknown")
        .put("motionActivity", "unknown")
        .put("batteryOptimization", "unknown")
        .put("backgroundAppRefresh", "unknown")
        .put("push", push)
    }
    val payload = JSONObject()
      .put("platform", "android")
      .put("deviceId", AndroidPermissionStatusStore.deviceId(context))
      .put("appVersion", AndroidPermissionStatusStore.appVersion(context))
      .put("build", AndroidPermissionStatusStore.build(context))
      .put("app_cycle", appCycle)
      .put("checkedAt", utcNow())
      .put("permissions", permissions)
    AndroidPermissionStatusStore.deviceName(context)?.let {
      payload.put("deviceName", it)
    }
    if (!killedAt.isNullOrEmpty()) {
      payload.put("killed_at", killedAt)
    }
    if (!openedAt.isNullOrEmpty()) {
      payload.put("opened_at", openedAt)
    }
    return payload
  }

  private fun seedAuthAndApiBase(context: Context) {
    val dutyAccess = com.smartnps360.app.duty.AndroidDutyKillStore.accessToken(context)
    val dutyRefresh = com.smartnps360.app.duty.AndroidDutyKillStore.refreshToken(context)
    if (AndroidPermissionStatusStore.accessToken(context).isNullOrEmpty() &&
      !dutyAccess.isNullOrEmpty()
    ) {
      AndroidPermissionStatusStore.writeAccessToken(context, dutyAccess)
    }
    if (AndroidPermissionStatusStore.refreshToken(context).isNullOrEmpty() &&
      !dutyRefresh.isNullOrEmpty()
    ) {
      AndroidPermissionStatusStore.writeRefreshToken(context, dutyRefresh)
    }
    val dutyBase = com.smartnps360.app.duty.AndroidDutyKillStore.apiBaseUrl(context)
    if (!dutyBase.isNullOrEmpty()) {
      // Keep kill uploads on the same API host Flutter is using.
      context.getSharedPreferences("smartnps360_android_permission_status", Context.MODE_PRIVATE)
        .edit()
        .putString("api_base_url", dutyBase)
        .apply()
    }
  }

  private fun resolveApiBaseUrl(context: Context): String {
    val dutyBase = com.smartnps360.app.duty.AndroidDutyKillStore.apiBaseUrl(context)
    if (!dutyBase.isNullOrEmpty()) return dutyBase.trimEnd('/')
    return AndroidPermissionStatusStore.apiBaseUrl(context).trimEnd('/')
  }

  private data class HttpResult(val code: Int, val body: String?)

  private fun postPermissionStatus(
    context: Context,
    payload: JSONObject,
    connectTimeoutMs: Int = 12_000,
    readTimeoutMs: Int = 12_000,
  ): HttpResult {
    val token = AndroidPermissionStatusStore.accessToken(context)
      ?: com.smartnps360.app.duty.AndroidDutyKillStore.accessToken(context)
      ?: return HttpResult(0, null)
    val base = resolveApiBaseUrl(context)
    val url = "$base/native-app/permission-status"
    return http(
      "POST",
      url,
      mapOf(
        "Accept" to "application/json",
        "Content-Type" to "application/json",
        "Authorization" to "Bearer $token",
      ),
      payload.toString(),
      connectTimeoutMs = connectTimeoutMs,
      readTimeoutMs = readTimeoutMs,
    )
  }

  private fun refreshAccessToken(context: Context): Boolean {
    var refresh = AndroidPermissionStatusStore.refreshToken(context)
    if (refresh.isNullOrEmpty()) {
      refresh = com.smartnps360.app.duty.AndroidDutyKillStore.refreshToken(context)
    }
    if (refresh.isNullOrEmpty()) return false
    val base = resolveApiBaseUrl(context)
    val body = JSONObject().put("refresh_token", refresh).toString()
    val result = http(
      "POST",
      "$base/auth/refresh",
      mapOf(
        "Accept" to "application/json",
        "Content-Type" to "application/json",
      ),
      body,
    )
    if (result.code !in 200..299 || result.body.isNullOrEmpty()) return false
    return try {
      val json = JSONObject(result.body)
      val payload = if (json.has("data") && json.opt("data") is JSONObject) {
        json.getJSONObject("data")
      } else {
        json
      }
      val access = firstString(payload, "access_token", "accessToken", "token")
      if (access.isNullOrEmpty()) return false
      AndroidPermissionStatusStore.writeAccessToken(context, access)
      com.smartnps360.app.duty.AndroidDutyKillStore.writeAccessToken(context, access)
      val newRefresh = firstString(payload, "refresh_token", "refreshToken")
      if (!newRefresh.isNullOrEmpty()) {
        AndroidPermissionStatusStore.writeRefreshToken(context, newRefresh)
        com.smartnps360.app.duty.AndroidDutyKillStore.writeRefreshToken(context, newRefresh)
      }
      true
    } catch (e: Exception) {
      Log.w(TAG, "refresh parse failed: ${e.message}")
      false
    }
  }

  private fun firstString(json: JSONObject, vararg keys: String): String? {
    for (key in keys) {
      val raw = json.opt(key)?.toString()?.trim()
      if (!raw.isNullOrEmpty() && raw != "null") return raw
    }
    return null
  }

  private fun utcNow(): String {
    val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
    fmt.timeZone = TimeZone.getTimeZone("UTC")
    // Native clock is millisecond-resolution; pad the microsecond part with 000
    // to match the 6-digit ISO-8601 used by updated_at (e.g. ...:00.123000Z).
    return "${fmt.format(Date())}000Z"
  }

  private fun http(
    method: String,
    url: String,
    headers: Map<String, String>,
    body: String?,
    connectTimeoutMs: Int = 12_000,
    readTimeoutMs: Int = 12_000,
  ): HttpResult {
    var connection: HttpURLConnection? = null
    return try {
      connection = (URL(url).openConnection() as HttpURLConnection).apply {
        requestMethod = method
        connectTimeout = connectTimeoutMs
        readTimeout = readTimeoutMs
        doInput = true
        instanceFollowRedirects = true
        headers.forEach { setRequestProperty(it.key, it.value) }
        if (body != null) {
          doOutput = true
          OutputStreamWriter(outputStream, Charsets.UTF_8).use { it.write(body) }
        }
      }
      val code = connection.responseCode
      val stream = if (code in 200..299) connection.inputStream else connection.errorStream
      val text = stream?.let { input ->
        BufferedReader(InputStreamReader(input, Charsets.UTF_8)).use { it.readText() }
      }
      HttpResult(code, text)
    } catch (e: Exception) {
      Log.w(TAG, "$method $url failed: ${e.message}")
      HttpResult(0, null)
    } finally {
      connection?.disconnect()
    }
  }
}
