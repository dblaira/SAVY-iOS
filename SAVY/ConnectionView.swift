import SwiftUI

enum ConnectionLayout {
    /// These heights reproduce the hierarchy measured from the Reminders screen.
    static let fullCardHeight: CGFloat = 186
    static let mediumCardHeight: CGFloat = 167
    static let minimalCardHeight: CGFloat = 124
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 11
    static let cardCornerRadius: CGFloat = 8
    static let headerHorizontalPadding: CGFloat = 24
}

enum ConnectionCardDetail {
    case full
    case medium
    case minimal

    var height: CGFloat {
        switch self {
        case .full: ConnectionLayout.fullCardHeight
        case .medium: ConnectionLayout.mediumCardHeight
        case .minimal: ConnectionLayout.minimalCardHeight
        }
    }
}

struct ConnectionView: View {
    @Environment(\.dismiss) private var dismiss

    let section: LeverageSection
    var onSignOut: (() -> Void)?

    private var pinnedItems: [LeverageItem] {
        Array(section.items.prefix(2))
    }

    private var remainingItems: [LeverageItem] {
        Array(section.items.dropFirst(pinnedItems.count))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    connectionHeader(topInset: proxy.safeAreaInsets.top)
                    connectionList
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(SavyTheme.deepNavy.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("connectionScreen")
    }

    private func connectionHeader(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(SavyTheme.crimson)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle()
                            .stroke(SavyTheme.crimson.opacity(0.85), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(section.title)
                .font(SavyTypography.bodoniModa(56, weight: 400, opticalSize: 56))
                .foregroundStyle(SavyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.top, 24)

            Text(section.headline)
                .font(SavyTypography.bodoniModa(22, weight: 400, opticalSize: 22))
                .foregroundStyle(SavyTheme.ink.opacity(0.62))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ConnectionLayout.headerHorizontalPadding)
        .padding(.top, topInset + 18)
        .padding(.bottom, 30)
        .background(SavyTheme.bottomNavTan)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SavyTheme.crimson)
                .frame(height: 2)
        }
    }

    private var connectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            connectionSectionHeading("PINNED", count: pinnedItems.count)

            VStack(spacing: ConnectionLayout.cardSpacing) {
                ForEach(Array(pinnedItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        LeverageDetailView(section: section, item: item)
                    } label: {
                        ConnectionBandCard(
                            item: item,
                            background: index == 0 ? .white : Brand.darkRed,
                            foreground: index == 0 ? SavyTheme.deepNavy : .white,
                            accent: index == 0 ? SavyTheme.crimson : .white,
                            detail: index == 0 ? .full : .medium,
                            showsPin: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("connectionCard-\(index)")
                }
            }

            if !remainingItems.isEmpty {
                connectionSectionHeading("ALL CONNECTIONS", count: remainingItems.count)
                    .padding(.top, 24)

                VStack(spacing: ConnectionLayout.cardSpacing) {
                    ForEach(Array(remainingItems.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            LeverageDetailView(section: section, item: item)
                        } label: {
                            ConnectionBandCard(
                                item: item,
                                background: SavyTheme.bottomNavTan,
                                foreground: SavyTheme.deepNavy,
                                accent: SavyTheme.crimson,
                                detail: .minimal,
                                showsPin: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("connectionCard-\(index + pinnedItems.count)")
                    }
                }
            }
        }
        .padding(.horizontal, ConnectionLayout.horizontalPadding)
        .padding(.top, 22)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SavyTheme.deepNavy)
    }

    private func connectionSectionHeading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .tracking(2.6)
                .foregroundStyle(SavyTheme.bottomNavTan)

            Spacer()

            Text("\(count)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SavyTheme.bottomNavTan.opacity(0.72))
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 12)
    }
}

private struct ConnectionBandCard: View {
    let item: LeverageItem
    let background: Color
    let foreground: Color
    let accent: Color
    let detail: ConnectionCardDetail
    let showsPin: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsPin {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(foreground.opacity(0.68))
            }

            Text(item.title)
                .font(SavyTypography.displaySerif(detail == .minimal ? 25 : 27, weight: .regular))
                .foregroundStyle(foreground)
                .lineLimit(detail == .minimal ? 2 : 3)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.leading)

            Rectangle()
                .fill(accent)
                .frame(width: 36, height: 2)

            if detail != .minimal, !item.summary.isEmpty {
                Text(item.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(foreground.opacity(0.72))
                    .lineLimit(detail == .full ? 3 : 1)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: detail.height)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: ConnectionLayout.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConnectionLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
