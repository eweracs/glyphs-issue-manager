import XCTest
@testable import IssueCore

final class ImageAttachmentTests: XCTestCase {

    func testContentTypeByExtension() {
        XCTAssertEqual(ImageAttachment.contentType(forFileName: "Ring.PNG"), "image/png")
        XCTAssertEqual(ImageAttachment.contentType(forFileName: "proof.jpeg"), "image/jpeg")
        XCTAssertEqual(ImageAttachment.contentType(forFileName: "outline.svg"), "image/svg+xml")
        XCTAssertNil(ImageAttachment.contentType(forFileName: "scan.tiff"))
        XCTAssertNil(ImageAttachment.contentType(forFileName: "Umiak.glyphspackage"))
    }

    func testMarkdownUsesFileNameAsAltText() {
        let url = URL(string: "https://github.com/user-attachments/assets/0b7e-41c2")!
        let screenshot = ImageAttachment(data: Data(), fileName: "Screenshot 2026-10-23 at 10.12.04.png", contentType: "image/png")
        XCTAssertEqual(screenshot.markdown(url: url), "![Screenshot 2026-10-23 at 10 12 04](https://github.com/user-attachments/assets/0b7e-41c2)")

        let bracketed = ImageAttachment(data: Data(), fileName: "a[ss01].png", contentType: "image/png")
        XCTAssertEqual(bracketed.markdown(url: url), #"![a\[ss01\]](https://github.com/user-attachments/assets/0b7e-41c2)"#)
    }

    func testPlaceholdersTellUploadsApart() {
        XCTAssertEqual(ImageAttachment.placeholder(for: "image.png"), "![Uploading image.png…]()")
        XCTAssertEqual(ImageAttachment.placeholder(for: "image.png", number: 2), "![Uploading image.png (2)…]()")
    }

    func testSizeLimit() {
        XCTAssertFalse(ImageAttachment(data: Data(count: ImageAttachment.maxBytes), fileName: "a.png", contentType: "image/png").isTooLarge)
        XCTAssertTrue(ImageAttachment(data: Data(count: ImageAttachment.maxBytes + 1), fileName: "a.png", contentType: "image/png").isTooLarge)
    }
}
