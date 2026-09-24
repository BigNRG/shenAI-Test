import ShenaiSDK
import UIKit

/// Hosts the SDK view. For `.sdkUI` / `.dashboard` it is full screen; for
/// `.customUI` it is a small camera preview above our own live metrics panel.
final class SessionViewController: UIViewController {
    private let mode: TestMode
    private var shenaiView: ShenaiView?
    private var pollTimer: Timer?
    private var lastResults: MeasurementResults?
    private var handedOffToResults = false

    // Custom UI widgets
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var liveValues: [String: UILabel] = [:]
    private var startButton: UIButton?
    private var stopButton: UIButton?
    private var resultsButton: UIButton?

    init(mode: TestMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode.title
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close", style: .plain, target: self, action: #selector(closeTapped)
        )
        navigationItem.hidesBackButton = true

        switch mode {
        case .sdkUI, .dashboard:
            buildFullScreenLayout()
        case .customUI:
            buildCustomLayout()
        }

        ShenaiSession.onEvent = { [weak self] event in self?.handle(event) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if mode == .customUI {
            startPolling()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopPolling()
        // Popped via Close / swipe back (not replaced by the results screen).
        if isMovingFromParent && !handedOffToResults {
            ShenaiSession.stop()
        }
    }

    deinit {
        pollTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func embedShenaiView(in container: UIView) {
        let controller = ShenaiView()
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        controller.didMove(toParent: self)
        shenaiView = controller
    }

    private func buildFullScreenLayout() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        embedShenaiView(in: container)
    }

    private func buildCustomLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        // Camera preview (SDK renders portrait ~9:16).
        let camera = UIView()
        camera.backgroundColor = .black
        camera.layer.cornerRadius = 16
        camera.clipsToBounds = true
        camera.translatesAutoresizingMaskIntoConstraints = false
        let cameraRow = UIView()
        cameraRow.addSubview(camera)
        NSLayoutConstraint.activate([
            camera.widthAnchor.constraint(equalToConstant: 220),
            camera.heightAnchor.constraint(equalTo: camera.widthAnchor, multiplier: 16.0 / 9.0),
            camera.centerXAnchor.constraint(equalTo: cameraRow.centerXAnchor),
            camera.topAnchor.constraint(equalTo: cameraRow.topAnchor),
            camera.bottomAnchor.constraint(equalTo: cameraRow.bottomAnchor),
        ])
        stack.addArrangedSubview(cameraRow)
        embedShenaiView(in: camera)

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.text = "Ready"
        stack.addArrangedSubview(statusLabel)

        progressView.progressTintColor = .label
        stack.addArrangedSubview(progressView)

        let tiles = [("HR", "bpm"), ("HRV", "ms"), ("BR", "brpm"), ("BP", "mmHg"), ("Stress", ""), ("Signal", "dB")]
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 8
        for rowItems in [Array(tiles[0..<3]), Array(tiles[3..<6])] {
            let row = UIStackView(arrangedSubviews: rowItems.map { makeTile(label: $0.0, unit: $0.1) })
            row.distribution = .fillEqually
            row.spacing = 8
            grid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(grid)

        let start = makeButton("Start", filled: true) { [weak self] in self?.startMeasurement() }
        let stop = makeButton("Stop") { [weak self] in self?.stopMeasurement() }
        let buttons = UIStackView(arrangedSubviews: [start, stop])
        buttons.distribution = .fillEqually
        buttons.spacing = 12
        stack.addArrangedSubview(buttons)
        startButton = start
        stopButton = stop

        let results = makeButton("Show results", filled: true) { [weak self] in self?.showResults() }
        results.isHidden = true
        stack.addArrangedSubview(results)
        resultsButton = results
    }

    private func makeTile(label: String, unit: String) -> UIView {
        let title = UILabel()
        title.text = label
        title.font = .preferredFont(forTextStyle: .caption1)
        title.textColor = .secondaryLabel

        let value = UILabel()
        value.text = "-"
        value.font = .systemFont(ofSize: 22, weight: .bold)
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.5
        liveValues[label] = value

        let unitLabel = UILabel()
        unitLabel.text = unit.isEmpty ? " " : unit
        unitLabel.font = .preferredFont(forTextStyle: .caption2)
        unitLabel.textColor = .secondaryLabel

        let tile = UIStackView(arrangedSubviews: [title, value, unitLabel])
        tile.axis = .vertical
        tile.spacing = 2
        tile.isLayoutMarginsRelativeArrangement = true
        tile.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tile.layer.borderWidth = 1
        tile.layer.borderColor = UIColor.separator.cgColor
        tile.layer.cornerRadius = 8
        return tile
    }

    // MARK: - SDK events

    private func handle(_ event: Event) {
        print("Shen.AI event: \(event.rawValue)")
        if event == .measurementFinished {
            lastResults = ShenaiSDK.getMeasurementResults() ?? lastResults
        } else if event == .userFlowFinished {
            lastResults = ShenaiSDK.getMeasurementResults() ?? lastResults
            if mode == .sdkUI, lastResults != nil {
                showResults()
            } else {
                close()
            }
        }
    }

    // MARK: - Custom UI measurement

    private func startMeasurement() {
        guard ShenaiSDK.isInitialized() else { return }
        lastResults = nil
        resultsButton?.isHidden = true
        ShenaiSDK.resetMeasurementSession()
        ShenaiSDK.setCameraMode(.facingUser)
        ShenaiSDK.setOperatingMode(.measure)
        ShenaiSDK.startMeasurement()
        poll()
    }

    private func stopMeasurement() {
        guard ShenaiSDK.isInitialized() else { return }
        ShenaiSDK.stopMeasurement()
        poll()
    }

    private func startPolling() {
        stopPolling()
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        guard mode == .customUI, ShenaiSDK.isInitialized() else { return }
        let state: MeasurementState? = ShenaiSDK.getMeasurementState()
        let running = isRunning(state)
        let finished = state == .finished

        statusLabel.text = statusText(state)
        progressView.progress = ShenaiSDK.getMeasurementProgressPercentage() / 100
        startButton?.isEnabled = !running
        stopButton?.isEnabled = running
        liveValues["Signal"]?.text = formatNumber(Double(ShenaiSDK.getCurrentSignalQualityMetric()), decimals: 1)

        var shown: MeasurementResults?
        if finished {
            lastResults = ShenaiSDK.getMeasurementResults() ?? lastResults
            shown = lastResults
        } else if running {
            shown = ShenaiSDK.getRealtimeMetrics(10.0)
        }
        if finished || running {
            let hr10s = ShenaiSDK.getHeartRate10s().map { "\($0)" } ?? "-"
            liveValues["HR"]?.text = shown.map { formatNumber($0.heartRateBpm) } ?? hr10s
            liveValues["HRV"]?.text = formatNumber(shown?.hrvSdnnMs, decimals: 1)
            liveValues["BR"]?.text = formatNumber(shown?.breathingRateBpm, decimals: 1)
            liveValues["BP"]?.text = formatBloodPressure(shown)
            liveValues["Stress"]?.text = formatNumber(shown?.stressIndex, decimals: 1)
        }
        resultsButton?.isHidden = !(finished && lastResults != nil)
    }

    private func isRunning(_ state: MeasurementState?) -> Bool {
        switch state {
        case .waitingForFace, .runningSignalShort, .runningSignalGood, .runningSignalBad,
             .runningSignalBadDeviceUnstable, .finalizing:
            return true
        default:
            return false
        }
    }

    private func statusText(_ state: MeasurementState?) -> String {
        switch state {
        case .finished: return "Measurement finished"
        case .failed: return "Measurement failed - try again"
        case .finalizing: return "Finalizing..."
        default: break
        }
        if let raw = ShenaiSDK.getCurrentViolatedMeasurementEnvironmentCondition(),
           let condition = MeasurementEnvironmentCondition(rawValue: raw.intValue) {
            switch condition {
            case .facePosition: return "Center your face in the frame"
            case .foreheadVisible: return "Uncover your forehead"
            case .glassesNotDetected: return "Remove your glasses"
            case .sufficientLightLevel: return "Move to brighter light"
            case .evenLighting: return "Use even lighting"
            case .noBacklight: return "Avoid backlight"
            case .faceStable: return "Keep your face still"
            case .deviceStable: return "Keep the phone still"
            @unknown default: break
            }
        }
        if state == .waitingForFace { return "Waiting for face..." }
        return isRunning(state) ? "Measuring..." : "Ready - press Start"
    }

    // MARK: - Navigation

    private func showResults() {
        guard let results = lastResults ?? ShenaiSDK.getMeasurementResults(),
              let nav = navigationController,
              let home = nav.viewControllers.first else {
            close()
            return
        }
        stopPolling()
        // Keep the SDK session (PDF export needs it) but release the camera.
        ShenaiSDK.setCameraMode(.off)
        handedOffToResults = true
        nav.setViewControllers([home, ResultsViewController(results: results)], animated: true)
    }

    @objc private func closeTapped() {
        close()
    }

    private func close() {
        stopPolling()
        ShenaiSession.stop()
        navigationController?.popToRootViewController(animated: true)
    }

    @objc private func appDidEnterBackground() {
        if ShenaiSDK.isInitialized() { ShenaiSDK.setCameraMode(.off) }
    }

    @objc private func appWillEnterForeground() {
        if ShenaiSDK.isInitialized(), !handedOffToResults { ShenaiSDK.setCameraMode(.facingUser) }
    }
}
