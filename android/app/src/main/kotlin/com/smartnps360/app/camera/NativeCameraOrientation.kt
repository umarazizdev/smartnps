package com.smartnps360.app.camera

import android.media.MediaMetadataRetriever
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import java.io.File

/**
 * Landscape validation for captured stills (EXIF-aware) and videos
 * (display size after rotation metadata).
 */
object NativeCameraOrientation {
  data class MediaSize(
    val width: Int,
    val height: Int,
    val orientationDegrees: Int,
  ) {
    val isLandscape: Boolean get() = width > height
    val isPortrait: Boolean get() = height > width
  }

  fun readPhotoSize(file: File): MediaSize? {
    return try {
      val exif = ExifInterface(file.absolutePath)
      val rawW = exif.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)
      val rawH = exif.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)
      val orientation = exif.getAttributeInt(
        ExifInterface.TAG_ORIENTATION,
        ExifInterface.ORIENTATION_NORMAL,
      )
      val degrees = orientationToDegrees(orientation)
      var width = rawW
      var height = rawH
      if (width <= 0 || height <= 0) {
        // Some OEMs omit EXIF pixel size; decode bounds only (no full decode).
        val bounds = android.graphics.BitmapFactory.Options().apply {
          inJustDecodeBounds = true
        }
        android.graphics.BitmapFactory.decodeFile(file.absolutePath, bounds)
        width = bounds.outWidth
        height = bounds.outHeight
      }
      if (width <= 0 || height <= 0) {
        null
      } else {
        val (w, h) = if (degrees == 90 || degrees == 270) {
          height to width
        } else {
          width to height
        }
        MediaSize(width = w, height = h, orientationDegrees = degrees)
      }
    } catch (error: Exception) {
      Log.d(NativeCameraContract.LOG_TAG, "photo EXIF read failed: ${error.message}")
      null
    }
  }

  fun readVideoSize(file: File): MediaSize? {
    val retriever = MediaMetadataRetriever()
    return try {
      retriever.setDataSource(file.absolutePath)
      val rawW = retriever.extractMetadata(
        MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
      )?.toIntOrNull() ?: 0
      val rawH = retriever.extractMetadata(
        MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
      )?.toIntOrNull() ?: 0
      val rotation = retriever.extractMetadata(
        MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
      )?.toIntOrNull() ?: 0
      val (w, h) = if (rotation == 90 || rotation == 270) {
        rawH to rawW
      } else {
        rawW to rawH
      }
      if (w <= 0 || h <= 0) null
      else MediaSize(width = w, height = h, orientationDegrees = rotation)
    } catch (error: Exception) {
      Log.d(NativeCameraContract.LOG_TAG, "video metadata read failed: ${error.message}")
      null
    } finally {
      try {
        retriever.release()
      } catch (_: Exception) {
      }
    }
  }

  fun readVideoDurationMs(file: File): Long? {
    val retriever = MediaMetadataRetriever()
    return try {
      retriever.setDataSource(file.absolutePath)
      retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
        ?.toLongOrNull()
    } catch (_: Exception) {
      null
    } finally {
      try {
        retriever.release()
      } catch (_: Exception) {
      }
    }
  }

  fun isLandscapePhoto(file: File): Boolean {
    // FAIL CLOSED: unverifiable EXIF/dimensions must reject evidence.
    val size = readPhotoSize(file) ?: return false
    return size.isLandscape
  }

  fun isLandscapeVideo(file: File): Boolean {
    // FAIL CLOSED: unverifiable video track must reject evidence.
    val size = readVideoSize(file) ?: return false
    return size.isLandscape
  }

  private fun orientationToDegrees(orientation: Int): Int {
    return when (orientation) {
      ExifInterface.ORIENTATION_ROTATE_90,
      ExifInterface.ORIENTATION_TRANSPOSE,
      -> 90
      ExifInterface.ORIENTATION_ROTATE_180,
      ExifInterface.ORIENTATION_FLIP_VERTICAL,
      -> 180
      ExifInterface.ORIENTATION_ROTATE_270,
      ExifInterface.ORIENTATION_TRANSVERSE,
      -> 270
      else -> 0
    }
  }
}
