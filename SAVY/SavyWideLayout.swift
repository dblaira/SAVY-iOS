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
