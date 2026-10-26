# Changelog

What changed in each release of the GitHub Issues plugin, newest first.
Versions follow [Semantic Versioning](https://semver.org/). The top
released heading is the bundle's version, and `release.command` turns
the `[Unreleased]` section into the release and its GitHub notes (see
RELEASING.md). Write for people using the plugin: what changed for
them, not how.

## [Unreleased]

The first release: a floating panel in Glyphs 3 and Glyphs 4 that shows
the GitHub issues of the font you're working on, and lets you comment
on, close, reopen, edit, label, assign and create them without leaving Glyphs.

### Added

- **The current font's issues.** *Window → GitHub Issues* finds the
  font's git repository and its GitHub remote and lists the open and
  closed issues, with search, a *Current glyph* filter for issues that
  mention the glyph you're editing, its variants, or glyphs that use it
  as a component, and a menu to filter by label, assignee and milestone
  and to sort as on GitHub (newest, recently updated, most commented …).
- **A palette or a split view.** Narrow, the panel is a compact
  palette; wide, the list and the open issue sit side by side.
- **Glyphs in issues.** Glyph names mentioned in an issue (`/a`, or
  plain title words) show as outlines and open in an Edit tab;
  images show in the text.
- **Activity.** Comments and history – closed, reopened, labelled,
  assigned, referenced – in time order.
- **Comment, close, reopen, create.** A comment box (⌘↩ to post),
  *Close with comment*, a button that adds the selected glyphs' names,
  images pasted or dropped in and uploaded to GitHub, and a form for
  new issues with labels. Your comments – or anyone's, with write
  access – can be edited in place or deleted.
- **Edit, label, assign, delete.** An issue's *⋯* menu edits its title
  and description in place, changes its labels, assignees and
  milestone, and deletes it, as far as GitHub lets you: your own
  issues, or anyone's with write access; labels and assignees with
  triage access; milestones with write access; deleting with admin
  access. Assignees and milestones also show in the list and above
  each issue.
- **Links as on GitHub.** `#12`, commit SHAs, `@people` and web
  addresses in issues and comments are links; links to issues and
  commits are shortened (`#12`, `a5c3785`), and the repository's
  issues open in the panel.
- **Suggestions while typing.** `@` suggests people, `#` issues and
  `/` glyph names from the font, with their outlines.
- **Keyboard.** Tab goes round the list and every control, ↑ ↓ and
  Return open issues, Esc steps back out, and ⌘F, ⌘N, ⌘R and ⇧⌘↩
  search, create, refresh and close; Cycle Through Windows reaches the
  panel.
- **Sign-in** with a token kept in the Keychain, or an existing `gh`
  login.
