import SwiftUI
import UIKit

enum SavyWideLayout {
    /// The phone card width, so cards keep their proportions when they flow into columns.
    static let cardMinimumWidth: CGFloat = 340
    static let cardMaximumWidth: CGFloat = 520
    /// The bottom navigation keeps its phone spacing in a wide window.
    static let navigationMaximumWidth: CGFloat = 640
    static let macMinimumWindowSize = CGSize(width: 420, height: 760)
    static let macInitialWindowSize = CGSize(width: 1280, height: 900)
    static let macFormSheetSize = CGSize(width: 680, height: 760)
}

/// iPhone keeps one column of cards. A regular-width window (the Mac app, a full-screen iPad)
/// flows the same cards into as many columns as fit.
struct SavyCardFlow<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: SavyWideLayout.cardMinimumWidth, maximum: SavyWideLayout.cardMaximumWidth),
                    spacing: spacing,
                    alignment: .top
                )],
                alignment: .leading,
                spacing: spacing
            ) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

extension View {
    /// On the Mac a pushed page's navigation bar would move into the window title bar, so the
    /// page draws the phone's navy bar and crimson back chevron itself.
    @ViewBuilder
    func savyMacNavigationBar(title: String? = nil) -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { SavyMacNavigationBar(title: title) }
        #else
        self
        #endif
    }

    /// Entry forms open as a page-sized sheet on the Mac instead of the small default.
    @ViewBuilder
    func savyMacFormSheet() -> some View {
        #if targetEnvironment(macCatalyst)
        frame(
            minWidth: SavyWideLayout.macFormSheetSize.width,
            idealWidth: SavyWideLayout.macFormSheetSize.width,
            minHeight: SavyWideLayout.macFormSheetSize.height,
            idealHeight: SavyWideLayout.macFormSheetSize.height
        )
        .presentationSizing(.page)
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct SavyMacNavigationBar: View {
    @Environment(\.dismiss) private var dismiss
    let title: String?

    var body: some View {
        HStack(spacing: 2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(SavyTheme.crimson)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Back")
            if let title {
                Text(title)
                    .font(SavyTypography.displaySerif(24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(SavyTheme.pageBackground)
    }
}

/// Gives the Mac window a usable minimum and opens it large the first time.
enum SavyMacWindow {
    private static let sizedKey = "savy.mac.initialWindowSized.v1"

    @MainActor
    static func configure() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.sizeRestrictions?.minimumSize = SavyWideLayout.macMinimumWindowSize
            // Each page draws its own heading, so the window title stays out of the title bar.
            scene.titlebar?.titleVisibility = .hidden
            guard !UserDefaults.standard.bool(forKey: sizedKey) else { continue }
            UserDefaults.standard.set(true, forKey: sizedKey)
            let screen = scene.screen.bounds
            let size = SavyWideLayout.macInitialWindowSize
            let frame = CGRect(
                x: max(0, (screen.width - size.width) / 2),
                y: max(0, (screen.height - size.height) / 2),
                width: min(size.width, screen.width),
                height: min(size.height, screen.height)
            )
            scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { _ in }
        }
    }
}
#endif
