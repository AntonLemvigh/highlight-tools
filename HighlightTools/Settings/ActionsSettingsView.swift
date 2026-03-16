import Cocoa

/// Unified row model for both built-in and custom actions.
private struct ActionRow {
    let id: String
    var name: String
    var icon: String
    var isEnabled: Bool
    var isCustom: Bool
    var promptTemplate: String  // Only meaningful for custom actions
}

/// Actions settings tab: unified table for all actions with reordering and icon editing.
class ActionsSettingsView: NSView {

    private var tableView: NSTableView!
    private var rows: [ActionRow] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let headerLabel = NSTextField(labelWithString: "Actions")
        headerLabel.font = .boldSystemFont(ofSize: 13)

        let hintLabel = NSTextField(labelWithString: "Drag to reorder. Double-click icon or name to edit.")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor

        // Table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 4, height: 2)
        tableView.registerForDraggedTypes([.string])
        tableView.draggingDestinationFeedbackStyle = .gap

        let enabledCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledCol.width = 24
        enabledCol.minWidth = 24
        enabledCol.maxWidth = 24
        tableView.addTableColumn(enabledCol)

        let iconCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("icon"))
        iconCol.title = "Icon"
        iconCol.width = 50
        iconCol.minWidth = 40
        tableView.addTableColumn(iconCol)

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"
        nameCol.width = 120
        tableView.addTableColumn(nameCol)

        let promptCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("prompt"))
        promptCol.title = "Prompt"
        promptCol.width = 220
        tableView.addTableColumn(promptCol)

        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        // Buttons
        let addButton = NSButton(title: "+", target: self, action: #selector(addCustomAction))
        addButton.bezelStyle = .smallSquare
        let removeButton = NSButton(title: "−", target: self, action: #selector(removeSelectedAction))
        removeButton.bezelStyle = .smallSquare
        let moveActionUpButton = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Move Up")!, target: self, action: #selector(moveActionUp))
        moveActionUpButton.bezelStyle = .smallSquare
        let moveActionDownButton = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Move Down")!, target: self, action: #selector(moveActionDown))
        moveActionDownButton.bezelStyle = .smallSquare

        let buttonRow = NSStackView(views: [addButton, removeButton, NSView(), moveActionUpButton, moveActionDownButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 4

        // Layout
        let stack = NSStackView(views: [headerLabel, hintLabel, scrollView, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttonRow.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        loadRows()
    }

    // MARK: - Data Loading

    private func loadRows() {
        rows = []
        let settings = SettingsManager.shared
        let iconOverrides = settings.actionIconOverrides

        // Built-in non-LLM actions
        let builtInNonLLM: [(id: String, name: String, icon: String)] = [
            ("copy", "Copy", "doc.on.doc"),
            ("search", "Search", "magnifyingglass"),
        ]
        for action in builtInNonLLM {
            rows.append(ActionRow(
                id: action.id,
                name: action.name,
                icon: iconOverrides[action.id] ?? action.icon,
                isEnabled: settings.showNonLLMActions,
                isCustom: false,
                promptTemplate: ""
            ))
        }

        // Default LLM actions
        for action in DefaultPrompts.all {
            rows.append(ActionRow(
                id: action.id,
                name: action.name,
                icon: iconOverrides[action.id] ?? action.icon,
                isEnabled: settings.isActionEnabled(action.id),
                isCustom: false,
                promptTemplate: action.promptTemplate
            ))
        }

        // Custom actions
        for config in settings.customActions {
            rows.append(ActionRow(
                id: config.id,
                name: config.name,
                icon: config.icon,
                isEnabled: true,
                isCustom: true,
                promptTemplate: config.promptTemplate
            ))
        }

        // Apply saved ordering
        let order = settings.actionOrder
        if !order.isEmpty {
            let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            rows.sort { a, b in
                let ai = orderMap[a.id] ?? Int.max
                let bi = orderMap[b.id] ?? Int.max
                return ai < bi
            }
        }

        tableView?.reloadData()
    }

    // MARK: - Persist

    private func saveState() {
        let settings = SettingsManager.shared

        // Save order
        settings.actionOrder = rows.map(\.id)

        // Save enabled states
        let nonLLMIDs = Set(["copy", "search"])
        let defaultLLMIDs = Set(DefaultPrompts.all.map(\.id))

        // Non-LLM: all share one toggle
        let anyNonLLMEnabled = rows.filter { nonLLMIDs.contains($0.id) }.contains { $0.isEnabled }
        settings.showNonLLMActions = anyNonLLMEnabled

        // Default LLM actions
        settings.enabledDefaultActions = rows.filter { defaultLLMIDs.contains($0.id) && $0.isEnabled }.map(\.id)

        // Icon overrides for built-in actions
        var iconOverrides: [String: String] = [:]
        let builtInDefaults: [String: String] = [
            "copy": "doc.on.doc", "search": "magnifyingglass",
            "explain": "lightbulb", "translate": "globe",
            "summarize": "text.alignleft", "fixgrammar": "pencil.line",
        ]
        for row in rows where !row.isCustom {
            if let defaultIcon = builtInDefaults[row.id], row.icon != defaultIcon {
                iconOverrides[row.id] = row.icon
            }
        }
        settings.actionIconOverrides = iconOverrides

        // Custom actions: rebuild from rows
        settings.customActions = rows.filter(\.isCustom).map {
            CustomActionConfig(id: $0.id, name: $0.name, icon: $0.icon, promptTemplate: $0.promptTemplate)
        }
    }

    // MARK: - Actions

    @objc private func addCustomAction() {
        let newAction = ActionRow(
            id: UUID().uuidString,
            name: "New Action",
            icon: "bolt",
            isEnabled: true,
            isCustom: true,
            promptTemplate: "{{selection}}"
        )
        rows.append(newAction)
        saveState()
        tableView.reloadData()
        // Select and scroll to new row
        let newIndex = rows.count - 1
        tableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(newIndex)
    }

    @objc private func removeSelectedAction() {
        let selected = tableView.selectedRow
        guard selected >= 0, rows[selected].isCustom else { return }
        rows.remove(at: selected)
        saveState()
        tableView.reloadData()
    }

    @objc private func moveActionUp() {
        let selected = tableView.selectedRow
        guard selected > 0 else { return }
        rows.swapAt(selected, selected - 1)
        saveState()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: selected - 1), byExtendingSelection: false)
    }

    @objc private func moveActionDown() {
        let selected = tableView.selectedRow
        guard selected >= 0, selected < rows.count - 1 else { return }
        rows.swapAt(selected, selected + 1)
        saveState()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: selected + 1), byExtendingSelection: false)
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension ActionsSettingsView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let actionRow = rows[row]
        let colID = tableColumn?.identifier.rawValue ?? ""

        switch colID {
        case "enabled":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(enabledToggled(_:)))
            checkbox.state = actionRow.isEnabled ? .on : .off
            checkbox.tag = row
            return checkbox

        case "icon":
            let btn = IconPreviewButton(symbolName: actionRow.icon, row: row) { [weak self] rowIndex, sourceRect, sourceView in
                guard let self else { return }
                IconPickerPanel.shared.show(near: sourceRect, in: sourceView) { [weak self] newIcon in
                    guard let self, rowIndex < self.rows.count else { return }
                    self.rows[rowIndex].icon = newIcon
                    self.saveState()
                    self.tableView.reloadData(forRowIndexes: IndexSet(integer: rowIndex),
                                              columnIndexes: IndexSet(integer: 1))
                }
            }
            return btn

        case "name":
            let field = NSTextField()
            field.stringValue = actionRow.name
            field.isEditable = actionRow.isCustom
            field.isBordered = false
            field.drawsBackground = false
            field.font = .systemFont(ofSize: 12)
            field.delegate = self
            field.tag = row * 10 + 2
            if !actionRow.isCustom {
                field.textColor = .labelColor
            }
            return field

        case "prompt":
            let field = NSTextField()
            field.stringValue = actionRow.promptTemplate
            field.isEditable = actionRow.isCustom
            field.isBordered = false
            field.drawsBackground = false
            field.font = .systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
            field.tag = row * 10 + 3
            return field

        default:
            return nil
        }
    }

    @objc private func enabledToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row < rows.count else { return }
        rows[row].isEnabled = (sender.state == .on)
        saveState()
    }

    // MARK: - Drag & Drop Reordering

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        NSString(string: "\(row)")
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let str = info.draggingPasteboard.string(forType: .string),
              let sourceRow = Int(str) else { return false }

        let item = rows.remove(at: sourceRow)
        let destRow = sourceRow < row ? row - 1 : row
        rows.insert(item, at: destRow)

        saveState()
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: destRow), byExtendingSelection: false)
        return true
    }
}

// MARK: - IconPreviewButton

/// A clickable SF Symbol preview that opens the icon picker panel when clicked.
private class IconPreviewButton: NSView {

    private let row: Int
    private let onTap: (Int, NSRect, NSView) -> Void
    private var imageView: NSImageView!
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(symbolName: String, row: Int, onTap: @escaping (Int, NSRect, NSView) -> Void) {
        self.row = row
        self.onTap = onTap
        super.init(frame: .zero)
        setup(symbolName: symbolName)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(symbolName: String) {
        wantsLayer = true
        layer?.cornerRadius = 5
        toolTip = "Click to change icon"

        imageView = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName)?
            .withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: "unknown")?
                .withSymbolConfiguration(config)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 24),
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
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onTap(row, bounds, self)
    }
}

// MARK: - NSTextFieldDelegate (inline editing)

extension ActionsSettingsView: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = field.tag / 10
        let column = field.tag % 10
        guard row < rows.count else { return }

        switch column {
        case 1: // icon
            rows[row].icon = field.stringValue.trimmingCharacters(in: .whitespaces)
        case 2: // name
            rows[row].name = field.stringValue
        case 3: // prompt
            rows[row].promptTemplate = field.stringValue
        default:
            break
        }

        saveState()
    }
}
