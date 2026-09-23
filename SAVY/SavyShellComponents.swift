import SwiftUI
import UIKit

extension View {
    /// The white canvas travels with the header. Navy behind the ScrollView is exposed
    /// only above it during a pull. Extend white below the content for bottom bounce.
    func savyHeaderPageContent(minHeight: CGFloat) -> some View {
        frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
            .background {
                GeometryReader { geometry in
                    SavyTheme.contentBackground
                        .frame(height: geometry.size.height + minHeight)
                }
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    func savyHeaderOverscrollCapture(_ screen: String) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_CAPTURE_HEADER_OVERSCROLL"),
           ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") {
            modifier(SavyHeaderOverscrollCapture(screen: screen))
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Applied to the main navigation hierarchy so every page header stays solid.
    @ViewBuilder
    func savySolidTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

#if DEBUG
/// Test-only evidence from the actual UIWindow while the finger is still holding a pull.
/// A screenshot after XCUI's drag returns would miss the overscroll defect entirely.
private struct SavyHeaderOverscrollCapture: ViewModifier {
    let screen: String
    @State private var offset: CGFloat = 0
    @State private var isScheduled = false
    @State private var didCapture = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                offset = newOffset
                guard newOffset < -40, !isScheduled, !didCapture else { return }
                isScheduled = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    defer { isScheduled = false }
                    guard offset < -40 else { return }
                    didCapture = capture()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if didCapture {
                    Text("Header pull captured")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .accessibilityIdentifier("headerOverscrollCapture-\(screen)")
                        .allowsHitTesting(false)
                }
            }
    }

    @MainActor private func capture() -> Bool {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return false }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let png = image.pngData() else { return false }
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("SAVY/HeaderOverscrollTest", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(screen).png"), options: .atomic)
            let metadata: [String: Any] = [
                "screen": screen, "normalizedOffsetY": offset,
                "scale": image.scale, "timestamp": Date().timeIntervalSince1970,
                "widthPoints": window.bounds.width, "heightPoints": window.bounds.height
            ]
            try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                .write(to: directory.appendingPathComponent("\(screen).json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif

enum SavyHapticFeedback {
    static let primaryImpactIntensity: CGFloat = 1.0

    @MainActor
    static func primaryImpact() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred(intensity: primaryImpactIntensity)
    }

    @MainActor
    static func menuOpen() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.92)
    }

    @MainActor
    static func menuClose() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.78)
    }

    @MainActor
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

enum SavyFabMenuMotion {
    static let open = Animation.spring(response: 0.34, dampingFraction: 0.72)
    static let close = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

enum SavyAccountMenuAppearance {
    case onDarkHero
    case onWhiteHeader
}

struct SavyAccountMenuButton: View {
    var onSignOut: (() -> Void)?
    var onOpenPersonalAuthorityReview: (() -> Void)?
    var appearance: SavyAccountMenuAppearance = .onDarkHero

    var body: some View {
        Menu {
            if let onOpenPersonalAuthorityReview {
                Button {
                    onOpenPersonalAuthorityReview()
                } label: {
                    Label("Teach Cowboy AI", systemImage: "sparkles")
                }
            }

            if onOpenPersonalAuthorityReview != nil, onSignOut != nil {
                Divider()
            }

            if let onSignOut {
                Button("Sign Out", role: .destructive) {
                    onSignOut()
                }
            }
        } label: {
            Image(systemName: RootHomeLayout.accountMenuSymbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(
                    width: RootHomeLayout.accountMenuButtonSize,
                    height: RootHomeLayout.accountMenuButtonSize
                )
                .background(backgroundColor, in: Circle())
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SAVY menu")
    }

    private var iconColor: Color {
        switch appearance {
        case .onDarkHero:
            .white.opacity(0.78)
        case .onWhiteHeader:
            SavyTheme.bottomNavTan
        }
    }

    private var backgroundColor: Color {
        switch appearance {
        case .onDarkHero:
            .white.opacity(0.08)
        case .onWhiteHeader:
            SavyTheme.deepNavy
        }
    }

    private var borderColor: Color {
        switch appearance {
        case .onDarkHero:
            .white.opacity(0.12)
        case .onWhiteHeader:
            SavyTheme.bottomNavTan.opacity(0.35)
        }
    }
}

struct SavyBottomNavigationBar: View {
    @ObservedObject var navigationState: SavyNavigationState
    let onSelectCaptureKind: (MetadataEntryKind) -> Void

    @State private var draggingFab = false
    @State private var menuWasOpenAtStart = false

    private let barBackground = SavyTheme.bottomNavTan
    private let inactiveColor = Color(red: 0.34, green: 0.27, blue: 0.21).opacity(0.68)
    private let navyTopBandHeight: CGFloat = 24
    private var topBandColor: Color {
        navigationState.activeSection == .now ? SavyTheme.deepNavy : SavyTheme.pageBackground
    }

    var body: some View {
        VStack(spacing: 0) {
            topBandColor
                .frame(height: navyTopBandHeight)

            ZStack(alignment: .top) {
                barBackground

                HStack(alignment: .center, spacing: 0) {
                    ForEach(SavyNavigationSection.leadingSections) { section in
                        navigationButton(for: section)
                    }

                    Spacer()
                        .frame(maxWidth: .infinity)

                    ForEach(SavyNavigationSection.trailingSections) { section in
                        navigationButton(for: section)
                    }
                }
                .padding(.horizontal, RootHomeLayout.bottomNavigationHorizontalPadding)
                .frame(maxHeight: .infinity, alignment: .top)

                ZStack {
                    if navigationState.isRadialMenuPresented {
                        // Four doors on one arc, left to right: Reminder, Action, Post, Calendar.
                        fabOption(.reminder).offset(x: -92, y: -62)
                        fabOption(.action).offset(x: -40, y: -122)
                        fabOption(.post).offset(x: 40, y: -122)
                        fabOption(.calendar).offset(x: 92, y: -62)
                    }

                    captureFab
                        .offset(y: -22)
                }
            }
            .frame(height: RootHomeLayout.bottomNavigationHeight - navyTopBandHeight)
        }
        .frame(height: RootHomeLayout.bottomNavigationHeight)
        .background(alignment: .top) {
            topBandColor
                .frame(
                    height: RootHomeLayout.bottomNavNavyRiserHeight + RootHomeLayout.bottomNavigationTopPadding
                )
                .offset(
                    y: -(RootHomeLayout.bottomNavNavyRiserHeight + RootHomeLayout.bottomNavigationTopPadding)
                )
        }
        .background(barBackground.ignoresSafeArea(edges: .bottom))
        .animation(SavyFabMenuMotion.open, value: navigationState.isRadialMenuPresented)
    }

    private var captureFab: some View {
        borderedSymbol(navigationState.isRadialMenuPresented ? "xmark" : "bolt.fill")
            .frame(
                width: RootHomeLayout.floatingCaptureSize,
                height: RootHomeLayout.floatingCaptureSize
            )
            .background(RootHomeLayout.floatingCaptureBackground, in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !draggingFab {
                            draggingFab = true
                            menuWasOpenAtStart = navigationState.isRadialMenuPresented
                            if !navigationState.isRadialMenuPresented {
                                SavyHapticFeedback.menuOpen()
                                withAnimation(SavyFabMenuMotion.open) {
                                    navigationState.isRadialMenuPresented = true
                                }
                            }
                        }

                        let target = targetKind(for: value.translation)
                        if target != navigationState.highlightedCaptureKind {
                            navigationState.highlightedCaptureKind = target
                            if target != nil {
                                SavyHapticFeedback.selection()
                            }
                        }
                    }
                    .onEnded { _ in
                        if let selected = navigationState.highlightedCaptureKind {
                            SavyHapticFeedback.primaryImpact()
                            withAnimation(SavyFabMenuMotion.close) {
                                onSelectCaptureKind(selected)
                            }
                        } else if menuWasOpenAtStart {
                            SavyHapticFeedback.menuClose()
                            withAnimation(SavyFabMenuMotion.close) {
                                navigationState.dismissRadialMenu()
                            }
                        }

                        draggingFab = false
                        navigationState.highlightedCaptureKind = nil
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                navigationState.isRadialMenuPresented
                    ? "Close quick entry menu"
                    : "Open quick entry menu"
            )
            .accessibilityIdentifier("chargeFab")
    }

    private func fabOption(_ kind: MetadataEntryKind) -> some View {
        let isHighlighted = navigationState.highlightedCaptureKind == kind

        return Button {
            SavyHapticFeedback.primaryImpact()
            withAnimation(SavyFabMenuMotion.close) {
                onSelectCaptureKind(kind)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: kind.fabMenuSymbolName)
                    .font(.system(size: RootHomeLayout.radialMenuIconSize, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(
                        width: RootHomeLayout.radialMenuButtonSize,
                        height: RootHomeLayout.radialMenuButtonSize
                    )
                    .background(
                        isHighlighted ? SavyTheme.crimson : Brand.nearBlack,
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                .white.opacity(isHighlighted ? 0.9 : 0.15),
                                lineWidth: 1.5
                            )
                    )
                    .scaleEffect(isHighlighted ? 1.15 : 1)

                Text(kind.menuTitle)
                    .font(.system(size: RootHomeLayout.radialMenuLabelSize, weight: .heavy))
                    .foregroundStyle(SavyTheme.crimson)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.menuTitle)
    }

    private func borderedSymbol(_ name: String) -> some View {
        ZStack {
            Image(systemName: name)
                .font(.system(size: RootHomeLayout.floatingCaptureSymbolOuterSize, weight: .bold))
                .foregroundStyle(.black)
            Image(systemName: name)
                .font(.system(size: RootHomeLayout.floatingCaptureSymbolInnerSize, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func targetKind(for translation: CGSize) -> MetadataEntryKind? {
        guard hypot(translation.width, translation.height) > 30 else { return nil }
        let angle = atan2(-translation.height, translation.width) * 180 / .pi
        if angle >= 90 && angle < 135 { return .action }
        if angle >= 45 && angle < 90 { return .post }
        if angle >= -45 && angle < 45 { return .calendar }
        if angle >= 135 || angle < -135 { return .reminder }
        return nil
    }

    private func navigationButton(for section: SavyNavigationSection) -> some View {
        let isActive = navigationState.activeSection == section

        return Button {
            SavyHapticFeedback.selection()
            navigationState.activeSection = section
            withAnimation(SavyFabMenuMotion.close) {
                navigationState.dismissRadialMenu()
            }
        } label: {
            VStack(spacing: RootHomeLayout.bottomNavigationIconLabelSpacing) {
                Image(systemName: section.symbolName)
                    .font(.system(
                        size: RootHomeLayout.bottomNavigationIconSize,
                        weight: RootHomeLayout.bottomNavigationIconWeight
                    ))

                Text(section.title)
                    .font(.system(size: RootHomeLayout.bottomNavigationLabelSize, weight: isActive ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.top, RootHomeLayout.bottomNavigationTopPadding)
            .padding(.bottom, RootHomeLayout.bottomNavigationBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(isActive ? SavyTheme.crimson : inactiveColor)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
    }
}
