import Cocoa

/// Floating window showing the last N LLM responses.
/// Layout: left side = list of items, right side = detail with full response.
class HistoryWindowController: NSWindowController {

    private var splitView: NSSplitView!
    private var tableView: NSTableView!
    private var detailTextView: NSTextView!
    private var detailActionLabel: NSTextField!
    private var detailSnippetLabel: NSTextField!
    private var detailDateLabel: NSTextField!
    private var clearButton: NSButton!
    private var copyDetailButton: NSButton!
    private var historyObserver: NSObjectProtocol?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Response History"
        window.minSize = NSSize(width: 500, height: 320)
        window.center()
        self.init(window: window)
        setupContent()
        subscribeToUpdates()
    }

    deinit {
        if let obs = historyObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Setup

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        // ---- Left: table ----
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.width = 240
        tableView.addTableColumn(col)

        scrollView.documentView = tableView

        // ---- Right: detail ----
        let detailContainer = NSView()

        detailActionLabel = NSTextField(labelWithString: "")
        detailActionLabel.font = .boldSystemFont(ofSize: 13)
        detailActionLabel.translatesAutoresizingMaskIntoConstraints = false

        detailSnippetLabel = NSTextField(labelWithString: "")
        detailSnippetLabel.font = .systemFont(ofSize: 11)
        detailSnippetLabel.textColor = .secondaryLabelColor
        detailSnippetLabel.lineBreakMode = .byTruncatingTail
        detailSnippetLabel.translatesAutoresizingMaskIntoConstraints = false

        detailDateLabel = NSTextField(labelWithString: "")
        detailDateLabel.font = .systemFont(ofSize: 10)
        detailDateLabel.textColor = .tertiaryLabelColor
        detailDateLabel.translatesAutoresizingMaskIntoConstraints = false

        let responseScroll = NSScrollView()
        responseScroll.hasVerticalScroller = true
        responseScroll.autohidesScrollers = true
        responseScroll.borderType = .noBorder
        responseScroll.drawsBackground = false
        responseScroll.translatesAutoresizingMaskIntoConstraints = false

        detailTextView = NSTextView()
        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.textContainerInset = NSSize(width: 8, height: 8)
        detailTextView.font = .systemFont(ofSize: 12.5)
        detailTextView.textColor = .labelColor
        detailTextView.isVerticallyResizable = true
        detailTextView.textContainer?.widthTracksTextView = true
        responseScroll.documentView = detailTextView

        copyDetailButton = NSButton(title: "Copy Response", target: self, action: #selector(copyDetail))
        copyDetailButton.bezelStyle = .rounded
        copyDetailButton.translatesAutoresizingMaskIntoConstraints = false
        copyDetailButton.isEnabled = false

        detailContainer.addSubview(detailActionLabel)
        detailContainer.addSubview(detailSnippetLabel)
        detailContainer.addSubview(detailDateLabel)
        detailContainer.addSubview(responseScroll)
        detailContainer.addSubview(copyDetailButton)
        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            detailActionLabel.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: 12),
            detailActionLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 12),
            detailActionLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -12),

            detailSnippetLabel.topAnchor.constraint(equalTo: detailActionLabel.bottomAnchor, constant: 2),
            detailSnippetLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 12),
            detailSnippetLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -12),

            detailDateLabel.topAnchor.constraint(equalTo: detailSnippetLabel.bottomAnchor, constant: 2),
            detailDateLabel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 12),
            detailDateLabel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -12),

            responseScroll.topAnchor.constraint(equalTo: detailDateLabel.bottomAnchor, constant: 8),
            responseScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            responseScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            responseScroll.bottomAnchor.constraint(equalTo: copyDetailButton.topAnchor, constant: -8),

            copyDetailButton.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -12),
            copyDetailButton.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -12),
        ])

        // ---- Bottom toolbar ----
        clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        // ---- Split view ----
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(detailContainer)
        splitView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(splitView)
        contentView.addSubview(clearButton)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),

            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            clearButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        ])

        // Set initial split position
        DispatchQueue.main.async {
            self.splitView.setPosition(220, ofDividerAt: 0)
        }

        tableView.reloadData()
    }

    private func subscribeToUpdates() {
        historyObserver = NotificationCenter.default.addObserver(
            forName: ResponseHistoryManager.historyDidUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    // MARK: - Actions

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if let window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    ResponseHistoryManager.shared.clearAll()
                    self.showDetail(nil)
                }
            }
        }
    }

    @objc private func copyDetail() {
        guard let text = detailTextView?.string, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyDetailButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyDetailButton.title = "Copy Response"
        }
    }

    private func showDetail(_ item: HistoryItem?) {
        guard let item else {
            detailActionLabel.stringValue = ""
            detailSnippetLabel.stringValue = ""
            detailDateLabel.stringValue = ""
            detailTextView.string = ""
            copyDetailButton.isEnabled = false
            return
        }

        detailActionLabel.stringValue = item.actionName
        let snippet = item.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        detailSnippetLabel.stringValue = "\u{201C}\(snippet)\u{201D}"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        detailDateLabel.stringValue = formatter.string(from: item.date)
        detailTextView.string = item.response
        copyDetailButton.isEnabled = true
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension HistoryWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        ResponseHistoryManager.shared.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = ResponseHistoryManager.shared.items
        guard row < items.count else { return nil }
        let item = items[row]

        let container = NSView()

        let actionLabel = NSTextField(labelWithString: item.actionName)
        actionLabel.font = .boldSystemFont(ofSize: 12)
        actionLabel.translatesAutoresizingMaskIntoConstraints = false

        let snippetLabel = NSTextField(labelWithString: item.selectedText.trimmingCharacters(in: .whitespacesAndNewlines))
        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = .secondaryLabelColor
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let dateLabel = NSTextField(labelWithString: formatter.localizedString(for: item.date, relativeTo: Date()))
        dateLabel.font = .systemFont(ofSize: 10)
        dateLabel.textColor = .tertiaryLabelColor
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(actionLabel)
        container.addSubview(snippetLabel)
        container.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            actionLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            actionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            actionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            snippetLabel.topAnchor.constraint(equalTo: actionLabel.bottomAnchor, constant: 2),
            snippetLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            snippetLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            dateLabel.topAnchor.constraint(equalTo: snippetLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
        ])

        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        let items = ResponseHistoryManager.shared.items
        showDetail(row >= 0 && row < items.count ? items[row] : nil)
    }
}
