import XCTest
@testable import IssueCore

final class ReferencesTests: XCTestCase {

    private let repo = GitHubRepo(owner: "acme-type", name: "halden-sans")
    private let sha = "a5c3785ed8d6a35868bc169f07e40e889087fd2e"

    private func found(_ text: String, linked: References.Linked? = nil) -> [(String, String, String)] {
        let string = text as NSString
        return References.find(in: text, repo: repo, linked: linked).map {
            (string.substring(with: $0.range), $0.display, $0.url.absoluteString)
        }
    }

    func testIssueNumbers() {
        let result = found("Same as #12 and GH-7, see acme-type/other#4. Not C#12, &#123; or a#1.")
        XCTAssertEqual(result.map(\.0), ["#12", "GH-7", "acme-type/other#4"])
        XCTAssertEqual(result.map(\.2), [
            "https://github.com/acme-type/halden-sans/issues/12",
            "https://github.com/acme-type/halden-sans/issues/7",
            "https://github.com/acme-type/other/issues/4",
        ])
    }

    func testIssueLinksAreShortened() {
        let result = found("""
        Before https://github.com/acme-type/halden-sans/issues/12 and \
        https://github.com/acme-type/halden-sans/issues/12#issuecomment-99, \
        (https://github.com/acme-type/other/pull/4).
        """)
        XCTAssertEqual(result.map(\.1), ["#12", "#12 (comment)", "acme-type/other#4"])
        XCTAssertEqual(result.last?.0, "https://github.com/acme-type/other/pull/4", "without the closing bracket and full stop")
    }

    func testCommitsAreShortened() {
        let result = found("Fixed in \(sha), https://github.com/acme-type/halden-sans/commit/\(sha) and acme-type/other@\(sha).")
        XCTAssertEqual(result.map(\.1), ["a5c3785", "a5c3785", "acme-type/other@a5c3785"])
        XCTAssertEqual(result.first?.2, "https://github.com/acme-type/halden-sans/commit/\(sha)")
    }

    func testShortSHAsOnlyWhereGitHubLinkedThem() {
        XCTAssertEqual(found("Fixed in a5c3785, not in deadbeef.").count, 0, "without GitHub's HTML, only full SHAs")

        let html = """
        <p>Fixed in <a href="https://github.com/acme-type/halden-sans/commit/\(sha)"><tt>a5c3785</tt></a>, not in deadbeef.</p>
        """
        let result = found("Fixed in a5c3785, not in deadbeef.", linked: References.Linked(html: html))
        XCTAssertEqual(result.map(\.1), ["a5c3785"])
        XCTAssertEqual(result.first?.2, "https://github.com/acme-type/halden-sans/commit/\(sha)", "to the full SHA")
    }

    func testOnlyWhatGitHubLinked() {
        let html = """
        <p>See <a class="issue-link js-issue-link" data-url="https://github.com/acme-type/halden-sans/issues/12" \
        href="https://github.com/acme-type/halden-sans/pull/12">#12</a>, #99, \
        <a class="user-mention notranslate" data-hovercard-type="user" href="https://github.com/lina-s">@lina-s</a> and @nobody.</p>
        """
        let result = found("See #12, #99, @lina-s and @nobody.", linked: References.Linked(html: html))
        XCTAssertEqual(result.map(\.0), ["#12", "@lina-s"])
        XCTAssertEqual(result.first?.2, "https://github.com/acme-type/halden-sans/pull/12", "where GitHub links it")
    }

    func testPeople() {
        let result = found("Thanks @lina-s and @mkoch! Mail me at type@acme.com or see @lina-s/team.")
        XCTAssertEqual(result.map(\.0), ["@lina-s", "@mkoch"])
        XCTAssertEqual(result.first?.2, "https://github.com/lina-s")
    }

    func testOtherAddressesStayAsTheyAre() {
        let result = found("Specimen at https://acme.com/halden?weight=700. Also https://github.com/acme-type/halden-sans/releases")
        XCTAssertEqual(result.map(\.1), ["https://acme.com/halden?weight=700", "https://github.com/acme-type/halden-sans/releases"])
    }

    func testIssueNumberInLink() {
        let url = { (string: String) in URL(string: string)! }
        XCTAssertEqual(References.issueNumber(in: url("https://github.com/acme-type/halden-sans/issues/12"), repo: repo), 12)
        XCTAssertEqual(References.issueNumber(in: url("https://github.com/Acme-Type/Halden-Sans/issues/12#issuecomment-9"), repo: repo), 12)
        XCTAssertNil(References.issueNumber(in: url("https://github.com/acme-type/other/issues/12"), repo: repo))
        XCTAssertNil(References.issueNumber(in: url("https://example.com/acme-type/halden-sans/issues/12"), repo: repo))
    }
}
