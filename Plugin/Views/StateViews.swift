import SwiftUI

/// Icon in a tinted circle, title, message and actions (mockup “Setup & empty states”).
struct EmptyStateView<Actions: View>: View {
    enum Tint {
        case neutral, positive, warning
    }

    let symbol: String
    var tint: Tint = .neutral
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(foreground)
                .frame(width: 48, height: 48)
                .background(Circle().fill(background))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Style.text)
                .multilineTextAlignment(.center)
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Style.icon)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                actions()
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var foreground: Color {
        switch tint {
        case .neutral: return Style.icon
        case .positive: return Style.openIcon
        case .warning: return .orange
        }
    }

    private var background: Color {
        switch tint {
        case .neutral: return Style.badge
        case .positive: return Style.openTint
        case .warning: return Color.orange.opacity(0.14)
        }
    }
}

/// Everything that isn't the issue list: no font, no repository, sign-in,
/// loading and errors.
struct StateView: View {
    @ObservedObject var model: IssuesModel

    var body: some View {
        Group {
            switch model.phase {
            case .noFont:
                EmptyStateView(symbol: "doc", title: "No font open", message: "Open a .glyphs file that lives in a GitHub repository.") {
                    EmptyView()
                }
            case .unsavedFont:
                EmptyStateView(symbol: "square.and.arrow.down", title: "Save the font first", message: "Issues are found through the git repository the font file is saved in.") {
                    EmptyView()
                }
            case .noRepository:
                EmptyStateView(
                    symbol: "book.closed",
                    title: "No GitHub repository found",
                    message: "\(model.fontURL?.lastPathComponent ?? "This font") isn’t inside a git repository with a github.com remote."
                ) {
                    Button("Choose Repository…", action: model.chooseRepository)
                        .buttonStyle(PrimaryButtonStyle())
                    Text("Remembered for this font file")
                        .font(.system(size: 11))
                        .foregroundColor(Style.secondaryText)
                }
            case .needsSignIn(let message):
                EmptyStateView(symbol: "key", title: "Connect to GitHub", message: message + " Your token is kept in the Keychain.") {
                    VStack(spacing: 8) {
                        if model.gitHubCLIAvailable {
                            Button("Use gh CLI Login", action: model.useGitHubCLI)
                                .buttonStyle(PrimaryButtonStyle())
                            Button("Paste Token…", action: model.pasteToken)
                                .buttonStyle(SecondaryButtonStyle())
                        } else {
                            Button("Paste Token…", action: model.pasteToken)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .frame(width: 200)
                    Button("Create a Token on GitHub…", action: model.openTokenPage)
                        .buttonStyle(AccentLinkButtonStyle())
                        .padding(.top, 2)
                    Button("Choose Another Repository…", action: model.chooseRepository)
                        .buttonStyle(AccentLinkButtonStyle())
                }
            case .loading:
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.repo.map { "Loading issues of \($0.description)…" } ?? "Loading issues…")
                        .font(.system(size: 12))
                        .foregroundColor(Style.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyStateView(symbol: "exclamationmark.triangle", tint: .warning, title: "Couldn’t load issues", message: message) {
                    Button("Try Again", action: model.reload)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Choose Repository…", action: model.chooseRepository)
                        .buttonStyle(AccentLinkButtonStyle())
                }
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Style.content)
    }
}
