import Cocoa

/// A persistent floating window that shows a single LLM response.
/// Multiple instances can coexist — created when the user clicks "Pin" in the popup.
class DetachedResponseWindowController: NSWindowController {

    private let actionName: String
    private let selectedText: String
    private let responseText: String

    private var textView: NSTextView!
    private var copyButton: NSButton!

    init(actionName: String, selectedText: String, response: String) {
        self.actionName = actionName
        self.selectedText = selectedText
        self.responseText = response

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = actionName
        window.minSize = NSSize(width: 280, height: 180)
        // Float slightly above normal windows so it stays visible
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)

        setupContent()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        // Header: action name + snippet of selected text
        let headerLabel = NSTextField(labelWithString: actionName)
        headerLabel.font = .boldSystemFont(ofSize: 13)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let snippetText = selectedText.prefix(120).trimmingCharacters(in: .whitespacesAndNewlines)
        let ellipsis = selectedText.count > 120 ? "\u{2026}" : ""
        let snippetLabel = NSTextField(labelWithString: "\u{201C}\(snippetText)\(ellipsis)\u{201D}")
        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = .secondaryLabelColor
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Response text
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.string = responseText
        scrollView.documentView = textView

        // Copy button
        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyResponse))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(headerLabel)
        contentView.addSubview(snippetLabel)
        contentView.addSubview(separator)
        contentView.addSubview(scrollView)
        contentView.addSubview(copyButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            snippetLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 3),
            snippetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            snippetLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),

            separator.topAnchor.constraint(equalTo: snippetLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -8),

            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
        ])
    }

    @objc private func copyResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText, forType: .string)
        copyButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }
}
