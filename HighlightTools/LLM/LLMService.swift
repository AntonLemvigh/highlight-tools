import Foundation

/// Errors that can occur when communicating with an LLM backend.
enum LLMError: LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case authenticationFailed
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .authenticationFailed: return "Authentication failed — check your API key"
        case .modelNotFound(let model): return "Model not found: \(model)"
        }
    }
}

/// Protocol for LLM service backends (Ollama, OpenAI-compatible, etc).
protocol LLMService {
    /// Check if the service is reachable and configured.
    var isAvailable: Bool { get async }

    /// Stream a completion response token by token.
    func stream(systemPrompt: String, userContent: String) async -> AsyncThrowingStream<String, Error>
}
