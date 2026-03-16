import Cocoa
import ServiceManagement

/// General settings tab: enable/disable, trigger delay, launch at login, per-app disable.
class GeneralSettingsView: NSView {

    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var delaySlider: NSSlider!
    private var delayLabel: NSTextField!
    private var nonLLMCheckbox: NSButton!

    // Per-app disable
    private var disabledAppsTable: NSTableView!
    private var disabledApps: [DisabledAppRow] = []

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

        let delayRow = NSStackView(views: [delayTitle, delaySlider, delayLabel])
        delayRow.orientation = .horizontal
        delayRow.spacing = 8

        // Show non-LLM actions
        nonLLMCheckbox = NSButton(checkboxWithTitle: "Show Copy & Search actions", target: self, action: #selector(toggleNonLLM))
        nonLLMCheckbox.state = SettingsManager.shared.showNonLLMActions ? .on : .off

        // ---- Per-app disable section ----
        let appsHeader = NSTextField(labelWithString: "Disabled Apps")
        appsHeader.font = .boldSystemFont(ofSize: 13)

        let appsHint = NSTextField(labelWithString: "Highlight Tools will not activate in these apps.")
        appsHint.font = .systemFont(ofSize: 11)
        appsHint.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        disabledAppsTable = NSTableView()
        disabledAppsTable.headerView = nil
        disabledAppsTable.rowHeight = 24

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.width = 200
        disabledAppsTable.addTableColumn(nameCol)

        let bundleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bundle"))
        bundleCol.width = 160
        disabledAppsTable.addTableColumn(bundleCol)

        disabledAppsTable.dataSource = self
        disabledAppsTable.delegate = self
        scrollView.documentView = disabledAppsTable

        let addAppButton = NSButton(title: "+ Add App", target: self, action: #selector(addApp))
        addAppButton.bezelStyle = .smallSquare
        let removeAppButton = NSButton(title: "− Remove", target: self, action: #selector(removeApp))
        removeAppButton.bezelStyle = .smallSquare
        let appButtonRow = NSStackView(views: [addAppButton, removeAppButton, NSView()])
        appButtonRow.orientation = .horizontal
        appButtonRow.spacing = 4

        loadDisabledApps()

        // Main layout
        let stack = NSStackView(views: [
            enabledCheckbox, launchAtLoginCheckbox, delayRow, nonLLMCheckbox,
            appsHeader, appsHint, scrollView, appButtonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            appButtonRow.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    // MARK: - General Actions

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

    // MARK: - Per-App Disable

    private struct DisabledAppRow {
        var name: String
        var bundleID: String
    }

    private func loadDisabledApps() {
        let bundleIDs = SettingsManager.shared.disabledBundleIDs
        disabledApps = bundleIDs.map { bundleID in
            // Try to resolve a human-readable name from installed apps
            let name = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleID })?.localizedName
                ?? bundleID
            return DisabledAppRow(name: name, bundleID: bundleID)
        }
        disabledAppsTable?.reloadData()
    }

    private func saveDisabledApps() {
        SettingsManager.shared.disabledBundleIDs = disabledApps.map(\.bundleID)
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose App to Disable"
        panel.message = "Select an application to exclude from Highlight Tools."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
            let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent

            // Avoid duplicates
            guard !self.disabledApps.contains(where: { $0.bundleID == bundleID }) else { return }
            self.disabledApps.append(DisabledAppRow(name: name, bundleID: bundleID))
            self.saveDisabledApps()
            self.disabledAppsTable.reloadData()
        }
    }

    @objc private func removeApp() {
        let selected = disabledAppsTable.selectedRow
        guard selected >= 0, selected < disabledApps.count else { return }
        disabledApps.remove(at: selected)
        saveDisabledApps()
        disabledAppsTable.reloadData()
    }
}

// MARK: - NSTableViewDataSource & Delegate (disabled apps)

extension GeneralSettingsView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        disabledApps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = disabledApps[row]
        let colID = tableColumn?.identifier.rawValue ?? ""
        let label = NSTextField(labelWithString: colID == "bundle" ? app.bundleID : app.name)
        label.font = .systemFont(ofSize: 12)
        label.textColor = colID == "bundle" ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
