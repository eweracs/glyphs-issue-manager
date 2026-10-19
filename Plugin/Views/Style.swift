import AppKit
import SwiftUI

/// The palette and type of the design mockups, with dark-mode counterparts.
enum Style {
    // Surfaces
    static let chromeNS = nsDynamic(light: 0xF5F5F7, dark: 0x2B2B2D)
    static let chrome = Color(nsColor: chromeNS)                     // title bar, header, footer
    static let content = dynamic(light: 0xFFFFFF, dark: 0x1F1F21)    // list and detail
    static let sidebar = dynamic(light: 0xF7F7F9, dark: 0x262628)    // list column, split layout
    static let border = dynamic(light: 0xE3E3E7, dark: 0x3A3A3D)     // header and footer rules, outlines
    static let rowRule = dynamic(light: 0xEFEFF2, dark: 0x2F2F32)    // between list rows
    static let rowHover = dynamic(light: 0xF7F7F9, dark: 0x27272A)
    static let selectedRow = dynamic(light: 0xFFFFFF, dark: 0x3A3A3E)

    // Text
    static let text = dynamic(light: 0x1D1D1F, dark: 0xF2F2F5)
    static let mutedText = dynamic(light: 0x3A3A3F, dark: 0xD2D2D7)
    static let secondaryText = dynamic(light: 0x6B6B70, dark: 0xA1A1A8)
    static let icon = dynamic(light: 0x55555A, dark: 0xB4B4BA)

    // Controls
    static let field = dynamic(light: 0xFFFFFF, dark: 0x3A3A3D)
    static let fieldRing = dynamic(light: 0xD2D2D7, dark: 0x505055)
    static let segmentTrack = dynamic(light: 0xE4E4E8, dark: 0x38383B)
    static let segmentActive = dynamic(light: 0xFFFFFF, dark: 0x606065)
    static let chip = dynamic(light: 0xF4F4F6, dark: 0x2F2F32)
    static let chipRing = dynamic(light: 0xD3D3D8, dark: 0x4A4A4F)
    static let cell = dynamic(light: 0xFAFAFB, dark: 0x262628)
    static let badge = dynamic(light: 0xF0F0F3, dark: 0x333336)
    static let rail = dynamic(light: 0xEAEAED, dark: 0x343437)
    static let neutralPill = dynamic(light: 0xEDEDF0, dark: 0x3A3A3D)

    // Issue states
    static let openIcon = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let openFill = dynamic(light: 0x1A7F37, dark: 0x238636)
    static let openTint = dynamic(light: 0xE3F5E8, dark: 0x1B3A25)
    static let closedIcon = dynamic(light: 0x8250DF, dark: 0xA371F7)
    static let closedFill = dynamic(light: 0x8250DF, dark: 0x8957E5)
    static let notPlannedIcon = dynamic(light: 0x6E7781, dark: 0x8B949E)
    static let notPlannedFill = dynamic(light: 0x6E7781, dark: 0x6E7681)

    static let accentTint = Color.accentColor.opacity(0.10)
    static let accentRing = Color.accentColor.opacity(0.38)

    static let mono = Font.system(size: 10.5, design: .monospaced)
    static let sectionTitle = Font.system(size: 10.5, weight: .semibold)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nsDynamic(light: light, dark: dark))
    }

    static func nsDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(hex: isDark(appearance) ? dark : light)
        }
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    convenience init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// WCAG relative luminance.
    var relativeLuminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0.5 }
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
    }

    func contrast(with other: NSColor) -> CGFloat {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Mixes in `fraction` of `other`, in sRGB.
    func mixed(with other: NSColor, fraction: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * fraction }
        return NSColor(
            srgbRed: mix(a.redComponent, b.redComponent),
            green: mix(a.greenComponent, b.greenComponent),
            blue: mix(a.blueComponent, b.blueComponent),
            alpha: 1
        )
    }
}

extension GitHubLabel {
    /// A pale tint of the label colour, as in the mockups.
    var pillFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            GitHubLabel.pillColors(hex: color, dark: Style.isDark(appearance)).fill
        })
    }

    /// The label colour, darkened (or lightened in dark mode) until it reads at 4.5:1 on the fill.
    var pillText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            GitHubLabel.pillColors(hex: color, dark: Style.isDark(appearance)).text
        })
    }

    static func pillColors(hex: String, dark: Bool) -> (fill: NSColor, text: NSColor) {
        let base = NSColor(hexString: hex) ?? NSColor(hex: 0x8C8C91)
        let surface = NSColor(hex: dark ? 0x1F1F21 : 0xFFFFFF)
        let fill = base.mixed(with: surface, fraction: dark ? 0.76 : 0.80)
        let target = dark ? NSColor.white : NSColor.black
        var text = base
        for _ in 0..<24 where text.contrast(with: fill) < 4.5 {
            text = text.mixed(with: target, fraction: 0.12)
        }
        return (fill, text)
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func string(for date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    /// Children get at most the available width, so a long one shortens
    /// instead of running past the edge.
    private func size(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = size(of: subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            width = max(width, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(width, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = size(of: subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
