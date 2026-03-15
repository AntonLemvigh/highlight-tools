import Foundation

/// The default set of LLM actions shipped with the app.
enum DefaultPrompts {

    static let all: [LLMAction] = [
        LLMAction(
            id: "explain",
            name: "Explain",
            icon: "lightbulb",
            promptTemplate: "Explain the following text clearly and concisely:\n\n{{selection}}"
        ),
        LLMAction(
            id: "translate",
            name: "Translate",
            icon: "globe",
            promptTemplate: "Translate the following text to English. If it is already in English, translate it to Danish:\n\n{{selection}}"
        ),
        LLMAction(
            id: "summarize",
            name: "Summarize",
            icon: "text.alignleft",
            promptTemplate: "Summarize the following text in 2-3 sentences:\n\n{{selection}}"
        ),
        LLMAction(
            id: "fixgrammar",
            name: "Fix Grammar",
            icon: "pencil.line",
            promptTemplate: "Fix the grammar and spelling of the following text. Return only the corrected text, nothing else:\n\n{{selection}}"
        ),
    ]
}
