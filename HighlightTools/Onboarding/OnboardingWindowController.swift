import Cocoa
import ApplicationServices

/// 3-step onboarding wizard shown on first launch.
/// Steps: Welcome → Accessibility Permission → LLM Setup
class OnboardingWindowController: NSWindowController {

    /// Called when the user completes or skips onboarding.
    var onComplete: (() -> Void)?

    private var currentStep = 0
    private let totalSteps = 3

    // Shared elements
    private var stepContainer: NSView!
    private var progressLabel: NSTextField!
    private var nextButton: NSButton!
    private var skipButton: NSButton!

    // Step 2 (AX) state
    private var axStatusLabel: NSTextField?
    private var axCheckTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Highlight Tools"
        window.isMovableByWindowBackground = true
        window.center()
        self.init(window: window)
        setupShellLayout()
        showStep(0)
    }

    deinit {
        axCheckTimer?.invalidate()
    }

    // MARK: - Shell Layout

    private func setupShellLayout() {
        guard let contentView = window?.contentView else { return }

        // Step container fills most of the window
        stepContainer = NSView()
        stepContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stepContainer)

        // Progress indicator
        progressLabel = NSTextField(labelWithString: "")
        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .tertiaryLabelColor
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressLabel)

        // Buttons
        nextButton = NSButton(title: "Next", target: self, action: #selector(next))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        skipButton = NSButton(title: "Skip setup", target: self, action: #selector(skip))
        skipButton.bezelStyle = .inline
        skipButton.isBordered = false
        skipButton.font = .systemFont(ofSize: 11)
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(skipButton)

        let buttonRow = NSStackView(views: [skipButton, NSView(), nextButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            stepContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            stepContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stepContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stepContainer.bottomAnchor.constraint(equalTo: progressLabel.topAnchor, constant: -12),

            progressLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),

            buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Navigation

    @objc private func next() {
        axCheckTimer?.invalidate()
        axCheckTimer = nil

        currentStep += 1
        if currentStep >= totalSteps {
            complete()
        } else {
            showStep(currentStep)
        }
    }

    @objc private func skip() {
        axCheckTimer?.invalidate()
        complete()
    }

    private func complete() {
        SettingsManager.shared.hasCompletedOnboarding = true
        window?.close()
        onComplete?()
    }

    // MARK: - Steps

    private func showStep(_ step: Int) {
        // Clear old content
        stepContainer.subviews.forEach { $0.removeFromSuperview() }
        progressLabel.stringValue = "Step \(step + 1) of \(totalSteps)"

        switch step {
        case 0: buildWelcomeStep()
        case 1: buildAccessibilityStep()
        case 2: buildLLMStep()
        default: break
        }
    }

    // ---- Step 0: Welcome ----

    private func buildWelcomeStep() {
        nextButton.title = "Get Started"
        nextButton.isEnabled = true
        skipButton.isHidden = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil)
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 52, weight: .light)
        icon.image = icon.image?.withSymbolConfiguration(iconConfig)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Welcome to Highlight Tools")
        title.font = .boldSystemFont(ofSize: 20)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString:
            "Select any text anywhere on your Mac and a popup will appear with instant AI actions — explain, translate, summarise, and more.\n\nThis quick setup takes about a minute.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 20, right: 40)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stepContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: stepContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: stepContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: stepContainer.trailingAnchor),
        ])
    }

    // ---- Step 1: Accessibility ----

    private func buildAccessibilityStep() {
        nextButton.title = "Continue"
        skipButton.isHidden = false

        let icon = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 40, weight: .light)
        icon.image = NSImage(systemSymbolName: "hand.raised.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Accessibility Permission")
        title.font = .boldSystemFont(ofSize: 18)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString:
            "Highlight Tools needs Accessibility permission to detect when you select text in other apps. This permission stays on your Mac and no data leaves without your action.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.translatesAutoresizingMaskIntoConstraints = false

        let grantButton = NSButton(title: "Open System Settings", target: self, action: #selector(openAccessibilitySettings))
        grantButton.bezelStyle = .rounded
        grantButton.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: AXIsProcessTrusted() ? "✓ Permission granted" : "Waiting for permission…")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = AXIsProcessTrusted() ? .systemGreen : .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        axStatusLabel = statusLabel

        // Update next button based on current permission
        nextButton.isEnabled = true  // allow continuing even without permission

        let stack = NSStackView(views: [icon, title, body, grantButton, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 40, bottom: 20, right: 40)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stepContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: stepContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: stepContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: stepContainer.trailingAnchor),
        ])

        // Poll every second so status updates live
        axCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let granted = AXIsProcessTrusted()
            self?.axStatusLabel?.stringValue = granted ? "✓ Permission granted" : "Waiting for permission…"
            self?.axStatusLabel?.textColor = granted ? .systemGreen : .secondaryLabelColor
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // ---- Step 2: LLM Setup ----

    private func buildLLMStep() {
        nextButton.title = "Done"
        skipButton.isHidden = false

        let icon = NSImageView()
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 40, weight: .light)
        icon.image = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Connect an AI Model")
        title.font = .boldSystemFont(ofSize: 18)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString:
            "Highlight Tools works with Ollama (free, local, private) or any OpenAI-compatible API.\n\nFor local AI: install Ollama from ollama.com and pull a model like llama3.2.\nFor cloud AI: enter your API key in Settings → Models.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.translatesAutoresizingMaskIntoConstraints = false

        let ollamaButton = NSButton(title: "Get Ollama (ollama.com)", target: self, action: #selector(openOllama))
        ollamaButton.bezelStyle = .rounded
        ollamaButton.translatesAutoresizingMaskIntoConstraints = false

        let settingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openModelSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "You can change this anytime in the Settings menu.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, title, body, ollamaButton, settingsButton, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 40, bottom: 16, right: 40)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stepContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: stepContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: stepContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: stepContainer.trailingAnchor),
        ])
    }

    @objc private func openOllama() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com")!)
    }

    @objc private func openModelSettings() {
        // Notify the app to open settings on the Models tab
        NotificationCenter.default.post(name: OnboardingWindowController.openModelSettingsNotification, object: nil)
    }

    static let openModelSettingsNotification = Notification.Name("OnboardingOpenModelSettings")
}
