import XCTest
@testable import IssueCore

final class MarkdownParserTests: XCTestCase {

    func testParagraphsKeepLineBreaks() {
        let blocks = MarkdownParser.blocks(from: "First line\nsecond line\n\nNext paragraph")
        XCTAssertEqual(blocks, [.paragraph("First line\nsecond line"), .paragraph("Next paragraph")])
    }

    func testStripsIssueTemplateComments() {
        let blocks = MarkdownParser.blocks(from: "<!-- Describe the bug -->\nThe dots collide.\n<!--\nmulti\nline\n-->")
        XCTAssertEqual(blocks, [.paragraph("The dots collide.")])
    }

    func testHeadingsListsTasksQuotesRules() {
        let markdown = """
        ## Steps
        1. Open Display Black
        2. Set 90 % leading
        - [ ] Black
        - [x] Bold
          checked in v2
        > Looks fine in Regular
        ---
        Setext
        ===
        """
        XCTAssertEqual(MarkdownParser.blocks(from: markdown), [
            .heading(level: 2, text: "Steps"),
            .listItem(marker: "1.", text: "Open Display Black", indent: 0),
            .listItem(marker: "2.", text: "Set 90 % leading", indent: 0),
            .task(checked: false, text: "Black", indent: 0),
            .task(checked: true, text: "Bold\nchecked in v2", indent: 0),
            .quote("Looks fine in Regular"),
            .rule,
            .heading(level: 1, text: "Setext"),
        ])
    }

    func testFencedCodeAndTables() {
        let markdown = """
        ```fea
        pos T o -40;
        ```
        | Weight | OK |
        |---|---|
        | Bold | yes |
        """
        XCTAssertEqual(MarkdownParser.blocks(from: markdown), [
            .code("pos T o -40;"),
            .code("| Weight | OK |\n|---|---|\n| Bold | yes |"),
        ])
    }

    func testExtractsImagesInOrder() {
        let markdown = "See this: ![collision](https://example.com/a.png) and <img width=\"300\" alt=\"second\" src=\"https://example.com/b.png\">"
        XCTAssertEqual(MarkdownParser.blocks(from: markdown), [
            .paragraph("See this:  and"),
            .image(alt: "collision", url: "https://example.com/a.png"),
            .image(alt: "second", url: "https://example.com/b.png"),
        ])
    }

    func testStripsLeftoverTags() {
        XCTAssertEqual(MarkdownParser.blocks(from: "<details><summary>Log</summary>line one<br>line two</details>"), [
            .paragraph("Logline one\nline two"),
        ])
    }

    func testImageSourcesInHTML() {
        let html = #"<p><img src="https://private-user-images.githubusercontent.com/1/a.png?jwt=x&amp;y=1" alt="a"></p><img alt="b" src='https://camo.githubusercontent.com/b'>"#
        XCTAssertEqual(MarkdownParser.imageSources(inHTML: html), [
            "https://private-user-images.githubusercontent.com/1/a.png?jwt=x&y=1",
            "https://camo.githubusercontent.com/b",
        ])
    }

    func testSettingTaskChangesOnlyItsBox() {
        let markdown = "<!-- - [ ] not a task -->\r\n- [ ] Black 🖤\r\n```\r\n- [ ] code\r\n```\r\n> - [ ] quoted\r\n  * [X] Bold\r\n1. [ ] Light"
        XCTAssertEqual(MarkdownParser.tasks(in: markdown).map(\.text), ["Black 🖤", "Bold", "Light"])
        XCTAssertEqual(
            MarkdownParser.settingTask(0, checked: true, in: markdown),
            markdown.replacingOccurrences(of: "- [ ] Black", with: "- [x] Black")
        )
        XCTAssertEqual(
            MarkdownParser.settingTask(1, checked: false, in: markdown),
            markdown.replacingOccurrences(of: "* [X] Bold", with: "* [ ] Bold")
        )
        XCTAssertEqual(
            MarkdownParser.settingTask(2, checked: true, in: markdown),
            markdown.replacingOccurrences(of: "1. [ ] Light", with: "1. [x] Light")
        )
        XCTAssertNil(MarkdownParser.settingTask(3, checked: true, in: markdown))
    }

    func testTaskProgress() {
        let progress = MarkdownParser.taskProgress(in: "- [x] Regular\n- [ ] Bold\n- [X] Black\n- plain")
        XCTAssertEqual(progress.done, 2)
        XCTAssertEqual(progress.total, 3)
    }
}
