import Cocoa
import ApplicationServices

/// Observes text selection changes for a single application.
///
/// Detection tiers:
/// 1. AX notifications (native apps — instant)
/// 2. AX polling (apps that update selection lazily)
/// 3. On mouseUp: AX read → Browser AppleScript → Menu-bar Copy fallback
///
/// The fallback tiers only run on mouseUp (drag or double-click) to avoid
/// interfering with the user's workflow.
class SelectionObserver {

    private let pid: pid_t
    private var observer: AXObserver?
    private let appElement: AXUIElement
    private let onSelection: (SelectionInfo?) -> Void
    private var pollTimer: Timer?
    private var lastPolledText: String?
    private var notificationFired = false

    /// After a successful copy-fallback, suppress polling for this duration
    /// to prevent the poll (which reads nil from AX) from dismissing the popup.
    private var fallbackCooldownUntil: Date = .distantPast

    /// Tracks whether AX has ever returned text for this app.
    /// If false, AX doesn't work for this app (Firefox, Electron, etc.)
    /// and polling should never dismiss the popup by reporting nil.
    private var axEverReturnedText = false

    /// How often to poll for selection changes in apps that don't fire AX notifications.
    private static let pollInterval: TimeInterval = 0.3

    init(pid: pid_t, onSelection: @escaping (SelectionInfo?) -> Void) {
        self.pid = pid
        self.appElement = AXUIElementCreateApplication(pid)
        self.onSelection = onSelection

        setupObserver()
        startPolling()
    }

    // MARK: - AX Observer Setup

    private func setupObserver() {
        let callback: AXObserverCallback = { _, element, notificationName, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<SelectionObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handleSelectionChange(element: element)
        }

        var axObserver: AXObserver?
        let result = AXObserverCreate(pid, callback, &axObserver)
        guard result == .success, let axObserver else {
            AppLogger.accessibility.warning("Failed to create AXObserver for PID \(self.pid): \(result.rawValue)")
            return
        }

        self.observer = axObserver

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let addResult = AXObserverAddNotification(
            axObserver,
            appElement,
            kAXSelectedTextChangedNotification as CFString,
            refcon
        )

        if addResult != .success {
            AppLogger.accessibility.warning("Failed to add notification for PID \(self.pid): \(addResult.rawValue)")
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(axObserver),
            .defaultMode
        )

        AppLogger.accessibility.debug("Observer created for PID \(self.pid)")
    }

    // MARK: - Polling (tier 2)

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.pollSelection()
        }
    }

    private func pollSelection() {
        // If the notification-based path is working, skip polling
        if notificationFired {
            notificationFired = false
            return
        }

        // Don't let polling override a recent copy-fallback result
        if Date() < fallbackCooldownUntil { return }

        let selectedText = readSelectedText()

        // Only fire if the text actually changed
        if selectedText == lastPolledText { return }

        if let selectedText,
           selectedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
            axEverReturnedText = true
            lastPolledText = selectedText
            let bounds = getSelectionBoundsFromFocused() ?? mouseLocationBounds()
            let info = SelectionInfo(text: selectedText, bounds: bounds, pid: pid)
            AppLogger.accessibility.debug("Poll: \"\(selectedText.prefix(50))\"")
            onSelection(info)
        } else if axEverReturnedText {
            // AX works for this app and now returns nil → user deselected text
            lastPolledText = selectedText
            onSelection(nil)
        }
        // If AX has NEVER returned text (Firefox, Electron), don't dismiss via polling.
        // The popup will be dismissed by user clicking outside or switching apps.
    }

    // MARK: - AX Text Reading (tier 1)

    /// Reads selected text via AX, trying multiple element sources.
    private func readSelectedText() -> String? {
        // Strategy 1: System-wide focused element (most native apps)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
           let fv = focusedValue, CFGetTypeID(fv) == AXUIElementGetTypeID() {
            let element = fv as! AXUIElement
            if let text = selectedText(from: element) { return text }
        }

        // Strategy 2: App-level focused element
        var appFocusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &appFocusedValue) == .success,
           let fv = appFocusedValue, CFGetTypeID(fv) == AXUIElementGetTypeID() {
            let element = fv as! AXUIElement
            if let text = selectedText(from: element) { return text }
        }

        // Strategy 3: App element directly
        if let text = selectedText(from: appElement) { return text }

        return nil
    }

    private func selectedText(from element: AXUIElement) -> String? {
        var textValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textValue)
        guard result == .success else { return nil }

        // Handle both String and NSAttributedString
        if let text = textValue as? String, !text.isEmpty { return text }
        if let attrStr = textValue as? NSAttributedString, attrStr.length > 0 { return attrStr.string }

        return nil
    }

    // MARK: - mouseUp Trigger (tier 3: full fallback chain)

    /// Called by AccessibilityManager on global mouseUp (drag or double-click).
    /// Both mouse positions are provided so we can estimate selection bounds for non-AX apps.
    func checkSelectionNow(mouseUpLocation: CGPoint, mouseDownLocation: CGPoint?) {
        // Tier 1: AX API (instant, no side effects)
        if let axText = readSelectedText() {
            reportText(axText, mouseUpLocation: mouseUpLocation, mouseDownLocation: mouseDownLocation, source: "AX-mouseUp")
            return
        }

        // Tier 2: AppleScript for known browsers (Safari, Chrome, Arc, Brave)
        if let browserText = readBrowserSelection() {
            reportText(browserText, mouseUpLocation: mouseUpLocation, mouseDownLocation: mouseDownLocation, source: "Browser")
            return
        }

        // Tier 3: Copy via menu bar or Cmd+C, then restore pasteboard
        performCopyFallback(mouseUpLocation: mouseUpLocation, mouseDownLocation: mouseDownLocation)
    }

    private func reportText(_ text: String, mouseUpLocation: CGPoint, mouseDownLocation: CGPoint?, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        lastPolledText = text
        let bounds = getSelectionBoundsFromFocused()
            ?? estimatedSelectionBounds(mouseUp: mouseUpLocation, mouseDown: mouseDownLocation)
        let info = SelectionInfo(text: text, bounds: bounds, pid: pid)
        AppLogger.accessibility.debug("\(source): \"\(text.prefix(50))\"")
        onSelection(info)
    }

    // MARK: - Browser AppleScript (tier 2)

    private func readBrowserSelection() -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let bundleID = app.bundleIdentifier ?? ""

        let script: String?

        if bundleID.contains("com.apple.Safari") || bundleID.localizedCaseInsensitiveContains("safari") {
            script = """
            tell application "Safari"
                do JavaScript "window.getSelection().toString()" in document 1
            end tell
            """
        } else if bundleID.contains("com.google.Chrome") || bundleID.localizedCaseInsensitiveContains("chrome") || bundleID.localizedCaseInsensitiveContains("chromium") {
            script = """
            tell application "Google Chrome"
                execute active tab of front window javascript "window.getSelection().toString()"
            end tell
            """
        } else if bundleID.localizedCaseInsensitiveContains("brave") {
            script = """
            tell application "Brave Browser"
                execute active tab of front window javascript "window.getSelection().toString()"
            end tell
            """
        } else if bundleID.contains("company.thebrowser") || bundleID.localizedCaseInsensitiveContains("arc") {
            script = """
            tell application "Arc"
                execute active tab of front window javascript "window.getSelection().toString()"
            end tell
            """
        } else {
            // Firefox, Electron apps, etc. don't support AppleScript JS — use copy fallback
            script = nil
        }

        guard let script else { return nil }

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        let result = appleScript.executeAndReturnError(&error)

        if error != nil { return nil }

        let text = result.stringValue
        return (text?.isEmpty == false) ? text : nil
    }

    // MARK: - Copy Fallback (tier 3)

    /// Saves the pasteboard, triggers Copy via menu bar AX action (or Cmd+C),
    /// reads the result, then restores the original pasteboard.
    private func performCopyFallback(mouseUpLocation: CGPoint, mouseDownLocation: CGPoint?) {
        // Suppress polling IMMEDIATELY — before any async work — to prevent
        // the poll timer from reading nil via AX and dismissing the popup.
        fallbackCooldownUntil = Date().addingTimeInterval(5.0)

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let backup = backupPasteboard()

        // Try to trigger Copy: first via AX menu bar, then via CGEvent Cmd+C
        let triggered = triggerCopyMenuItem() || sendCmdC()

        guard triggered else {
            AppLogger.accessibility.debug("Copy fallback: failed to trigger copy")
            fallbackCooldownUntil = .distantPast
            return
        }

        // Wait for the target app to process the copy on a background thread
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let copiedText: String?

            if pasteboard.changeCount != previousChangeCount {
                copiedText = pasteboard.string(forType: .string)
            } else {
                // Try again with a longer wait
                Thread.sleep(forTimeInterval: 0.15)
                if pasteboard.changeCount != previousChangeCount {
                    copiedText = pasteboard.string(forType: .string)
                } else {
                    copiedText = nil
                }
            }

            // Do restore + report atomically on main thread in a single block
            DispatchQueue.main.async {
                guard let self else { return }

                // Restore the original pasteboard content
                self.restorePasteboard(backup)

                if let text = copiedText, !text.isEmpty {
                    self.reportText(text, mouseUpLocation: mouseUpLocation, mouseDownLocation: mouseDownLocation, source: "CopyFallback")
                } else {
                    // Copy didn't work — clear cooldown
                    self.fallbackCooldownUntil = .distantPast
                }
            }
        }
    }

    /// Finds the "Copy" menu item in the app's menu bar and presses it via AX.
    private func triggerCopyMenuItem() -> Bool {
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue else { return false }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let menus = childrenValue as? [AXUIElement] else { return false }

        // Common "Copy" translations
        let copyNames: Set<String> = ["Copy", "Kopier", "Kopiér", "Copier", "Kopieren", "Copiar",
                                       "Copia", "コピー", "拷贝", "复制", "복사", "Копировать"]

        for menu in menus {
            var menuChildrenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &menuChildrenValue)
            guard let subMenus = menuChildrenValue as? [AXUIElement] else { continue }

            for subMenu in subMenus {
                var itemsValue: CFTypeRef?
                AXUIElementCopyAttributeValue(subMenu, kAXChildrenAttribute as CFString, &itemsValue)
                guard let items = itemsValue as? [AXUIElement] else { continue }

                for item in items {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                    if let title = titleValue as? String, copyNames.contains(title) {
                        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                        if result == .success {
                            AppLogger.accessibility.debug("Triggered Copy menu item")
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    /// Sends Cmd+C via CGEvent as a last resort.
    private func sendCmdC() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        AppLogger.accessibility.debug("Sent Cmd+C via CGEvent")
        return true
    }

    // MARK: - Pasteboard Backup/Restore

    private func backupPasteboard() -> [(Data, NSPasteboard.PasteboardType)] {
        let pasteboard = NSPasteboard.general
        var saved: [(Data, NSPasteboard.PasteboardType)] = []
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.append((data, type))
                }
            }
        }
        return saved
    }

    private func restorePasteboard(_ items: [(Data, NSPasteboard.PasteboardType)]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pbItem = NSPasteboardItem()
        for (data, type) in items {
            pbItem.setData(data, forType: type)
        }
        pasteboard.writeObjects([pbItem])
    }

    // MARK: - Selection Bounds

    private func getSelectionBoundsFromFocused() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        if focusResult == .success, let fv = focusedValue, CFGetTypeID(fv) == AXUIElementGetTypeID() {
            return getSelectionBounds(element: fv as! AXUIElement)
        }
        return nil
    }

    // MARK: - Handle Selection Change (AX notification — tier 1)

    private func handleSelectionChange(element: AXUIElement) {
        notificationFired = true

        // If we triggered a copy-fallback recently, the menu interaction causes AX
        // selection notifications to fire with nil text — ignore them during cooldown.
        if Date() < fallbackCooldownUntil { return }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        let focusedElement: AXUIElement
        if focusResult == .success, let fv = focusedValue, CFGetTypeID(fv) == AXUIElementGetTypeID() {
            focusedElement = fv as! AXUIElement
        } else {
            focusedElement = element
        }

        var textValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &textValue)

        guard textResult == .success,
              let selectedText = textValue as? String,
              selectedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            lastPolledText = nil
            onSelection(nil)
            return
        }

        axEverReturnedText = true
        lastPolledText = selectedText

        let bounds = getSelectionBounds(element: focusedElement) ?? mouseLocationBounds()
        let info = SelectionInfo(text: selectedText, bounds: bounds, pid: pid)
        AppLogger.accessibility.debug("Notification: \"\(selectedText.prefix(50))\" at \(NSStringFromRect(bounds))")
        onSelection(info)
    }

    // MARK: - Selection Bounds

    private func getSelectionBounds(element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeResult == .success, let rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard boundsResult == .success, let boundsValue else { return nil }

        var cgRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &cgRect) else { return nil }

        return Self.cgRectToAppKit(cgRect)
    }

    /// Converts CG coordinates (top-left origin) to AppKit coordinates (bottom-left origin).
    private static func cgRectToAppKit(_ cgRect: CGRect) -> CGRect {
        guard let mainScreenHeight = NSScreen.main?.frame.height else { return cgRect }
        return CGRect(
            x: cgRect.origin.x,
            y: mainScreenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// Estimates selection bounds from mouse down + up positions when AX bounds are unavailable.
    /// Uses the bounding box of the two cursor positions to approximate the selection rect.
    private func estimatedSelectionBounds(mouseUp: CGPoint, mouseDown: CGPoint?) -> CGRect {
        guard let down = mouseDown else {
            // No mouseDown info — small rect just above the cursor
            return CGRect(x: mouseUp.x - 20, y: mouseUp.y - 4, width: 40, height: 20)
        }
        // Build a rect spanning both endpoints (works for single-line and multi-line selections)
        let minX = min(down.x, mouseUp.x) - 4
        let maxX = max(down.x, mouseUp.x) + 4
        let minY = min(down.y, mouseUp.y)
        let maxY = max(down.y, mouseUp.y)
        let height = max(maxY - minY, 16)  // At least 16pt so single-line selections have real height
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 40), height: height)
    }

    /// Used by polling path (no mouse position context).
    private func mouseLocationBounds() -> CGRect {
        let pos = NSEvent.mouseLocation
        return CGRect(x: pos.x - 20, y: pos.y - 4, width: 40, height: 20)
    }

    // MARK: - Teardown

    func teardown() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard let observer else { return }

        AXObserverRemoveNotification(
            observer,
            appElement,
            kAXSelectedTextChangedNotification as CFString
        )

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        self.observer = nil
        AppLogger.accessibility.debug("Observer torn down for PID \(self.pid)")
    }

    deinit {
        teardown()
    }
}
