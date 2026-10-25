#!/bin/bash
#
# Cuts a release (see RELEASING.md):
#
#   1. turns the changelog's [Unreleased] section into [X.Y.Z] and makes the
#      release notes from it,
#   2. runs the tests and builds the plugin for Glyphs 3 and Glyphs 4,
#   3. commits the Glyphs 3 bundle, GitHubIssuesG3.glyphsPlugin, at the top
#      of the repository – the Glyphs 3 Plugin Manager installs it from a
#      clone – together with the changelog, as “Cut release X.Y.Z”,
#   4. tags vX.Y.Z, pushes the branch and the tag, and
#   5. publishes the GitHub release with GitHubIssues.zip (both bundles),
#      which the Glyphs 4 Plugin Manager downloads from the latest release.
#
# Usage:
#   ./release.command X.Y.Z "Short title" --dry-run   # steps 1–2 and the zip; changes nothing
#   ./release.command X.Y.Z "Short title"             # all of it
#
# Environment:
#   GLYPHS3_APP, GLYPHS4_APP   the Glyphs applications to build against
#                              (default: /Applications/Glyphs 3.app, /Applications/Glyphs 4.app)
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

usage() {
    echo "usage: ./release.command X.Y.Z \"Short title\" [--dry-run]" >&2
    exit 1
}
VERSION="${1:-}"
TITLE="${2:-}"
MODE="${3:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ -n "$TITLE" ]] || usage
case "$MODE" in
    "") DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    *) usage ;;
esac

TAG="v$VERSION"
BRANCH="master"
REPO="$(git remote get-url origin | sed -E 's#(\.git)?/*$##; s#^.*github\.com[:/]##')"
OUT="$DIR/build/Release"
ZIP="GitHubIssues.zip"
G3="GitHubIssuesG3"
G4="GitHubIssuesG4"
DATE="$(date +%Y-%m-%d)"

fail() {
    echo "error: $*" >&2
    exit 1
}
step() {
    echo
    echo "==> $*"
}

# MARK: Checks

step "Checking"
for app in "${GLYPHS3_APP:-/Applications/Glyphs 3.app}" "${GLYPHS4_APP:-/Applications/Glyphs 4.app}"; do
    [[ -d "$app/Contents/Frameworks/GlyphsCore.framework" ]] || fail "$app not found; set GLYPHS3_APP / GLYPHS4_APP"
done
if ! $DRY_RUN; then
    command -v gh >/dev/null || fail "publishing needs the GitHub CLI, gh"
    gh auth status >/dev/null 2>&1 || fail "gh isn't signed in (gh auth login)"
    [[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "releases are cut from $BRANCH"
    dirty="$(git status --porcelain | grep -v ' CHANGELOG.md$' || true)"
    [[ -z "$dirty" ]] || fail "uncommitted changes other than CHANGELOG.md:
$dirty"
    git fetch --quiet origin "$BRANCH" --tags
    git merge-base --is-ancestor "origin/$BRANCH" HEAD || fail "$BRANCH is behind or has diverged from origin/$BRANCH"
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then fail "tag $TAG exists already"; fi
    if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then fail "release $TAG exists already"; fi
    if [[ "$(gh repo view "$REPO" --json visibility -q .visibility)" != "PUBLIC" ]]; then
        echo "warning: $REPO is private. The release is only visible to people with access, and the"
        echo "         Plugin Manager can't install from it until the repository is public."
    fi
fi

# MARK: Changelog and release notes

step "Release notes from CHANGELOG.md"
rm -rf "$OUT"
mkdir -p "$OUT"
python3 - "$VERSION" "$DATE" "$DRY_RUN" "$OUT/notes.md" "$G3" "$G4" "$ZIP" <<'PY'
import re
import sys

version, date, dry_run, notes_path, g3, g4, zip_name = sys.argv[1:]
path = "CHANGELOG.md"
text = open(path, encoding="utf-8").read()
heading = re.compile(r"^## \[([^\]]+)\].*$", re.M)
sections = list(heading.finditer(text))

def body(index):
    start = sections[index].end()
    end = sections[index + 1].start() if index + 1 < len(sections) else len(text)
    return text[start:end].strip()

found = next((i for i, m in enumerate(sections) if m.group(1) == version), None)
if found is None:
    unreleased = next((i for i, m in enumerate(sections) if m.group(1).lower() == "unreleased"), None)
    if unreleased is None or not body(unreleased):
        sys.exit(f"error: CHANGELOG.md has no [{version}] section and nothing under [Unreleased]")
    notes = body(unreleased)
    if dry_run != "true":
        m = sections[unreleased]
        text = text[:m.start()] + f"## [Unreleased]\n\n## [{version}] — {date}" + text[m.end():]
        open(path, "w", encoding="utf-8").write(text)
        print(f"[Unreleased] is now [{version}] — {date}")
else:
    notes = body(found)

# For GitHub: `### ` headings become `## `, and lines wrapped for reading
# in a text editor are joined again.
blocks, current = [], []
for line in notes.splitlines():
    stripped = line.strip()
    if not stripped:
        if current:
            blocks.append(current)
            current = []
        continue
    starts_item = stripped.startswith(("- ", "* ", "#")) or re.match(r"\d+\. ", stripped)
    if starts_item or not current:
        current.append(stripped)
    else:
        current[-1] += " " + stripped
if current:
    blocks.append(current)
lines = []
for block in blocks:
    block = ["## " + l[4:] if l.startswith("### ") else l for l in block]
    lines.append("\n".join(block))
footer = (
    "## Install\n\n"
    f"Download `{zip_name}` below and unzip it. Double-click `{g3}.glyphsPlugin` for Glyphs 3 "
    f"or `{g4}.glyphsPlugin` for Glyphs 4, restart Glyphs and choose *Window → GitHub Issues*. "
    "Needs macOS 13 or later."
)
open(notes_path, "w", encoding="utf-8").write("\n\n".join(lines + [footer]) + "\n")
PY

# MARK: Build

step "Running the tests"
swift test >"$OUT/test.log" 2>&1 || fail "the tests failed; see $OUT/test.log"

for glyphs in 3 4; do
    name="$G3"
    app="${GLYPHS3_APP:-/Applications/Glyphs 3.app}"
    if [[ "$glyphs" == 4 ]]; then
        name="$G4"
        app="${GLYPHS4_APP:-/Applications/Glyphs 4.app}"
    fi
    step "Building $name.glyphsPlugin"
    GLYPHS="$glyphs" GLYPHS_APP="$app" BUILD_DIR="$OUT" BUNDLE_NAME="$name" PLUGIN_VERSION="$VERSION" \
        ./build.command >"$OUT/build-g$glyphs.log" 2>&1 || fail "the Glyphs $glyphs build failed; see $OUT/build-g$glyphs.log"
    built="$(plutil -extract CFBundleShortVersionString raw "$OUT/$name.glyphsPlugin/Contents/Info.plist")"
    [[ "$built" == "$VERSION" ]] || fail "$name.glyphsPlugin has version $built, not $VERSION"
    codesign --verify --strict "$OUT/$name.glyphsPlugin" || fail "$name.glyphsPlugin isn't signed properly"
done

step "Packaging $ZIP"
(cd "$OUT" && zip -qry "$ZIP" "$G3.glyphsPlugin" "$G4.glyphsPlugin")
unzip -l "$OUT/$ZIP" | tail -1

if $DRY_RUN; then
    step "Dry run done; nothing was committed, tagged, pushed or published"
    echo "Bundles and $ZIP: $OUT"
    echo "Release title:    $TAG – $TITLE"
    echo "Release notes:    $OUT/notes.md"
    echo
    cat "$OUT/notes.md"
    exit 0
fi

# MARK: Commit, tag, push, publish

step "Committing $G3.glyphsPlugin and the changelog"
rm -rf "$DIR/$G3.glyphsPlugin"
cp -R "$OUT/$G3.glyphsPlugin" "$DIR/$G3.glyphsPlugin"
git add CHANGELOG.md "$G3.glyphsPlugin"
git commit -q -m "Cut release $VERSION"
git tag "$TAG"

step "Pushing $BRANCH and $TAG"
git push -q origin "$BRANCH"
git push -q origin "$TAG"

step "Publishing the GitHub release"
gh release create "$TAG" "$OUT/$ZIP" -R "$REPO" --verify-tag --title "$TAG – $TITLE" --notes-file "$OUT/notes.md"
echo
echo "Release:  https://github.com/$REPO/releases/tag/$TAG"
echo "Download: https://github.com/$REPO/releases/latest/download/$ZIP"
