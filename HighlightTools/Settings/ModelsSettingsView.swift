import Cocoa

/// Models settings tab — LLM backend, API keys, model selection, system prompt.
class ModelsSettingsView: NSView {

    private var backendSelector: NSSegmentedControl!
    private var ollamaFields: NSStackView!
    private var openaiFields: NSStackView!
    private var ollamaURLField: NSTextField!
    private var ollamaModelField: NSTextField!
    private var openaiURLField: NSTextField!
    private var openaiKeyField: NSSecureTextField!
    private var openaiModelField: NSTextField!
    private var testButton: NSButton!
    private var statusLabel: NSTextField!
    private var systemPromptView: NSTextView!

    private let fieldWidth: CGFloat = 300
    private let labelWidth: CGFloat = 100

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let settings = SettingsManager.shared

        // ── Section: Backend ──────────────────────────────────────────────
        let backendHeader = sectionHeader("AI Backend")

        backendSelector = NSSegmentedControl(
            labels: ["Ollama (Local)", "OpenAI-compatible"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(backendChanged)
        )
        backendSelector.selectedSegment = settings.selectedBackend == "openai" ? 1 : 0

        // Ollama fields
        ollamaURLField   = makeField(value: settings.ollamaBaseURL, placeholder: "http://localhost:11434")
        ollamaModelField = makeField(value: settings.ollamaModel, placeholder: "llama3.2")
        ollamaFields = NSStackView(views: [
            labeledRow("Server URL", ollamaURLField),
            labeledRow("Model",      ollamaModelField),
        ])
        ollamaFields.orientation = .vertical
        ollamaFields.alignment   = .leading
        ollamaFields.spacing     = 8

        // OpenAI fields
        openaiURLField = makeField(value: settings.openaiBaseURL, placeholder: "https://api.openai.com")
        openaiKeyField = NSSecureTextField()
        openaiKeyField.stringValue       = settings.openaiAPIKey
        openaiKeyField.placeholderString = "sk-…"
        openaiKeyField.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        openaiModelField = makeField(value: settings.openaiModel, placeholder: "gpt-4o-mini")
        openaiFields = NSStackView(views: [
            labeledRow("API Base URL", openaiURLField),
            labeledRow("API Key",      openaiKeyField),
            labeledRow("Model",        openaiModelField),
        ])
        openaiFields.orientation = .vertical
        openaiFields.alignment   = .leading
        openaiFields.spacing     = 8

        // Test + Save row
        testButton  = NSButton(title: "Test Connection", target: self, action: #selector(testConnection))
        testButton.bezelStyle = .rounded
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font      = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        let testRow = NSStackView(views: [testButton, statusLabel])
        testRow.orientation = .horizontal
        testRow.spacing = 8

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        // ── Section: System Prompt ────────────────────────────────────────
        let promptHeader = sectionHeader("System Prompt")
        let promptHint = hintLabel("Prepended to every AI request. Customise the tone, language, or behaviour.")

        let promptScroll = NSScrollView()
        promptScroll.hasVerticalScroller = true
        promptScroll.autohidesScrollers  = true
        promptScroll.borderType          = .bezelBorder
        promptScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true

        systemPromptView = NSTextView()
        systemPromptView.isEditable    = true
        systemPromptView.isRichText    = false
        systemPromptView.font          = .systemFont(ofSize: 12)
        systemPromptView.string        = settings.systemPrompt
        systemPromptView.textContainerInset = NSSize(width: 4, height: 4)
        systemPromptView.isVerticallyResizable = true
        systemPromptView.textContainer?.widthTracksTextView = true
        promptScroll.documentView = systemPromptView

        // ── Main stack ────────────────────────────────────────────────────
        let main = NSStackView(views: [
            backendHeader,
            backendSelector,
            ollamaFields,
            openaiFields,
            testRow,
            saveButton,
            hairline(),
            promptHeader,
            promptHint,
            promptScroll,
        ])
        main.orientation = .vertical
        main.alignment   = .leading
        main.spacing     = 10
        main.edgeInsets  = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.translatesAutoresizingMaskIntoConstraints = false

        addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor),
            main.leadingAnchor.constraint(equalTo: leadingAnchor),
            main.trailingAnchor.constraint(equalTo: trailingAnchor),
            main.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            promptScroll.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -40),
        ])

        updateFieldVisibility()
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func hintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeField(value: String, placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.stringValue       = value
        f.placeholderString = placeholder
        f.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        return f
    }

    private func labeledRow(_ labelText: String, _ control: NSView) -> NSStackView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font      = .systemFont(ofSize: 12)
        lbl.textColor = .secondaryLabelColor
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        let r = NSStackView(views: [lbl, control])
        r.orientation = .horizontal
        r.spacing = 8
        return r
    }

    private func hairline() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    // MARK: - Actions

    @objc private func backendChanged() { updateFieldVisibility() }

    private func updateFieldVisibility() {
        let isOllama = backendSelector.selectedSegment == 0
        ollamaFields.isHidden = !isOllama
        openaiFields.isHidden = isOllama
    }

    @objc private func save() {
        let s = SettingsManager.shared
        s.selectedBackend = backendSelector.selectedSegment == 0 ? "ollama" : "openai"
        s.ollamaBaseURL   = ollamaURLField.stringValue
        s.ollamaModel     = ollamaModelField.stringValue
        s.openaiBaseURL   = openaiURLField.stringValue
        s.openaiAPIKey    = openaiKeyField.stringValue
        s.openaiModel     = openaiModelField.stringValue

        let prompt = systemPromptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { s.systemPrompt = prompt }

        statusLabel.stringValue = "Saved!"
        statusLabel.textColor   = .systemGreen
    }

    @objc private func testConnection() {
        statusLabel.stringValue = "Testing…"
        statusLabel.textColor   = .secondaryLabelColor
        testButton.isEnabled    = false
        save()

        Task {
            let available = await LLMServiceFactory.create().isAvailable
            await MainActor.run {
                self.testButton.isEnabled  = true
                self.statusLabel.stringValue = available ? "Connected!" : "Connection failed"
                self.statusLabel.textColor   = available ? .systemGreen : .systemRed
            }
        }
    }
}
