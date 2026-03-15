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
        popupPanel.contentView = contentView
    }

    private func setupClickMonitors() {
        // Dismiss when clicking outside the popup
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }

        // Dismiss on Escape key
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
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

    // MARK: - Action Handling

    private func handleAction(_ action: any Action) {
        guard let info = currentSelectionInfo else { return }

        let service = LLMServiceFactory.create()

        currentStreamTask = Task {
            let result = await action.execute(selectedText: info.text, llmService: service)

            await MainActor.run {
                switch result {
                case .stream(let stream):
                    streamResponse(stream)
                case .completed:
                    // Brief flash, then dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.dismiss()
                    }
                case .openURL(let url):
                    NSWorkspace.shared.open(url)
                    dismiss()
                }
            }
        }
    }

    private func streamResponse(_ stream: AsyncThrowingStream<String, Error>) {
        // Expand the popup to show the response area
        contentView.showResponseArea()
        resizeForResponse(animated: false)

        currentStreamTask = Task {
            do {
                for try await token in stream {
                    await MainActor.run {
                        contentView.appendResponseToken(token)
                        if contentView.updateResponseHeight() {
                            resizeForResponse(animated: true)
                        }
                    }
                }
                await MainActor.run {
                    contentView.finishResponse()
                    resizeForResponse(animated: true)
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        contentView.showError(error.localizedDescription)
                    }
                }
            }
        }
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

        frame.origin.y -= heightDelta  // Grow downward (adjust origin since AppKit is bottom-left)
        frame.size = newSize

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                popupPanel.animator().setFrame(frame, display: true)
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
