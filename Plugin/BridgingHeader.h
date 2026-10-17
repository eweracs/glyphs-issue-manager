//
//  BridgingHeader.h
//  Exposes the GlyphsCore Objective-C API to Swift.
//
//  The classes and protocols (GSFont, GSGlyph, GSLayer, the window controller
//  protocol, …) are provided at runtime by the host application. We compile
//  against the public headers shipped inside GlyphsCore.framework and link with
//  `-undefined dynamic_lookup`, so the symbols resolve when Glyphs loads the
//  bundle.
//

#import <Cocoa/Cocoa.h>
#import <GlyphsCore/GlyphsCore.h>
#import <GlyphsCore/GlyphsPluginProtocol.h>
#import <GlyphsCore/GSWindowControllerProtocol.h>
