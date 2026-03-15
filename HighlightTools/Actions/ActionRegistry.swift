import Foundation

/// Central registry of all available actions (built-in + custom).
/// Rebuilds the action list whenever settings change.
class ActionRegistry {

    static let shared = ActionRegistry()

    private(set) var actions: [any Action] = []
    private var settingsObserver: NSObjectProtocol?

    private init() {
        reload()

        // Rebuild when settings change
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        var list: [any Action] = []
        let settings = SettingsManager.shared
        let iconOverrides = settings.actionIconOverrides

        // Non-LLM actions
        if settings.showNonLLMActions {
            list.append(CopyAction(icon: iconOverrides["copy"] ?? "doc.on.doc"))
            list.append(SearchAction(icon: iconOverrides["search"] ?? "magnifyingglass"))
        }

        // Default LLM actions (only if enabled), applying icon overrides
        for action in DefaultPrompts.all {
            if settings.isActionEnabled(action.id) {
                if let overrideIcon = iconOverrides[action.id] {
                    list.append(LLMAction(id: action.id, name: action.name, icon: overrideIcon, promptTemplate: action.promptTemplate))
                } else {
                    list.append(action)
                }
            }
        }

        // Custom actions defined by the user
        for config in settings.customActions {
            list.append(LLMAction(custom: config))
        }

        // Apply saved ordering
        let order = settings.actionOrder
        if !order.isEmpty {
            let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            list.sort { a, b in
                let ai = orderMap[a.id] ?? Int.max
                let bi = orderMap[b.id] ?? Int.max
                return ai < bi
            }
        }

        actions = list
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
