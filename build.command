#!/bin/bash
#
# Builds the GitHub Issues plugin by compiling the IssueCore + Plugin Swift
# sources directly with swiftc, against the public headers shipped inside
# Glyphs.app. Glyphs symbols are resolved at load time
# (`-undefined dynamic_lookup`), exactly like an Objective-C plugin.
#
# The same sources build for Glyphs 3 and Glyphs 4, whose headers differ:
# the Glyphs 4 build defines `GLYPHS4` (see Plugin/GlyphsCompat.swift).
#
# Usage:
#   ./build.command            # build only
#   ./build.command install    # build, then copy into that Glyphs version's Plugins folder
#
# Environment:
#   GLYPHS          3 (default) or 4
#   GLYPHS_APP      Glyphs application to compile against
#                   (default: /Applications/Glyphs 3.app or /Applications/Glyphs 4.app)
#   GLYPHS_PLUGINS  Plugins folder for `install`
#                   (default: ~/Library/Application Support/Glyphs 3 or 4/Plugins)
#   BUILD_DIR       where the bundle goes (default: build/ for Glyphs 3, build/Glyphs 4/ for Glyphs 4)
#   BUNDLE_NAME     bundle name without .glyphsPlugin (default: GitHubIssues)
#   ARCHS           architectures to build (default: "arm64 x86_64")
#   PLUGIN_VERSION  the bundle's version (default: the newest released
#                   `## [X.Y.Z]` in CHANGELOG.md)
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GLYPHS="${GLYPHS:-3}"
case "$GLYPHS" in
    3) DEFINES=() ;;
    4) DEFINES=(-D GLYPHS4) ;;
    *) echo "error: GLYPHS must be 3 or 4, not “$GLYPHS”"; exit 1 ;;
esac
APP="${GLYPHS_APP:-/Applications/Glyphs $GLYPHS.app}"
FW="$APP/Contents/Frameworks"
ARCHS="${ARCHS:-arm64 x86_64}"
MODULE="GlyphsIssueManager"
DEPLOYMENT="13.0"

if [[ ! -d "$FW/GlyphsCore.framework" ]]; then
    echo "error: GlyphsCore.framework not found in $FW"
    echo "       set GLYPHS_APP to your Glyphs $GLYPHS application bundle."
    exit 1
fi

if [[ "$GLYPHS" == 3 ]]; then
    OUT="${BUILD_DIR:-$DIR/build}"
else
    OUT="${BUILD_DIR:-$DIR/build/Glyphs 4}"
fi
NAME="${BUNDLE_NAME:-GitHubIssues}"
BUNDLE="$OUT/$NAME.glyphsPlugin"
MACOS="$BUNDLE/Contents/MacOS"
rm -rf "$BUNDLE"
mkdir -p "$MACOS"
cp "$DIR/Plugin/Info.plist" "$BUNDLE/Contents/Info.plist"

# The version: the first `## [X.Y.Z]` heading in the changelog (builds between
# releases carry the last released version), and a build number that grows
# with every commit.
VERSION="${PLUGIN_VERSION:-}"
if [[ -z "$VERSION" && -f "$DIR/CHANGELOG.md" ]]; then
    VERSION="$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p' "$DIR/CHANGELOG.md" | head -1)"
fi
if [[ -n "$VERSION" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$BUNDLE/Contents/Info.plist"
fi
if BUILD_NUMBER="$(git -C "$DIR" rev-list --count HEAD 2>/dev/null)"; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$BUNDLE/Contents/Info.plist"
fi

SOURCES=()
while IFS= read -r -d '' f; do
    SOURCES+=("$f")
done < <(find "$DIR/Sources/IssueCore" "$DIR/Plugin" -name '*.swift' -print0 | sort -z)

SLICES=()
for arch in $ARCHS; do
    echo "Compiling for Glyphs $GLYPHS ($arch)…"
    slice="$OUT/$MODULE-$arch"
    swiftc \
        -module-name "$MODULE" \
        -swift-version 5 \
        -O \
        -target "${arch}-apple-macos${DEPLOYMENT}" \
        -sdk "$(xcrun --show-sdk-path)" \
        -import-objc-header "$DIR/Plugin/BridgingHeader.h" \
        -F "$FW" \
        ${DEFINES[@]+"${DEFINES[@]}"} \
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

echo "Built: $BUNDLE (version ${VERSION:-from Info.plist}, Glyphs $GLYPHS)"
file "$MACOS/$MODULE"

if [[ "${1:-}" == "install" ]]; then
    PLUGINS="${GLYPHS_PLUGINS:-$HOME/Library/Application Support/Glyphs $GLYPHS/Plugins}"
    mkdir -p "$PLUGINS"
    rm -rf "$PLUGINS/$NAME.glyphsPlugin"
    cp -R "$BUNDLE" "$PLUGINS/$NAME.glyphsPlugin"
    echo "Installed to: $PLUGINS/$NAME.glyphsPlugin"
    echo "Restart Glyphs, then choose Window → GitHub Issues."
fi
