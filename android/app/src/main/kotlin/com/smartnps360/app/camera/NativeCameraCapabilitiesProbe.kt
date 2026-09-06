package com.smartnps360.app.camera

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.media.CamcorderProfile
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.extensions.ExtensionMode
import androidx.camera.extensions.ExtensionsManager
import androidx.camera.lifecycle.ProcessCameraProvider
import java.util.concurrent.TimeUnit

/**
 * Probes rear-camera capabilities for [NativeCameraPlugin.getCapabilities]
 * without presenting UI.
 */
object NativeCameraCapabilitiesProbe {
  @Volatile
  private var cachedPhoto: Map<String, Any?>? = null
  @Volatile
  private var cachedVideo: Map<String, Any?>? = null

  fun probe(context: Context, type: String): Map<String, Any?> {
    val isVideo = type == NativeCameraContract.TYPE_VIDEO
    val cached = if (isVideo) cachedVideo else cachedPhoto
    if (cached != null) {
      Log.d(NativeCameraContract.LOG_TAG, "CAPABILITY_PROBE_CACHE_HIT type=$type")
      return cached
    }
    Log.d(NativeCameraContract.LOG_TAG, "CAPABILITY_PROBE_START type=$type")
    val started = SystemClock.elapsedRealtime()
    val result = probeUncached(context, type)
    Log.d(
      NativeCameraContract.LOG_TAG,
      "CAPABILITY_PROBE_END type=$type +${SystemClock.elapsedRealtime() - started}ms",
    )
    if (isVideo) cachedVideo = result else cachedPhoto = result
    return result
  }

  fun invalidateCache() {
    cachedPhoto = null
    cachedVideo = null
  }

  private fun probeUncached(context: Context, type: String): Map<String, Any?> {
    return try {
      val providerFuture = ProcessCameraProvider.getInstance(context)
      val provider = providerFuture.get(8, TimeUnit.SECONDS)
      val hasBack = provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
      if (!hasBack) {
        return emptyCapabilities()
      }

      // Probe every extension mode independently — HDR / NIGHT must never be
      // inferred from AUTO availability.
      var hdr = false
      var night = false
      var auto = false
      try {
        val extFuture = ExtensionsManager.getInstanceAsync(context, provider)
        val extensions = extFuture.get(8, TimeUnit.SECONDS)
        val back = CameraSelector.DEFAULT_BACK_CAMERA
        hdr = isExtensionAvailable(extensions, back, ExtensionMode.HDR)
        night = isExtensionAvailable(extensions, back, ExtensionMode.NIGHT)
        auto = isExtensionAvailable(extensions, back, ExtensionMode.AUTO)
        // Share with session so camera open can skip a second extension probe.
        val labels = mutableListOf<String>()
        if (auto) labels.add("auto")
        if (hdr) labels.add("hdr")
        if (night) labels.add("night")
        NativeCameraSession.processExtensionCache = labels
      } catch (error: Exception) {
        Log.d(
          NativeCameraContract.LOG_TAG,
          "extensions probe skipped: ${error.message}",
        )
      }

      val zoom = probeZoom(context)
      val flash = probeFlash(context)
      val isVideo = type == NativeCameraContract.TYPE_VIDEO
      val rear = rearCharacteristics(context)
      val chars = rear?.second
      val exposure = probeExposure(chars)
      val video = probeVideoQualities(rear?.first)

      val extensionModes = mutableListOf<String>()
      if (!isVideo) {
        if (auto) extensionModes.add(NativeCameraContract.ExtensionModeLabel.AUTO)
        if (hdr) extensionModes.add(NativeCameraContract.ExtensionModeLabel.HDR)
        if (night) extensionModes.add(NativeCameraContract.ExtensionModeLabel.NIGHT)
      }

      val logicalMultiCamera = physicalCameraIds(chars).isNotEmpty()
      val photoSize = probeMaxJpegSize(chars)

      mapOf(
        "rearCameraAvailable" to true,
        "logicalMultiCamera" to logicalMultiCamera,
        "hdrPhoto" to (!isVideo && hdr),
        "nightPhoto" to (!isVideo && night),
        "autoExtension" to (!isVideo && auto),
        "supportedExtensionModes" to extensionModes,
        "flash" to flash,
        "torch" to flash,
        "tapToFocus" to true,
        "continuousAutofocus" to probeContinuousAutofocus(chars),
        "exposureCompensation" to exposure.supported,
        "minExposureIndex" to exposure.minIndex,
        "maxExposureIndex" to exposure.maxIndex,
        "exposureStep" to exposure.step,
        "stabilization" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP),
        "heic" to false,
        // Android has no public low-light-boost API; iOS-only capability.
        "lowLightBoost" to false,
        "virtualDeviceFusion" to logicalMultiCamera,
        "distortionCorrection" to false,
        "ultraWide" to (zoom.min <= 0.70),
        "telephoto" to zoom.usefulLevels.any { it >= 1.9 },
        "hdrVideo" to false,
        "videoHd" to video.hd,
        "videoFhd" to video.fhd,
        "videoUhd" to video.uhd,
        "highQualityCapture" to true,
        "maxPhotoWidth" to photoSize?.first,
        "maxPhotoHeight" to photoSize?.second,
        "availableSceneModes" to probeSceneModes(chars),
        "usefulZoomLevels" to zoom.usefulLevels,
        "minZoom" to zoom.min,
        "maxZoom" to zoom.cappedMax,
      )
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "capabilities probe failed: ${error.message}",
      )
      emptyCapabilities()
    }
  }

  private fun emptyCapabilities(): Map<String, Any?> = mapOf(
    "rearCameraAvailable" to false,
    "logicalMultiCamera" to false,
    "hdrPhoto" to false,
    "nightPhoto" to false,
    "autoExtension" to false,
    "supportedExtensionModes" to emptyList<String>(),
    "flash" to false,
    "torch" to false,
    "tapToFocus" to false,
    "continuousAutofocus" to false,
    "exposureCompensation" to false,
    "minExposureIndex" to null,
    "maxExposureIndex" to null,
    "exposureStep" to null,
    "stabilization" to false,
    "heic" to false,
    "lowLightBoost" to false,
    "virtualDeviceFusion" to false,
    "distortionCorrection" to false,
    "ultraWide" to false,
    "telephoto" to false,
    "hdrVideo" to false,
    "videoHd" to false,
    "videoFhd" to false,
    "videoUhd" to false,
    "highQualityCapture" to false,
    "maxPhotoWidth" to null,
    "maxPhotoHeight" to null,
    "availableSceneModes" to emptyList<String>(),
    "usefulZoomLevels" to emptyList<Double>(),
    "minZoom" to 1.0,
    "maxZoom" to 1.0,
  )

  private fun isExtensionAvailable(
    extensions: ExtensionsManager,
    selector: CameraSelector,
    mode: Int,
  ): Boolean {
    return try {
      extensions.isExtensionAvailable(selector, mode)
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "extension mode=$mode probe failed: ${error.message}",
      )
      false
    }
  }

  data class ExposureInfo(
    val supported: Boolean,
    val minIndex: Int?,
    val maxIndex: Int?,
    val step: Double?,
  )

  data class VideoQualityInfo(
    val hd: Boolean,
    val fhd: Boolean,
    val uhd: Boolean,
  )

  /** Best rear camera characteristics: prefer a logical multi-camera. */
  private fun rearCharacteristics(
    context: Context,
  ): Pair<String, CameraCharacteristics>? {
    return try {
      val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      var fallback: Pair<String, CameraCharacteristics>? = null
      for (id in manager.cameraIdList) {
        val chars = try {
          manager.getCameraCharacteristics(id)
        } catch (_: Exception) {
          continue
        }
        if (chars.get(CameraCharacteristics.LENS_FACING) !=
          CameraCharacteristics.LENS_FACING_BACK
        ) {
          continue
        }
        if (physicalCameraIds(chars).isNotEmpty()) return id to chars
        if (fallback == null) fallback = id to chars
      }
      fallback
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "rear characteristics probe failed: ${error.message}",
      )
      null
    }
  }

  private fun physicalCameraIds(chars: CameraCharacteristics?): Set<String> {
    if (chars == null) return emptySet()
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return emptySet()
    return try {
      chars.physicalCameraIds
    } catch (_: Exception) {
      emptySet()
    }
  }

  /** Real AE compensation support — a [0, 0] range means unsupported. */
  private fun probeExposure(chars: CameraCharacteristics?): ExposureInfo {
    if (chars == null) return ExposureInfo(false, null, null, null)
    return try {
      val range = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        ?: return ExposureInfo(false, null, null, null)
      val lower: Int = range.lower
      val upper: Int = range.upper
      val supported = upper > lower
      val step = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
        ?.toDouble()
      ExposureInfo(
        supported = supported,
        minIndex = if (supported) lower else null,
        maxIndex = if (supported) upper else null,
        step = if (supported) step else null,
      )
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "exposure probe failed: ${error.message}",
      )
      ExposureInfo(false, null, null, null)
    }
  }

  private fun probeContinuousAutofocus(chars: CameraCharacteristics?): Boolean {
    if (chars == null) return false
    return try {
      val modes = chars.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
        ?: return false
      modes.any {
        it == CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE ||
          it == CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO
      }
    } catch (_: Exception) {
      false
    }
  }

  /** Debug-only scene mode names for the bound rear camera. */
  private fun probeSceneModes(chars: CameraCharacteristics?): List<String> {
    if (chars == null) return emptyList()
    return try {
      val modes = chars.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES)
        ?: return emptyList()
      modes.map { sceneModeName(it) }.distinct()
    } catch (_: Exception) {
      emptyList()
    }
  }

  private fun sceneModeName(mode: Int): String = when (mode) {
    CameraMetadata.CONTROL_SCENE_MODE_DISABLED -> "disabled"
    CameraMetadata.CONTROL_SCENE_MODE_FACE_PRIORITY -> "facePriority"
    CameraMetadata.CONTROL_SCENE_MODE_ACTION -> "action"
    CameraMetadata.CONTROL_SCENE_MODE_PORTRAIT -> "portrait"
    CameraMetadata.CONTROL_SCENE_MODE_LANDSCAPE -> "landscape"
    CameraMetadata.CONTROL_SCENE_MODE_NIGHT -> "night"
    CameraMetadata.CONTROL_SCENE_MODE_NIGHT_PORTRAIT -> "nightPortrait"
    CameraMetadata.CONTROL_SCENE_MODE_THEATRE -> "theatre"
    CameraMetadata.CONTROL_SCENE_MODE_BEACH -> "beach"
    CameraMetadata.CONTROL_SCENE_MODE_SNOW -> "snow"
    CameraMetadata.CONTROL_SCENE_MODE_SUNSET -> "sunset"
    CameraMetadata.CONTROL_SCENE_MODE_STEADYPHOTO -> "steadyPhoto"
    CameraMetadata.CONTROL_SCENE_MODE_FIREWORKS -> "fireworks"
    CameraMetadata.CONTROL_SCENE_MODE_SPORTS -> "sports"
    CameraMetadata.CONTROL_SCENE_MODE_PARTY -> "party"
    CameraMetadata.CONTROL_SCENE_MODE_CANDLELIGHT -> "candlelight"
    CameraMetadata.CONTROL_SCENE_MODE_BARCODE -> "barcode"
    CameraMetadata.CONTROL_SCENE_MODE_HDR -> "hdr"
    else -> "scene_$mode"
  }

  private fun probeMaxJpegSize(chars: CameraCharacteristics?): Pair<Int, Int>? {
    if (chars == null) return null
    return try {
      val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        ?: return null
      val best = map.getOutputSizes(ImageFormat.JPEG)
        ?.maxByOrNull { it.width.toLong() * it.height.toLong() }
        ?: return null
      best.width to best.height
    } catch (_: Exception) {
      null
    }
  }

  /**
   * Best-effort video quality probe via CamcorderProfile so no CameraX bind is
   * required. Falls back to HD/FHD true for rear cameras.
   */
  private fun probeVideoQualities(cameraId: String?): VideoQualityInfo {
    val numericId = cameraId?.toIntOrNull()
      ?: return VideoQualityInfo(hd = true, fhd = true, uhd = false)
    return try {
      VideoQualityInfo(
        hd = CamcorderProfile.hasProfile(numericId, CamcorderProfile.QUALITY_720P),
        fhd = CamcorderProfile.hasProfile(numericId, CamcorderProfile.QUALITY_1080P),
        uhd = CamcorderProfile.hasProfile(numericId, CamcorderProfile.QUALITY_2160P),
      )
    } catch (error: Exception) {
      Log.d(
        NativeCameraContract.LOG_TAG,
        "video quality probe failed: ${error.message}",
      )
      VideoQualityInfo(hd = true, fhd = true, uhd = false)
    }
  }

  data class ZoomInfo(
    val min: Double,
    val max: Double,
    val cappedMax: Double,
    val usefulLevels: List<Double>,
  )

  fun probeZoom(context: Context): ZoomInfo {
    return try {
      // Probe DEFAULT back logical camera only — do not merge every rear
      // sensor id (that falsely advertises 0.5x when UW is a separate camera).
      val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      val providerFuture = ProcessCameraProvider.getInstance(context)
      val provider = providerFuture.get(8, TimeUnit.SECONDS)
      if (!provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
        return ZoomInfo(1.0, 1.0, 1.0, listOf(1.0))
      }

      // Prefer Camera2 zoom range of the first rear logical camera that looks
      // like the primary multi-cam device (largest zoom span).
      var bestMin = 1.0
      var bestMax = 1.0
      var bestId: String? = null
      var bestSpan = -1.0
      for (id in manager.cameraIdList) {
        val chars = manager.getCameraCharacteristics(id)
        val facing = chars.get(CameraCharacteristics.LENS_FACING)
        if (facing != CameraCharacteristics.LENS_FACING_BACK) continue
        // Skip dedicated physical-only sensors when possible; prefer logical.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
          val physical = chars.physicalCameraIds
          val isLogical = physical.isNotEmpty()
          val range = chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE) ?: continue
          val minZ = range.lower.toDouble()
          val maxZ = range.upper.toDouble()
          val span = maxZ - minZ + if (isLogical) 100.0 else 0.0
          if (span > bestSpan) {
            bestSpan = span
            bestMin = minZ
            bestMax = maxZ
            bestId = id
          }
        } else {
          val range = chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
          if (range != null) {
            val minZ = range.lower.toDouble()
            val maxZ = range.upper.toDouble()
            val span = maxZ - minZ
            if (span > bestSpan) {
              bestSpan = span
              bestMin = minZ
              bestMax = maxZ
              bestId = id
            }
          }
        }
      }

      val capped = NativeCameraZoom.capMaxZoom(bestMin, bestMax)
      val optical = NativeCameraZoom.opticalZoomRatios(context, bestId)
      ZoomInfo(
        min = bestMin,
        max = bestMax,
        cappedMax = capped,
        usefulLevels = NativeCameraZoom.usefulLevels(bestMin, capped, optical),
      )
    } catch (error: Exception) {
      Log.d(NativeCameraContract.LOG_TAG, "zoom probe failed: ${error.message}")
      ZoomInfo(1.0, 1.0, 1.0, listOf(1.0))
    }
  }

  fun probeFlash(context: Context): Boolean {
    return try {
      val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      manager.cameraIdList.any { id ->
        val chars = manager.getCameraCharacteristics(id)
        val facing = chars.get(CameraCharacteristics.LENS_FACING)
        facing == CameraCharacteristics.LENS_FACING_BACK &&
          chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
      }
    } catch (_: Exception) {
      false
    }
  }
}

object NativeCameraZoom {
  /** Cap extreme digital zoom relative to 1x. */
  fun capMaxZoom(minZoom: Double, deviceMax: Double): Double {
    val relativeCap = 8.0
    return minOf(deviceMax, maxOf(minZoom, relativeCap))
  }

  /**
   * Stock-camera style zoom chips from the *bound* camera only.
   *
   * - Ultra-wide only when [minZoom] is below ~1x (or optical reports UW)
   * - 1x always when available
   * - Tele only from real optical ratios / clear switchovers
   * - Never invent digital 5x shortcuts the OS camera does not show
   */
  fun usefulLevels(
    minZoom: Double,
    maxZoom: Double,
    opticalRatios: List<Double> = emptyList(),
  ): List<Double> {
    val levels = linkedSetOf<Double>()
    val optical = opticalRatios.map { niceZoom(it) }.distinct().sorted()

    // Ultra-wide from bound zoom range and/or optical focal ratios.
    val opticalUltra = optical.filter { it in 0.35..0.75 }
    when {
      minZoom <= 0.70 -> {
        val ultra = when {
          minZoom <= 0.55 -> 0.5
          opticalUltra.isNotEmpty() -> opticalUltra.first()
          else -> niceZoom(minZoom)
        }
        val clamped = ultra.coerceIn(minZoom, maxZoom)
        if (clamped <= 0.75) levels.add(clamped)
      }
      opticalUltra.isNotEmpty() && opticalUltra.first() >= minZoom - 0.02 -> {
        levels.add(opticalUltra.first().coerceIn(minZoom, maxZoom))
      }
    }

    // Primary wide / 1x — stock default lens.
    if (maxZoom >= 0.95) {
      val oneX = 1.0.coerceIn(minZoom.coerceAtMost(1.0), maxZoom)
      levels.add(oneX)
    }

    // Optical tele / switchover levels (2x, 3x, …) only when real.
    val opticalTele = optical
      .filter { it >= 1.4 && it <= maxZoom + 0.05 }
      .distinct()
      .sorted()

    for (ratio in opticalTele) {
      val clamped = ratio.coerceIn(minZoom, maxZoom)
      if (levels.none { abs(it - clamped) < 0.12 }) {
        levels.add(clamped)
      }
    }

    // Dual-cam without optical metadata: expose a single 2x if in range.
    if (opticalTele.isEmpty() && maxZoom >= 1.95 && minZoom <= 1.05) {
      if (levels.none { abs(it - 2.0) < 0.12 }) {
        levels.add(2.0.coerceIn(minZoom, maxZoom))
      }
    }

    if (levels.isEmpty()) {
      levels.add(1.0.coerceIn(minZoom, maxZoom))
    }

    return levels.sorted().take(4)
  }

  /**
   * Optical zoom ratios for the active logical camera, relative to the
   * primary wide lens (1x). Ultra-wide ratios are < 1; tele > 1.
   */
  fun opticalZoomRatios(context: Context, cameraId: String?): List<Double> {
    if (cameraId.isNullOrBlank()) return emptyList()
    return try {
      val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      val logical = manager.getCameraCharacteristics(cameraId)
      val physicalIds = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        logical.physicalCameraIds
      } else {
        emptySet()
      }

      val focals = mutableListOf<Double>()
      if (physicalIds.isNotEmpty()) {
        for (pid in physicalIds) {
          val chars = try {
            manager.getCameraCharacteristics(pid)
          } catch (_: Exception) {
            continue
          }
          val lensFacing = chars.get(CameraCharacteristics.LENS_FACING)
          if (lensFacing != null && lensFacing != CameraCharacteristics.LENS_FACING_BACK) {
            continue
          }
          val available = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            ?: continue
          val shortest = available.minOrNull()?.toDouble() ?: continue
          focals.add(shortest)
        }
      } else {
        val available = logical.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
        if (available != null) {
          for (f in available) focals.add(f.toDouble())
        }
      }

      if (focals.size < 2) return emptyList()
      focals.sort()

      // Primary wide ≈ second-shortest focal when UW exists; otherwise shortest.
      val hasUltraWidePair = focals.size >= 2 && focals[0] / focals[1] <= 0.75
      val wideFocal = if (hasUltraWidePair) focals[1] else focals[0]
      if (wideFocal <= 0.0) return emptyList()

      focals.map { niceZoom(it / wideFocal) }
        .filter { it > 0.0 }
        .distinct()
        .sorted()
    } catch (error: Exception) {
      Log.d(NativeCameraContract.LOG_TAG, "optical zoom probe failed: ${error.message}")
      emptyList()
    }
  }

  fun lensLabel(zoomRatio: Double, minZoom: Double): String {
    return when {
      zoomRatio < 0.95 || (minZoom < 0.95 && zoomRatio <= minZoom + 0.05) -> "ultrawide"
      zoomRatio >= 2.4 -> "tele"
      else -> "wide"
    }
  }

  private fun niceZoom(value: Double): Double {
    val candidates = listOf(0.5, 0.6, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 10.0)
    val nearest = candidates.minByOrNull { abs(it - value) } ?: value
    return if (abs(nearest - value) <= 0.35) nearest else (Math.round(value * 10.0) / 10.0)
  }

  private fun abs(value: Double): Double = kotlin.math.abs(value)
}
