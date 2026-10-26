import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The composer's text view: plain text in the panel's type. Images pasted or
/// dropped into it go to `onImage`, which starts their upload and returns the
/// placeholder that stands in the text meanwhile.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var onImage: ((ImageAttachment) -> String?)?
    /// Suggestions for what is typed after `@`, `#` or `/`.
    var suggest: ((CompletionQuery) -> [Suggestion])?
    /// Takes focus when this turns true (Tab, Return, ⌘N).
    var wantsFocus = false
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ImageAcceptingTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = Style.textNS
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Style.textNS]
        textView.insertionPointColor = Style.textNS
        textView.drawsBackground = false
        // With the line fragment padding (5), text starts 9 pt in, as the
        // placeholder and the sizing text in ComposerEditor do.
        textView.textContainerInset = NSSize(width: 4, height: 7)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ImageAcceptingTextView else { return }
        context.coordinator.text = $text
        textView.onImage = onImage
        textView.suggest = suggest
        textView.onFocusChange = onFocusChange
        textView.isEditable = context.environment.isEnabled
        if textView.string != text {
            context.coordinator.isApplying = true
            textView.apply(text)
            context.coordinator.isApplying = false
        }
        // Only when asked anew, so a request that is out of date doesn't
        // take focus back from where the user has clicked since.
        if wantsFocus, !context.coordinator.wantedFocus {
            // Later: a new text view isn't in its window yet, and SwiftUI may
            // still be moving focus out of another field.
            DispatchQueue.main.async { [weak textView, weak scrollView] in
                guard let textView, let window = textView.window, window.firstResponder !== textView else { return }
                window.makeFirstResponder(textView)
                // Into view, if the issue's scroll view has it out of sight.
                if let scrollView { scrollView.scrollToVisible(scrollView.bounds) }
            }
        }
        context.coordinator.wantedFocus = wantsFocus
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Set while a change from outside is applied, which needn't go back.
        var isApplying = false
        var wantedFocus = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

final class ImageAcceptingTextView: NSTextView {
    var onImage: ((ImageAttachment) -> String?)? {
        didSet {
            if (onImage == nil) != (oldValue == nil) { updateDragTypeRegistration() }
        }
    }
    var onFocusChange: ((Bool) -> Void)?
    var suggest: ((CompletionQuery) -> [Suggestion])?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { notifyFocus(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            notifyFocus(false)
            hideSuggestions()
        }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hideSuggestions() }
    }

    /// Esc leaves the text (a second Esc then goes back or cancels), rather
    /// than offering word completions.
    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    // MARK: Suggestions

    private let popup = SuggestionPopup()
    private var query: CompletionQuery?
    private var suggestions: [Suggestion] = []
    private var selection = 0
    /// Where the query starts that Esc or taking a suggestion closed the
    /// list for; it stays closed there until another query begins.
    private var closedAt: Int?

    /// The list is showing: ↑ ↓ choose, Return or Tab take, Esc closes it.
    var isSuggesting: Bool { popup.isVisible }

    override func didChangeText() {
        super.didChangeText()
        updateSuggestions()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { updateSuggestions() }
    }

    override func doCommand(by selector: Selector) {
        if isSuggesting {
            switch selector {
            case #selector(moveUp(_:)):
                moveSuggestion(by: -1)
                return
            case #selector(moveDown(_:)):
                moveSuggestion(by: 1)
                return
            case #selector(insertNewline(_:)), #selector(insertTab(_:)):
                takeSuggestion(at: selection)
                return
            case #selector(cancelOperation(_:)):
                closedAt = query?.range.location
                hideSuggestions()
                return
            default:
                break
            }
        }
        super.doCommand(by: selector)
    }

    private func updateSuggestions() {
        let caret = selectedRange()
        guard let suggest, window?.firstResponder === self, !hasMarkedText(), caret.length == 0,
              let query = CompletionQuery.at(caret.location, in: string) else {
            closedAt = nil
            hideSuggestions()
            return
        }
        guard closedAt != query.range.location else {
            hideSuggestions()
            return
        }
        closedAt = nil
        let found = suggest(query)
        guard !found.isEmpty, let window else {
            hideSuggestions()
            return
        }
        // The same suggestion stays selected while the list narrows.
        let selectedID = suggestions.indices.contains(selection) ? suggestions[selection].id : nil
        selection = found.firstIndex { $0.id == selectedID } ?? 0
        self.query = query
        suggestions = found
        let anchor = firstRect(forCharacterRange: NSRange(location: query.range.location, length: 1), actualRange: nil)
        popup.show(found, selected: selection, below: anchor, in: window) { [weak self] index in
            self?.takeSuggestion(at: index)
        }
    }

    private func moveSuggestion(by step: Int) {
        guard !suggestions.isEmpty, let query, let window else { return }
        selection = min(max(selection + step, 0), suggestions.count - 1)
        let anchor = firstRect(forCharacterRange: NSRange(location: query.range.location, length: 1), actualRange: nil)
        popup.show(suggestions, selected: selection, below: anchor, in: window) { [weak self] index in
            self?.takeSuggestion(at: index)
        }
    }

    /// Puts the suggestion in place of the query, as one undoable edit.
    private func takeSuggestion(at index: Int) {
        guard let query, suggestions.indices.contains(index) else { return }
        let insertion = suggestions[index].insertion
        closedAt = query.range.location
        hideSuggestions()
        insertText(insertion, replacementRange: query.range)
    }

    private func hideSuggestions() {
        popup.hide()
        query = nil
        suggestions = []
        selection = 0
    }

    /// Later, so SwiftUI isn't told in the middle of an update.
    private func notifyFocus(_ focused: Bool) {
        let handler = onFocusChange
        DispatchQueue.main.async { handler?(focused) }
    }

    /// Takes a change made elsewhere (an upload finishing, a comment sent) as
    /// one edit, so the caret stays where it was and Undo keeps working.
    func apply(_ newText: String) {
        let old = string as NSString
        let new = newText as NSString
        let shorter = min(old.length, new.length)
        var prefix = 0
        while prefix < shorter, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        let range = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))

        var selection = selectedRange()
        breakUndoCoalescing()
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
        } else {
            string = newText
        }
        let delta = new.length - old.length
        if selection.location >= NSMaxRange(range) {
            selection.location += delta
        } else if NSMaxRange(selection) > range.location {
            selection = NSRange(location: range.location + (replacement as NSString).length, length: 0)
        }
        selection.location = min(selection.location, new.length)
        selection.length = min(selection.length, new.length - selection.location)
        setSelectedRange(selection)
    }

    // MARK: Pasting and dropping images

    /// Keeps Paste available when the pasteboard holds only an image.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        guard onImage != nil else { return super.readablePasteboardTypes }
        return super.readablePasteboardTypes + PastedImages.types
    }

    override func paste(_ sender: Any?) {
        if !insertImages(from: .general) { super.paste(sender) }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if !insertImages(from: .general) { super.pasteAsPlainText(sender) }
    }

    override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        if onImage != nil, PastedImages.mayHoldImages(dragInfo.draggingPasteboard) { return .copy }
        return super.dragOperation(for: dragInfo, type: type)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard onImage != nil, let images = PastedImages.read(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        window?.makeFirstResponder(self)
        insert(images)
        return true
    }

    private func insertImages(from pasteboard: NSPasteboard) -> Bool {
        guard onImage != nil, let images = PastedImages.read(from: pasteboard) else { return false }
        insert(images)
        return true
    }

    /// Puts each image's placeholder on a line of its own at the caret.
    private func insert(_ images: [ImageAttachment]) {
        guard let onImage else { return }
        let placeholders = images.compactMap(onImage)
        guard !placeholders.isEmpty else { return }
        let range = selectedRange()
        let atLineStart = range.location == 0 || (string as NSString).character(at: range.location - 1) == 0x0A
        insertText((atLineStart ? "" : "\n") + placeholders.joined(separator: "\n") + "\n", replacementRange: range)
    }
}

/// Reads images from a pasteboard (Paste, or a drop) as GitHub's web editor
/// takes them: image files, or image data such as a screenshot.
enum PastedImages {
    private static let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    private static let gif = NSPasteboard.PasteboardType(UTType.gif.identifier)

    static let types: [NSPasteboard.PasteboardType] = [.png, gif, jpeg, .tiff, .pdf]

    private static let imageFiles: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    static func mayHoldImages(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFiles) { return true }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return false }
        return pasteboard.availableType(from: types) != nil && !holdsText(pasteboard)
    }

    /// Nil when the pasteboard holds no image, or text to paste instead.
    static func read(from pasteboard: NSPasteboard) -> [ImageAttachment]? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFiles) as? [URL], !urls.isEmpty {
            let images = urls.compactMap(image(at:))
            return images.isEmpty ? nil : images
        }
        // Finder puts each file's icon next to its URL; other files paste as their path.
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return nil }
        guard !holdsText(pasteboard), let image = imageData(in: pasteboard) else { return nil }
        return [image]
    }

    /// Whether there is text to paste: more than the link a browser's Copy
    /// Image adds to the picture.
    private static func holdsText(_ pasteboard: NSPasteboard) -> Bool {
        guard let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return false }
        let isLink = string.hasPrefix("http") && !string.contains(where: \.isWhitespace)
        return !isLink
    }

    private static func image(at url: URL) -> ImageAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent
        if let contentType = ImageAttachment.contentType(forFileName: name) {
            return ImageAttachment(data: data, fileName: name, contentType: contentType)
        }
        // Types GitHub doesn't take (TIFF, HEIC, PSD …) go up as PNG.
        guard let png = pngData(from: data) else { return nil }
        return ImageAttachment(data: png, fileName: (name as NSString).deletingPathExtension + ".png", contentType: "image/png")
    }

    private static func imageData(in pasteboard: NSPasteboard) -> ImageAttachment? {
        let asTheyAre: [(type: NSPasteboard.PasteboardType, name: String, contentType: String)] = [
            (.png, "image.png", "image/png"),
            (gif, "image.gif", "image/gif"),
            (jpeg, "image.jpg", "image/jpeg"),
        ]
        for item in asTheyAre {
            if let data = pasteboard.data(forType: item.type) {
                return ImageAttachment(data: data, fileName: item.name, contentType: item.contentType)
            }
        }
        for type in [NSPasteboard.PasteboardType.tiff, .pdf] {
            if let data = pasteboard.data(forType: type), let png = pngData(from: data) {
                return ImageAttachment(data: png, fileName: "image.png", contentType: "image/png")
            }
        }
        return nil
    }

    /// A PNG of the image, at its full pixel size.
    private static func pngData(from data: Data) -> Data? {
        if let bitmap = NSBitmapImageRep(data: data) {
            return bitmap.representation(using: .png, properties: [:])
        }
        // Vector images (PDF) are drawn at twice their size, for Retina screens.
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(image.size.width * 2),
                  pixelsHigh: Int(image.size.height * 2),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ) else { return nil }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
