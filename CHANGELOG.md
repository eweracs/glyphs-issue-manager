# Changelog

What changed in each release of the GitHub Issues plugin, newest first.
Versions follow [Semantic Versioning](https://semver.org/). The top
released heading is the bundle's version, and `release.command` turns
the `[Unreleased]` section into the release and its GitHub notes (see
RELEASING.md). Write for people using the plugin: what changed for
them, not how.

## [Unreleased]

## [0.1.0] — 2026-10-26

Initial release. A floating panel in Glyphs that shows the GitHub issues
of the current font and allows issue management without leaving Glyphs.

### Added

- **The current font's issues.** *Window → GitHub Issues* finds the
  font's git repository and its GitHub remote and lists the open and
  closed issues, with search, a *Current glyph* filter for issues that
  mention the current glyph, its variants, or glyphs that use it as a
  component, and a menu to filter by label, assignee and milestone and
  to sort as on GitHub (newest, recently updated, most commented …).
- **Glyphs in issues.** Glyph names mentioned in an issue (`/a`, or
  plain title words) show as outlines and open in an Edit tab.
- **Activity.** Comments and history of the issues, as a timeline.
- **Comment, close, reopen, create.** A comment box (⌘↩ to post), *Close
  with comment*, a button that adds the selected glyphs' names, images
  pasted or dropped in and uploaded to GitHub and a form for new issues
  with labels.
- **Edit, label, assign, delete.** Access additional options through an
  issue's *⋯* menu.
- **Suggestions while typing.** `@` suggests people, `#` issues and `/`
  glyph names from the font, with their outlines.
- **Sign-in** with a token kept in the Keychain, or an existing `gh`
  login.
