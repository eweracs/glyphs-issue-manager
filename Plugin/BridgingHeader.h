//
//  BridgingHeader.h
//  Exposes the Glyphs Objective-C API to Swift.
//
//  The classes and protocols (GSFont, GSGlyph, GSLayer, the window controller,
//  …) are provided at runtime by the host application. We compile against the
//  public headers shipped inside Glyphs.app and link with
//  `-undefined dynamic_lookup`, so the symbols resolve when Glyphs loads the
//  bundle.
//

#import <Cocoa/Cocoa.h>
#import <GlyphsCore/GlyphsCore.h>

// Glyphs 4 moved the app-side types (the plugin protocol, GSWindowController)
// out of GlyphsCore into GlyphsApp.framework, which Glyphs 3 doesn't have.
#if __has_include(<GlyphsApp/GlyphsApp.h>)
#import <GlyphsApp/GlyphsApp.h>
#else
#import <GlyphsCore/GlyphsPluginProtocol.h>
#import <GlyphsCore/GSWindowControllerProtocol.h>
#endif
