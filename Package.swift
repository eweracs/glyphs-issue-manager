// swift-tools-version:5.9
import PackageDescription

// SwiftPM is used ONLY for the platform-independent core (git remote detection,
// the GitHub API client, glyph-name parsing, markdown blocks) so it can be
// unit-tested without launching Glyphs.
//
// The actual Glyphs plugin bundle (`GitHubIssues.glyphsPlugin`) is built by
// `build.command`, which compiles these same `IssueCore` sources together with
// the AppKit/SwiftUI/GlyphsCore-dependent sources in `Plugin/`.
let package = Package(
    name: "GlyphsIssueManager",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "IssueCore"),
        .testTarget(
            name: "IssueCoreTests",
            dependencies: ["IssueCore"]
        ),
    ]
)
