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

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.activate()
        panel.orderFront(nil)
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
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.delegate = self
        apply(Self.compactBar, to: panel)

        chrome.onLayoutChange = { [weak self] wide in
            guard let self, let panel = self.panel else { return }
            self.apply(wide ? Self.wideBar : Self.compactBar, to: panel)
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

    /// Become key first, so the click that focuses the panel also reaches the
    /// row or button under it instead of being used up on focusing.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow, canBecomeKey {
            makeKey()
        }
        super.sendEvent(event)
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
