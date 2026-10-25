import AppKit

// Glyphs 3 and Glyphs 4.
//
// build.command compiles the same sources against Glyphs 3's headers and,
// with `GLYPHS4` defined, against Glyphs 4's, which spell a few things
// differently. Those are used under their Glyphs 4 spelling everywhere and
// shimmed here for Glyphs 3, so call sites need no `#if`.

#if !GLYPHS4
/// Glyphs 4 has a `GSWindowController` class (GlyphsApp.framework); Glyphs 3
/// exposes the font window controller only through a protocol.
typealias GSWindowController = any NSWindowController & GSWindowControllerProtocol

extension GSWindowControllerProtocol {
    /// A property in Glyphs 4, a method in Glyphs 3.
    var selectedLayers: NSArray? { selectedLayers() as NSArray? }
}
#endif
