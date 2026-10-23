import Foundation

/// An image to attach to an issue or comment: its bytes, file name and type.
public struct ImageAttachment: Equatable {
    public let data: Data
    public let fileName: String
    public let contentType: String

    /// GitHub takes images up to 10 MB.
    public static let maxBytes = 10 * 1024 * 1024

    /// The image types GitHub takes, by file extension.
    private static let contentTypes: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "svg": "image/svg+xml",
    ]

    public init(data: Data, fileName: String, contentType: String) {
        self.data = data
        self.fileName = fileName
        self.contentType = contentType
    }

    /// The type GitHub takes a file with this name as; nil when it takes no such files.
    public static func contentType(forFileName name: String) -> String? {
        contentTypes[(name as NSString).pathExtension.lowercased()]
    }

    public var isTooLarge: Bool { data.count > Self.maxBytes }

    /// As GitHub's web uploader writes it: the file name without its
    /// extension, dots as spaces (“Screenshot 2026-10-23 at 10.12.04”).
    public var altText: String {
        (fileName as NSString).deletingPathExtension.replacingOccurrences(of: ".", with: " ")
    }

    /// `![alt](url)`, with brackets in the alt text escaped.
    public func markdown(url: URL) -> String {
        var alt = ""
        for character in altText {
            if character == "[" || character == "]" || character == "\\" { alt.append("\\") }
            alt.append(character)
        }
        return "![\(alt)](\(url.absoluteString))"
    }

    /// What stands in the text while the image uploads, as on GitHub;
    /// `number` tells apart uploads of files with the same name.
    public static func placeholder(for fileName: String, number: Int = 1) -> String {
        number > 1 ? "![Uploading \(fileName) (\(number))…]()" : "![Uploading \(fileName)…]()"
    }
}
