package com.smartnps360.app.camera

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
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
    color = Color.WHITE
  }

  private val holeRect = RectF()
  private val cardRect = RectF()
  private val arrowPath = Path()

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
    if (!arrowPath.isEmpty) {
      canvas.drawPath(arrowPath, arrowPaint)
    }
    canvas.restoreToCount(checkpoint)
    super.dispatchDraw(canvas)
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
    val holeCx = holeRect.centerX()
    val holeCy = holeRect.centerY()

    val preferred = when (arrowDirection.lowercase()) {
      "left" -> "left"
      "right" -> "right"
      "up" -> "up"
      "down" -> "down"
      else -> if (holeCx > width * 0.55f) "left" else "right"
    }

    var cardLeft: Int
    var cardTop: Int
    when (preferred) {
      "left" -> {
        cardLeft = (holeRect.left - cardW - dp(28)).toInt().coerceAtLeast(margin)
        cardTop = (holeCy - cardH / 2f).toInt()
          .coerceIn(margin, (height - cardH - margin).coerceAtLeast(margin))
      }
      "right" -> {
        cardLeft = (holeRect.right + dp(28)).toInt()
          .coerceAtMost(width - cardW - margin)
          .coerceAtLeast(margin)
        cardTop = (holeCy - cardH / 2f).toInt()
          .coerceIn(margin, (height - cardH - margin).coerceAtLeast(margin))
      }
      "up" -> {
        cardLeft = (holeCx - cardW / 2f).toInt()
          .coerceIn(margin, (width - cardW - margin).coerceAtLeast(margin))
        cardTop = (holeRect.top - cardH - dp(28)).toInt().coerceAtLeast(margin)
      }
      else -> {
        cardLeft = (holeCx - cardW / 2f).toInt()
          .coerceIn(margin, (width - cardW - margin).coerceAtLeast(margin))
        cardTop = (holeRect.bottom + dp(28)).toInt()
          .coerceAtMost(height - cardH - margin)
          .coerceAtLeast(margin)
      }
    }

    card.layout(cardLeft, cardTop, cardLeft + cardW, cardTop + cardH)
    cardRect.set(
      cardLeft.toFloat(),
      cardTop.toFloat(),
      (cardLeft + cardW).toFloat(),
      (cardTop + cardH).toFloat(),
    )
    buildArrow(preferred)
  }

  private fun buildArrow(preferred: String) {
    arrowPath.reset()
    val tipSize = 12f * density
    val holeCx = holeRect.centerX()
    val holeCy = holeRect.centerY()
    when (preferred) {
      "left" -> {
        val tipX = holeRect.left - 4f * density
        val tipY = holeCy
        val baseX = cardRect.right
        val baseY = cardRect.centerY().coerceIn(cardRect.top + tipSize, cardRect.bottom - tipSize)
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX, baseY - tipSize)
        arrowPath.lineTo(baseX, baseY + tipSize)
        arrowPath.close()
      }
      "right" -> {
        val tipX = holeRect.right + 4f * density
        val tipY = holeCy
        val baseX = cardRect.left
        val baseY = cardRect.centerY().coerceIn(cardRect.top + tipSize, cardRect.bottom - tipSize)
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX, baseY - tipSize)
        arrowPath.lineTo(baseX, baseY + tipSize)
        arrowPath.close()
      }
      "up" -> {
        val tipX = holeCx
        val tipY = holeRect.top - 4f * density
        val baseY = cardRect.bottom
        val baseX = cardRect.centerX().coerceIn(cardRect.left + tipSize, cardRect.right - tipSize)
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX - tipSize, baseY)
        arrowPath.lineTo(baseX + tipSize, baseY)
        arrowPath.close()
      }
      else -> {
        val tipX = holeCx
        val tipY = holeRect.bottom + 4f * density
        val baseY = cardRect.top
        val baseX = cardRect.centerX().coerceIn(cardRect.left + tipSize, cardRect.right - tipSize)
        arrowPath.moveTo(tipX, tipY)
        arrowPath.lineTo(baseX - tipSize, baseY)
        arrowPath.lineTo(baseX + tipSize, baseY)
        arrowPath.close()
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
