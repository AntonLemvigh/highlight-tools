import Cocoa
import ServiceManagement

/// General settings tab: enable/disable, trigger delay, launch at login.
class GeneralSettingsView: NSView {

    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var delaySlider: NSSlider!
    private var delayLabel: NSTextField!
    private var nonLLMCheckbox: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Enabled toggle
        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Highlight Tools", target: self, action: #selector(toggleEnabled))
        enabledCheckbox.state = SettingsManager.shared.isEnabled ? .on : .off

        // Launch at login
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off

        // Trigger delay
        let delayTitle = NSTextField(labelWithString: "Popup delay:")
        delaySlider = NSSlider(value: SettingsManager.shared.triggerDelay, minValue: 0.1, maxValue: 1.0, target: self, action: #selector(delayChanged))
        delaySlider.numberOfTickMarks = 10
        delaySlider.allowsTickMarkValuesOnly = false
        delayLabel = NSTextField(labelWithString: String(format: "%.1fs", SettingsManager.shared.triggerDelay))

        // Show non-LLM actions
        nonLLMCheckbox = NSButton(checkboxWithTitle: "Show Copy & Search actions", target: self, action: #selector(toggleNonLLM))
        nonLLMCheckbox.state = SettingsManager.shared.showNonLLMActions ? .on : .off

        // Layout
        let delayRow = NSStackView(views: [delayTitle, delaySlider, delayLabel])
        delayRow.orientation = .horizontal
        delayRow.spacing = 8

        let stack = NSStackView(views: [enabledCheckbox, launchAtLoginCheckbox, delayRow, nonLLMCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @objc private func toggleEnabled() {
        SettingsManager.shared.isEnabled = enabledCheckbox.state == .on
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.general.error("Failed to toggle launch at login: \(error.localizedDescription)")
            // Revert checkbox to actual state
            launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
    }

    @objc private func delayChanged() {
        SettingsManager.shared.triggerDelay = delaySlider.doubleValue
        delayLabel.stringValue = String(format: "%.1fs", delaySlider.doubleValue)
    }

    @objc private func toggleNonLLM() {
        SettingsManager.shared.showNonLLMActions = nonLLMCheckbox.state == .on
    }
}
