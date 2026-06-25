import Foundation
import SwiftUI

enum SavyNavigationSection: String, CaseIterable, Identifiable {
    case now
    case reminders
    case actions
    case calendar

    var id: String { rawValue }

    static let leadingSections: [SavyNavigationSection] = [.now, .reminders]
    static let trailingSections: [SavyNavigationSection] = [.actions, .calendar]

    var title: String {
        switch self {
        case .now:
            "Now"
        case .reminders:
            "Reminders"
        case .actions:
            "Actions"
        case .calendar:
            "Calendar"
        }
    }

    var symbolName: String {
        switch self {
        case .now:
            "house"
        case .reminders:
            "bell"
        case .actions:
            "bolt"
        case .calendar:
            "calendar"
        }
    }
}

@MainActor
final class SavyNavigationState: ObservableObject {
    @Published var activeSection: SavyNavigationSection = .now
    @Published var isRadialMenuPresented = false
    @Published var highlightedCaptureKind: MetadataEntryKind?
    @Published var activeComposerKind: MetadataEntryKind?

    func toggleRadialMenu() {
        isRadialMenuPresented.toggle()
        if !isRadialMenuPresented {
            highlightedCaptureKind = nil
        }
    }

    func dismissRadialMenu() {
        isRadialMenuPresented = false
        highlightedCaptureKind = nil
    }

    func openComposer(for kind: MetadataEntryKind) {
        activeComposerKind = kind
        isRadialMenuPresented = false
        highlightedCaptureKind = nil
    }
}
