import Cocoa

/// Preferences window with a toolbar at the top — the standard macOS pattern.
/// Each toolbar item switches between General, Models, and Actions panes.
class SettingsWindowController: NSWindowController, NSToolbarDelegate {

    private struct Pane {
        let id: String
        let label: String
        let symbolName: String
        let size: NSSize
    }

    private let paneDefs: [Pane] = [
        Pane(id: "general", label: "General", symbolName: "gearshape",    size: NSSize(width: 500, height: 400)),
        Pane(id: "models",  label: "Models",  symbolName: "cpu",          size: NSSize(width: 500, height: 530)),
        Pane(id: "actions", label: "Actions", symbolName: "list.bullet",  size: NSSize(width: 580, height: 490)),
    ]

    private lazy var generalView  = wrap(GeneralSettingsView())
    private lazy var modelsView   = wrap(ModelsSettingsView())
    private lazy var actionsView  = wrap(ActionsSettingsView())

    private var toolbar: NSToolbar!
    private var currentPaneID: String = ""

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "General"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference

        super.init(window: window)

        toolbar = NSToolbar(identifier: "HighlightToolsSettings")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar

        switchPane(to: paneDefs[0], animate: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Pane management

    /// Wraps a settings view in a scroll view so it can handle taller-than-window content.
    private func wrap(_ view: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = view
        // Pin the document view's width to the scroll view
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.translatesAutoresizingMaskIntoConstraints = false
        // Width tracking is handled by the document view's own constraints
        return scroll
    }

    private func paneView(for pane: Pane) -> NSScrollView {
        switch pane.id {
        case "general": return generalView
        case "models":  return modelsView
        case "actions": return actionsView
        default: fatalError("Unknown pane: \(pane.id)")
        }
    }

    private func switchPane(to pane: Pane, animate: Bool) {
        guard pane.id != currentPaneID else { return }
        currentPaneID = pane.id
        window?.title = pane.label
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(pane.id)

        guard let window else { return }

        let newContentView = paneView(for: pane)
        var newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: pane.size))
        newFrame.origin.x = window.frame.origin.x
        newFrame.origin.y = window.frame.maxY - newFrame.height

        if animate {
            // Fade out → resize + swap → fade in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                window.contentView?.animator().alphaValue = 0
            }, completionHandler: {
                window.contentView = newContentView
                window.setFrame(newFrame, display: true)
                newContentView.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    newContentView.animator().alphaValue = 1
                }
            })
        } else {
            window.contentView = newContentView
            window.setFrame(newFrame, display: false)
        }
    }

    /// Jump directly to a pane by index (0 = General, 1 = Models, 2 = Actions).
    func selectTab(_ index: Int) {
        guard index < paneDefs.count else { return }
        switchPane(to: paneDefs[index], animate: window?.isVisible == true)
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneDefs.map { .init($0.id) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneDefs.map { .init($0.id) }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneDefs.map { .init($0.id) }
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = paneDefs.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.label
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let pane = paneDefs.first(where: { $0.id == sender.itemIdentifier.rawValue }) else { return }
        switchPane(to: pane, animate: true)
    }
}
