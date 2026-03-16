import Cocoa

/// A floating panel that shows a curated grid of SF Symbols for picking an action icon.
/// Opens anchored below the icon cell in the actions table.
class IconPickerPanel: NSPanel {

    var onIconSelected: ((String) -> Void)?

    private var searchField: NSSearchField!
    private var collectionContainer: NSScrollView!
    private var iconGrid: NSStackView!
    private var allIcons: [(category: String, names: [String])] = []
    private var filteredIcons: [String] = []

    static let shared = IconPickerPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces]
        setupContent()
        setupIcons()
    }

    // MARK: - Setup

    private func setupContent() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        // Glass background
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = "Search symbols…"
        searchField.font = .systemFont(ofSize: 12)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        (searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true

        // Scrollable icon grid
        collectionContainer = NSScrollView()
        collectionContainer.hasVerticalScroller = true
        collectionContainer.autohidesScrollers = true
        collectionContainer.scrollerStyle = .overlay
        collectionContainer.drawsBackground = false
        collectionContainer.borderType = .noBorder
        collectionContainer.translatesAutoresizingMaskIntoConstraints = false

        iconGrid = NSStackView()
        iconGrid.orientation = .vertical
        iconGrid.alignment = .leading
        iconGrid.spacing = 2
        iconGrid.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        iconGrid.translatesAutoresizingMaskIntoConstraints = false

        let clipView = collectionContainer.contentView
        collectionContainer.documentView = iconGrid

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(effect)
        container.addSubview(searchField)
        container.addSubview(separator)
        container.addSubview(collectionContainer)
        container.translatesAutoresizingMaskIntoConstraints = false

        contentView = container

        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            collectionContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            collectionContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            collectionContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            collectionContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        // Dismiss on click outside
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                self.close()
            }
        }
    }

    private func setupIcons() {
        allIcons = [
            ("Text & Writing", [
                "text.alignleft", "text.aligncenter", "text.alignright", "text.justify",
                "doc.text", "doc.plaintext", "note.text", "square.and.pencil",
                "pencil", "pencil.line", "pencil.and.outline", "pencil.tip",
                "textformat", "textformat.abc", "textformat.size", "bold",
                "italic", "underline", "strikethrough", "quote.bubble",
                "quote.opening", "character.cursor.ibeam", "text.badge.star",
            ]),
            ("Language & Translation", [
                "globe", "globe.americas", "globe.europe.africa", "globe.asia.australia",
                "character", "character.bubble", "a.magnify",
                "translate", "person.2.wave.2",
            ]),
            ("AI & Intelligence", [
                "brain", "brain.head.profile", "cpu", "memorychip",
                "wand.and.stars", "wand.and.sparkles", "sparkles", "sparkle",
                "bolt", "bolt.fill", "bolt.circle", "star",
                "lightbulb", "lightbulb.fill", "lightbulb.circle",
            ]),
            ("Actions & Tools", [
                "wrench.and.screwdriver", "hammer", "scissors", "paintbrush",
                "magnifyingglass", "magnifyingglass.circle", "eye", "eye.circle",
                "arrow.triangle.2.circlepath", "arrow.clockwise", "arrow.counterclockwise",
                "checkmark", "checkmark.circle", "xmark", "xmark.circle",
                "plus", "minus", "equal", "multiply",
            ]),
            ("Documents & Clipboard", [
                "doc", "doc.fill", "doc.on.doc", "doc.on.clipboard",
                "clipboard", "tray", "tray.fill", "folder",
                "square.and.arrow.up", "square.and.arrow.down",
                "arrow.up.doc", "arrow.down.doc",
                "list.bullet", "list.number", "checklist",
            ]),
            ("Communication", [
                "bubble.left", "bubble.right", "bubble.left.and.bubble.right",
                "message", "message.circle", "envelope", "envelope.open",
                "megaphone", "speaker.wave.2", "mic",
                "phone", "video", "hand.raised",
            ]),
            ("Objects & Symbols", [
                "heart", "heart.fill", "star.fill", "bookmark", "tag",
                "bell", "flag", "mappin", "location",
                "camera", "photo", "music.note",
                "clock", "timer", "calendar",
                "lock", "key", "shield",
            ]),
        ]
        showAllIcons()
    }

    // MARK: - Grid Rendering

    private func showAllIcons() {
        iconGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for section in allIcons {
            let header = NSTextField(labelWithString: section.category.uppercased())
            header.font = .systemFont(ofSize: 9, weight: .semibold)
            header.textColor = .tertiaryLabelColor
            header.translatesAutoresizingMaskIntoConstraints = false
            iconGrid.addArrangedSubview(header)

            let row = makeIconRow(names: section.names)
            iconGrid.addArrangedSubview(row)
        }

        layoutIconGrid()
    }

    private func showFilteredIcons(_ names: [String]) {
        iconGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if names.isEmpty {
            let label = NSTextField(labelWithString: "No results")
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 12)
            label.translatesAutoresizingMaskIntoConstraints = false
            iconGrid.addArrangedSubview(label)
        } else {
            let row = makeIconRow(names: names)
            iconGrid.addArrangedSubview(row)
        }
        layoutIconGrid()
    }

    private func makeIconRow(names: [String]) -> NSView {
        // Wrap icons into rows of ~9 per line
        let iconsPerRow = 9
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 1

        var rowStack: NSStackView?
        for (i, name) in names.enumerated() {
            if i % iconsPerRow == 0 {
                let stack = NSStackView()
                stack.orientation = .horizontal
                stack.spacing = 1
                container.addArrangedSubview(stack)
                rowStack = stack
            }
            let btn = IconCell(symbolName: name) { [weak self] selected in
                self?.onIconSelected?(selected)
                self?.close()
            }
            rowStack?.addArrangedSubview(btn)
        }
        return container
    }

    private func layoutIconGrid() {
        iconGrid.layoutSubtreeIfNeeded()
        // Expand the icon grid's width to match the scroll view
        if let sv = collectionContainer {
            iconGrid.frame = CGRect(x: 0, y: 0, width: sv.frame.width - 12, height: iconGrid.fittingSize.height)
        }
    }

    @objc private func searchChanged() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            showAllIcons()
        } else {
            let allNames = allIcons.flatMap(\.names)
            filteredIcons = allNames.filter { $0.contains(query) }
            showFilteredIcons(filteredIcons)
        }
    }

    // MARK: - Show

    func show(near rect: NSRect, in view: NSView, onSelect: @escaping (String) -> Void) {
        onIconSelected = onSelect
        searchField.stringValue = ""
        showAllIcons()

        guard let screen = view.window?.screen ?? NSScreen.main else { return }

        // Convert rect to screen coordinates
        let screenRect = view.convert(rect, to: nil)
        let windowRect = view.window?.convertToScreen(screenRect) ?? screenRect

        var origin = CGPoint(x: windowRect.minX, y: windowRect.minY - frame.height - 4)

        // Clamp to screen
        if origin.y < screen.visibleFrame.minY {
            origin.y = windowRect.maxY + 4
        }
        if origin.x + frame.width > screen.visibleFrame.maxX {
            origin.x = screen.visibleFrame.maxX - frame.width - 4
        }

        setFrameOrigin(origin)
        orderFrontRegardless()
    }
}

// MARK: - IconCell

private class IconCell: NSView {

    private let symbolName: String
    private let onSelect: (String) -> Void
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(symbolName: String, onSelect: @escaping (String) -> Void) {
        self.symbolName = symbolName
        self.onSelect = onSelect
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        toolTip = symbolName

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let imageView = NSImageView()
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName) {
            imageView.image = img.withSymbolConfiguration(config)
        }
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 28),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onSelect(symbolName)
    }
}
