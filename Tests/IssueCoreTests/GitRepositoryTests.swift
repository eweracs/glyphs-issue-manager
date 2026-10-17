import XCTest
@testable import IssueCore

final class GitHubRepoTests: XCTestCase {

    func testParsesRemoteURLForms() {
        let expected = GitHubRepo(owner: "acme-type", name: "halden-sans")
        let forms = [
            "git@github.com:acme-type/halden-sans.git",
            "git@github.com:acme-type/halden-sans",
            "ssh://git@github.com/acme-type/halden-sans.git",
            "ssh://git@ssh.github.com:443/acme-type/halden-sans.git",
            "https://github.com/acme-type/halden-sans",
            "https://github.com/acme-type/halden-sans.git",
            "https://github.com/acme-type/halden-sans/",
            "https://token@github.com/acme-type/halden-sans.git",
            "git@github-work:acme-type/halden-sans.git",
            "git@github.com-work:acme-type/halden-sans.git",
        ]
        for form in forms {
            XCTAssertEqual(GitHubRepo(remoteURL: form), expected, form)
        }
    }

    func testRejectsOtherHosts() {
        XCTAssertNil(GitHubRepo(remoteURL: "git@gitlab.com:acme/font.git"))
        XCTAssertNil(GitHubRepo(remoteURL: "https://bitbucket.org/acme/font"))
        XCTAssertNil(GitHubRepo(remoteURL: "https://github.example.com/acme/font"))
        XCTAssertNil(GitHubRepo(remoteURL: "/Users/me/fonts/halden.git"))
        XCTAssertNil(GitHubRepo(remoteURL: "https://github.com/acme"))
    }

    func testParsesShorthand() {
        XCTAssertEqual(GitHubRepo(string: " acme-type/halden-sans "), GitHubRepo(owner: "acme-type", name: "halden-sans"))
        XCTAssertEqual(GitHubRepo(string: "https://github.com/acme-type/halden-sans/issues/12"), GitHubRepo(owner: "acme-type", name: "halden-sans"))
        XCTAssertNil(GitHubRepo(string: "halden-sans"))
        XCTAssertNil(GitHubRepo(string: "a/b/c"))
        XCTAssertNil(GitHubRepo(string: "acme type/halden"))
    }

    func testURLs() {
        let repo = GitHubRepo(owner: "acme-type", name: "halden-sans")
        XCTAssertEqual(repo.issuesURL.absoluteString, "https://github.com/acme-type/halden-sans/issues")
        XCTAssertEqual(repo.newIssueURL.absoluteString, "https://github.com/acme-type/halden-sans/issues/new")
    }
}

final class GitRepositoryTests: XCTestCase {

    func testParsesRemotesInOrder() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/original/halden-sans.git
        \tfetch = +refs/heads/*:refs/remotes/upstream/*
        [remote "origin"]
        \turl = git@github.com:me/halden-sans.git
        [branch "main"]
        \tremote = origin
        """
        let remotes = GitRepository.parseRemotes(config: config)
        XCTAssertEqual(remotes.map(\.name), ["upstream", "origin"])
        XCTAssertEqual(remotes.last?.url, "git@github.com:me/halden-sans.git")
    }

    func testParsesHEAD() {
        XCTAssertEqual(GitRepository.parseHEAD("ref: refs/heads/main\n"), "main")
        XCTAssertEqual(GitRepository.parseHEAD("ref: refs/heads/feature/kerning\n"), "feature/kerning")
        XCTAssertEqual(GitRepository.parseHEAD("3f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49\n"), "3f2a9c1")
    }

    func testPrefersOriginThenUpstream() throws {
        let repo = GitRepository(
            workTree: URL(fileURLWithPath: "/tmp"), gitDir: URL(fileURLWithPath: "/tmp/.git"),
            commonDir: URL(fileURLWithPath: "/tmp/.git"),
            remotes: [
                .init(name: "backup", url: "git@gitlab.com:me/x.git"),
                .init(name: "upstream", url: "https://github.com/original/x"),
                .init(name: "origin", url: "https://github.com/me/x"),
            ],
            branch: "main"
        )
        XCTAssertEqual(repo.gitHubRemote?.repo, GitHubRepo(owner: "me", name: "x"))

        let noOrigin = GitRepository(
            workTree: repo.workTree, gitDir: repo.gitDir, commonDir: repo.commonDir,
            remotes: [.init(name: "mirror", url: "https://github.com/m/x"), .init(name: "upstream", url: "https://github.com/original/x")],
            branch: nil
        )
        XCTAssertEqual(noOrigin.gitHubRemote?.repo, GitHubRepo(owner: "original", name: "x"))
    }

    func testLocatesRepositoryAboveFontFile() throws {
        let root = try makeTempDir()
        try write("[remote \"origin\"]\n\turl = git@github.com:acme-type/halden-sans.git\n", to: root.appendingPathComponent(".git/config"))
        try write("ref: refs/heads/main\n", to: root.appendingPathComponent(".git/HEAD"))
        let package = root.appendingPathComponent("sources/Halden Sans.glyphspackage")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        let repo = try XCTUnwrap(GitRepository.locate(containing: package))
        XCTAssertEqual(repo.workTree.standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertEqual(repo.branch, "main")
        XCTAssertEqual(repo.gitHubRemote?.repo, GitHubRepo(owner: "acme-type", name: "halden-sans"))
    }

    func testLocatesLinkedWorktree() throws {
        let main = try makeTempDir()
        try write("[remote \"origin\"]\n\turl = https://github.com/acme-type/halden-sans\n", to: main.appendingPathComponent(".git/config"))
        try write("ref: refs/heads/main\n", to: main.appendingPathComponent(".git/HEAD"))
        let worktreeGitDir = main.appendingPathComponent(".git/worktrees/kerning")
        try write("ref: refs/heads/kerning\n", to: worktreeGitDir.appendingPathComponent("HEAD"))
        try write("../..\n", to: worktreeGitDir.appendingPathComponent("commondir"))

        let worktree = try makeTempDir()
        try write("gitdir: \(worktreeGitDir.path)\n", to: worktree.appendingPathComponent(".git"))
        let font = worktree.appendingPathComponent("Halden.glyphs")
        try write("{}", to: font)

        let repo = try XCTUnwrap(GitRepository.locate(containing: font))
        XCTAssertEqual(repo.branch, "kerning")
        XCTAssertEqual(repo.gitHubRemote?.repo, GitHubRepo(owner: "acme-type", name: "halden-sans"))
    }

    func testReturnsNilOutsideRepository() throws {
        let dir = try makeTempDir()
        let font = dir.appendingPathComponent("Loose.glyphs")
        try write("{}", to: font)
        // The temp directory may itself sit inside a repository on some setups;
        // only assert when it doesn't.
        if let repo = GitRepository.locate(containing: font) {
            XCTAssertFalse(repo.workTree.path.hasPrefix(dir.path))
        }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IssueCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
