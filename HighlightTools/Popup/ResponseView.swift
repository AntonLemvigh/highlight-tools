import Cocoa

/// Dedicated view for streaming LLM response display.
/// Uses batched text storage updates for performance.
class ResponseView: NSView {

    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var tokenBuffer: String = ""
    private var flushTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor

        scrollView.documentView = textView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Batch token appends every 50ms for performance
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.flushTokenBuffer()
        }
    }

    /// Buffer a token for batched display.
    func appendToken(_ token: String) {
        tokenBuffer += token
    }

    /// Flush the buffer into the text view.
    private func flushTokenBuffer() {
        guard !tokenBuffer.isEmpty else { return }

        let text = tokenBuffer
        tokenBuffer = ""

        let storage = textView.textStorage!
        storage.beginEditing()
        storage.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]))
        storage.endEditing()
        textView.scrollToEndOfDocument(nil)
    }

    func clear() {
        tokenBuffer = ""
        textView.string = ""
    }

    deinit {
        flushTimer?.invalidate()
    }
}
