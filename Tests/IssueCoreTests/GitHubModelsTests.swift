import XCTest
@testable import IssueCore

final class GitHubModelsTests: XCTestCase {

    func testDecodesIssuesAndFlagsPullRequests() throws {
        let json = """
        [
          {
            "id": 1, "number": 39, "title": "Dieresis clashes with descenders",
            "body": "Dots on /adieresis", "body_html": "<p>Dots on /adieresis</p>",
            "state": "open", "state_reason": null,
            "user": {"login": "mkoch", "avatar_url": "https://avatars.githubusercontent.com/u/1", "html_url": "https://github.com/mkoch"},
            "labels": [{"id": 7, "name": "diacritics", "color": "d4c5f9", "description": null}],
            "comments": 4,
            "created_at": "2026-10-14T09:12:00Z", "updated_at": "2026-10-16T18:40:11Z", "closed_at": null,
            "html_url": "https://github.com/acme-type/halden-sans/issues/39"
          },
          {
            "id": 2, "number": 40, "title": "Fix kerning", "body": null, "state": "closed", "state_reason": "completed",
            "user": null, "labels": [], "comments": 0,
            "created_at": "2026-10-15T09:12:00Z", "updated_at": "2026-10-15T10:00:00Z", "closed_at": "2026-10-15T10:00:00Z",
            "html_url": "https://github.com/acme-type/halden-sans/pull/40",
            "pull_request": {"url": "https://api.github.com/repos/acme-type/halden-sans/pulls/40"}
          }
        ]
        """
        let issues = try JSONDecoder.gitHub.decode([GitHubIssue].self, from: Data(json.utf8))
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0].number, 39)
        XCTAssertTrue(issues[0].isOpen)
        XCTAssertFalse(issues[0].isPullRequest)
        XCTAssertEqual(issues[0].labels.first?.name, "diacritics")
        XCTAssertEqual(issues[0].user?.login, "mkoch")
        XCTAssertEqual(issues[0].bodyHTML, "<p>Dots on /adieresis</p>")
        XCTAssertTrue(issues[1].isPullRequest)
        XCTAssertFalse(issues[1].isOpen)
    }

    func testNextPageLink() {
        let header = #"<https://api.github.com/repositories/1/issues?page=2&per_page=100>; rel="next", <https://api.github.com/repositories/1/issues?page=5&per_page=100>; rel="last""#
        XCTAssertEqual(
            GitHubClient.nextPageURL(fromLinkHeader: header)?.absoluteString,
            "https://api.github.com/repositories/1/issues?page=2&per_page=100"
        )
        XCTAssertNil(GitHubClient.nextPageURL(fromLinkHeader: #"<https://api.github.com/x?page=1>; rel="prev""#))
        XCTAssertNil(GitHubClient.nextPageURL(fromLinkHeader: nil))
    }
}
