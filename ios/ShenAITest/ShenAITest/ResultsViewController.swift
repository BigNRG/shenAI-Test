import ShenaiSDK
import UIKit

/// Our own summary of the final measurement results.
final class ResultsViewController: UIViewController {
    private let results: MeasurementResults
    private let statusLabel = UILabel()

    init(results: MeasurementResults) {
        self.results = results
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Results"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
        ])

        let r = results
        let q = r.qualityMetrics
        let rows: [(String, String?)] = [
            ("Vitals", nil),
            ("Heart rate", "\(formatNumber(r.heartRateBpm)) bpm"),
            ("HRV SDNN", "\(formatNumber(r.hrvSdnnMs, decimals: 1)) ms"),
            ("HRV lnRMSSD", "\(formatNumber(r.hrvLnrmssdMs, decimals: 2)) ms"),
            ("Breathing rate", "\(formatNumber(r.breathingRateBpm, decimals: 1)) brpm"),
            ("Blood pressure", "\(formatBloodPressure(r)) mmHg"),
            ("Cardiac stress", formatNumber(r.stressIndex, decimals: 1)),
            ("PNS activity", formatNumber(r.parasympatheticActivity, decimals: 1)),
            ("Cardiac workload", "\(formatNumber(r.cardiacWorkloadMmhgPerSec, decimals: 1)) mmHg/s"),
            ("Body", nil),
            ("Age estimate", "\(formatNumber(r.ageYears)) years"),
            ("BMI", "\(formatNumber(r.bmiKgPerM2, decimals: 1)) kg/m²"),
            ("Weight", "\(formatNumber(r.weightKg, decimals: 1)) kg"),
            ("Height", "\(formatNumber(r.heightCm, decimals: 1)) cm"),
            ("Signal", nil),
            ("Average signal quality", "\(formatNumber(r.averageSignalQuality, decimals: 1)) dB"),
            ("PPG quality index", formatNumber(q?.ppgQualityIndex, decimals: 1)),
            ("BCG quality index", formatNumber(q?.bcgQualityIndex, decimals: 1)),
            ("Heartbeats detected", "\(r.heartbeats.count)"),
        ]

        for (label, value) in rows {
            if let value {
                stack.addArrangedSubview(makeRow(label: label, value: value))
            } else {
                let header = makeSectionTitle(label)
                if !stack.arrangedSubviews.isEmpty {
                    stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
                }
                stack.addArrangedSubview(header)
            }
        }

        let pdfButton = makeButton("Open PDF report") { [weak self] in
            ShenaiSDK.openMeasurementResultsPdfInBrowser()
            self?.statusLabel.text = "PDF open request sent."
        }
        let doneButton = makeButton("Done", filled: true) { [weak self] in self?.doneTapped() }
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(pdfButton)
        stack.setCustomSpacing(12, after: pdfButton)
        stack.addArrangedSubview(doneButton)

        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(statusLabel)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            ShenaiSession.stop()
        }
    }

    @objc private func doneTapped() {
        ShenaiSession.stop()
        navigationController?.popToRootViewController(animated: true)
    }

    private func makeRow(label: String, value: String) -> UIView {
        let name = UILabel()
        name.text = label
        name.textColor = .secondaryLabel
        let val = UILabel()
        val.text = value
        val.font = .systemFont(ofSize: 17, weight: .semibold)
        val.textAlignment = .right
        val.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [name, val])
        row.spacing = 8
        return row
    }
}
