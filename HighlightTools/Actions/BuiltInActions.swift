import Cocoa

/// Copies the selected text to the clipboard.
struct CopyAction: Action {
    let id = "copy"
    let name = "Copy"
    let icon: String
    let isLLMAction = false

    init(icon: String = "doc.on.doc") {
        self.icon = icon
    }

    func execute(selectedText: String, llmService: (any LLMService)?) async -> ActionResult {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
        return .completed
    }
}

/// Opens a web search for the selected text.
struct SearchAction: Action {
    let id = "search"
    let name = "Search"
    let icon: String
    let isLLMAction = false

    init(icon: String = "magnifyingglass") {
        self.icon = icon
    }

    func execute(selectedText: String, llmService: (any LLMService)?) async -> ActionResult {
        let query = selectedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedText
        if let url = URL(string: "https://www.google.com/search?q=\(query)") {
            return .openURL(url)
        }
        return .completed
    }
}
