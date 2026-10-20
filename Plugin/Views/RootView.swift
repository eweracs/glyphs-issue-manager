import AppKit
import SwiftUI

/// Picks the layout from the panel's width: narrow panels are the compact
/// palette (mockups A1/A2); wide panels show list and detail side by side (B).
/// The views extend under the transparent title bar and draw its contents.
struct RootView: View {
    @ObservedObject var model: IssuesModel
    @ObservedObject var chrome: WindowChrome

    /// At this width and above, list and detail sit side by side; below it the
    /// split layout's one-row title bar wouldn't fit.
    static let splitWidth: CGFloat = 780

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= Self.splitWidth && model.phase == .ready
            VStack(spacing: 0) {
                if wide {
                    WideTitleBar(model: model, chrome: chrome, width: geometry.size.width)
                    Rule()
                    split(width: geometry.size.width)
                } else {
                    CompactTitleBar(model: model, chrome: chrome)
                    compact
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear { chrome.setWide(wide) }
            .onChange(of: wide) { chrome.setWide($0) }
        }
        .ignoresSafeArea()
        .background(Style.chrome)
    }

    @ViewBuilder
    private var compact: some View {
        switch model.phase {
        case .ready:
            if model.isComposingIssue {
                NewIssueView(model: model, compact: true)
            } else if let issue = model.selectedIssue {
                IssueDetailView(issue: issue, model: model, compact: true)
            } else {
                VStack(spacing: 0) {
                    CompactHeader(model: model)
                    Rule()
                    IssueListView(model: model, style: .ruled)
                    ListFooter(model: model)
                }
            }
        default:
            VStack(spacing: 0) {
                Rule()
                StateView(model: model)
            }
        }
    }

    private func split(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                IssueListView(model: model, style: .sidebar)
                ListFooter(model: model, showsGitHubLink: false)
                    .background(Style.sidebar)
            }
            .frame(width: min(max(width * 0.36, 300), 360))
            Rectangle()
                .fill(Style.border)
                .frame(width: 1)
            if model.isComposingIssue {
                NewIssueView(model: model, compact: false)
            } else if let issue = model.selectedIssue {
                IssueDetailView(issue: issue, model: model, compact: false)
            } else {
                EmptyStateView(symbol: "sidebar.left", title: "No issue selected", message: "Choose an issue from the list.") {
                    EmptyView()
                }
                .background(Style.content)
            }
        }
    }
}

/// The title bar of the compact palette (mockup A1): traffic lights, the
/// centred title and the refresh button.
struct CompactTitleBar: View {
    @ObservedObject var model: IssuesModel
    @ObservedObject var chrome: WindowChrome

    var body: some View {
        ZStack {
            WindowDragArea()
            Text("GitHub Issues")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Style.text)
                .lineLimit(1)
                .padding(.horizontal, chrome.trafficLightsInset)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                Spacer()
                    .allowsHitTesting(false)
                NewIssueButton(model: model)
                RefreshButton(model: model)
            }
            .padding(.trailing, 8)
        }
        .frame(height: chrome.titlebarHeight)
    }
}

/// Opens the new-issue form.
struct NewIssueButton: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        Button(action: model.startNewIssue) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13))
                .foregroundColor(Style.icon)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .ready)
        .help(model.canChangeIssues ? "New issue" : "New issue (sign in to create it)")
        .accessibilityLabel("New issue")
    }
}

/// The refresh button at the right end of the title bar.
struct RefreshButton: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        Button(action: model.reload) {
            Group {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundColor(Style.icon)
                }
            }
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing || model.repo == nil)
        .help("Refresh")
        .accessibilityLabel("Refresh")
    }
}

/// Lets the custom title bar move the window, and zoom it on double-click
/// like a standard title bar.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                if action != "None", action != "Minimize" { window.performZoom(nil) }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
