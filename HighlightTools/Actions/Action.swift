import Foundation

/// Result of executing an action on selected text.
enum ActionResult {
    /// A streaming LLM response — tokens arrive one by one
    case stream(AsyncThrowingStream<String, Error>)
    /// Action completed immediately (e.g., copy to clipboard)
    case completed
    /// Open a URL (e.g., web search)
    case openURL(URL)
}

/// Protocol for all popup actions (LLM-based and non-LLM).
protocol Action: Identifiable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }           // SF Symbol name or emoji
    var isLLMAction: Bool { get }
    func execute(selectedText: String, llmService: (any LLMService)?) async -> ActionResult
}
