import XCTest
@testable import IssueCore

final class GlyphMentionsTests: XCTestCase {

    func testFindsSlashNotation() {
        XCTAssertEqual(GlyphMentions.names(in: "Dots on /adieresis and /odieresis collide."), ["adieresis", "odieresis"])
        XCTAssertEqual(GlyphMentions.names(in: "Kerning /T/o/a is too tight"), ["T", "o", "a"])
        XCTAssertEqual(GlyphMentions.names(in: "ss01 not applied to /a.ss01 (see /aacute)."), ["a.ss01", "aacute"])
        XCTAssertEqual(GlyphMentions.names(in: "`/germandbls.cap` missing"), ["germandbls.cap"])
        XCTAssertEqual(GlyphMentions.names(in: "**/R** and /ka-deva"), ["R", "ka-deva"])
        XCTAssertEqual(GlyphMentions.names(in: "corner /_corner.inktrap"), ["_corner.inktrap"])
    }

    func testDeduplicatesInOrder() {
        XCTAssertEqual(GlyphMentions.names(in: "/a /b /a /c /b"), ["a", "b", "c"])
    }

    func testTrimsSentencePunctuation() {
        XCTAssertEqual(GlyphMentions.names(in: "Look at /udieresis."), ["udieresis"])
        XCTAssertEqual(GlyphMentions.names(in: "Look at /udieresis..."), ["udieresis"])
    }

    func testIgnoresWordsPathsAndURLs() {
        XCTAssertEqual(GlyphMentions.names(in: "and/or, T/o pairs"), [])
        XCTAssertEqual(GlyphMentions.names(in: "see https://github.com/acme/font/issues/3"), [])
        XCTAssertEqual(GlyphMentions.names(in: "in ~/fonts/halden or ./build/x"), [])
        XCTAssertEqual(GlyphMentions.names(in: "[docs](/docs/a)"), [])
        XCTAssertEqual(GlyphMentions.names(in: "1/2 and 3/4"), [])
        XCTAssertEqual(GlyphMentions.names(in: "a lone / slash, /123 and /.notdef"), [])
    }

    func testTitleCandidates() {
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "k wider"), ["k", "wider"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "N contrast"), ["N", "contrast"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "a bottom join thiccness"), ["a", "bottom", "join", "thiccness"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "Dieresiscomb too small"), ["Dieresiscomb", "dieresiscomb", "too", "small"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "T/o and T/a kerning"), ["T", "o", "and", "a", "kerning"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "A/t.sc too tight"), ["A", "t.sc", "too", "tight"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "F/A a bit tight?"), ["F", "A", "bit", "tight"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "Add a dot to i."), ["Add", "add", "dot", "to", "i"])
        XCTAssertEqual(GlyphMentions.titleCandidates(in: "A bug I found in 2024"), ["bug", "found", "in"])
    }

    func testRelation() {
        let components: [String: [String]] = [
            "adieresis": ["a", "dieresiscomb"],
            "aacute.sc": ["a.sc", "acutecomb.sc"],
            "odieresis": ["o", "dieresiscomb"],
        ]
        let lookup: (String) -> [String] = { components[$0] ?? [] }
        XCTAssertTrue(GlyphRelation.name("a", relatesTo: "a", components: lookup))
        XCTAssertTrue(GlyphRelation.name("a.ss01", relatesTo: "a", components: lookup))
        XCTAssertTrue(GlyphRelation.name("adieresis", relatesTo: "a", components: lookup))
        XCTAssertTrue(GlyphRelation.name("aacute.sc", relatesTo: "a", components: lookup))
        XCTAssertFalse(GlyphRelation.name("odieresis", relatesTo: "a", components: lookup))
        XCTAssertFalse(GlyphRelation.name("ae", relatesTo: "a", components: lookup))
        XCTAssertTrue(GlyphRelation.name("odieresis", relatesTo: "dieresiscomb", components: lookup))
    }
}
