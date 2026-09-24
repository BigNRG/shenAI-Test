import AVFoundation
import UIKit

/// API key entry + mode selection.
final class HomeViewController: UIViewController, UITextFieldDelegate {
    private let apiKeyField = UITextField()
    private let userIdField = UITextField()
    private let statusLabel = UILabel()
    private var modeButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Shen.AI Test"
        view.backgroundColor = .systemBackground

        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
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
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
        ])

        stack.addArrangedSubview(makeCaption("Shen.AI iOS SDK \(ShenaiSession.sdkVersion)"))

        stack.addArrangedSubview(makeSectionTitle("API key"))
        stack.addArrangedSubview(makeCaption("Get an API key from developer.shen.ai. It is stored only on this device."))

        apiKeyField.placeholder = "Shen.AI API key"
        apiKeyField.text = ShenaiSession.apiKey
        apiKeyField.isSecureTextEntry = true
        configure(apiKeyField)

        let toggle = UIButton(type: .system)
        toggle.setTitle("Show", for: .normal)
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            guard let self else { return }
            self.apiKeyField.isSecureTextEntry.toggle()
            toggle?.setTitle(self.apiKeyField.isSecureTextEntry ? "Show" : "Hide", for: .normal)
        }, for: .touchUpInside)
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        let keyRow = UIStackView(arrangedSubviews: [apiKeyField, toggle])
        keyRow.spacing = 8
        stack.addArrangedSubview(keyRow)

        userIdField.placeholder = "User ID (optional)"
        userIdField.text = ShenaiSession.userId
        configure(userIdField)
        stack.addArrangedSubview(userIdField)

        stack.setCustomSpacing(28, after: userIdField)
        stack.addArrangedSubview(makeSectionTitle("Test the SDK"))

        let sdkUiButton = makeButton("Measurement (SDK UI)", filled: true) { [weak self] in self?.open(.sdkUI) }
        let customButton = makeButton("Measurement (Custom UI + live metrics)") { [weak self] in self?.open(.customUI) }
        let dashboardButton = makeButton("Dashboard") { [weak self] in self?.open(.dashboard) }
        modeButtons = [sdkUiButton, customButton, dashboardButton]
        modeButtons.forEach(stack.addArrangedSubview)

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        stack.addArrangedSubview(statusLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func configure(_ field: UITextField) {
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.delegate = self
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabel
    }

    private func open(_ mode: TestMode) {
        view.endEditing(true)
        let key = apiKeyField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            setStatus("Enter your Shen.AI API key first.", isError: true)
            return
        }
        ShenaiSession.apiKey = key
        ShenaiSession.userId = userIdField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        withCameraPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.setStatus("Camera access is required. Enable it in Settings > Shen.AI Test.", isError: true)
                return
            }
            self.startSession(mode)
        }
    }

    private func startSession(_ mode: TestMode) {
        setStatus("Initializing SDK...")
        modeButtons.forEach { $0.isEnabled = false }
        // Let the status label render before the (synchronous) license activation.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.modeButtons.forEach { $0.isEnabled = true } }
            if let error = ShenaiSession.start(mode: mode) {
                self.setStatus(error, isError: true)
                return
            }
            self.setStatus("")
            self.navigationController?.pushViewController(SessionViewController(mode: mode), animated: true)
        }
    }

    private func withCameraPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }
}

// MARK: - Shared UI helpers

func makeButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 17, weight: filled ? .semibold : .regular)
    button.layer.cornerRadius = 8
    button.layer.borderWidth = 1
    button.layer.borderColor = UIColor.label.cgColor
    button.backgroundColor = filled ? .label : .clear
    button.setTitleColor(filled ? .systemBackground : .label, for: .normal)
    button.setTitleColor(.tertiaryLabel, for: .disabled)
    button.heightAnchor.constraint(equalToConstant: 52).isActive = true
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
}

func makeSectionTitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .headline)
    return label
}

func makeCaption(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    return label
}
