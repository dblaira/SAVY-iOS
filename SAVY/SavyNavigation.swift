import Foundation
import SwiftUI

enum SavyNavigationSection: String, CaseIterable, Identifiable {
    case now
    case essays
    case beliefs
    case news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now:
            "ACTION"
        case .essays:
            "Essays"
        case .beliefs:
            "Beliefs"
        case .news:
            "News"
        }
    }

    var symbolName: String {
        switch self {
        case .now:
            "sparkle"
        case .essays:
            "doc.text"
        case .beliefs:
            "quote.bubble"
        case .news:
            "newspaper"
        }
    }

    var leverageSectionID: String? {
        switch self {
        case .now:
            nil
        case .essays:
            "field-essays"
        case .beliefs:
            "beliefs"
        case .news:
            "news-channel"
        }
    }
}

@MainActor
final class SavyNavigationState: ObservableObject {
    @Published var activeSection: SavyNavigationSection = .now
    @Published var isRadialMenuPresented = false
    @Published var activeComposerKind: MetadataEntryKind?

    func toggleRadialMenu() {
        isRadialMenuPresented.toggle()
    }

    func dismissRadialMenu() {
        isRadialMenuPresented = false
    }

    func openComposer(for kind: MetadataEntryKind) {
        activeComposerKind = kind
        isRadialMenuPresented = false
    }
}
