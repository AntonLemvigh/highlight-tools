import Foundation

/// Central settings manager backed by UserDefaults.
/// All app configuration lives here — LLM backend, API keys, custom actions, etc.
class SettingsManager {

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let isEnabled = "isEnabled"
        static let selectedBackend = "selectedBackend"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let ollamaModel = "ollamaModel"
        static let openaiBaseURL = "openaiBaseURL"
        static let openaiAPIKey = "openaiAPIKey"
        static let openaiModel = "openaiModel"
        static let customActions = "customActions"
        static let showNonLLMActions = "showNonLLMActions"
        static let triggerDelay = "triggerDelay"
        static let enabledDefaultActions = "enabledDefaultActions"
        static let actionOrder = "actionOrder"
        static let actionIconOverrides = "actionIconOverrides"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let disabledBundleIDs = "disabledBundleIDs"
        static let systemPrompt = "systemPrompt"
        static let defaultActionNameOverrides = "defaultActionNameOverrides"
        static let defaultActionPromptOverrides = "defaultActionPromptOverrides"
    }

    // MARK: - Init (register defaults)

    private init() {
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.selectedBackend: "ollama",
            Key.ollamaBaseURL: "http://localhost:11434",
            Key.ollamaModel: "llama3.2",
            Key.openaiBaseURL: "https://api.openai.com",
            Key.openaiAPIKey: "",
            Key.openaiModel: "gpt-4o-mini",
            Key.showNonLLMActions: true,
            Key.triggerDelay: 0.3,
            Key.enabledDefaultActions: ["explain", "translate", "summarize", "fixgrammar"],
            Key.hasCompletedOnboarding: false,
            Key.disabledBundleIDs: [String](),
            Key.systemPrompt: "You are a helpful assistant. Be concise and direct.",
        ])
    }

    // MARK: - General

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    var triggerDelay: Double {
        get { defaults.double(forKey: Key.triggerDelay) }
        set { defaults.set(newValue, forKey: Key.triggerDelay) }
    }

    var showNonLLMActions: Bool {
        get { defaults.bool(forKey: Key.showNonLLMActions) }
        set { defaults.set(newValue, forKey: Key.showNonLLMActions) }
    }

    // MARK: - LLM Backend

    /// "ollama" or "openai"
    var selectedBackend: String {
        get { defaults.string(forKey: Key.selectedBackend) ?? "ollama" }
        set { defaults.set(newValue, forKey: Key.selectedBackend) }
    }

    // MARK: - Ollama

    var ollamaBaseURL: String {
        get { defaults.string(forKey: Key.ollamaBaseURL) ?? "http://localhost:11434" }
        set { defaults.set(newValue, forKey: Key.ollamaBaseURL) }
    }

    var ollamaModel: String {
        get { defaults.string(forKey: Key.ollamaModel) ?? "llama3.2" }
        set { defaults.set(newValue, forKey: Key.ollamaModel) }
    }

    // MARK: - OpenAI-compatible

    var openaiBaseURL: String {
        get { defaults.string(forKey: Key.openaiBaseURL) ?? "https://api.openai.com" }
        set { defaults.set(newValue, forKey: Key.openaiBaseURL) }
    }

    var openaiAPIKey: String {
        get { defaults.string(forKey: Key.openaiAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.openaiAPIKey) }
    }

    var openaiModel: String {
        get { defaults.string(forKey: Key.openaiModel) ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Key.openaiModel) }
    }

    // MARK: - Default Action Toggles

    var enabledDefaultActions: [String] {
        get { defaults.stringArray(forKey: Key.enabledDefaultActions) ?? [] }
        set { defaults.set(newValue, forKey: Key.enabledDefaultActions) }
    }

    func isActionEnabled(_ actionID: String) -> Bool {
        enabledDefaultActions.contains(actionID)
    }

    // MARK: - Action Order & Icon Overrides

    /// Ordered list of all action IDs. Actions not in the list go at the end in default order.
    var actionOrder: [String] {
        get { defaults.stringArray(forKey: Key.actionOrder) ?? [] }
        set { defaults.set(newValue, forKey: Key.actionOrder) }
    }

    /// Icon overrides for built-in/default actions (keyed by action ID).
    var actionIconOverrides: [String: String] {
        get { defaults.dictionary(forKey: Key.actionIconOverrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.actionIconOverrides) }
    }

    func iconForAction(_ actionID: String) -> String? {
        actionIconOverrides[actionID]
    }

    func setIcon(_ icon: String, forAction actionID: String) {
        var overrides = actionIconOverrides
        overrides[actionID] = icon
        actionIconOverrides = overrides
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: - Per-App Disable

    /// Bundle IDs of apps where Highlight Tools should not activate (e.g. "com.1password.1password").
    var disabledBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.disabledBundleIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.disabledBundleIDs) }
    }

    func isBundleIDDisabled(_ bundleID: String) -> Bool {
        disabledBundleIDs.contains(bundleID)
    }

    // MARK: - System Prompt

    /// Global system prompt prepended to all LLM calls.
    var systemPrompt: String {
        get { defaults.string(forKey: Key.systemPrompt) ?? "You are a helpful assistant. Be concise and direct." }
        set { defaults.set(newValue, forKey: Key.systemPrompt) }
    }

    // MARK: - Default Action Customisation (name + prompt overrides)

    /// User-edited display names for built-in LLM actions, keyed by action ID.
    var defaultActionNameOverrides: [String: String] {
        get { defaults.dictionary(forKey: Key.defaultActionNameOverrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.defaultActionNameOverrides) }
    }

    /// User-edited prompt templates for built-in LLM actions, keyed by action ID.
    var defaultActionPromptOverrides: [String: String] {
        get { defaults.dictionary(forKey: Key.defaultActionPromptOverrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.defaultActionPromptOverrides) }
    }

    // MARK: - Custom Actions

    var customActions: [CustomActionConfig] {
        get {
            guard let data = defaults.data(forKey: Key.customActions) else { return [] }
            return (try? JSONDecoder().decode([CustomActionConfig].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.customActions)
        }
    }
}

/// Configuration for a user-defined custom action.
/// Stored as JSON in UserDefaults.
struct CustomActionConfig: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String  // SF Symbol name or emoji
    var promptTemplate: String  // Use {{selection}} as placeholder
}
