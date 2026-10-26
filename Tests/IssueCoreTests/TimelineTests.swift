import XCTest
@testable import IssueCore

final class TimelineTests: XCTestCase {

    // A timeline in GitHub's shape, including entries the thread leaves out
    // and one that doesn't decode.
    private let json = """
    [
      {"event": "labeled", "id": 1, "actor": {"login": "mkoch"}, "created_at": "2026-10-14T09:00:00Z",
       "label": {"name": "diacritics", "color": "d4c5f9"}},
      {"event": "labeled", "id": 2, "actor": {"login": "mkoch"}, "created_at": "2026-10-14T09:00:05Z",
       "label": {"name": "Display", "color": "ededed"}},
      {"event": "assigned", "id": 3, "actor": {"login": "mkoch"}, "created_at": "2026-10-14T09:00:09Z",
       "assignee": {"login": "lina-s"}},
      {"event": "subscribed", "id": 4, "actor": {"login": "mkoch"}, "created_at": "2026-10-14T09:00:10Z"},
      {"event": "renamed", "id": 5, "actor": {"login": "mkoch"}, "created_at": "2026-10-14T09:30:00Z",
       "rename": {"from": "Dieresis too high in Black", "to": "Dieresis clashes with descenders"}},
      {"event": "commented", "id": 6, "actor": {"login": "lina-s"}, "user": {"login": "lina-s"},
       "created_at": "2026-10-15T10:00:00Z", "body": "Lowering by 20 units fixes it.", "body_html": "<p>Lowering by 20 units fixes it.</p>",
       "html_url": "https://github.com/acme-type/halden-sans/issues/39#issuecomment-6"},
      {"event": "referenced", "id": 7, "actor": {"login": "lina-s"}, "created_at": "2026-10-15T11:00:00Z",
       "commit_id": "4f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49",
       "commit_url": "https://api.github.com/repos/acme-type/halden-sans/commits/4f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49"},
      {"event": "referenced", "id": 8, "actor": {"login": "lina-s"}, "created_at": "2026-10-15T11:05:00Z",
       "commit_id": "4f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49", "commit_url": null},
      {"event": "closed", "id": 9, "actor": {"login": "lina-s"}, "created_at": "2026-10-16T08:00:00Z",
       "state_reason": null, "commit_id": "4f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49",
       "commit_url": "https://api.github.com/repos/acme-type/halden-sans/commits/4f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49"},
      {"event": "reopened", "id": 10, "actor": {"login": "mkoch"}, "created_at": "2026-10-16T09:00:00Z", "state_reason": "reopened"},
      {"event": "cross-referenced", "actor": {"login": "thao-ng"}, "created_at": "2026-10-17T12:00:00Z",
       "source": {"type": "issue", "issue": {"number": 37, "title": "Add Vietnamese support", "state": "open",
                  "html_url": "https://github.com/acme-type/halden-sans/issues/37",
                  "repository": {"full_name": "acme-type/halden-sans"}}}},
      {"event": "closed", "id": 11, "actor": {"login": "mkoch"}, "created_at": "2026-10-17T13:00:00Z", "state_reason": "not_planned"},
      {"event": "commented", "id": "not-a-number", "created_at": 42}
    ]
    """

    private func entries() throws -> [TimelineEntry] {
        try JSONDecoder.gitHub.decode([Lenient<TimelineEntry>].self, from: Data(json.utf8)).compactMap(\.value)
    }

    func testDecodesLenientlyAndBuildsItemsInOrder() throws {
        let entries = try entries()
        XCTAssertEqual(entries.count, 12, "the malformed entry is skipped")

        let items = ActivityBuilder.items(from: entries)
        let kinds: [String] = items.map { item in
            switch item {
            case .comment: return "comment"
            case .event(let event):
                switch event.kind {
                case .changes: return "changes"
                case .renamed: return "renamed"
                case .referenced: return "referenced"
                case .closed(let notPlanned, _): return notPlanned ? "closed-not-planned" : "closed"
                case .reopened: return "reopened"
                case .crossReferenced: return "cross-referenced"
                case .markedDuplicate: return "duplicate"
                }
            }
        }
        // `subscribed` is left out; the second reference to the same commit too.
        XCTAssertEqual(kinds, ["changes", "renamed", "comment", "referenced", "closed", "reopened", "cross-referenced", "closed-not-planned"])

        guard case .comment(let comment) = items[2] else { return XCTFail("expected the comment third") }
        XCTAssertEqual(comment.commentID, 6, "the comment keeps GitHub's id, for editing and deleting")
    }

    func testMergesChangesBySamePersonInWindow() throws {
        let items = ActivityBuilder.items(from: try entries())
        guard case .event(let first) = items[0], case .changes(let changes) = first.kind else {
            return XCTFail("expected merged changes first")
        }
        XCTAssertEqual(first.actor, "mkoch")
        XCTAssertEqual(changes, [
            .addedLabel(TimelineLabel(name: "diacritics", color: "d4c5f9")),
            .addedLabel(TimelineLabel(name: "Display", color: "ededed")),
            .assigned("lina-s"),
        ])
    }

    func testClosedInCommitAndCommitURL() throws {
        let items = ActivityBuilder.items(from: try entries())
        let closed = items.compactMap { item -> CommitRef?? in
            if case .event(let event) = item, case .closed(false, let commit) = event.kind { return commit }
            return nil
        }.first
        let commit = try XCTUnwrap(closed ?? nil)
        XCTAssertEqual(commit.shortSHA, "4f2a9c1")
        XCTAssertEqual(commit.webURL?.absoluteString, "https://github.com/acme-type/halden-sans/commit/4f2a9c1d0e8b7a6f5e4d3c2b1a0f9e8d7c6b5a49")
    }

    func testCrossReference() throws {
        let items = ActivityBuilder.items(from: try entries())
        let ref = items.compactMap { item -> IssueRef? in
            if case .event(let event) = item, case .crossReferenced(let ref) = event.kind { return ref }
            return nil
        }.first
        XCTAssertEqual(ref?.number, 37)
        XCTAssertEqual(ref?.isPullRequest, false)
        XCTAssertEqual(ref?.isOpen, true)
    }

    func testSelfAssignmentAndSeparateGroups() {
        let entries = [
            entry("assigned", actor: "lina-s", at: 0, assignee: "lina-s"),
            entry("labeled", actor: "mkoch", at: 10, label: "bug"),
            entry("labeled", actor: "mkoch", at: 1000, label: "kerning"),
        ]
        let items = ActivityBuilder.items(from: entries)
        XCTAssertEqual(items.count, 3, "different person, then outside the window")
        guard case .event(let first) = items[0] else { return XCTFail() }
        XCTAssertEqual(first.kind, .changes([.selfAssigned]))
    }

    func testLabelAddedAndRemovedCancels() {
        let entries = [
            entry("labeled", actor: "mkoch", at: 0, label: "bug"),
            entry("unlabeled", actor: "mkoch", at: 20, label: "bug"),
            entry("commented", actor: "mkoch", at: 30),
        ]
        let items = ActivityBuilder.items(from: entries)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isComment)
    }

    func testRowsFilterAndCollapseLongRuns() {
        let events = (0..<8).map { i in entry("labeled", actor: "user\(i)", at: Double(i) * 1000, label: "l\(i)") }
        let items = ActivityBuilder.items(from: [entry("commented", actor: "a", at: -10)] + events)
        XCTAssertEqual(items.count, 9)

        let collapsed = ActivityBuilder.rows(for: items, showEvents: true, expandedRuns: [])
        XCTAssertEqual(collapsed.count, 1 + 2 + 1 + 2)
        guard case .more(let runID, let count) = collapsed[3] else { return XCTFail("expected a more row") }
        XCTAssertEqual(count, 4)

        let expanded = ActivityBuilder.rows(for: items, showEvents: true, expandedRuns: [runID])
        XCTAssertEqual(expanded.count, 9)

        let commentsOnly = ActivityBuilder.rows(for: items, showEvents: false, expandedRuns: [])
        XCTAssertEqual(commentsOnly.count, 1)
    }

    // MARK: - Helpers

    private func entry(_ event: String, actor: String, at seconds: Double, assignee: String? = nil, label: String? = nil) -> TimelineEntry {
        var object: [String: Any] = [
            "event": event,
            "id": Int.random(in: 1...1_000_000),
            "actor": ["login": actor],
            "created_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_000_000 + seconds)),
        ]
        if let assignee { object["assignee"] = ["login": assignee] }
        if let label { object["label"] = ["name": label, "color": "ededed"] }
        if event == "commented" { object["user"] = ["login": actor]; object["body"] = "Hi" }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder.gitHub.decode(TimelineEntry.self, from: data)
    }
}
