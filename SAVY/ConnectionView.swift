import SwiftUI

enum ConnectionLayout {
    static let horizontalPadding: CGFloat = 20
    static let gridSpacing: CGFloat = 8
    static let gridColumnCount = 3
    static let gridCardSide: CGFloat = 108
    static let featuredCardWidth: CGFloat = 336
    static let featuredCardHeight: CGFloat = 196
}

enum ConnectionCardStyle {
    case black
    case crimson
    case white

    static func style(for index: Int) -> ConnectionCardStyle {
        switch index % 3 {
        case 0: .black
        case 1: .crimson
        default: .white
        }
    }
}

enum ConnectionDisplayText {
    static func gridPhrase(_ text: String, maxWords: Int = 3) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let words = trimmed.split(separator: " ")
        guard words.count > maxWords else { return trimmed }
        return words.prefix(maxWords).joined(separator: " ")
    }

    static func featuredTitle(_ text: String, maxWords: Int = 14) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let words = trimmed.split(separator: " ")
        guard words.count > maxWords else { return trimmed }
        return words.prefix(maxWords).joined(separator: " ")
    }
}

struct ConnectionView: View {
    let section: LeverageSection
    var onSignOut: (() -> Void)?

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: ConnectionLayout.gridSpacing),
            count: ConnectionLayout.gridColumnCount
        )
    }

    private var featuredItems: [LeverageItem] {
        guard section.items.count > 3 else { return [] }
        return Array(section.items.prefix(3))
    }

    private var gridItems: [LeverageItem] {
        if section.items.count > 3 {
            return Array(section.items.dropFirst(3))
        }
        return section.items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                connectionHeader

                if !featuredItems.isEmpty {
                    featuredSection
                }

                if !gridItems.isEmpty {
                    gridSection
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }

    private var connectionHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("CONNECTION")
                    .font(SavyTypography.displaySerif(34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                headerIconButton(symbol: "magnifyingglass")

                if let onSignOut {
                    Menu {
                        Button("Sign Out", role: .destructive, action: onSignOut)
                    } label: {
                        headerIconButton(symbol: "line.3.horizontal")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Account menu")
                }
            }
            .padding(.horizontal, ConnectionLayout.horizontalPadding)
            .padding(.top, 56)
            .padding(.bottom, 18)

            Rectangle()
                .fill(SavyTheme.crimson)
                .frame(height: 2)
        }
        .background(Color.black)
    }

    private func headerIconButton(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.14), in: Circle())
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, ConnectionLayout.horizontalPadding)
                .padding(.top, 24)

            LazyVGrid(columns: gridColumns, spacing: ConnectionLayout.gridSpacing) {
                ForEach(Array(gridItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        LeverageDetailView(section: section, item: item)
                    } label: {
                        ConnectionGridCard(
                            item: item,
                            style: ConnectionCardStyle.style(for: index)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ConnectionLayout.horizontalPadding)
            .padding(.bottom, 20)
        }
        .background(Color.white)
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connection")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))

                Spacer()

                Text("See all")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SavyTheme.crimson)
            }
            .padding(.horizontal, ConnectionLayout.horizontalPadding)
            .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(featuredItems) { item in
                        NavigationLink {
                            LeverageDetailView(section: section, item: item)
                        } label: {
                            ConnectionFeaturedCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ConnectionLayout.horizontalPadding)
            }
            .padding(.bottom, 28)
        }
        .background(Color.black)
    }
}

private struct ConnectionFeaturedCard: View {
    let item: LeverageItem

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 10) {
                Text(ConnectionDisplayText.featuredTitle(item.title))
                    .font(SavyTypography.displaySerif(26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Rectangle()
                    .fill(SavyTheme.crimson)
                    .frame(width: 36, height: 2)

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: ConnectionLayout.featuredCardWidth, height: ConnectionLayout.featuredCardHeight, alignment: .leading)
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct ConnectionGridCard: View {
    let item: LeverageItem
    let style: ConnectionCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(foregroundColor.opacity(0.35))
                .frame(width: 14, height: 10)
                .padding(.bottom, 8)

            Text(ConnectionDisplayText.gridPhrase(item.title))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(foregroundColor)
                .lineSpacing(0)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(cardBackground)
        .overlay {
            if style == .white {
                Rectangle()
                    .stroke(Color.black.opacity(0.14), lineWidth: 1)
            }
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .black, .crimson: .white
        case .white: .black
        }
    }

    private var cardBackground: Color {
        switch style {
        case .black: .black
        case .crimson: SavyTheme.crimson
        case .white: .white
        }
    }
}
