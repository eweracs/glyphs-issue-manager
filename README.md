# GitHub Issues for Glyphs

A Swift plugin for Glyphs 3 that shows the GitHub issues of the font you're
working on in a floating panel. Open it with **Window → GitHub Issues**.

- **Finds the repository by itself.** It walks up from the font file
  (`.glyphs` or `.glyphspackage`) to the enclosing git repository and reads its
  GitHub remote (`origin`, then `upstream`, then any GitHub remote). Linked
  worktrees and SSH host aliases (`git@github-work:…`) work. If the font isn't
  in a GitHub repository, choose one by hand; it is remembered per font file.
- **Floats while you draw.** The panel stays above the font windows, hides when
  Glyphs is in the background, and remembers its size and position.
- **Adapts to its width.** Narrow, it is a compact palette: the list, and a
  detail view you open and close with the back button (or Escape). From 780 pt
  wide, list and detail sit side by side.
- **Knows about glyphs.** Glyph names in an issue become chips in the list and
  outline cells in the detail, drawn from your font in the current master.
  Click one to open it in a new Edit tab. Names count when they are
  - written in slash notation anywhere (`/adieresis`, `/T/o`, `/a.ss01`), or
  - plain words in the title that are glyph names in the font ("k wider",
    "N contrast", "Dieresiscomb too small").

  Only names that exist in the font count.
- **Current glyph filter.** Shows only issues about the glyph you're editing:
  issues that mention it, one of its variants (`a.ss01` for `a`), or a glyph
  that uses it as a component (`adieresis` for `a`).
- **Search, labels, open/closed.** Search matches titles, bodies, labels and
  numbers (`#12`); start with `/` to search for mentioned glyphs.
- **New activity.** A dot marks issues that changed since you last opened them
  in the panel.
- **Bodies and comments** render the markdown issues usually contain: headings,
  lists, task lists, quotes, code and images. Images use the signed URLs that
  GitHub includes with each issue.

- **Activity.** Under each issue, its comments and history in time order,
  on a rail: closed (as completed or not planned, or in a commit), reopened,
  labels, assignees, milestones, title changes, commits that reference the
  issue (with their messages), and mentions in other issues and pull
  requests. Changes one person makes together become one line; runs of more
  than six events collapse behind **Show n more events**; **All | Comments**
  hides the events.
- **Step through issues.** **‹ #9 ›** above an issue (or ⌥⌘← and ⌥⌘→) goes
  to the issue numbered just below or above, open or closed, whatever the
  filters. In the split view, ↑ and ↓ go to the issue above or below in the
  list, as filtered (except while you type in a field).
- **Close and reopen issues.** **Close issue** closes as completed; its menu
  also offers **Close as Not Planned**, as on GitHub. Closed issues show
  **Reopen issue**. In the compact palette the button sits in the bar at the
  bottom of an issue, in the split view next to **Open on GitHub**, and both
  are in a row's context menu.
- **Comment.** A comment box under each issue (in the compact palette's
  bottom bar; at the end of the activity in the split view). **Comment** or
  ⌘↩ posts it; with text in the box, closing becomes **Close with comment**
  (and **Reopen with comment**), as on GitHub. The glyph button adds the
  current glyph's name, e.g. `/a`, or all selected glyphs', e.g.
  `/Aring/Aacute/Abreve`. Unsent comments are kept per issue while Glyphs
  runs.
- **Images.** Paste an image (a screenshot, an image file copied in Finder)
  into a comment or a new issue's description, or drop one in. It uploads to
  GitHub as when pasted on the website: `![Uploading image.png…]()` stands in
  until it is up, then becomes `![image](https://github.com/user-attachments/…)`.
  PNG, JPEG, GIF, WebP and SVG go up as they are, other image types as PNG,
  up to 10 MB each. Posting waits until the uploads are done.
- **New issues.** The compose button in the title bar (or **New Issue…** in
  the repository menu) opens a form for title, description and labels;
  **Create issue** or ⌘↩ files it and opens it. **Cancel** keeps what you
  typed for next time.

Commenting, closing, creating and adding images need a sign-in (see below). Editing labels
of existing issues happens on GitHub (**Open on GitHub**).

## Signing in

Public repositories work without signing in, within GitHub's limit of 60
requests an hour. For private repositories, or to raise that limit, the plugin
uses, in this order:

1. a token you pasted (**Paste Token…**), stored in your Keychain, or
2. your existing `gh` CLI login (`gh auth token`), if `gh` is installed.

A fine-grained token with read-only access to **Issues** for your font
repositories is enough to read them; to comment, close, reopen and create issues it needs
**Issues: Read and write** (a classic token needs the `repo` scope; a `gh`
login has it). Adding images needs write access to the repository itself, as
on GitHub. **Sign Out** removes the saved token and stops using
the `gh` login until you choose **Use gh CLI Login** again. Responses are
cached by ETag, so refreshes that find nothing new don't use up the limit.
Issues refresh every five minutes while the panel is open, and when you return
to the panel after a minute or more.

## Build & install

Requirements: Glyphs 3 (for `GlyphsCore.framework`), Xcode or the Xcode
command-line tools, macOS 13 or later.

```sh
./build.command            # builds build/GitHubIssues.glyphsPlugin
./build.command install    # …and copies it into the Glyphs 3 Plugins folder
```

Restart Glyphs after installing. `GLYPHS_APP`, `GLYPHS_PLUGINS` and `ARCHS`
override the Glyphs app to compile against, the Plugins folder to install to,
and the architectures to build (default `arm64 x86_64`).

## Layout of the code

```
Sources/IssueCore/   platform-independent, unit-tested with `swift test`
  GitRepository.swift   finds the repository and its GitHub remote from .git files
  GitHubClient.swift    REST client: issues, timeline, comments, create/close/reopen, image uploads, ETags
  ImageAttachment.swift an image to upload: type, size limit, markdown, placeholder
  GitHubModels.swift    issue, comment, label and user models
  Timeline.swift        timeline entries → activity items, merging, collapsing
  GlyphMentions.swift   glyph names in issue text; relation to the current glyph
  MarkdownBlocks.swift  block-level markdown parsing for issue bodies
Plugin/              the Glyphs plugin (AppKit, SwiftUI, GlyphsCore)
  GitHubIssuesPlugin.swift    principal class, Window menu item
  IssuesPanelController.swift the floating NSPanel
  IssuesModel.swift           state: font, repository, issues, filters, selection
  GlyphsContext.swift         current font, glyph and master; outlines; Edit tabs
  TokenStore.swift            Keychain and gh CLI tokens
  Views/                      SwiftUI views
Tests/IssueCoreTests/
```

`build.command` compiles `Sources/IssueCore` and `Plugin` together with `swiftc`
against the GlyphsCore headers inside Glyphs.app and links with
`-undefined dynamic_lookup`; SwiftPM is only used to test the core.

## Limitations

- github.com only; GitHub Enterprise remotes aren't recognised.
- Images upload through the endpoint `gh issue comment --attach` uses
  (`uploads.github.com/user-attachments/assets`); GitHub documents the `gh`
  flag, not the endpoint itself. Videos can't be added from the panel.
- Loads up to 1,000 issues per repository (pull requests are left out).
- GitHub's REST timeline doesn't say which pull request closed an issue, or
  which issue a duplicate points to. The pull request shows as its own
  “mentioned this in” line; the duplicate line has no number.
- Glyphs posts no notification for selection changes, so the current glyph is
  polled while the panel is open, a few times a second.
- Built against Glyphs 3.5. Glyphs 4 is untested.
