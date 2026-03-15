import Foundation

/// An action that sends selected text to an LLM with a prompt template.
/// The template uses {{selection}} as a placeholder for the selected text.
struct LLMAction: Action {
    let id: String
    let name: String
    let icon: String
    let isLLMAction = true
    let promptTemplate: String

    private static let maxSelectionLength = 4000

    func execute(selectedText: String, llmService: (any LLMService)?) async -> ActionResult {
        guard let service = llmService else {
            return .stream(AsyncThrowingStream { $0.finish(throwing: LLMError.connectionFailed("No LLM service configured")) })
        }

        // Truncate very long selections to avoid excessive token usage
        let truncated = selectedText.count > Self.maxSelectionLength
        let text = truncated
            ? String(selectedText.prefix(Self.maxSelectionLength)) + "\n\n[...truncated, \(selectedText.count) total characters]"
            : selectedText

        // Replace the {{selection}} placeholder with the (possibly truncated) selected text
        let prompt = promptTemplate.replacingOccurrences(of: "{{selection}}", with: text)

        let stream = await service.stream(
            systemPrompt: "You are a helpful assistant. Be concise and direct.",
            userContent: prompt
        )

        return .stream(stream)
    }

    /// Create from a user-defined custom action config.
    init(custom: CustomActionConfig) {
        self.id = custom.id
        self.name = custom.name
        self.icon = custom.icon
        self.promptTemplate = custom.promptTemplate
    }

    /// Create with explicit parameters.
    init(id: String, name: String, icon: String, promptTemplate: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.promptTemplate = promptTemplate
    }
}
