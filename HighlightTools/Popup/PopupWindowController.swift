import Cocoa

/// Controls the floating popup panel that appears near text selections.
///
/// The panel is a borderless, non-activating NSPanel that floats above all windows.
/// It does NOT steal focus from the app where the user selected text.
class PopupWindowController: NSWindowController {

    private let popupPanel: PopupPanel
    private var contentView: PopupContentView!
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var currentSelectionInfo: SelectionInfo?
    private var currentStreamTask: Task<Void, Never>?
    private var pendingResizeWork: DispatchWorkItem?

    // For history & pin support
    private var currentActionName: String?
    private var currentResponseAccumulator: String = ""
    /// All detached (pinned) response windows — kept alive so they don't deallocate.
    private var detachedWindows: [DetachedResponseWindowController] = []

    init() {
        let panel = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.popupPanel = panel
        super.init(window: panel)

        setupPanel()
        setupContentView()
        setupClickMonitors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        popupPanel.level = .popUpMenu
        popupPanel.isOpaque = false
        popupPanel.backgroundColor = .clear
        popupPanel.hasShadow = true
        popupPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popupPanel.hidesOnDeactivate = false
        popupPanel.isMovableByWindowBackground = false
        popupPanel.animationBehavior = .utilityWindow
    }

    private func setupContentView() {
        contentView = PopupContentView(frame: popupPanel.contentView!.bounds)
        contentView.onActionSelected = { [weak self] action in
            self?.handleAction(action)
        }
        contentView.onStopStreaming = { [weak self] in
            self?.currentStreamTask?.cancel()
            self?.currentStreamTask = nil
            self?.saveHistoryIfNeeded()
            self?.contentView.finishResponse()
            self?.contentView.clearActiveButton()
            self?.resizeForResponse(animated: true)
        }
        contentView.onPinResponse = { [weak self] in
            self?.pinCurrentResponse()
        }
        popupPanel.contentView = contentView
    }

    private func setupClickMonitors() {
        // Dismiss when clicking outside the popup (ignore clicks inside the popup frame)
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            guard !self.popupPanel.frame.contains(NSEvent.mouseLocation) else { return }
            self.dismiss()
        }

        // Keyboard shortcuts (only when popup is visible, non-activating panel so local monitor works)
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popupPanel.isVisible else { return event }

            let key = event.keyCode
            let char = event.charactersIgnoringModifiers?.lowercased()

            // Escape: back to buttons if response showing, else dismiss
            if key == 53 {
                if self.contentView.isShowingResponse {
                    self.contentView.hideResponseArea()
                    self.pendingResizeWork?.cancel()
                    self.resizeForResponse(animated: true)
                } else {
                    self.dismiss()
                }
                return nil
            }

            // "C" — copy response when response is visible
            if char == "c", self.contentView.isShowingResponse, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.contentView.copyCurrentResponse()
                return nil
            }

            // "P" — pin/detach response when response is done
            if char == "p", self.contentView.isShowingResponse, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.pinCurrentResponse()
                return nil
            }

            // 1-9 — trigger nth action (when no response is showing)
            if !self.contentView.isShowingResponse,
               let num = Int(char ?? ""), num >= 1 && num <= 9,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.contentView.triggerAction(at: num - 1)
                return nil
            }

            return event
        }
    }

    // MARK: - Show / Dismiss

    func show(for info: SelectionInfo) {
        currentSelectionInfo = info

        // Cancel any in-flight LLM stream
        currentStreamTask?.cancel()
        currentStreamTask = nil

        // Update content and resize
        contentView.configure(with: info)
        let idealSize = contentView.fittingSize
        let panelSize = NSSize(width: max(idealSize.width, 100), height: max(idealSize.height, 32))

        // Position the popup near the selection
        let origin = PopupPositioning.position(popupSize: panelSize, selectionBounds: info.bounds)
        popupPanel.setFrame(NSRect(origin: origin, size: panelSize), display: true)

        // Fade in
        if !popupPanel.isVisible {
            popupPanel.alphaValue = 0
            popupPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                popupPanel.animator().alphaValue = 1.0
            }
        } else {
            // Already visible — just reposition (no flicker)
            popupPanel.alphaValue = 1.0
        }
    }

    func dismiss() {
        guard popupPanel.isVisible else { return }

        currentStreamTask?.cancel()
        currentStreamTask = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            popupPanel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.popupPanel.orderOut(nil)
            self?.contentView.reset()
        })
    }

    // MARK: - History & Pin

    private func saveHistoryIfNeeded() {
        guard let actionName = currentActionName,
              !currentResponseAccumulator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selectedText = currentSelectionInfo?.text else { return }
        ResponseHistoryManager.shared.add(
            actionName: actionName,
            selectedText: selectedText,
            response: currentResponseAccumulator
        )
        currentResponseAccumulator = ""
    }

    private func pinCurrentResponse() {
        guard let actionName = currentActionName,
              !currentResponseAccumulator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selectedText = currentSelectionInfo?.text else { return }
        let detached = DetachedResponseWindowController(
            actionName: actionName,
            selectedText: selectedText,
            response: currentResponseAccumulator
        )
        detachedWindows.append(detached)
        detached.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Action Handling

    private func handleAction(_ action: any Action) {
        guard let info = currentSelectionInfo else { return }

        currentActionName = action.name
        currentResponseAccumulator = ""

        contentView.setActiveButton(action)
        let service = LLMServiceFactory.create()

        currentStreamTask = Task {
            let result = await action.execute(selectedText: info.text, llmService: service)

            await MainActor.run {
                switch result {
                case .stream(let stream):
                    streamResponse(stream)
                case .completed:
                    self.contentView.clearActiveButton()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.dismiss()
                    }
                case .openURL(let url):
                    self.contentView.clearActiveButton()
                    NSWorkspace.shared.open(url)
                    dismiss()
                }
            }
        }
    }

    private func streamResponse(_ stream: AsyncThrowingStream<String, Error>) {
        contentView.showResponseArea()
        resizeForResponse(animated: false)

        currentStreamTask = Task {
            do {
                for try await token in stream {
                    await MainActor.run {
                        self.currentResponseAccumulator += token
                        self.contentView.appendResponseToken(token)
                        if self.contentView.updateResponseHeight() {
                            self.scheduleResize()
                        }
                    }
                }
                await MainActor.run {
                    self.pendingResizeWork?.cancel()
                    self.saveHistoryIfNeeded()
                    self.contentView.finishResponse()
                    self.contentView.clearActiveButton()
                    self.resizeForResponse(animated: true)
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.contentView.showError(error.localizedDescription)
                        self.contentView.clearActiveButton()
                    }
                }
            }
        }
    }

    /// Coalesces rapid per-token resize calls into one smooth animation every ~60ms.
    private func scheduleResize() {
        guard pendingResizeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingResizeWork = nil
            self?.resizeForResponse(animated: true)
        }
        pendingResizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func resizeForResponse(animated: Bool) {
        let idealSize = contentView.fittingSize
        let maxHeight: CGFloat = 400
        let newSize = NSSize(
            width: max(idealSize.width, 280),
            height: min(max(idealSize.height, 80), maxHeight)
        )

        var frame = popupPanel.frame
        let heightDelta = newSize.height - frame.height
        guard abs(heightDelta) > 1 else { return }

        frame.origin.y -= heightDelta
        frame.size = newSize

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                self.popupPanel.animator().setFrame(frame, display: true)
            }
        } else {
            popupPanel.setFrame(frame, display: true)
        }
    }

    deinit {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - PopupPanel

/// Custom NSPanel subclass that refuses to become key window,
/// preventing it from stealing focus from the source application.
private class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
