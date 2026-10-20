import SwiftUI

/// The same icon-only control is used in SAVY and Understood.
struct EntryShareMenu: View {
    let content: EntryShareContent

    var body: some View {
        ShareLink(item: content.entireForm) {
            shareIcon
        }
        .buttonStyle(.plain)
        .tint(.black)
        .accessibilityLabel("Share")
        .accessibilityIdentifier("shareForm")
    }

    @ViewBuilder private var shareIcon: some View {
        if #available(iOS 26.0, *) {
            symbol.glassEffect(.regular.interactive(), in: Circle())
        } else {
            symbol
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.1), lineWidth: 0.5))
        }
    }

    private var symbol: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 30))
            .foregroundStyle(.black)
            .frame(width: 64, height: 64)
            .contentShape(Circle())
    }
}

/// The circle crosses the bar's top edge with the same 22-point rise as the FAB.
struct EntryShareBar: View {
    let content: EntryShareContent
    var isEnabled = true
    var bottomPadding: CGFloat = 18
    private let raisedOverlap: CGFloat = 22

    var body: some View {
        Color.white
            .frame(height: 64 - raisedOverlap + bottomPadding)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                EntryShareMenu(content: content)
                    .disabled(!isEnabled)
                    .background(Color.white, in: Circle())
                    .offset(y: -raisedOverlap)
            }
            .background(Color.white.ignoresSafeArea(.container, edges: .bottom))
    }
}
