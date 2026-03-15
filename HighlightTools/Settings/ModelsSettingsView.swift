import Cocoa

/// Models settings tab: backend selection, API keys, model names, endpoints.
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Backend selector
        backendSelector = NSSegmentedControl(labels: ["Ollama (Local)", "OpenAI-compatible"], trackingMode: .selectOne, target: self, action: #selector(backendChanged))
        backendSelector.selectedSegment = SettingsManager.shared.selectedBackend == "openai" ? 1 : 0

        // Ollama fields
        ollamaURLField = makeTextField(value: SettingsManager.shared.ollamaBaseURL, placeholder: "http://localhost:11434")
        ollamaModelField = makeTextField(value: SettingsManager.shared.ollamaModel, placeholder: "llama3.2")
        ollamaFields = NSStackView(views: [
            labeledField("Server URL:", ollamaURLField),
            labeledField("Model:", ollamaModelField),
        ])
        ollamaFields.orientation = .vertical
        ollamaFields.alignment = .leading
        ollamaFields.spacing = 8

        // OpenAI fields
        openaiURLField = makeTextField(value: SettingsManager.shared.openaiBaseURL, placeholder: "https://api.openai.com")
        openaiKeyField = NSSecureTextField()
        openaiKeyField.stringValue = SettingsManager.shared.openaiAPIKey
        openaiKeyField.placeholderString = "sk-..."
        openaiKeyField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        openaiModelField = makeTextField(value: SettingsManager.shared.openaiModel, placeholder: "gpt-4o-mini")
        openaiFields = NSStackView(views: [
            labeledField("API Base URL:", openaiURLField),
            labeledField("API Key:", openaiKeyField),
            labeledField("Model:", openaiModelField),
        ])
        openaiFields.orientation = .vertical
        openaiFields.alignment = .leading
        openaiFields.spacing = 8

        // Test connection button
        testButton = NSButton(title: "Test Connection", target: self, action: #selector(testConnection))
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        let testRow = NSStackView(views: [testButton, statusLabel])
        testRow.orientation = .horizontal
        testRow.spacing = 8

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        // Main layout
        let stack = NSStackView(views: [backendSelector, ollamaFields, openaiFields, testRow, saveButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        updateFieldVisibility()
    }

    private func makeTextField(value: String, placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.stringValue = value
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return field
    }

    private func labeledField(_ label: String, _ field: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        labelView.alignment = .right
        let row = NSStackView(views: [labelView, field])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func backendChanged() {
        updateFieldVisibility()
    }

    private func updateFieldVisibility() {
        let isOllama = backendSelector.selectedSegment == 0
        ollamaFields.isHidden = !isOllama
        openaiFields.isHidden = isOllama
    }

    @objc private func save() {
        SettingsManager.shared.selectedBackend = backendSelector.selectedSegment == 0 ? "ollama" : "openai"
        SettingsManager.shared.ollamaBaseURL = ollamaURLField.stringValue
        SettingsManager.shared.ollamaModel = ollamaModelField.stringValue
        SettingsManager.shared.openaiBaseURL = openaiURLField.stringValue
        SettingsManager.shared.openaiAPIKey = openaiKeyField.stringValue
        SettingsManager.shared.openaiModel = openaiModelField.stringValue

        statusLabel.stringValue = "Saved!"
        statusLabel.textColor = .systemGreen
    }

    @objc private func testConnection() {
        statusLabel.stringValue = "Testing..."
        statusLabel.textColor = .secondaryLabelColor
        testButton.isEnabled = false

        save()

        Task {
            let service = LLMServiceFactory.create()
            let available = await service.isAvailable

            await MainActor.run {
                testButton.isEnabled = true
                if available {
                    statusLabel.stringValue = "Connected!"
                    statusLabel.textColor = .systemGreen
                } else {
                    statusLabel.stringValue = "Connection failed"
                    statusLabel.textColor = .systemRed
                }
            }
        }
    }
}
