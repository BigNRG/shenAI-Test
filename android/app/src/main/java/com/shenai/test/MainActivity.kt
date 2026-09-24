package com.shenai.test

import ai.mxlabs.shenai_sdk.ShenAIAndroidSDK
import ai.mxlabs.shenai_sdk.ShenAIView
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts.RequestPermission
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.util.Locale
import java.util.Optional
import kotlin.math.roundToInt

/**
 * Single-activity test app for the Shen.AI Android SDK.
 *
 * Screens:
 *  - Home: API key entry + mode selection
 *  - SDK UI: the SDK's built-in measurement -> results -> health risks flow
 *  - Custom UI: SDK camera preview + our own live metrics panel (polling)
 *  - Dashboard: the SDK's built-in measurements dashboard
 *  - Results: our own summary of the final measurement results
 */
class MainActivity : ComponentActivity() {

    private enum class Mode { SDK_UI, CUSTOM_UI, DASHBOARD }
    private enum class Page { HOME, SDK, RESULTS }

    private val sdk = ShenAIAndroidSDK()
    private val handler = Handler(Looper.getMainLooper())
    private val prefs by lazy { getSharedPreferences("shenai-test", Context.MODE_PRIVATE) }

    private var page = Page.HOME
    private var mode: Mode? = null
    private var pendingMode: Mode? = null
    private var lastResults: ShenAIAndroidSDK.MeasurementResults? = null

    // Home widgets
    private var apiKeyInput: EditText? = null
    private var userIdInput: EditText? = null
    private var homeStatus: TextView? = null

    // Custom UI widgets
    private var liveStatus: TextView? = null
    private var liveProgress: ProgressBar? = null
    private var startButton: Button? = null
    private var stopButton: Button? = null
    private var resultsButton: Button? = null
    private val liveValues = mutableMapOf<String, TextView>()

    private val pollTask = object : Runnable {
        override fun run() {
            pollSdk()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private val requestCameraPermission = registerForActivityResult(RequestPermission()) { granted ->
        val m = pendingMode
        pendingMode = null
        if (granted && m != null) {
            startSession(m)
        } else {
            setHomeStatus("Camera permission is required to measure.", isError = true)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (page == Page.HOME) finish() else closeSession()
            }
        })
        showHome()
    }

    // ---------------------------------------------------------------------
    // Home
    // ---------------------------------------------------------------------

    private fun showHome() {
        page = Page.HOME
        val stack = verticalStack()

        stack.addView(title("Shen.AI Test"))
        stack.addView(caption("Shen.AI Android SDK ${BuildConfig.SHENAI_SDK_VERSION}"))

        stack.addView(sectionTitle("API key"), topMargin(24))
        stack.addView(caption("Get an API key from developer.shen.ai. It is stored only on this device."))
        apiKeyInput = EditText(this).apply {
            hint = "Shen.AI API key"
            isSingleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setText(prefs.getString(PREF_API_KEY, null)?.takeIf { it.isNotBlank() } ?: BuildConfig.SHENAI_API_KEY)
        }
        stack.addView(apiKeyInput, matchWrap())
        stack.addView(outlineButton("Show / hide key") {
            apiKeyInput?.let {
                val hidden = (it.inputType and InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_PASSWORD
                it.inputType = InputType.TYPE_CLASS_TEXT or
                    if (hidden) InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD else InputType.TYPE_TEXT_VARIATION_PASSWORD
                it.setSelection(it.text.length)
            }
        }, buttonParams(8, 44))
        userIdInput = EditText(this).apply {
            hint = "User ID (optional)"
            isSingleLine = true
            setText(prefs.getString(PREF_USER_ID, ""))
        }
        stack.addView(userIdInput, topMargin(8))

        stack.addView(sectionTitle("Test the SDK"), topMargin(24))
        stack.addView(filledButton("Measurement (SDK UI)") { openMode(Mode.SDK_UI) }, buttonParams(8))
        stack.addView(outlineButton("Measurement (Custom UI + live metrics)") { openMode(Mode.CUSTOM_UI) }, buttonParams(12))
        stack.addView(outlineButton("Dashboard") { openMode(Mode.DASHBOARD) }, buttonParams(12))

        homeStatus = TextView(this).apply { gravity = Gravity.CENTER; setTextColor(Color.DKGRAY) }
        stack.addView(homeStatus, topMargin(16))

        setContentView(scroll(stack))
    }

    private fun setHomeStatus(text: String, isError: Boolean = false) {
        homeStatus?.text = text
        homeStatus?.setTextColor(if (isError) ERROR_COLOR else Color.DKGRAY)
    }

    private fun openMode(m: Mode) {
        val apiKey = apiKeyInput?.text?.toString()?.trim().orEmpty()
        if (apiKey.isEmpty()) {
            setHomeStatus("Enter your Shen.AI API key first.", isError = true)
            return
        }
        prefs.edit()
            .putString(PREF_API_KEY, apiKey)
            .putString(PREF_USER_ID, userIdInput?.text?.toString()?.trim().orEmpty())
            .apply()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startSession(m)
        } else {
            pendingMode = m
            requestCameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    // ---------------------------------------------------------------------
    // SDK session
    // ---------------------------------------------------------------------

    private fun startSession(m: Mode) {
        val apiKey = prefs.getString(PREF_API_KEY, "").orEmpty()
        val userId = prefs.getString(PREF_USER_ID, "").orEmpty()
        if (sdk.isInitialized) sdk.deinitialize()

        setHomeStatus("Initializing SDK...")
        val settings = settingsFor(m).apply {
            eventCallback = ShenAIAndroidSDK.EventCallback { event -> runOnUiThread { onSdkEvent(event) } }
        }
        val result = sdk.initialize(this, apiKey, userId, settings)
        if (result != ShenAIAndroidSDK.InitializationResult.OK) {
            Log.w(TAG, "Initialization failed: $result")
            setHomeStatus("Initialization failed: $result\nCheck the API key and internet connection.", isError = true)
            return
        }
        Log.i(TAG, "SDK initialized in $m mode")

        mode = m
        lastResults = null
        when (m) {
            Mode.SDK_UI -> {
                sdk.setEnableMeasurementsDashboard(false)
                sdk.resetMeasurementSession()
                sdk.setScreen(ShenAIAndroidSDK.Screen.MEASUREMENT)
                showSdkFullScreen()
            }
            Mode.DASHBOARD -> showSdkFullScreen()
            Mode.CUSTOM_UI -> showCustomUi()
        }
    }

    private fun closeSession() {
        handler.removeCallbacks(pollTask)
        if (sdk.isInitialized) sdk.deinitialize()
        mode = null
        showHome()
    }

    private fun onSdkEvent(event: ShenAIAndroidSDK.Event) {
        Log.i(TAG, "Shen.AI event: $event")
        when (event) {
            ShenAIAndroidSDK.Event.MEASUREMENT_FINISHED -> {
                lastResults = sdk.measurementResults ?: lastResults
            }
            ShenAIAndroidSDK.Event.USER_FLOW_FINISHED -> {
                lastResults = sdk.measurementResults ?: lastResults
                if (mode == Mode.SDK_UI && lastResults != null) showResults() else closeSession()
            }
            else -> Unit
        }
    }

    private fun baseSettings(): ShenAIAndroidSDK.InitializationSettings =
        sdk.defaultInitializationSettings.apply {
            precisionMode = ShenAIAndroidSDK.PrecisionMode.RELAXED
            operatingMode = ShenAIAndroidSDK.OperatingMode.MEASURE
            measurementPreset = ShenAIAndroidSDK.MeasurementPreset.THIRTY_SECONDS_ALL_METRICS
            cameraMode = ShenAIAndroidSDK.CameraMode.FACING_USER
            uiVersion = ShenAIAndroidSDK.UiVersion.V2
            enableHealthRisks = true
            saveHealthRisksFactors = true
            risksFactors = exampleRiskFactors()
        }

    private fun settingsFor(m: Mode): ShenAIAndroidSDK.InitializationSettings = baseSettings().apply {
        when (m) {
            Mode.SDK_UI -> {
                onboardingMode = ShenAIAndroidSDK.OnboardingMode.SHOW_ONCE
                showUserInterface = true
                showFacePositioningOverlay = true
                showVisualWarnings = true
                enableCameraSwap = true
                showFaceMask = true
                showBloodFlow = true
                enableStartAfterSuccess = false
                enableSummaryScreen = true
                showResultsFinishButton = true
                showHealthIndicesFinishButton = true
                showOutOfRangeResultIndicators = true
                showSignalQualityIndicator = true
                showSignalTile = true
                showStartStopButton = true
                showInfoButton = true
                showDisclaimer = true
                uiFlowScreens.clear()
                uiFlowScreens.addAll(
                    listOf(
                        ShenAIAndroidSDK.Screen.MEASUREMENT,
                        ShenAIAndroidSDK.Screen.RESULTS,
                        ShenAIAndroidSDK.Screen.HEALTH_RISKS,
                    ),
                )
            }
            Mode.DASHBOARD -> {
                onboardingMode = ShenAIAndroidSDK.OnboardingMode.HIDDEN
                showUserInterface = true
                enableSummaryScreen = false
                showResultsFinishButton = false
                showHealthIndicesFinishButton = false
                showStartStopButton = false
                showInfoButton = false
                showDisclaimer = false
                uiFlowScreens.clear()
                uiFlowScreens.add(ShenAIAndroidSDK.Screen.DASHBOARD)
            }
            Mode.CUSTOM_UI -> {
                // SDK renders only the camera preview + face mask; we draw the rest.
                onboardingMode = ShenAIAndroidSDK.OnboardingMode.HIDDEN
                showUserInterface = false
                showFacePositioningOverlay = false
                showVisualWarnings = false
                enableCameraSwap = false
                showFaceMask = true
                showBloodFlow = false
                enableStartAfterSuccess = false
                enableSummaryScreen = false
                showResultsFinishButton = false
                showHealthIndicesFinishButton = false
                showSignalQualityIndicator = false
                showSignalTile = false
                showStartStopButton = false
                showInfoButton = false
                showDisclaimer = false
            }
        }
    }

    private fun exampleRiskFactors(): ShenAIAndroidSDK.RisksFactors = sdk.RisksFactors().apply {
        age = Optional.of(45)
        cholesterol = Optional.of(190f)
        cholesterolHdl = Optional.of(52f)
        sbp = Optional.of(128f)
        dbp = Optional.of(82f)
        isSmoker = Optional.of(false)
        hypertensionTreatment = Optional.of(ShenAIAndroidSDK.HypertensionTreatment.NO)
        hasDiabetes = Optional.of(false)
        bodyHeight = Optional.of(172f)
        bodyWeight = Optional.of(74f)
        gender = Optional.of(ShenAIAndroidSDK.Gender.FEMALE)
        physicalActivity = Optional.of(ShenAIAndroidSDK.PhysicalActivity.MODERATELY)
        country = "US"
        race = Optional.of(ShenAIAndroidSDK.Race.WHITE)
    }

    // ---------------------------------------------------------------------
    // SDK UI / Dashboard: full-screen SDK view
    // ---------------------------------------------------------------------

    private fun showSdkFullScreen() {
        page = Page.SDK
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(8), dp(8))
        }
        bar.addView(sectionTitle(if (mode == Mode.DASHBOARD) "Dashboard" else "Measurement (SDK UI)"), LinearLayout.LayoutParams(0, WRAP, 1f))
        bar.addView(outlineButton("Close") { closeSession() }, LinearLayout.LayoutParams(dp(96), dp(40)))
        root.addView(bar, matchWrap())
        root.addView(ShenAIView(this), LinearLayout.LayoutParams(MATCH, 0, 1f))
        setContentView(applySystemBarInsets(root))
    }

    // ---------------------------------------------------------------------
    // Custom UI: SDK camera view + our own live panel
    // ---------------------------------------------------------------------

    private fun showCustomUi() {
        page = Page.SDK
        liveValues.clear()
        val stack = verticalStack(padding = 16)

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(title("Custom UI"), LinearLayout.LayoutParams(0, WRAP, 1f))
        header.addView(outlineButton("Close") { closeSession() }, LinearLayout.LayoutParams(dp(96), dp(40)))
        stack.addView(header, matchWrap())

        // Camera preview (SDK renders portrait ~9:16).
        val cameraWidth = dp(220)
        val cameraFrame = FrameLayout(this).apply {
            clipToOutline = true
            background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(Color.BLACK) }
        }
        cameraFrame.addView(ShenAIView(this), FrameLayout.LayoutParams(MATCH, MATCH))
        stack.addView(
            cameraFrame,
            LinearLayout.LayoutParams(cameraWidth, (cameraWidth * 16f / 9f).roundToInt()).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setMargins(0, dp(12), 0, dp(12))
            },
        )

        liveStatus = TextView(this).apply { gravity = Gravity.CENTER; textSize = 16f; setTextColor(Color.BLACK) }
        stack.addView(liveStatus, matchWrap())
        liveProgress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 1000 }
        stack.addView(liveProgress, topMargin(8))

        val grid = GridLayout(this).apply { columnCount = 3 }
        listOf(
            "HR" to "bpm", "HRV" to "ms", "BR" to "brpm",
            "BP" to "mmHg", "Stress" to "", "Signal" to "dB",
        ).forEach { (label, unit) -> grid.addView(metricTile(label, unit), gridTileParams()) }
        stack.addView(grid, topMargin(12))

        val buttons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        startButton = filledButton("Start") { startCustomMeasurement() }
        stopButton = outlineButton("Stop") { stopCustomMeasurement() }
        buttons.addView(startButton, LinearLayout.LayoutParams(0, dp(48), 1f))
        buttons.addView(stopButton, LinearLayout.LayoutParams(0, dp(48), 1f).apply { setMargins(dp(12), 0, 0, 0) })
        stack.addView(buttons, topMargin(16))

        resultsButton = filledButton("Show results") { showResults() }.apply { visibility = View.GONE }
        stack.addView(resultsButton, buttonParams(12))

        setContentView(scroll(stack))
        handler.removeCallbacks(pollTask)
        handler.post(pollTask)
    }

    private fun startCustomMeasurement() {
        if (!sdk.isInitialized) return
        lastResults = null
        resultsButton?.visibility = View.GONE
        sdk.resetMeasurementSession()
        sdk.setCameraMode(ShenAIAndroidSDK.CameraMode.FACING_USER)
        sdk.setOperatingMode(ShenAIAndroidSDK.OperatingMode.MEASURE)
        sdk.startMeasurement()
        pollSdk()
    }

    private fun stopCustomMeasurement() {
        if (!sdk.isInitialized) return
        sdk.stopMeasurement()
        pollSdk()
    }

    private fun pollSdk() {
        if (mode != Mode.CUSTOM_UI || page != Page.SDK || !sdk.isInitialized) return
        val state = sdk.measurementState
        val running = isRunning(state)
        val finished = state == ShenAIAndroidSDK.MeasurementState.FINISHED

        liveStatus?.text = statusText(state, sdk.currentViolatedMeasurementEnvironmentCondition)
        liveProgress?.progress = (sdk.measurementProgressPercentage * 10).roundToInt()
        startButton?.isEnabled = !running
        stopButton?.isEnabled = running
        setLive("Signal", fmt(sdk.currentSignalQualityMetric, 1))

        val shown = when {
            finished -> (sdk.measurementResults ?: lastResults).also { lastResults = it }
            running -> sdk.getRealtimeMetrics(10f)
            else -> null
        }
        if (finished || running) {
            setLive("HR", shown?.let { fmt(it.hrBpm) } ?: sdk.heartRate10s.takeIf { it > 0 }?.toString() ?: "-")
            setLive("HRV", fmt(shown?.hrvSdnnMs, 1))
            setLive("BR", fmt(shown?.brBpm, 1))
            setLive("BP", bp(shown))
            setLive("Stress", fmt(shown?.stressIndex, 1))
        }
        resultsButton?.visibility = if (finished && lastResults != null) View.VISIBLE else View.GONE
    }

    private fun isRunning(state: ShenAIAndroidSDK.MeasurementState?): Boolean = when (state) {
        ShenAIAndroidSDK.MeasurementState.WAITING_FOR_FACE,
        ShenAIAndroidSDK.MeasurementState.RUNNING_SIGNAL_SHORT,
        ShenAIAndroidSDK.MeasurementState.RUNNING_SIGNAL_GOOD,
        ShenAIAndroidSDK.MeasurementState.RUNNING_SIGNAL_BAD,
        ShenAIAndroidSDK.MeasurementState.RUNNING_SIGNAL_BAD_DEVICE_UNSTABLE,
        ShenAIAndroidSDK.MeasurementState.FINALIZING -> true
        else -> false
    }

    private fun statusText(
        state: ShenAIAndroidSDK.MeasurementState?,
        condition: ShenAIAndroidSDK.MeasurementEnvironmentCondition?,
    ): String {
        when (state) {
            ShenAIAndroidSDK.MeasurementState.FINISHED -> return "Measurement finished"
            ShenAIAndroidSDK.MeasurementState.FAILED -> return "Measurement failed - try again"
            ShenAIAndroidSDK.MeasurementState.FINALIZING -> return "Finalizing..."
            else -> Unit
        }
        val hint = when (condition) {
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.FACE_POSITION -> "Center your face in the frame"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.FOREHEAD_VISIBLE -> "Uncover your forehead"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.GLASSES_NOT_DETECTED -> "Remove your glasses"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.SUFFICIENT_LIGHT_LEVEL -> "Move to brighter light"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.EVEN_LIGHTING -> "Use even lighting"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.NO_BACKLIGHT -> "Avoid backlight"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.FACE_STABLE -> "Keep your face still"
            ShenAIAndroidSDK.MeasurementEnvironmentCondition.DEVICE_STABLE -> "Keep the phone still"
            null -> null
        }
        if (hint != null) return hint
        return when {
            state == ShenAIAndroidSDK.MeasurementState.WAITING_FOR_FACE -> "Waiting for face..."
            isRunning(state) -> "Measuring..."
            else -> "Face: ${sdk.faceState} - press Start"
        }
    }

    private fun metricTile(label: String, unit: String): View {
        val tile = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setStroke(dp(1), Color.LTGRAY)
            }
        }
        tile.addView(TextView(this).apply { text = label; textSize = 12f; setTextColor(Color.GRAY) })
        val value = TextView(this).apply { text = "-"; textSize = 20f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.BLACK) }
        liveValues[label] = value
        tile.addView(value)
        tile.addView(TextView(this).apply { text = unit; textSize = 11f; setTextColor(Color.GRAY) })
        return tile
    }

    private fun setLive(label: String, value: String) {
        liveValues[label]?.text = value
    }

    // ---------------------------------------------------------------------
    // Results
    // ---------------------------------------------------------------------

    private fun showResults() {
        handler.removeCallbacks(pollTask)
        val r = lastResults ?: sdk.measurementResults
        if (r == null) {
            closeSession()
            return
        }
        page = Page.RESULTS
        // Keep the session alive (needed for the PDF export) but release the camera.
        sdk.setCameraMode(ShenAIAndroidSDK.CameraMode.OFF)

        val stack = verticalStack()
        stack.addView(title("Measurement results"))

        val q = r.qualityMetrics
        val rows = listOf(
            "Vitals" to null,
            "Heart rate" to "${fmt(r.hrBpm)} bpm",
            "HRV SDNN" to "${fmt(r.hrvSdnnMs, 1)} ms",
            "HRV lnRMSSD" to "${fmt(r.hrvLnrmssdMs, 2)} ms",
            "Breathing rate" to "${fmt(r.brBpm, 1)} brpm",
            "Blood pressure" to "${bp(r)} mmHg",
            "Cardiac stress" to fmt(r.stressIndex, 1),
            "PNS activity" to fmt(r.parasympatheticActivity, 1),
            "Cardiac workload" to "${fmt(r.cardiacWorkloadMmhgPerSec, 1)} mmHg/s",
            "Body" to null,
            "Age estimate" to "${fmt(r.ageYears)} years",
            "BMI" to "${fmt(r.bmiKgPerM2, 1)} kg/m²",
            "BMI category" to (r.bmiCategory?.orElse(null)?.toString() ?: "-"),
            "Weight" to "${fmt(r.weightKg, 1)} kg",
            "Height" to "${fmt(r.heightCm, 1)} cm",
            "Signal" to null,
            "Average signal quality" to "${fmt(r.averageSignalQuality, 1)} dB",
            "PPG quality index" to fmt(q?.ppgQualityIndex, 1),
            "BCG quality index" to fmt(q?.bcgQualityIndex, 1),
            "Heartbeats detected" to (r.heartbeats?.size ?: 0).toString(),
            "Measurement ID" to (sdk.measurementID?.takeIf { it.isNotBlank() } ?: "-"),
        )
        rows.forEach { (label, value) ->
            if (value == null) stack.addView(sectionTitle(label), topMargin(16)) else stack.addView(resultRow(label, value), matchWrap())
        }

        stack.addView(outlineButton("Open PDF report") {
            sdk.openMeasurementResultsPdfInBrowser()
            Toast.makeText(this, "PDF open request sent", Toast.LENGTH_SHORT).show()
        }, buttonParams(24))
        stack.addView(filledButton("Done") { closeSession() }, buttonParams(12))

        setContentView(scroll(stack))
    }

    private fun resultRow(label: String, value: String): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(6), 0, dp(6))
        }
        row.addView(TextView(this).apply { text = label; setTextColor(Color.DKGRAY) }, LinearLayout.LayoutParams(0, WRAP, 1f))
        row.addView(TextView(this).apply { text = value; setTextColor(Color.BLACK); typeface = Typeface.DEFAULT_BOLD })
        return row
    }

    // ---------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------

    override fun onPause() {
        super.onPause()
        if (page == Page.SDK && sdk.isInitialized) sdk.setCameraMode(ShenAIAndroidSDK.CameraMode.OFF)
    }

    override fun onResume() {
        super.onResume()
        if (page == Page.SDK && sdk.isInitialized) sdk.setCameraMode(ShenAIAndroidSDK.CameraMode.FACING_USER)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (sdk.isInitialized) sdk.deinitialize()
        super.onDestroy()
    }

    // ---------------------------------------------------------------------
    // Formatting + view helpers
    // ---------------------------------------------------------------------

    private fun fmt(value: Float?, decimals: Int = 0): String =
        if (value == null || value.isNaN()) "-" else String.format(Locale.US, "%.${decimals}f", value)

    private fun fmt(value: Optional<Float>?, decimals: Int = 0): String = fmt(value?.orElse(null), decimals)

    private fun bp(r: ShenAIAndroidSDK.MeasurementResults?): String {
        val sys = r?.systolicBloodPressureMmhg?.orElse(null)
        val dia = r?.diastolicBloodPressureMmhg?.orElse(null)
        return if (sys != null && dia != null) "${fmt(sys)}/${fmt(dia)}" else "-"
    }

    private fun verticalStack(padding: Int = 24) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(padding), dp(padding), dp(padding), dp(padding))
    }

    private fun scroll(content: View): View = applySystemBarInsets(
        ScrollView(this).apply {
            setBackgroundColor(Color.WHITE)
            addView(content)
        },
    )

    private fun applySystemBarInsets(view: View): View {
        ViewCompat.setOnApplyWindowInsetsListener(view) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        return view
    }

    private fun title(text: String) = TextView(this).apply {
        this.text = text
        textSize = 22f
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(Color.BLACK)
    }

    private fun sectionTitle(text: String) = TextView(this).apply {
        this.text = text
        textSize = 16f
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(Color.BLACK)
    }

    private fun caption(text: String) = TextView(this).apply {
        this.text = text
        textSize = 13f
        setTextColor(Color.GRAY)
    }

    private fun outlineButton(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setTextColor(Color.BLACK)
        background = GradientDrawable().apply {
            setColor(Color.WHITE)
            setStroke(dp(1), Color.BLACK)
            cornerRadius = dp(8).toFloat()
        }
        setOnClickListener { onClick() }
    }

    private fun filledButton(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setTextColor(Color.WHITE)
        typeface = Typeface.DEFAULT_BOLD
        background = GradientDrawable().apply {
            setColor(Color.BLACK)
            cornerRadius = dp(8).toFloat()
        }
        setOnClickListener { onClick() }
    }

    private fun gridTileParams() = GridLayout.LayoutParams(
        GridLayout.spec(GridLayout.UNDEFINED, 1f),
        GridLayout.spec(GridLayout.UNDEFINED, 1f),
    ).apply {
        width = 0
        setMargins(dp(4), dp(4), dp(4), dp(4))
    }

    private fun matchWrap() = LinearLayout.LayoutParams(MATCH, WRAP)

    private fun topMargin(marginDp: Int) = matchWrap().apply { setMargins(0, dp(marginDp), 0, 0) }

    private fun buttonParams(topMarginDp: Int, heightDp: Int = 54) =
        LinearLayout.LayoutParams(MATCH, dp(heightDp)).apply { setMargins(0, dp(topMarginDp), 0, 0) }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

    private companion object {
        const val TAG = "ShenAITest"
        const val PREF_API_KEY = "apiKey"
        const val PREF_USER_ID = "userId"
        const val POLL_INTERVAL_MS = 200L
        const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
        val ERROR_COLOR: Int = Color.rgb(179, 38, 30)
    }
}
