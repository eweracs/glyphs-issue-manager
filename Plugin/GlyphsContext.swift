import AppKit

/// The font, glyph and master the user is working on, read from Glyphs.
///
/// `-currentFontDocument` tracks the frontmost *font* document the way
/// `Glyphs.font` does in the Python API, also while our panel is key.
/// `GSDocument` is only forward-declared in the public headers, so it is
/// called dynamically; the object is a real `NSDocument` at runtime.
enum GlyphsContext {

    static func currentDocument() -> NSDocument? {
        let selector = NSSelectorFromString("currentFontDocument")
        guard let app = NSApp, app.responds(to: selector) else { return nil }
        return app.perform(selector)?.takeUnretainedValue() as? NSDocument
    }

    static func font(of document: NSDocument?) -> GSFont? {
        document?.value(forKey: "font") as? GSFont
    }

    static func windowController(of document: NSDocument?) -> GSWindowControllerProtocol? {
        document?.windowControllers.lazy.compactMap { $0 as? GSWindowControllerProtocol }.first
    }

    /// The glyph being edited (Edit view) or selected (Font view).
    static func currentGlyphName(in document: NSDocument?) -> String? {
        guard let wc = windowController(of: document) else { return nil }
        if let layer = wc.activeLayer { return layer.parent?.name }
        return wc.selectedLayers().lazy.compactMap { ($0 as? GSLayer)?.parent?.name }.first
    }

    /// The glyphs selected in the Font view, or in the Edit view's text in
    /// their order there; the glyph being edited when nothing else is.
    static func selectedGlyphNames(in document: NSDocument?) -> [String] {
        guard let wc = windowController(of: document) else { return [] }
        let names = wc.selectedLayers().compactMap { ($0 as? GSLayer)?.parent?.name }
        if !names.isEmpty { return names }
        return wc.activeLayer?.parent?.name.map { [$0] } ?? []
    }

    static func currentMaster(in document: NSDocument?) -> GSFontMaster? {
        guard let font = font(of: document) else { return nil }
        let index = windowController(of: document).map { Int($0.masterIndex) } ?? 0
        return font.fontMaster(at: index) ?? font.fontMasters.first
    }

    // MARK: Glyphs

    static func glyphExists(_ name: String, in font: GSFont) -> Bool {
        font.glyph(forName: name) != nil
    }

    /// Component names of the glyph's layer in `masterID`, traversing nested components.
    static func componentNames(of name: String, in font: GSFont, masterID: String?) -> [String] {
        guard let layer = layer(of: name, in: font, masterID: masterID) else { return [] }
        return layer.componentNamesTraversingComponents
    }

    static func outline(of name: String, in font: GSFont, master: GSFontMaster?) -> GlyphOutline? {
        guard let layer = layer(of: name, in: font, masterID: master?.id) else { return nil }
        let path = layer.drawBezierPath()
        let ascender = master?.ascender(for: layer) ?? CGFloat(font.unitsPerEm) * 0.8
        let descender = master?.descender(for: layer) ?? -CGFloat(font.unitsPerEm) * 0.2
        return GlyphOutline(
            path: path.isEmpty ? nil : path.cgPathCompat,
            bounds: path.isEmpty ? .zero : path.bounds,
            advance: layer.width,
            ascender: ascender,
            descender: descender
        )
    }

    private static func layer(of name: String, in font: GSFont, masterID: String?) -> GSLayer? {
        guard let glyph = font.glyph(forName: name) else { return nil }
        let id = masterID ?? font.fontMasters.first?.id
        return id.flatMap { glyph.layer(forId: $0) }
    }

    // MARK: Actions

    /// Opens the glyphs in a new Edit tab and brings the font window forward.
    @discardableResult
    static func openTab(with names: [String]) -> Bool {
        let document = currentDocument()
        guard let font = font(of: document), let wc = windowController(of: document) else {
            NSSound.beep()
            return false
        }
        var seen = Set<String>()
        let glyphs = names.compactMap { name -> GSGlyph? in
            guard seen.insert(name).inserted else { return nil }
            return font.glyph(forName: name)
        }
        guard !glyphs.isEmpty else {
            NSSound.beep()
            return false
        }
        wc.addTab(with: glyphs)
        (wc as? NSWindowController)?.window?.makeKeyAndOrderFront(nil)
        return true
    }
}

/// A glyph's outline with the metrics needed to draw it at a consistent scale.
struct GlyphOutline {
    let path: CGPath?
    let bounds: CGRect
    let advance: CGFloat
    let ascender: CGFloat
    let descender: CGFloat
}

extension NSBezierPath {
    var cgPathCompat: CGPath {
        if #available(macOS 14, *) { return cgPath }
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .closePath:
                path.closeSubpath()
            default:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            }
        }
        return path
    }
}
