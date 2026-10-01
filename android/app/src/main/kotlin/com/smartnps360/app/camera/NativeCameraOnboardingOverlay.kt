package com.smartnps360.app.camera

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Typeface
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.toColorInt

/**
 * First-launch Capture coachmarks: dark scrim with a cutout around the active
 * control, short copy, and Next / Skip actions.
 *
 * Step content is supplied from Flutter; this view only resolves targets and
 * renders the spotlight UI.
 */
class NativeCameraOnboardingOverlay @JvmOverloads constructor(
  context: Context,
  attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

  data class Step(
    val id: String,
    val title: String,
    val body: String,
    val arrow: String,
  )

  fun interface TargetResolver {
    fun resolve(stepId: String): View?
  }

  fun interface StepPreparer {
    fun prepare(stepId: String)
  }

  var onCompleted: (() -> Unit)? = null
  var onFinishedUi: (() -> Unit)? = null
  private var preparer: StepPreparer? = null

  private val density = resources.displayMetrics.density
  private val scrimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = "#B8000000".toColorInt()
  }
  private val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
  }
  private val holeStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    strokeWidth = 2.5f * density
    color = "#FFE48E15".toColorInt()
  }
  private val arrowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.FILL
    color = "#FFE48E15".toColorInt()
  }
  private val connectorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    strokeWidth = 2.25f * density
    strokeCap = Paint.Cap.ROUND
    color = "#E6E48E15".toColorInt()
  }

  private val holeRect = RectF()
  private val cardRect = RectF()
  private val arrowPath = Path()
  private val connectorPath = Path()
  private val overlapScratch = RectF()

  private val card = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(dp(16), dp(14), dp(16), dp(14))
    setBackgroundColor("#F21A2332".toColorInt())
    elevation = 12f * density
  }
  private val stepLabel = TextView(context).apply {
    setTextColor("#FF94A3B8".toColorInt())
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
    typeface = Typeface.DEFAULT_BOLD
  }
  private val titleView = TextView(context).apply {
    setTextColor("#FFF1F5F9".toColorInt())
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
    typeface = Typeface.DEFAULT_BOLD
    setPadding(0, dp(4), 0, 0)
  }
  private val bodyView = TextView(context).apply {
    setTextColor("#FFCBD5E1".toColorInt())
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
    setLineSpacing(0f, 1.25f)
    setPadding(0, dp(6), 0, dp(12))
  }
  private val actions = LinearLayout(context).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.END
  }
  private val skipButton = TextView(context).apply {
    text = "Skip"
    setTextColor("#FFCBD5E1".toColorInt())
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
    typeface = Typeface.DEFAULT_BOLD
    setPadding(dp(14), dp(8), dp(14), dp(8))
    isClickable = true
    isFocusable = true
  }
  private val nextButton = TextView(context).apply {
    text = "Next"
    setTextColor("#FF022A67".toColorInt())
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
    typeface = Typeface.DEFAULT_BOLD
    setBackgroundColor("#FFE48E15".toColorInt())
    setPadding(dp(18), dp(8), dp(18), dp(8))
    isClickable = true
    isFocusable = true
  }

  private var steps: List<Step> = emptyList()
  private var index = 0
  private var resolver: TargetResolver? = null
  private var currentTarget: View? = null
  private var arrowDirection = "auto"

  init {
    setWillNotDraw(false)
    // Needed for CLEAR cutouts.
    setLayerType(LAYER_TYPE_HARDWARE, null)
    isClickable = true
    isFocusable = true
    // Camera chrome (zoom rail, shutter rail, flash) uses elevation up to ~13dp.
    // Without a higher Z here, bringToFront() alone still leaves tips behind those views.
    elevation = OVERLAY_ELEVATION_DP * density
    translationZ = OVERLAY_ELEVATION_DP * density

    actions.addView(skipButton)
    actions.addView(
      nextButton,
      LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
      ).apply { marginStart = dp(8) },
    )
    card.addView(stepLabel)
    card.addView(titleView)
    card.addView(bodyView)
    card.addView(actions)
    addView(
      card,
      LayoutParams(dp(300), LayoutParams.WRAP_CONTENT),
    )

    skipButton.setOnClickListener { finishTour(completed = true) }
    nextButton.setOnClickListener { advance() }
  }

  fun start(
    steps: List<Step>,
    resolver: TargetResolver,
    preparer: StepPreparer? = null,
  ) {
    this.resolver = resolver
    this.preparer = preparer
    // Keep the full list; missing targets are skipped per-step after prepare.
    this.steps = steps
    index = 0
    visibility = View.VISIBLE
    // Re-assert stacking every start — siblings may have been elevated later.
    elevation = OVERLAY_ELEVATION_DP * density
    translationZ = OVERLAY_ELEVATION_DP * density
    bringToFront()
    alpha = 0f
    animate().alpha(1f).setDuration(220L).start()
    post { showCurrentStep() }
  }

  fun isActive(): Boolean = visibility == View.VISIBLE && steps.isNotEmpty()

  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
    super.onLayout(changed, left, top, right, bottom)
    if (visibility == View.VISIBLE) {
      layoutCurrentStep()
    }
  }

  override fun dispatchDraw(canvas: Canvas) {
    val checkpoint = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), scrimPaint)
    if (!holeRect.isEmpty) {
      val radius = 18f * density
      canvas.drawRoundRect(holeRect, radius, radius, clearPaint)
      canvas.drawRoundRect(holeRect, radius, radius, holeStrokePaint)
    }
    canvas.restoreToCount(checkpoint)
    // Card first, then connector + caret on top so the pointer is never buried.
    super.dispatchDraw(canvas)
    if (!connectorPath.isEmpty) {
      canvas.drawPath(connectorPath, connectorPaint)
    }
    if (!arrowPath.isEmpty) {
      canvas.drawPath(arrowPath, arrowPaint)
    }
  }

  private fun advance() {
    index += 1
    while (index <= steps.lastIndex) {
      preparer?.prepare(steps[index].id)
      if (isUsableTarget(resolver?.resolve(steps[index].id))) break
      index += 1
    }
    if (index > steps.lastIndex) {
      finishTour(completed = true)
      return
    }
    showCurrentStep()
  }

  private fun finishTour(completed: Boolean) {
    if (completed) {
      onCompleted?.invoke()
    }
    onFinishedUi?.invoke()
    animate()
      .alpha(0f)
      .setDuration(160L)
      .withEndAction {
        visibility = View.GONE
        steps = emptyList()
        currentTarget = null
      }
      .start()
  }

  private fun isUsableTarget(target: View?): Boolean {
    if (target == null) return false
    if (target.visibility == View.GONE) return false
    return target.width > 0 && target.height > 0
  }

  private fun showCurrentStep(attempt: Int = 0) {
    while (index <= steps.lastIndex) {
      val candidate = steps[index]
      preparer?.prepare(candidate.id)
      if (isUsableTarget(resolver?.resolve(candidate.id))) break
      index += 1
    }
    if (index > steps.lastIndex) {
      if (attempt < 6) {
        index = 0
        postDelayed({ showCurrentStep(attempt + 1) }, 160L)
        return
      }
      finishTour(completed = false)
      return
    }

    val step = steps[index]
    preparer?.prepare(step.id)
    currentTarget = resolver?.resolve(step.id)
    if (!isUsableTarget(currentTarget)) {
      if (attempt < 6) {
        postDelayed({ showCurrentStep(attempt + 1) }, 160L)
        return
      }
      index += 1
      showCurrentStep(attempt)
      return
    }

    arrowDirection = step.arrow
    stepLabel.text = "Tip ${index + 1} of ${steps.size}"
    titleView.text = step.title
    bodyView.text = step.body
    val hasMore = (index + 1..steps.lastIndex).any { i ->
      preparer?.prepare(steps[i].id)
      isUsableTarget(resolver?.resolve(steps[i].id))
    }
    // Restore current demo after the look-ahead.
    preparer?.prepare(step.id)
    currentTarget = resolver?.resolve(step.id)
    nextButton.text = if (hasMore) "Next" else "Done"
    layoutCurrentStep()
    invalidate()
  }

  private fun layoutCurrentStep() {
    val target = currentTarget ?: return
    val loc = IntArray(2)
    val selfLoc = IntArray(2)
    target.getLocationInWindow(loc)
    getLocationInWindow(selfLoc)
    val pad = 10f * density
    holeRect.set(
      loc[0] - selfLoc[0] - pad,
      loc[1] - selfLoc[1] - pad,
      loc[0] - selfLoc[0] + target.width + pad,
      loc[1] - selfLoc[1] + target.height + pad,
    )

    card.measure(
      MeasureSpec.makeMeasureSpec(dp(300), MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
    )
    val cardW = card.measuredWidth
    val cardH = card.measuredHeight
    val margin = dp(20)
    val gap = dp(36)
    val holeCx = holeRect.centerX()

    val preferred = when (arrowDirection.lowercase()) {
      "left" -> "left"
      "right" -> "right"
      "up" -> "up"
      "down" -> "down"
      else -> if (holeCx > width * 0.55f) "left" else "right"
    }

    val (cardLeft, cardTop, resolved) = placeCard(
      preferred = preferred,
      cardW = cardW,
      cardH = cardH,
      margin = margin,
      gap = gap,
    )

    card.layout(cardLeft, cardTop, cardLeft + cardW, cardTop + cardH)
    cardRect.set(
      cardLeft.toFloat(),
      cardTop.toFloat(),
      (cardLeft + cardW).toFloat(),
      (cardTop + cardH).toFloat(),
    )
    buildPointer(resolved)
  }

  /**
   * Prefer the catalog arrow side, but never let the tip card cover the
   * spotlight — try alternates until the card clears the hole with a gap.
   */
  private fun placeCard(
    preferred: String,
    cardW: Int,
    cardH: Int,
    margin: Int,
    gap: Int,
  ): Triple<Int, Int, String> {
    val order = linkedSetOf(preferred, "down", "up", "left", "right")
    var bestLeft = margin
    var bestTop = margin
    var bestDir = preferred
    var bestScore = Float.NEGATIVE_INFINITY
    for (dir in order) {
      val (left, top) = cardOriginFor(dir, cardW, cardH, margin, gap)
      val candidate = RectF(
        left.toFloat(),
        top.toFloat(),
        (left + cardW).toFloat(),
        (top + cardH).toFloat(),
      )
      overlapScratch.set(holeRect)
      overlapScratch.inset(-8f * density, -8f * density)
      val overlaps = RectF.intersects(candidate, overlapScratch)
      val score = when {
        overlaps -> -1_000f
        dir == preferred -> 100f
        else -> 50f
      } + clearanceScore(candidate)
      if (score > bestScore) {
        bestScore = score
        bestLeft = left
        bestTop = top
        bestDir = dir
      }
      if (!overlaps && dir == preferred) break
    }
    return Triple(bestLeft, bestTop, bestDir)
  }

  private fun cardOriginFor(
    dir: String,
    cardW: Int,
    cardH: Int,
    margin: Int,
    gap: Int,
  ): Pair<Int, Int> {
    val holeCx = holeRect.centerX()
    val holeCy = holeRect.centerY()
    val maxLeft = (width - cardW - margin).coerceAtLeast(margin)
    val maxTop = (height - cardH - margin).coerceAtLeast(margin)
    return when (dir) {
      "left" -> {
        val left = (holeRect.left - cardW - gap).toInt().coerceIn(margin, maxLeft)
        val top = (holeCy - cardH / 2f).toInt().coerceIn(margin, maxTop)
        left to top
      }
      "right" -> {
        val left = (holeRect.right + gap).toInt().coerceIn(margin, maxLeft)
        val top = (holeCy - cardH / 2f).toInt().coerceIn(margin, maxTop)
        left to top
      }
      "up" -> {
        val left = (holeCx - cardW / 2f).toInt().coerceIn(margin, maxLeft)
        val top = (holeRect.top - cardH - gap).toInt().coerceIn(margin, maxTop)
        left to top
      }
      else -> {
        val left = (holeCx - cardW / 2f).toInt().coerceIn(margin, maxLeft)
        val top = (holeRect.bottom + gap).toInt().coerceIn(margin, maxTop)
        left to top
      }
    }
  }

  private fun clearanceScore(candidate: RectF): Float {
    val dx = when {
      candidate.right < holeRect.left -> holeRect.left - candidate.right
      candidate.left > holeRect.right -> candidate.left - holeRect.right
      else -> 0f
    }
    val dy = when {
      candidate.bottom < holeRect.top -> holeRect.top - candidate.bottom
      candidate.top > holeRect.bottom -> candidate.top - holeRect.bottom
      else -> 0f
    }
    return minOf(dx + dy, 80f * density)
  }

  /**
   * Speech-bubble caret on the card edge closest to the spotlight, plus a short
   * connector into the cutout so the tip clearly names the control.
   */
  private fun buildPointer(preferred: String) {
    arrowPath.reset()
    connectorPath.reset()
    val caret = 11f * density
    val nest = 1.5f * density
    val holeCx = holeRect.centerX()
    val holeCy = holeRect.centerY()

    val tipX: Float
    val tipY: Float
    val baseX: Float
    val baseY: Float
    when (preferred) {
      "left" -> {
        // Card left of target → caret on card's trailing edge, tip toward hole.
        baseX = cardRect.right - nest
        baseY = holeCy.coerceIn(cardRect.top + caret, cardRect.bottom - caret)
        tipX = cardRect.right + caret
        tipY = baseY
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX, baseY - caret)
        arrowPath.lineTo(baseX, baseY + caret)
        arrowPath.close()
        connectorPath.moveTo(tipX, tipY)
        connectorPath.lineTo(holeRect.left - 2f * density, holeCy)
      }
      "right" -> {
        baseX = cardRect.left + nest
        baseY = holeCy.coerceIn(cardRect.top + caret, cardRect.bottom - caret)
        tipX = cardRect.left - caret
        tipY = baseY
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX, baseY - caret)
        arrowPath.lineTo(baseX, baseY + caret)
        arrowPath.close()
        connectorPath.moveTo(tipX, tipY)
        connectorPath.lineTo(holeRect.right + 2f * density, holeCy)
      }
      "up" -> {
        baseY = cardRect.bottom - nest
        baseX = holeCx.coerceIn(cardRect.left + caret, cardRect.right - caret)
        tipX = baseX
        tipY = cardRect.bottom + caret
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX - caret, baseY)
        arrowPath.lineTo(baseX + caret, baseY)
        arrowPath.close()
        connectorPath.moveTo(tipX, tipY)
        connectorPath.lineTo(holeCx, holeRect.top - 2f * density)
      }
      else -> {
        // Card below target → caret on card top, tip toward hole.
        baseY = cardRect.top + nest
        baseX = holeCx.coerceIn(cardRect.left + caret, cardRect.right - caret)
        tipX = baseX
        tipY = cardRect.top - caret
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX - caret, baseY)
        arrowPath.lineTo(baseX + caret, baseY)
        arrowPath.close()
        connectorPath.moveTo(tipX, tipY)
        connectorPath.lineTo(holeCx, holeRect.bottom + 2f * density)
      }
    }
  }

  private fun dp(value: Int): Int = (value * density + 0.5f).toInt()

  companion object {
    /** Above zoom (10), rails (12), and flash (13) in activity_native_camera.xml. */
    private const val OVERLAY_ELEVATION_DP = 32f

    fun parseSteps(json: String?): List<Step> {
      if (json.isNullOrBlank()) return emptyList()
      return try {
        val array = org.json.JSONArray(json)
        val out = ArrayList<Step>(array.length())
        for (i in 0 until array.length()) {
          val map = array.optJSONObject(i) ?: continue
          val id = map.optString("id").trim()
          val title = map.optString("title").trim()
          val body = map.optString("body").trim()
          if (id.isEmpty() || title.isEmpty() || body.isEmpty()) continue
          val arrow = map.optString("arrow").trim().ifEmpty { "auto" }
          out.add(Step(id = id, title = title, body = body, arrow = arrow))
        }
        out
      } catch (_: Exception) {
        emptyList()
      }
    }
  }
}
