import Cocoa

/// Main application delegate.
/// Sets up the app as a menubar-only app (no Dock icon) and wires together
/// the status bar, accessibility manager, and popup controller.
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var accessibilityManager: AccessibilityManager!
    private var popupController: PopupWindowController!
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and Cmd-Tab switcher (also set via LSUIElement in Info.plist)
        NSApp.setActivationPolicy(.accessory)

        // Initialize settings manager (loads defaults)
        _ = SettingsManager.shared

        // Create the popup controller
        popupController = PopupWindowController()

        // Create the accessibility manager and wire selection events to the popup
        accessibilityManager = AccessibilityManager { [weak self] selectionInfo in
            guard let self else { return }
            if let info = selectionInfo {
                self.popupController.show(for: info)
            } else {
                self.popupController.dismiss()
            }
        }

        // Create the menubar status item
        statusBarController = StatusBarController(
            onToggle: { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.accessibilityManager.start()
                } else {
                    self.accessibilityManager.stop()
                    self.popupController.dismiss()
                }
            },
            onSettings: { [weak self] in
                self?.showSettings()
            }
        )

        // Start listening for selections if enabled
        if SettingsManager.shared.isEnabled {
            accessibilityManager.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityManager?.stop()
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
