import Cocoa

/// Manages the menubar status item (icon + dropdown menu).
/// The app lives entirely in the menubar — no Dock icon.
class StatusBarController {

    private var statusItem: NSStatusItem
    private let onToggle: (Bool) -> Void
    private let onSettings: () -> Void
    private let onHistory: () -> Void
    private var enabledMenuItem: NSMenuItem!

    init(onToggle: @escaping (Bool) -> Void, onSettings: @escaping () -> Void, onHistory: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onSettings = onSettings
        self.onHistory = onHistory

        // Create a status item with a fixed-width icon slot
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Use an SF Symbol as the menubar icon — "text.cursor" looks like a text selection
            button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Highlight Tools")
            button.image?.isTemplate = true  // Adapts to light/dark menu bar automatically
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Toggle enabled/disabled
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        enabledMenuItem.state = SettingsManager.shared.isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        menu.addItem(.separator())

        // History
        let historyItem = NSMenuItem(title: "Response History…", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        // Open settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Highlight Tools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleEnabled() {
        let newValue = !SettingsManager.shared.isEnabled
        SettingsManager.shared.isEnabled = newValue
        enabledMenuItem.state = newValue ? .on : .off
        onToggle(newValue)
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func openHistory() {
        onHistory()
    }
}
