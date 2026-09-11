package com.smartnps360.app.duty

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

internal object AndroidDutyKillHeartbeat {
  private const val TAG = "AndroidDutyKill"
  private const val HEARTBEAT_URL = "https://smartnps360.com/api/heartbeat"
  private const val REFRESH_URL = "https://smartnps360.com/api/auth/refresh"

  enum class DutyStatus {
    ON_DUTY,
    OFF_DUTY,
    UNPAID_BREAK,
    UNKNOWN,
  }

  fun confirmDuty(context: android.content.Context): DutyStatus {
    val first = authorizedGet(context, HEARTBEAT_URL)
    if (first.code == 401 || first.code == 403) {
      if (!refreshAccessToken(context)) return DutyStatus.UNKNOWN
      return parseDuty(context, authorizedGet(context, HEARTBEAT_URL))
    }
    return parseDuty(context, first)
  }

  private data class HttpResult(val code: Int, val body: String?)

  private fun authorizedGet(context: android.content.Context, url: String): HttpResult {
    val token = AndroidDutyKillStore.accessToken(context) ?: return HttpResult(0, null)
    return http("GET", url, mapOf(
      "Accept" to "application/json",
      "Authorization" to "Bearer $token",
    ), null)
  }

  private fun refreshAccessToken(context: android.content.Context): Boolean {
    val refresh = AndroidDutyKillStore.refreshToken(context) ?: return false
    val body = JSONObject().put("refresh_token", refresh).toString()
    val result = http(
      "POST",
      REFRESH_URL,
      mapOf(
        "Accept" to "application/json",
        "Content-Type" to "application/json",
      ),
      body,
    )
    if (result.code !in 200..299 || result.body.isNullOrEmpty()) return false
    val json = result.body.toJsonValue() ?: return false
    val payload = unwrap(json)
    val access = stringField(payload, "access_token", "accessToken", "token")
    if (access.isNullOrEmpty()) return false
    AndroidDutyKillStore.writeAccessToken(context, access)
    val newRefresh = stringField(payload, "refresh_token", "refreshToken")
    if (!newRefresh.isNullOrEmpty()) {
      AndroidDutyKillStore.writeRefreshToken(context, newRefresh)
    }
    return true
  }

  private fun parseDuty(context: android.content.Context, result: HttpResult): DutyStatus {
    if (result.code !in 200..299) return DutyStatus.UNKNOWN
    val body = result.body ?: return DutyStatus.UNKNOWN
    Log.i(TAG, "heartbeat payload=$body")
    val trimmed = body.trim().lowercase()
    if (trimmed == "on_duty" || trimmed == "\"on_duty\"") {
      AndroidDutyKillStore.setUnpaidBreak(context, false)
      return DutyStatus.ON_DUTY
    }
    if (trimmed == "off_duty" || trimmed == "\"off_duty\"") {
      AndroidDutyKillStore.setUnpaidBreak(context, false)
      return DutyStatus.OFF_DUTY
    }
    val json = body.toJsonValue() ?: return DutyStatus.UNKNOWN
    return parseDutyValue(context, json)
  }

  private fun parseDutyValue(context: android.content.Context, value: Any?): DutyStatus {
    when (value) {
      is String -> return normalize(value)
      is JSONObject -> {
        var duty: DutyStatus = DutyStatus.UNKNOWN
        for (key in arrayOf("status", "duty_status", "dutyStatus", "duty", "state")) {
          if (!value.has(key)) continue
          val parsed = when (val nested = value.opt(key)) {
            is String -> normalize(nested)
            else -> parseDutyValue(context, nested)
          }
          if (parsed != DutyStatus.UNKNOWN) {
            duty = parsed
            break
          }
        }

        if (duty == DutyStatus.ON_DUTY) {
          if (isUnpaidBreak(value)) {
            AndroidDutyKillStore.setUnpaidBreak(context, true)
            return DutyStatus.UNPAID_BREAK
          }
          AndroidDutyKillStore.setUnpaidBreak(context, false)
          return DutyStatus.ON_DUTY
        }
        if (duty == DutyStatus.OFF_DUTY) {
          AndroidDutyKillStore.setUnpaidBreak(context, false)
          return DutyStatus.OFF_DUTY
        }

        for (key in arrayOf("data", "payload", "result")) {
          if (value.has(key)) {
            val parsed = parseDutyValue(context, value.opt(key))
            if (parsed != DutyStatus.UNKNOWN) return parsed
          }
        }
      }
    }
    return DutyStatus.UNKNOWN
  }

  private fun isUnpaidBreak(map: JSONObject): Boolean {
    val working = map.optString("working_status", map.optString("workingStatus", ""))
      .trim()
      .lowercase()
    val onBreak = working == "on_break" ||
      working == "on-break" ||
      working == "onbreak" ||
      working == "break"
    if (!onBreak) return false

    if (map.has("break_paid")) {
      when (val raw = map.opt("break_paid")) {
        is Boolean -> return !raw
        else -> {
          val text = raw?.toString()?.trim()?.lowercase()
          if (text == "true" || text == "1" || text == "paid") return false
          if (text == "false" || text == "0" || text == "unpaid") return true
        }
      }
    }
    if (map.has("breakPaid")) {
      when (val raw = map.opt("breakPaid")) {
        is Boolean -> return !raw
        else -> {
          val text = raw?.toString()?.trim()?.lowercase()
          if (text == "true" || text == "1" || text == "paid") return false
          if (text == "false" || text == "0" || text == "unpaid") return true
        }
      }
    }

    val breakType = map.optString("break_type", map.optString("breakType", ""))
      .trim()
      .lowercase()
    return breakType == "unpaid" || breakType == "break_unpaid"
  }

  private fun normalize(raw: String): DutyStatus {
    val value = raw.trim().lowercase()
    if (value == "on_duty" || value == "onduty" || value == "on-duty") {
      return DutyStatus.ON_DUTY
    }
    if (value == "off_duty" || value == "offduty" || value == "off-duty") {
      return DutyStatus.OFF_DUTY
    }
    return DutyStatus.UNKNOWN
  }

  private fun unwrap(value: Any): Any {
    if (value is JSONObject && value.has("data")) {
      return value.opt("data") ?: value
    }
    return value
  }

  private fun stringField(value: Any, vararg keys: String): String? {
    if (value !is JSONObject) return null
    for (key in keys) {
      val raw = value.opt(key)?.toString()?.trim()
      if (!raw.isNullOrEmpty() && raw != "null") return raw
    }
    return null
  }

  private fun String.toJsonValue(): Any? {
    return try {
      when {
        startsWith("{") -> JSONObject(this)
        startsWith("[") -> JSONArray(this)
        else -> null
      }
    } catch (e: Exception) {
      Log.w(TAG, "json parse failed: ${e.message}")
      null
    }
  }

  private fun http(
    method: String,
    url: String,
    headers: Map<String, String>,
    body: String?,
  ): HttpResult {
    var connection: HttpURLConnection? = null
    return try {
      connection = (URL(url).openConnection() as HttpURLConnection).apply {
        requestMethod = method
        connectTimeout = 10_000
        readTimeout = 10_000
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
