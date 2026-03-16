import Cocoa

/// Manages the Preferences window with tabs for General, Models, and Actions.
class SettingsWindowController: NSWindowController {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Highlight Tools Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupTabs()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    private var tabView: NSTabView!

    private func setupTabs() {
        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // General tab
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = GeneralSettingsView()
        tabView.addTabViewItem(generalTab)

        // Models tab
        let modelsTab = NSTabViewItem(identifier: "models")
        modelsTab.label = "Models"
        modelsTab.view = ModelsSettingsView()
        tabView.addTabViewItem(modelsTab)

        // Actions tab
        let actionsTab = NSTabViewItem(identifier: "actions")
        actionsTab.label = "Actions"
        actionsTab.view = ActionsSettingsView()
        tabView.addTabViewItem(actionsTab)

        window?.contentView = tabView
    }

    /// Select a specific tab by index (0=General, 1=Models, 2=Actions).
    func selectTab(_ index: Int) {
        guard let tabView, index < tabView.numberOfTabViewItems else { return }
        tabView.selectTabViewItem(at: index)
    }
}
