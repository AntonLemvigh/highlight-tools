import Cocoa
import ApplicationServices

/// Manages Accessibility API integration for detecting text selections system-wide.
///
/// Detection strategy:
/// 1. AX notifications for native apps (instant)
/// 2. On mouseUp after drag or double-click: try AX, then browser AppleScript, then menu-bar Copy
/// 3. Polling fallback for apps that update selection with delay
class AccessibilityManager {

    /// Called when selected text changes. `nil` means selection was cleared.
    private let onSelectionChange: (SelectionInfo?) -> Void

    private var currentObserver: SelectionObserver?
    private var workspaceObserver: NSObjectProtocol?
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var permissionTimer: Timer?
    private var appSwitchWorkItem: DispatchWorkItem?
    private let debouncer: Debouncer
    private var dragCount: Int = 0

    init(onSelectionChange: @escaping (SelectionInfo?) -> Void) {
        self.onSelectionChange = onSelectionChange
        self.debouncer = Debouncer(delay: SettingsManager.shared.triggerDelay)
    }

    // MARK: - Start / Stop

    func start() {
        if hasAccessibilityPermission() {
            AppLogger.accessibility.info("Accessibility permission granted — starting observation")
            beginObserving()
            return
        }

        // Prompt once, then poll silently until permission is granted
        promptForPermission()
        AppLogger.accessibility.info("Waiting for accessibility permission... (grant in System Settings > Privacy & Security > Accessibility)")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if self?.hasAccessibilityPermission() == true {
                AppLogger.accessibility.info("Accessibility permission granted!")
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
                self?.beginObserving()
            }
        }
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        appSwitchWorkItem?.cancel()
        appSwitchWorkItem = nil
        currentObserver?.teardown()
        currentObserver = nil
        debouncer.cancel()

        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = mouseDragMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDragMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    // MARK: - Permission

    /// Prompts the user to grant Accessibility permission (shows System Settings dialog).
    private func promptForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Silently checks if accessibility permission is granted, without prompting.
    private func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Observation

    private func beginObserving() {
        AppLogger.accessibility.info("Starting accessibility observation")

        // Track mouseDown — reset drag count
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dragCount = 0
        }

        // Count drag events to distinguish drag-selection from click
        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.dragCount += 1
        }

        // On mouseUp: trigger selection check for drags and double-clicks
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self, let observer = self.currentObserver else { return }
            let mouseUpLocation = NSEvent.mouseLocation
            let wasDragged = self.dragCount >= 3
            let isDoubleClick = event.clickCount >= 2
            self.dragCount = 0

            // Only check if user actually selected something (drag or double-click)
            guard wasDragged || isDoubleClick else { return }

            // Short delay to let the target app finalize its selection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                observer.checkSelectionNow(mouseLocation: mouseUpLocation)
            }
        }

        // Observe frontmost app changes
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.switchToApp(pid: app.processIdentifier)
        }

        // Observe the currently active app immediately
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            switchToApp(pid: frontApp.processIdentifier)
        }
    }

    private func switchToApp(pid: pid_t) {
        // Cancel any pending app-switch setup
        appSwitchWorkItem?.cancel()

        // Tear down the previous observer
        currentObserver?.teardown()
        currentObserver = nil

        // Dismiss any visible popup on app switch
        debouncer.cancel()
        onSelectionChange(nil)

        // Don't observe ourselves
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        // Small delay to avoid thrashing during rapid Cmd-Tab switching
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            AppLogger.accessibility.debug("Switching observer to PID \(pid)")

            self.currentObserver = SelectionObserver(pid: pid) { [weak self] info in
                guard let self else { return }
                if let info {
                    self.debouncer.debounce {
                        self.onSelectionChange(info)
                    }
                } else {
                    self.debouncer.cancel()
                    self.onSelectionChange(nil)
                }
            }
        }
        appSwitchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}
