import Cocoa
import ServiceManagement

/// General settings tab — enable/disable, trigger delay, launch at login, per-app disable.
class GeneralSettingsView: NSView {

    private var enabledCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var delaySlider: NSSlider!
    private var delayLabel: NSTextField!
    private var nonLLMCheckbox: NSButton!
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

        // ── Section: Behaviour ─────────────────────────────────────────────
        let behaviourHeader = sectionHeader("Behaviour")

        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Highlight Tools",
                                   target: self, action: #selector(toggleEnabled))
        enabledCheckbox.state = SettingsManager.shared.isEnabled ? .on : .off

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login",
                                         target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off

        nonLLMCheckbox = NSButton(checkboxWithTitle: "Show Copy & Search actions",
                                   target: self, action: #selector(toggleNonLLM))
        nonLLMCheckbox.state = SettingsManager.shared.showNonLLMActions ? .on : .off

        // Popup delay row
        let delayTitle = NSTextField(labelWithString: "Popup delay")
        delayTitle.font = .systemFont(ofSize: 13)
        delayTitle.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        delaySlider = NSSlider(value: SettingsManager.shared.triggerDelay,
                               minValue: 0.1, maxValue: 1.0,
                               target: self, action: #selector(delayChanged))
        delaySlider.numberOfTickMarks = 10
        delaySlider.allowsTickMarkValuesOnly = false
        delaySlider.controlSize = .small

        delayLabel = NSTextField(labelWithString: String(format: "%.1fs", SettingsManager.shared.triggerDelay))
        delayLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        delayLabel.textColor = .secondaryLabelColor
        delayLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let delayRow = NSStackView(views: [delayTitle, delaySlider, delayLabel])
        delayRow.orientation = .horizontal
        delayRow.spacing = 8

        let behaviourBox = groupBox(views: [enabledCheckbox, launchAtLoginCheckbox, nonLLMCheckbox, delayRow])

        // ── Section: Disabled Apps ─────────────────────────────────────────
        let appsHeader = sectionHeader("Disabled Apps")
        let appsHint = hintLabel("Highlight Tools stays silent in these apps.")

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(equalToConstant: 130).isActive = true

        disabledAppsTable = NSTableView()
        disabledAppsTable.headerView = nil
        disabledAppsTable.rowHeight = 22
        disabledAppsTable.intercellSpacing = NSSize(width: 0, height: 1)
        disabledAppsTable.style = .plain

        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.width = 220
        disabledAppsTable.addTableColumn(nameCol)

        let bundleCol = NSTableColumn(identifier: .init("bundle"))
        bundleCol.width = 220
        disabledAppsTable.addTableColumn(bundleCol)

        disabledAppsTable.dataSource = self
        disabledAppsTable.delegate = self
        scrollView.documentView = disabledAppsTable

        let addBtn = NSButton(title: "+", target: self, action: #selector(addApp))
        addBtn.bezelStyle = .smallSquare
        let removeBtn = NSButton(title: "−", target: self, action: #selector(removeApp))
        removeBtn.bezelStyle = .smallSquare

        let appsButtonRow = NSStackView(views: [addBtn, removeBtn, NSView()])
        appsButtonRow.orientation = .horizontal
        appsButtonRow.spacing = 4

        loadDisabledApps()

        // ── Main stack ─────────────────────────────────────────────────────
        let main = NSStackView(views: [
            behaviourHeader, behaviourBox,
            appsHeader, appsHint, scrollView, appsButtonRow,
        ])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 8
        main.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.translatesAutoresizingMaskIntoConstraints = false

        addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor),
            main.leadingAnchor.constraint(equalTo: leadingAnchor),
            main.trailingAnchor.constraint(equalTo: trailingAnchor),
            main.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -40),
            appsButtonRow.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            behaviourBox.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -40),
        ])
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .labelColor
        return label
    }

    private func hintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Wraps controls in a rounded NSBox (group box style).
    private func groupBox(views: [NSView]) -> NSBox {
        let box = NSBox()
        box.boxType = .primary
        box.titlePosition = .noTitle
        box.cornerRadius = 8
        box.contentViewMargins = NSSize(width: 12, height: 8)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)

        if let cv = box.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cv.topAnchor),
                stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
        }
        return box
    }

    // MARK: - General actions

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

    // MARK: - Per-app disable

    private struct DisabledAppRow {
        var name: String
        var bundleID: String
    }

    private func loadDisabledApps() {
        let bundleIDs = SettingsManager.shared.disabledBundleIDs
        disabledApps = bundleIDs.map { id in
            let name = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == id })?.localizedName ?? id
            return DisabledAppRow(name: name, bundleID: id)
        }
        disabledAppsTable?.reloadData()
    }

    private func saveDisabledApps() {
        SettingsManager.shared.disabledBundleIDs = disabledApps.map(\.bundleID)
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose App to Disable"
        panel.message = "Highlight Tools will not activate in the selected app."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
                ?? url.deletingPathExtension().lastPathComponent
            let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            guard !self.disabledApps.contains(where: { $0.bundleID == bundleID }) else { return }
            self.disabledApps.append(DisabledAppRow(name: name, bundleID: bundleID))
            self.saveDisabledApps()
            self.disabledAppsTable.reloadData()
        }
    }

    @objc private func removeApp() {
        let row = disabledAppsTable.selectedRow
        guard row >= 0, row < disabledApps.count else { return }
        disabledApps.remove(at: row)
        saveDisabledApps()
        disabledAppsTable.reloadData()
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension GeneralSettingsView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { disabledApps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = disabledApps[row]
        let isBundle = tableColumn?.identifier.rawValue == "bundle"
        let label = NSTextField(labelWithString: isBundle ? app.bundleID : app.name)
        label.font = .systemFont(ofSize: 12)
        label.textColor = isBundle ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
