import Foundation
import ShenaiSDK

/// Which part of the SDK a session exercises.
enum TestMode {
    /// SDK's built-in UI: measurement -> results -> health risks.
    case sdkUI
    /// SDK renders only the camera preview; the app draws its own live metrics.
    case customUI
    /// SDK's built-in measurements dashboard.
    case dashboard

    var title: String {
        switch self {
        case .sdkUI: return "Measurement (SDK UI)"
        case .customUI: return "Custom UI"
        case .dashboard: return "Dashboard"
        }
    }
}

// Some Obj-C enum cases from the SDK are not imported as Swift dot-syntax cases
// (same workaround as the official Shen.AI examples).
private enum ShenaiEnumValues {
    static let uiVersionV2 = UiVersion(rawValue: 1)!
    static let activityModerately = PhysicalActivity(rawValue: 2)!
}

/// Thin wrapper around the static `ShenaiSDK` API: API key storage,
/// initialization settings per mode and event forwarding.
enum ShenaiSession {
    private static let apiKeyDefaultsKey = "shenai-test.apiKey"
    private static let userIdDefaultsKey = "shenai-test.userId"

    /// Called on the main queue for every SDK event of the active session.
    static var onEvent: ((Event) -> Void)?

    static var sdkVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "SHENAI_SDK_VERSION") as? String) ?? "-"
    }

    /// Saved key (entered in the app) > build setting (Secrets.xcconfig) > scheme env var.
    static var apiKey: String {
        get {
            if let saved = normalized(UserDefaults.standard.string(forKey: apiKeyDefaultsKey)) { return saved }
            if let built = normalized(Bundle.main.object(forInfoDictionaryKey: "SHENAI_API_KEY") as? String) { return built }
            return normalized(ProcessInfo.processInfo.environment["SHENAI_API_KEY"]) ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyDefaultsKey) }
    }

    static var userId: String {
        get { UserDefaults.standard.string(forKey: userIdDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userIdDefaultsKey) }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "$(SHENAI_API_KEY)" else { return nil }
        return trimmed
    }

    /// Initializes the SDK for `mode`. Returns nil on success or an error message.
    static func start(mode: TestMode) -> String? {
        if ShenaiSDK.isInitialized() {
            ShenaiSDK.deinitialize()
        }
        let settings = makeSettings(for: mode)
        settings.eventCallback = { event in
            DispatchQueue.main.async { onEvent?(event) }
        }

        let result = ShenaiSDK.initialize(apiKey, userID: userId, settings: settings)
        guard result == .success else {
            return "Initialization failed (\(result), code \(result.rawValue)). "
                + "Check the API key and internet connection."
        }

        switch mode {
        case .sdkUI:
            ShenaiSDK.setEnableMeasurementsDashboard(false)
            ShenaiSDK.resetMeasurementSession()
            ShenaiSDK.setScreen(.measurement)
        case .customUI, .dashboard:
            break
        }
        return nil
    }

    static func stop() {
        onEvent = nil
        if ShenaiSDK.isInitialized() {
            ShenaiSDK.deinitialize()
        }
    }

    private static func makeSettings(for mode: TestMode) -> InitializationSettings {
        let settings = InitializationSettings()
        settings.precisionMode = .relaxed
        settings.operatingMode = .measure
        settings.measurementPreset = .thirtySecondsAllMetrics
        settings.cameraMode = .facingUser
        settings.uiVersion = ShenaiEnumValues.uiVersionV2
        settings.enableHealthRisks = true
        settings.saveHealthRisksFactors = true
        settings.applyPrecisionModeToBloodPressure = false
        settings.risksFactors = exampleRiskFactors()

        switch mode {
        case .sdkUI:
            settings.onboardingMode = .showOnce
            settings.showUserInterface = true
            settings.showFacePositioningOverlay = true
            settings.showVisualWarnings = true
            settings.enableCameraSwap = true
            settings.showFaceMask = true
            settings.showBloodFlow = true
            settings.enableStartAfterSuccess = false
            settings.enableSummaryScreen = true
            settings.showResultsFinishButton = true
            settings.showHealthIndicesFinishButton = true
            settings.showOutOfRangeResultIndicators = true
            settings.showSignalQualityIndicator = true
            settings.showSignalTile = true
            settings.showStartStopButton = true
            settings.showInfoButton = true
            settings.showDisclaimer = true
            settings.uiFlowScreens = [Screen.measurement, Screen.results, Screen.healthRisks]
                .map { NSNumber(value: $0.rawValue) }
        case .dashboard:
            settings.onboardingMode = .hidden
            settings.showUserInterface = true
            settings.enableSummaryScreen = false
            settings.showResultsFinishButton = false
            settings.showHealthIndicesFinishButton = false
            settings.showStartStopButton = false
            settings.showInfoButton = false
            settings.showDisclaimer = false
            settings.uiFlowScreens = [NSNumber(value: Screen.dashboard.rawValue)]
        case .customUI:
            settings.onboardingMode = .hidden
            settings.showUserInterface = false
            settings.showFacePositioningOverlay = false
            settings.showVisualWarnings = false
            settings.enableCameraSwap = false
            settings.showFaceMask = true
            settings.showBloodFlow = false
            settings.enableStartAfterSuccess = false
            settings.enableSummaryScreen = false
            settings.showResultsFinishButton = false
            settings.showHealthIndicesFinishButton = false
            settings.showOutOfRangeResultIndicators = false
            settings.showSignalQualityIndicator = false
            settings.showSignalTile = false
            settings.showStartStopButton = false
            settings.showInfoButton = false
            settings.showDisclaimer = false
        }
        return settings
    }

    private static func exampleRiskFactors() -> RisksFactors {
        let factors = RisksFactors()
        factors.age = 45
        factors.cholesterol = 190
        factors.cholesterolHDL = 52
        factors.sbp = 128
        factors.dbp = 82
        factors.isSmoker = false
        factors.hypertensionTreatment = .no
        factors.hasDiabetes = false
        factors.bodyHeight = 172
        factors.bodyWeight = 74
        factors.gender = .female
        factors.physicalActivity = ShenaiEnumValues.activityModerately
        factors.country = "US"
        factors.race = .white
        return factors
    }
}

// MARK: - Formatting

func formatNumber(_ value: NSNumber?, decimals: Int = 0) -> String {
    guard let value else { return "-" }
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = decimals
    formatter.maximumFractionDigits = decimals
    return formatter.string(from: value) ?? "-"
}

func formatNumber(_ value: Double?, decimals: Int = 0) -> String {
    guard let value, !value.isNaN else { return "-" }
    return formatNumber(NSNumber(value: value), decimals: decimals)
}

func formatBloodPressure(_ results: MeasurementResults?) -> String {
    guard let sbp = results?.systolicBloodPressureMmhg, let dbp = results?.diastolicBloodPressureMmhg else {
        return "-"
    }
    return "\(formatNumber(sbp))/\(formatNumber(dbp))"
}
