#!/bin/bash
#
# Builds GitHubIssues.glyphsPlugin by compiling the IssueCore + Plugin Swift
# sources directly with swiftc, against the GlyphsCore public headers shipped
# inside Glyphs.app. GlyphsCore symbols are resolved at load time
# (`-undefined dynamic_lookup`), exactly like an Objective-C plugin.
#
# Usage:
#   ./build.command            # build only
#   ./build.command install    # build, then copy into the Glyphs 3 Plugins folder
#
# Environment:
#   GLYPHS_APP      Glyphs application to compile against (default: /Applications/Glyphs 3.app)
#   GLYPHS_PLUGINS  Plugins folder for `install` (default: ~/Library/Application Support/Glyphs 3/Plugins)
#   ARCHS           Architectures to build (default: "arm64 x86_64")
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${GLYPHS_APP:-/Applications/Glyphs 3.app}"
FW="$APP/Contents/Frameworks"
ARCHS="${ARCHS:-arm64 x86_64}"
MODULE="GlyphsIssueManager"
DEPLOYMENT="13.0"

if [[ ! -d "$FW/GlyphsCore.framework" ]]; then
    echo "error: GlyphsCore.framework not found in $FW"
    echo "       set GLYPHS_APP to your Glyphs application bundle."
    exit 1
fi

OUT="$DIR/build"
BUNDLE="$OUT/GitHubIssues.glyphsPlugin"
MACOS="$BUNDLE/Contents/MacOS"
rm -rf "$BUNDLE"
mkdir -p "$MACOS"
cp "$DIR/Plugin/Info.plist" "$BUNDLE/Contents/Info.plist"

SOURCES=()
while IFS= read -r -d '' f; do
    SOURCES+=("$f")
done < <(find "$DIR/Sources/IssueCore" "$DIR/Plugin" -name '*.swift' -print0 | sort -z)

SLICES=()
for arch in $ARCHS; do
    echo "Compiling ($arch)…"
    slice="$OUT/$MODULE-$arch"
    swiftc \
        -module-name "$MODULE" \
        -swift-version 5 \
        -O \
        -target "${arch}-apple-macos${DEPLOYMENT}" \
        -sdk "$(xcrun --show-sdk-path)" \
        -import-objc-header "$DIR/Plugin/BridgingHeader.h" \
        -F "$FW" \
        -emit-library \
        -o "$slice" \
        -Xlinker -bundle \
        -Xlinker -undefined -Xlinker dynamic_lookup \
        "${SOURCES[@]}"
    SLICES+=("$slice")
done

echo "Creating binary…"
lipo -create "${SLICES[@]}" -output "$MACOS/$MODULE"
rm -f "${SLICES[@]}"

echo "Ad-hoc signing…"
codesign --force --deep --sign - "$BUNDLE"

echo "Built: $BUNDLE"
file "$MACOS/$MODULE"

if [[ "${1:-}" == "install" ]]; then
    PLUGINS="${GLYPHS_PLUGINS:-$HOME/Library/Application Support/Glyphs 3/Plugins}"
    mkdir -p "$PLUGINS"
    rm -rf "$PLUGINS/GitHubIssues.glyphsPlugin"
    cp -R "$BUNDLE" "$PLUGINS/GitHubIssues.glyphsPlugin"
    echo "Installed to: $PLUGINS/GitHubIssues.glyphsPlugin"
    echo "Restart Glyphs, then choose Window → GitHub Issues."
fi
