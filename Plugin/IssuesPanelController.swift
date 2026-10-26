import AppKit
import SwiftUI

/// Owns the floating panel. It floats above the font windows, hides while
/// Glyphs is in the background and remembers its frame.
@MainActor
final class IssuesPanelController: NSObject, NSWindowDelegate {

    private static let frameName = "com.eweracs.GlyphsIssueManager.panel"
    /// Narrower than this, the compact header's filter row (Open/Closed,
    /// Current glyph, labels) no longer fits between its margins.
    private static let minimumSize = NSSize(width: 340, height: 380)

    private var panel: IssuesPanel?
    private let model = IssuesModel()
    private let chrome = WindowChrome()
    /// List and detail side by side.
    private var isWide = false

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Window → GitHub Issues: hides the panel when it is the key window,
    /// and otherwise brings it up as the key window, ready for the keyboard.
    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow {
            hide()
        } else {
            show(makingKey: true)
        }
    }

    /// `makingKey` false (restoring the panel at launch) leaves the keyboard
    /// with the font window.
    func show(makingKey: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.activate()
        if makingKey {
            panel.makeKeyAndOrderFront(nil)
            model.focusList()
        } else {
            panel.orderFront(nil)
        }
        panel.layoutTrafficLights()
        Defaults.panelWasVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        model.deactivate()
        Defaults.panelWasVisible = false
    }

    private func makePanel() -> IssuesPanel {
        let panel = IssuesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.title = "GitHub Issues"
        panel.backgroundColor = Style.chromeNS
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        // Panels are left out of Cycle Through Windows (⌘`, ⌘< on German
        // keyboards); this one takes part, so it can be reached and closed
        // (⌘W) from the keyboard.
        panel.collectionBehavior = [.fullScreenAuxiliary, .participatesInCycle]
        panel.delegate = self
        apply(Self.compactBar, to: panel)

        chrome.onLayoutChange = { [weak self] wide in
            guard let self, let panel = self.panel else { return }
            self.isWide = wide
            self.apply(wide ? Self.wideBar : Self.compactBar, to: panel)
        }
        panel.onKey = { [weak self] key in
            guard let self else { return false }
            return self.model.handle(key, wide: self.isWide)
        }
        let hosting = PanelHostingView(rootView: RootView(model: model, chrome: chrome))
        hosting.sizingOptions = []
        panel.contentView = hosting
        // After the hosting view is in place, which may otherwise set its own.
        panel.minSize = Self.minimumSize
        panel.contentMinSize = Self.minimumSize

        if !panel.setFrameUsingName(Self.frameName) {
            panel.center()
        }
        // A frame saved before the minimum was raised may be too small.
        var frame = panel.frame
        if frame.width < Self.minimumSize.width || frame.height < Self.minimumSize.height {
            frame.size.width = max(frame.width, Self.minimumSize.width)
            let height = max(frame.height, Self.minimumSize.height)
            frame.origin.y -= height - frame.height
            frame.size.height = height
            panel.setFrame(frame, display: false)
        }
        panel.setFrameAutosaveName(Self.frameName)
        model.window = panel
        return panel
    }

    // MARK: Title bar

    /// Mockup A1: a 38 pt bar, traffic lights 12 pt from the edge.
    private static let compactBar = (height: CGFloat(38), leading: CGFloat(12))
    /// Mockup B: a 52 pt bar, traffic lights 14 pt from the edge.
    private static let wideBar = (height: CGFloat(52), leading: CGFloat(14))

    private func apply(_ bar: (height: CGFloat, leading: CGFloat), to panel: IssuesPanel) {
        panel.titleBarHeight = bar.height
        panel.trafficLightsLeading = bar.leading
        chrome.titlebarHeight = bar.height
        chrome.trafficLightsInset = panel.trafficLightsTrailingEdge + 16
    }

    // MARK: NSWindowDelegate

    /// Only the user closing the panel lands here; Glyphs closing every window
    /// on quit doesn't, so the panel comes back on the next launch.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Defaults.panelWasVisible = false
        return true
    }

    func windowWillClose(_ notification: Notification) {
        model.deactivate()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        panel?.layoutTrafficLights()
        model.panelBecameKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        panel?.layoutTrafficLights()
    }

    func windowDidResize(_ notification: Notification) {
        panel?.layoutTrafficLights()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, Self.minimumSize.width), height: max(frameSize.height, Self.minimumSize.height))
    }
}

/// Keys the panel acts on itself, ahead of the focused view and Glyphs' menus.
enum PanelKey {
    /// Tab or ⇧Tab: the next or previous stop (IssuesModel.tabOrder).
    case tab(backward: Bool)
    /// ↑ (-1) or ↓ (1); `inField` while a text field has focus.
    case arrow(step: Int, inField: Bool)
    /// ← (-1) or → (1) outside text fields.
    case sideways(Int)
    /// Return, Space and Esc outside text fields.
    case confirm, space, escape
    /// ⌘F, ⌘N, ⌘R, ⇧⌘↩.
    case find, newIssue, refresh, closeOrReopen
}

/// A panel whose transparent title bar is as tall as the mockup's top bar,
/// with the traffic lights centred in it. The content (RootView) draws the
/// bar itself underneath.
final class IssuesPanel: NSPanel {
    var titleBarHeight: CGFloat = 38 {
        didSet { layoutTrafficLights() }
    }
    var trafficLightsLeading: CGFloat = 12 {
        didSet { layoutTrafficLights() }
    }

    /// Distance between the origins of neighbouring traffic lights.
    private let trafficLightsStep: CGFloat = 20
    private var isLayingOut = false

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        // AppKit lays the title bar out again on many occasions; put the
        // traffic lights back each time it does.
        if let container = titlebarContainer {
            container.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(titlebarFrameChanged), name: NSView.frameDidChangeNotification, object: container
            )
        }
    }

    /// Right edge of the zoom button, in window coordinates.
    var trafficLightsTrailingEdge: CGFloat {
        let width = standardWindowButton(.zoomButton)?.frame.width ?? 14
        return trafficLightsLeading + 2 * trafficLightsStep + width
    }

    private var titlebarContainer: NSView? {
        standardWindowButton(.closeButton)?.superview?.superview
    }

    @objc private func titlebarFrameChanged(_ notification: Notification) {
        layoutTrafficLights()
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        layoutTrafficLights()
    }

    /// Keys for the panel to act on (IssuesModel.handle); returns whether
    /// it did. They come here before the focused view and Glyphs' menus.
    var onKey: ((PanelKey) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        // Become key first, so the click that focuses the panel also reaches
        // the row or button under it instead of being used up on focusing.
        if event.type == .leftMouseDown, !isKeyWindow, canBecomeKey {
            makeKey()
        }
        // While a text shows suggestions, its keys (Tab among them) are its own.
        if event.type == .keyDown, (firstResponder as? ImageAcceptingTextView)?.isSuggesting == true {
            super.sendEvent(event)
            return
        }
        if event.type == .keyDown, let key = Self.key(for: event, inField: firstResponder is NSText), onKey?(key) == true {
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let key = Self.commandKey(for: event), onKey?(key) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    private static func modifiers(of event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
    }

    /// Tab everywhere; the other keys only outside text fields, which keep
    /// them (except ↓ in the search field, which the model decides on).
    private static func key(for event: NSEvent, inField: Bool) -> PanelKey? {
        let modifiers = modifiers(of: event)
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {  // Tab
            return .tab(backward: modifiers == .shift)
        }
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case 126: return .arrow(step: -1, inField: inField)  // ↑
        case 125: return .arrow(step: 1, inField: inField)  // ↓
        case _ where inField: return nil
        case 123: return .sideways(-1)  // ←
        case 124: return .sideways(1)  // →
        case 36, 76: return .confirm  // Return, Enter
        case 49: return .space
        case 53: return .escape
        default: return nil
        }
    }

    private static func commandKey(for event: NSEvent) -> PanelKey? {
        let modifiers = modifiers(of: event)
        if modifiers == [.command, .shift], event.keyCode == 36 || event.keyCode == 76 { return .closeOrReopen }
        guard modifiers == .command else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f": return .find
        case "n": return .newIssue
        case "r": return .refresh
        default: return nil
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutTrafficLights()
    }

    func layoutTrafficLights() {
        guard !isLayingOut,
              let close = standardWindowButton(.closeButton),
              let titlebar = close.superview,
              let container = titlebar.superview else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        let containerFrame = NSRect(x: 0, y: frame.height - titleBarHeight, width: frame.width, height: titleBarHeight)
        if container.frame != containerFrame { container.frame = containerFrame }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttons.enumerated() {
            guard let button = standardWindowButton(type) else { continue }
            var buttonFrame = button.frame
            buttonFrame.origin.x = trafficLightsLeading + CGFloat(index) * trafficLightsStep
            buttonFrame.origin.y = ((titleBarHeight - buttonFrame.height) / 2).rounded()
            if button.frame != buttonFrame { button.frame = buttonFrame }
        }
    }
}

/// Acts on the first click even while the panel isn't key, as palettes do;
/// otherwise that click would only focus the panel.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Title-bar measurements shared with the SwiftUI views, and the way back to
/// the controller when the layout switches between compact and split.
@MainActor
final class WindowChrome: ObservableObject {
    /// Height of the top bar; the panel's title bar is made the same height.
    @Published var titlebarHeight: CGFloat = 38
    /// Where content may start to the right of the traffic lights.
    @Published var trafficLightsInset: CGFloat = 82

    var onLayoutChange: ((Bool) -> Void)?

    func setWide(_ wide: Bool) {
        onLayoutChange?(wide)
    }
}
