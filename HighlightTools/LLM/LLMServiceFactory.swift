import Foundation

/// Creates the appropriate LLM service based on current settings.
/// Called each time an action is invoked so settings changes take effect immediately.
enum LLMServiceFactory {

    static func create() -> any LLMService {
        switch SettingsManager.shared.selectedBackend {
        case "openai":
            return OpenAIService()
        case "ollama":
            return OllamaService()
        default:
            return OllamaService()
        }
    }
}
