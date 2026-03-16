import Foundation

/// A single item in the response history.
struct HistoryItem: Codable, Identifiable {
    let id: String
    let date: Date
    let actionName: String
    let selectedText: String   // The text that was highlighted
    let response: String       // The LLM response

    init(actionName: String, selectedText: String, response: String) {
        self.id = UUID().uuidString
        self.date = Date()
        self.actionName = actionName
        self.selectedText = selectedText
        self.response = response
    }
}

/// Stores the last N LLM responses so the user can review them later.
/// Posts `historyDidUpdateNotification` whenever the list changes.
class ResponseHistoryManager {

    static let shared = ResponseHistoryManager()

    /// Posted on the main thread whenever history changes.
    static let historyDidUpdateNotification = Notification.Name("ResponseHistoryDidUpdate")

    private let maxItems = 20
    private let defaultsKey = "responseHistory"
    private let defaults = UserDefaults.standard

    private(set) var items: [HistoryItem] = []

    private init() {
        load()
    }

    // MARK: - Public API

    /// Add a completed response to history (called after streaming finishes).
    func add(actionName: String, selectedText: String, response: String) {
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let item = HistoryItem(
            actionName: actionName,
            selectedText: String(selectedText.prefix(300)),   // cap stored snippet length
            response: response
        )
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
        NotificationCenter.default.post(name: Self.historyDidUpdateNotification, object: self)
    }

    /// Remove all history items.
    func clearAll() {
        items = []
        save()
        NotificationCenter.default.post(name: Self.historyDidUpdateNotification, object: self)
    }

    /// Remove a single item by id.
    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
        NotificationCenter.default.post(name: Self.historyDidUpdateNotification, object: self)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey) else { return }
        items = (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        let data = try? JSONEncoder().encode(items)
        defaults.set(data, forKey: defaultsKey)
    }
}
