import SwiftUI

/// Home's small projection of the saved entry. Other fields remain in the entry itself.
struct SavyCarouselDetail: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case theme, pattern, priority, energy
    }

    let kind: Kind
    let text: String
    let systemImage: String
    let accessibilityLabel: String

    var id: Kind { kind }

    static func values(for reminder: Reminder) -> [SavyCarouselDetail] {
        var values: [SavyCarouselDetail] = []
        let savedName = reminder.postThemeName.flatMap { name in
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        }
        let theme = PostThemeCatalog.theme(id: reminder.postThemeID)
            ?? PostThemeCatalog.themes.first { $0.name == savedName }
        if let name = savedName ?? theme?.name {
            values.append(SavyCarouselDetail(
                kind: .theme,
                text: name,
                systemImage: theme?.questions.first?.symbol ?? "list.bullet",
                accessibilityLabel: "Theme: \(name)"
            ))
        }
        if reminder.context != .none {
            values.append(SavyCarouselDetail(
                kind: .pattern,
                text: reminder.context.label,
                systemImage: "list.number",
                accessibilityLabel: "Pattern: \(reminder.context.label)"
            ))
        }
        if reminder.priority != .none {
            values.append(SavyCarouselDetail(
                kind: .priority,
                text: "\(reminder.priority.label) priority",
                systemImage: "exclamationmark.3",
                accessibilityLabel: "Priority: \(reminder.priority.label)"
            ))
        }
        if reminder.energy != .none {
            values.append(SavyCarouselDetail(
                kind: .energy,
                text: "\(reminder.energy.label) energy",
                systemImage: "bolt",
                accessibilityLabel: "Energy: \(reminder.energy.label)"
            ))
        }
        return values
    }
}

/// Intrinsic one-to-three-row footer; the card owns its bottom-left placement.
struct SavyCarouselDetailPills: View {
    let details: [SavyCarouselDetail]

    var body: some View {
        if !details.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                pillRow(details.filter { $0.kind == .theme || $0.kind == .pattern })
                pillRow(details.filter { $0.kind == .priority || $0.kind == .energy })
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // These deliberately quiet details keep the approved regular weight.
            .environment(\.legibilityWeight, .regular)
        }
    }

    @ViewBuilder
    private func pillRow(_ row: [SavyCarouselDetail]) -> some View {
        if !row.isEmpty {
            SavyCarouselPillLayout(spacing: 4) {
                ForEach(row) { detail in
                    HStack(spacing: 3) {
                        Image(systemName: detail.systemImage)
                            .font(.system(size: 10, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Brand.crimson)
                            .accessibilityHidden(true)
                        Text(detail.text)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(Color(hex: 0x737373))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Color(hex: 0xE2D4B9), in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(detail.accessibilityLabel)
                    .accessibilityIdentifier("carouselDetail-\(detail.kind.rawValue)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The existing counts and post references on an expanded lower Home destination card.
struct SavyHomeCardDetails {
    let countText: String
    let postReferences: String
    let background: Color
    let foreground: Color
}

struct SavyHomeCardDetailPills: View {
    let details: SavyHomeCardDetails

    var body: some View {
        SavyCarouselPillLayout(spacing: 4) {
            if !details.countText.isEmpty {
                pill(details.countText, identifier: "homeCardDetail-count")
            }
            if !details.postReferences.isEmpty {
                pill(details.postReferences, identifier: "homeCardDetail-posts")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.legibilityWeight, .regular)
    }

    private func pill(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(details.foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(details.background, in: Capsule())
            .accessibilityLabel(text)
            .accessibilityIdentifier(identifier)
    }
}

/// Wraps whole pills in their saved-field order. The layout never scales the text.
private struct SavyCarouselPillLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard !subviews.isEmpty else { return (.zero, []) }
        let availableWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? .greatestFiniteMagnitude
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, availableWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}
