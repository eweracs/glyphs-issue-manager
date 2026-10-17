import AppKit

/// The plugin's principal class: adds Window → GitHub Issues and owns the panel.
@objc(GitHubIssuesPlugin)
final class GitHubIssuesPlugin: NSObject, GlyphsPlugin, NSMenuItemValidation {

    /// Distinguishes the API version the plugin was built for.
    let interfaceVersion: UInt = 1

    private var panelController: IssuesPanelController?

    @objc var title: String { "GitHub Issues" }

    // Glyphs calls the plugin on the main thread.

    func load() {
        MainActor.assumeIsolated {
            let item = NSMenuItem(title: title, action: #selector(togglePanel(_:)), keyEquivalent: "")
            item.target = self
            // 17 is the tag of Glyphs' Window menu.
            NSApp.mainMenu?.item(withTag: 17)?.submenu?.addItem(item)

            let controller = IssuesPanelController()
            panelController = controller
            if Defaults.panelWasVisible {
                DispatchQueue.main.async { controller.show() }
            }
        }
    }

    @objc func togglePanel(_ sender: Any?) {
        MainActor.assumeIsolated { panelController?.toggle() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePanel(_:)) {
            let visible = MainActor.assumeIsolated { panelController?.isVisible ?? false }
            menuItem.state = visible ? .on : .off
        }
        return true
    }
}
