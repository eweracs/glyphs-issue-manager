import XCTest
@testable import IssueCore

final class CompletionQueryTests: XCTestCase {

    /// The query at the end of `text`, as trigger and typed text.
    private func query(_ text: String) -> String? {
        CompletionQuery.at((text as NSString).length, in: text).map { String($0.trigger.rawValue) + $0.text }
    }

    func testPeople() {
        XCTAssertEqual(query("Thanks @"), "@")
        XCTAssertEqual(query("Thanks @lina-s"), "@lina-s")
        XCTAssertEqual(query("(@mk"), "@mk")
        XCTAssertNil(query("mail type@acme"), "an e-mail address")
        XCTAssertNil(query("Thanks @lina-s "), "after the word")
    }

    func testIssues() {
        XCTAssertEqual(query("Same as #"), "#")
        XCTAssertEqual(query("Same as #12"), "#12")
        XCTAssertEqual(query("#kern"), "#kern")
        XCTAssertNil(query("C#"), "inside a word")
        XCTAssertNil(query("##"), "a heading")
    }

    func testGlyphs() {
        XCTAssertEqual(query("/adie"), "/adie")
        XCTAssertEqual(query("Too wide: /"), "/")
        XCTAssertEqual(query("/T/o"), "/o", "in a run of slash names")
        XCTAssertEqual(query("/a.ss0"), "/a.ss0")
        XCTAssertNil(query("and/or"), "a word")
        XCTAssertNil(query("https://github.com/acme"), "a path")
    }

    func testRangeIsTriggerAndText() {
        let text = "See /T/o and @li"
        let found = CompletionQuery.at((text as NSString).length, in: text)
        XCTAssertEqual(found?.range, NSRange(location: 13, length: 3))
        XCTAssertEqual(found?.trigger, .person)
    }

    func testOnlyAtTheEndOfAWord() {
        let text = "@lina-s is on it"
        XCTAssertNil(CompletionQuery.at(3, in: text), "the caret inside the name")
        XCTAssertEqual(CompletionQuery.at(7, in: text)?.text, "lina-s")
    }
}
