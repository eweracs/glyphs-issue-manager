# Releasing

Each release is a `vX.Y.Z` tag plus a [GitHub release](https://github.com/eweracs/glyphs-issue-manager/releases)
with `GitHubIssues.zip` attached. The zip holds two bundles, built from the
same sources against each Glyphs version's headers:

- `GitHubIssuesG3.glyphsPlugin` for Glyphs 3
- `GitHubIssuesG4.glyphsPlugin` for Glyphs 4 (built with `GLYPHS4` defined;
  see `Plugin/GlyphsCompat.swift`)

The Glyphs 3 bundle is also committed at the top of the repository, because
the Glyphs 3 Plugin Manager installs by cloning the repository. The Glyphs 4
Plugin Manager instead downloads the zip from the latest release (see
[Plugin Manager](#plugin-manager) below).

## What you need

- Glyphs 3 and Glyphs 4 in /Applications (or set `GLYPHS3_APP` and
  `GLYPHS4_APP`), for their headers.
- The GitHub CLI, `gh`, signed in to an account that can push to the
  repository.
- A clean checkout of `master`. Only `CHANGELOG.md` may have changes.

## Cutting a release

1. **Pick the version.** Use [SemVer](https://semver.org/) from the last tag
   (`git tag --sort=-v:refname | head -1`). Bump the patch for fixes, the
   minor for anything new users notice, and the major for changes that would
   surprise them.

2. **Write the notes** under `## [Unreleased]` in `CHANGELOG.md`. Start with a
   short paragraph, then use `### Fixed`, `### Changed` and `### Added`, in
   that order and only the ones that apply. Write for people using the
   plugin: a bold lead-in per entry and a sentence or two, without file or
   function names. Wrap at about 70 characters; the script joins the lines
   again for GitHub. Ideally each user-visible change adds its entry in the
   commit that makes it.

3. **Try it:**

   ```bash
   ./release.command X.Y.Z "Short title" --dry-run
   ```

   This runs the tests, builds both bundles into `build/Release/`, packs
   `GitHubIssues.zip` and prints the release notes. It doesn't change
   anything in the repository.

4. **Release:**

   ```bash
   ./release.command X.Y.Z "Short title"
   ```

   The script:

   1. Renames `## [Unreleased]` to `## [X.Y.Z] — YYYY-MM-DD` and adds a fresh,
      empty `## [Unreleased]` above it. If a `## [X.Y.Z]` section already
      exists, it uses that one instead.
   2. Runs the tests and builds both bundles. It checks that each carries
      version X.Y.Z and is properly signed (ad hoc).
   3. Copies `GitHubIssuesG3.glyphsPlugin` to the top of the repository and
      commits it with the changelog as `Cut release X.Y.Z`.
   4. Tags `vX.Y.Z` and pushes `master` and the tag.
   5. Creates the release `vX.Y.Z – Short title` with the notes and the zip.

   Before it starts, the script refuses to run in any of these cases:
   - the tag or the release already exists;
   - `master` is behind `origin/master`;
   - there are changes other than `CHANGELOG.md`;
   - `gh` isn't signed in.

   It warns when the repository is private.

5. **Check** `gh release view vX.Y.Z`. The title, the notes and the
   `GitHubIssues.zip` asset should be there.

The bundle's version (`CFBundleShortVersionString`) comes from the top
released heading in `CHANGELOG.md`; `build.command` stamps it, so don't edit
the `0.1` in `Plugin/Info.plist`. `CFBundleVersion` is the number of commits.
Builds between releases carry the last released version.

## When something goes wrong

- **A build failed.** The script names the log in `build/Release/`. Fix the
  problem and run it again. Nothing has been committed at that point; the
  renamed changelog section is reused.
- **Pushed, but no release.** The commit and the tag exist, so the script
  refuses to run again. Publish by hand, from the bundles it built:

  ```bash
  gh release create vX.Y.Z build/Release/GitHubIssues.zip \
    --verify-tag --title "vX.Y.Z – Short title" --notes-file build/Release/notes.md
  ```

- **The release is wrong.** Edit it in place
  (`gh release edit vX.Y.Z --notes-file …`, or
  `gh release upload vX.Y.Z build/Release/GitHubIssues.zip --clobber`), or
  delete it (`gh release delete vX.Y.Z --yes`) and publish by hand as above.

## Plugin Manager

The plugin isn't listed yet. To list it, add two entries to `packages.plist`
in [glyphs-packages](https://github.com/schriftgestalt/glyphs-packages), at
the end of `plugins = ( … )`, one per Glyphs version:

```
{
	titles = {
		en = "GitHub Issues";
	};
	url = "https://github.com/eweracs/glyphs-issue-manager";
	path = "GitHubIssuesG3.glyphsPlugin";
	descriptions = {
		en = "*Window > GitHub Issues* shows the GitHub issues of the current font’s repository in a floating panel. Filter them by the glyph you are editing, open the glyphs they mention, and comment on, close, create and edit issues, and add labels, assignees and milestones.";
	};
	screenshot = "https://raw.githubusercontent.com/eweracs/glyphs-issue-manager/master/Images/Screenshot.png";
	minGlyphsVersion = "3.5";
	maxVersion = "3799";
	minSystemVersion = "13.0";
},
{
	titles = {
		en = "GitHub Issues";
	};
	url = "https://github.com/eweracs/glyphs-issue-manager";
	archiveURL = "https://github.com/eweracs/glyphs-issue-manager/releases/latest/download/GitHubIssues.zip";
	path = "GitHubIssuesG4.glyphsPlugin";
	descriptions = {
		en = "*Window > GitHub Issues* shows the GitHub issues of the current font’s repository in a floating panel. Filter them by the glyph you are editing, open the glyphs they mention, and comment on, close, create and edit issues, and add labels, assignees and milestones.";
	};
	screenshot = "https://raw.githubusercontent.com/eweracs/glyphs-issue-manager/master/Images/Screenshot.png";
	minVersion = "4000";
	minSystemVersion = "13.0";
},
```

Before listing:

- The repository has to be **public**. The Glyphs 3 Plugin Manager clones it,
  and the Glyphs 4 one downloads the release asset without signing in.
- At least one release has to be cut, so that `GitHubIssuesG3.glyphsPlugin`
  is on `master` and `releases/latest/download/GitHubIssues.zip` exists.
- `minGlyphsVersion = "3.5"` is the oldest Glyphs 3 the plugin has run in
  (3.5.1). Lower it only after trying an older version. The Glyphs 4 build
  is compiled against 4.1.1 (build 4108) and should be tried in Glyphs 4
  before listing.
- The screenshot is `Images/Screenshot.png` on `master`, with a capital I:
  the URL is case-sensitive. Moving or renaming it breaks the entries.
- Optionally add `identifier = "github-issues";` for a short deep link
  (`glyphsapp3://showplugin/github-issues`).

Once listed, nothing changes per release. Both Plugin Managers pick up the
latest one: Glyphs 3 through the bundle on `master`, Glyphs 4 through the
latest release's zip. If a bundle name, the zip's name or layout, or the
repository's URL ever changes, the index entries have to change with it.
Then mention the Plugin Manager in the install text at the end of the notes
in `release.command`.
