import Cocoa

/// The content view of the popup panel.
/// Uses Liquid Glass (NSGlassEffectView on macOS 26+) with fallback to NSVisualEffectView.
/// Shows action buttons as monochrome SF Symbol icons, and expands to show LLM responses.
class PopupContentView: NSView {

    var onActionSelected: ((any Action) -> Void)?
    var onStopStreaming: (() -> Void)?
    var onPinResponse: (() -> Void)?

    /// Ordered list of actions shown in the popup (mirrors buttonStack order).
    private var orderedActions: [any Action] = []

    private var buttonStack: NSStackView!
    private var responseScrollView: NSScrollView?
    private var responseTextView: NSTextView?
    private var responseContainer: NSView?
    private var copyResponseButton: NSView?
    private var mainStack: NSStackView!
    private var glassBackground: NSView!
    private var responseHeightConstraint: NSLayoutConstraint?
    private(set) var hasReachedMaxHeight = false
    private let maxResponseHeight: CGFloat = 300
    private var actionButtons: [String: ActionButton] = [:]  // keyed by action name
    private var wordCountLabel: NSTextField?
    private var stopButton: NSView?

    var isShowingResponse: Bool { responseContainer != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // Set up the glass background
        glassBackground = Self.makeGlassBackground(frame: bounds)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)

        // Button row — icon-only, tight spacing
        buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 0
        buttonStack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)

        // Main vertical stack (buttons on top, response below)
        mainStack = NSStackView(views: [buttonStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Liquid Glass / Vibrancy Background

    /// Creates an NSGlassEffectView (macOS 26+) or falls back to NSVisualEffectView.
    private static func makeGlassBackground(frame: NSRect) -> NSView {
        // Try to use NSGlassEffectView (Liquid Glass, macOS 26+)
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glassView = glassClass.init(frame: frame)
            glassView.wantsLayer = true
            glassView.layer?.cornerRadius = 14
            glassView.layer?.masksToBounds = true
            return glassView
        }

        // Fallback: NSVisualEffectView with popover material
        let effectView = NSVisualEffectView(frame: frame)
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        return effectView
    }

    // MARK: - Configure with selection

    func configure(with info: SelectionInfo) {
        buttonStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll()

        let actions = ActionRegistry.shared.actions
        orderedActions = actions
        for action in actions {
            let button = ActionButton(action: action) { [weak self] action in
                self?.onActionSelected?(action)
            }
            buttonStack.addArrangedSubview(button)
            actionButtons[action.name] = button
        }

        // Word / character count badge
        let words = info.text.split(whereSeparator: \.isWhitespace).count
        let chars = info.text.count
        let countText = words == 1 ? "1 word" : "\(words) words · \(chars) chars"
        if let existing = wordCountLabel {
            existing.stringValue = countText
        } else {
            let label = NSTextField(labelWithString: countText)
            label.font = .systemFont(ofSize: 10, weight: .regular)
            label.textColor = .tertiaryLabelColor
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
            buttonStack.addArrangedSubview(label)
            wordCountLabel = label
        }
    }

    // MARK: - Loading State

    func setActiveButton(_ action: any Action) {
        for (name, button) in actionButtons {
            button.setActive(name == action.name)
        }
    }

    func clearActiveButton() {
        actionButtons.values.forEach { $0.setActive(false) }
    }

    // MARK: - Response Area

    func showResponseArea() {
        guard responseContainer == nil else { return }

        // Thin separator
        let separator = NSBox()
        separator.boxType = .separator

        // Scroll view with text view for the response
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor

        scrollView.documentView = textView

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(separator)
        container.addSubview(scrollView)

        let heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 40)
        self.responseHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            heightConstraint,
        ])

        mainStack.addArrangedSubview(container)

        self.responseScrollView = scrollView
        self.responseTextView = textView
        self.responseContainer = container

        // Stop button — appears while streaming, dismissed in finishResponse()
        let stop = StopStreamingButton { [weak self] in
            self?.onStopStreaming?()
        }
        stop.translatesAutoresizingMaskIntoConstraints = false
        let stopWrapper = NSStackView(views: [NSView(), stop])
        stopWrapper.orientation = .horizontal
        stopWrapper.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 4, right: 8)
        mainStack.addArrangedSubview(stopWrapper)
        self.stopButton = stopWrapper
    }

    func appendResponseToken(_ token: String) {
        guard let textView = responseTextView else { return }
        let storage = textView.textStorage!
        storage.beginEditing()
        storage.append(NSAttributedString(string: token, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]))
        storage.endEditing()
        textView.scrollToEndOfDocument(nil)
    }

    /// Updates the response area height constraint based on actual text content.
    /// Returns `true` if the height changed (caller should resize the panel).
    @discardableResult
    func updateResponseHeight() -> Bool {
        guard !hasReachedMaxHeight else { return false }
        guard let textView = responseTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return false }

        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height
        let contentHeight = textHeight + textView.textContainerInset.height * 2 + 4

        let newHeight = min(max(contentHeight, 40), maxResponseHeight)
        let oldHeight = responseHeightConstraint?.constant ?? 40

        if abs(newHeight - oldHeight) < 2 { return false }

        responseHeightConstraint?.constant = newHeight

        if newHeight >= maxResponseHeight {
            hasReachedMaxHeight = true
        }

        return true
    }

    func finishResponse() {
        // Remove stop button, replace with copy + pin buttons
        stopButton?.removeFromSuperview()
        stopButton = nil

        guard copyResponseButton == nil else { return }

        let copyBtn = CopyResponseButton { [weak self] in
            self?.copyCurrentResponse()
        }
        copyBtn.translatesAutoresizingMaskIntoConstraints = false

        let pinBtn = PinResponseButton { [weak self] in
            self?.onPinResponse?()
        }
        pinBtn.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSStackView(views: [NSView(), copyBtn, pinBtn])
        wrapper.orientation = .horizontal
        wrapper.spacing = 6
        wrapper.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 4, right: 8)

        mainStack.addArrangedSubview(wrapper)
        copyResponseButton = wrapper
    }

    /// Copy response text to clipboard (also triggered by keyboard shortcut "C").
    func copyCurrentResponse() {
        guard let text = responseTextView?.string, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Trigger the action at position `index` in the displayed button list.
    /// Used for keyboard shortcuts 1–9.
    func triggerAction(at index: Int) {
        guard index < orderedActions.count else { return }
        onActionSelected?(orderedActions[index])
    }

    func showError(_ message: String) {
        guard let textView = responseTextView else { return }
        let storage = textView.textStorage!
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: "Error: \(message)", attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.systemRed,
        ]))
        storage.endEditing()
    }

    /// Hides just the response area, leaving action buttons visible.
    /// Called when user presses Esc while a response is shown.
    func hideResponseArea() {
        stopButton?.removeFromSuperview()
        stopButton = nil
        responseContainer?.removeFromSuperview()
        responseContainer = nil
        responseScrollView = nil
        responseTextView = nil
        responseHeightConstraint = nil
        hasReachedMaxHeight = false
        copyResponseButton?.removeFromSuperview()
        copyResponseButton = nil
        clearActiveButton()
    }

    func reset() {
        hideResponseArea()
        actionButtons.removeAll()
        orderedActions = []
        wordCountLabel = nil
    }

    // MARK: - Sizing

    override var fittingSize: NSSize {
        mainStack.fittingSize
    }
}

// MARK: - ActionButton

/// A compact, icon-based button for an action in the popup.
/// Uses SF Symbols for a monochrome, native look.
/// Handles mouse events directly (since the panel can't become key).
private class ActionButton: NSView {

    private let action: any Action
    private let onClick: (any Action) -> Void
    private var isHovered = false
    private var isPressed = false
    private var isActive = false
    private var trackingArea: NSTrackingArea?
    private var pulseTimer: Timer?

    private let iconView: NSImageView

    init(action: any Action, onClick: @escaping (any Action) -> Void) {
        self.action = action
        self.onClick = onClick
        self.iconView = NSImageView()
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 7
        toolTip = action.name

        // SF Symbol icon — monochrome, medium weight
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let image = NSImage(systemSymbolName: action.icon, accessibilityDescription: action.name) {
            iconView.image = image.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 26),
        ])

        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        updateAppearance()
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick(action)
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            iconView.contentTintColor = .controlAccentColor
            // Pulse: alternate opacity between 1.0 and 0.4
            pulseTimer?.invalidate()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
                guard let self else { return }
                let current = self.iconView.alphaValue
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.45
                    self.iconView.animator().alphaValue = current > 0.7 ? 0.35 : 1.0
                }
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            iconView.alphaValue = 1.0
            updateAppearance()
        }
    }

    private func updateAppearance() {
        guard !isActive else { return }
        if isPressed {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            iconView.contentTintColor = .controlAccentColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            iconView.contentTintColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = .labelColor
        }
    }
}

// MARK: - StopStreamingButton

/// Small "Stop" button shown while an LLM response is streaming.
private class StopStreamingButton: NSView {

    private let onClick: () -> Void
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "Stop")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stop")?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        label.textColor = .systemRed
        iconView.contentTintColor = .systemRed
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
        label.textColor = .secondaryLabelColor
        iconView.contentTintColor = .secondaryLabelColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick()
    }
}

// MARK: - PinResponseButton

/// Small "Pin" button to detach the response into a persistent floating window.
private class PinResponseButton: NSView {

    private let onClick: () -> Void
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "Pin")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = "Pin response (P)"

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")?.withSymbolConfiguration(config)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = isHovered ? NSColor.labelColor.withAlphaComponent(0.06).cgColor : NSColor.clear.cgColor
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick()
    }
}

// MARK: - CopyResponseButton

/// Small "Copy" button shown after an LLM response finishes.
/// Shows a checkmark for 1 second after copying.
private class CopyResponseButton: NSView {

    private let onClick: () -> Void
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "Copy")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")?.withSymbolConfiguration(config)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = isHovered ? NSColor.labelColor.withAlphaComponent(0.06).cgColor : NSColor.clear.cgColor
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }

        onClick()

        // Show "Copied!" feedback for 1 second
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")?.withSymbolConfiguration(config)
        iconView.contentTintColor = .systemGreen
        label.stringValue = "Copied!"
        label.textColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.iconView.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")?.withSymbolConfiguration(config)
            self?.iconView.contentTintColor = .secondaryLabelColor
            self?.label.stringValue = "Copy"
            self?.label.textColor = .secondaryLabelColor
        }
    }
}
