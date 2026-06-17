import SwiftUI

enum RootHomeLayout {
    static let leverageGridColumnCount = 2
    static let leverageGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 17),
        count: leverageGridColumnCount
    )
    static let horizontalPadding: CGFloat = 31
    static let heroTopPadding: CGFloat = 92
    static let latestSectionBandHeight: CGFloat = 80
    static let floatingCaptureAlignment: Alignment = .bottom
    static let floatingCaptureBottomPadding: CGFloat = 56
    static let floatingCaptureSize: CGFloat = 72
    static let floatingCaptureBackground = SavyTheme.crimson
}

struct RootView: View {
    @StateObject private var store = CaptureStore()
    @State private var isCapturing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: RootHomeLayout.floatingCaptureAlignment) {
                SavyTheme.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, RootHomeLayout.horizontalPadding)
                            .padding(.top, RootHomeLayout.heroTopPadding)

                        principleCard
                            .padding(.horizontal, RootHomeLayout.horizontalPadding)
                            .padding(.top, 35)

                        latestSection
                    }
                    .padding(.bottom, 150)
                }

                Button {
                    isCapturing = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 33, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(
                            width: RootHomeLayout.floatingCaptureSize,
                            height: RootHomeLayout.floatingCaptureSize
                        )
                        .background(RootHomeLayout.floatingCaptureBackground, in: Circle())
                        .shadow(color: SavyTheme.crimson.opacity(0.28), radius: 18, y: 10)
                }
                .accessibilityLabel("Capture")
                .padding(.bottom, RootHomeLayout.floatingCaptureBottomPadding)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isCapturing) {
                NativeCaptureView { title, meaning in
                    store.save(title: title, meaning: meaning)
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SAVY")
                    .font(.system(size: 48, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(SavyTheme.crimson)

                Text("A STUDY IN LEVERAGE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(.black.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isCapturing = true
            } label: {
                Image(systemName: "pencil.line")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.42))
                    .frame(width: 45, height: 45)
                    .background(SavyTheme.paperAccent, in: Circle())
            }
            .accessibilityLabel("Quick capture")
            .offset(y: -10)
        }
    }

    private var principleCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(SavyTheme.crimson)
                    .frame(width: 4, height: 75)

                Text("“The 10 minutes exporting\nyour judgment builds a\nsystem th...”")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .italic()
                    .lineSpacing(4)
                    .foregroundStyle(SavyTheme.ink)
            }

            HStack(spacing: 8) {
                Capsule()
                    .fill(SavyTheme.crimson)
                    .frame(width: 27, height: 7)

                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(.black.opacity(0.12))
                        .frame(width: 7, height: 7)
                }

                Text("2 / 7")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(.black.opacity(0.3))
            }
            .padding(.leading, 50)
        }
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
        .padding(.horizontal, 34)
        .padding(.vertical, 26)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("LATEST LEVERAGE")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(SavyTheme.ink)
                .frame(maxWidth: .infinity, minHeight: RootHomeLayout.latestSectionBandHeight, alignment: .leading)
                .padding(.horizontal, RootHomeLayout.horizontalPadding)
                .background(SavyTheme.sectionBand)

            LazyVGrid(columns: RootHomeLayout.leverageGridColumns, spacing: 27) {
                ForEach(HomeLeverageCard.referenceCards) { card in
                    HomeLeverageCardView(card: card)
                }
            }
            .padding(.horizontal, RootHomeLayout.horizontalPadding)
        }
        .padding(.top, 41)
    }
}

struct HomeLeverageCard: Identifiable {
    let id: String
    let eyebrow: String
    let title: String

    static let referenceCards: [HomeLeverageCard] = [
        HomeLeverageCard(id: "news", eyebrow: "NEWS CHANNEL", title: "News\nChannel"),
        HomeLeverageCard(id: "essays", eyebrow: "FIELD ESSAYS", title: "Field\nEssays"),
        HomeLeverageCard(id: "ontology", eyebrow: "ONTOLOGY", title: "Adam's\nOntology"),
        HomeLeverageCard(id: "beliefs", eyebrow: "BELIEFS", title: "Belief\nLibrary")
    ]
}

private struct HomeLeverageCardView: View {
    let card: HomeLeverageCard

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(spacing: 10) {
                Circle()
                    .fill(SavyTheme.green)
                    .frame(width: 10, height: 10)

                Text(card.eyebrow)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.black.opacity(0.36))
            }

            Text(card.title)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .lineSpacing(-1)
                .foregroundStyle(SavyTheme.ink)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
        .padding(.top, 31)
        .padding(.horizontal, 30)
        .padding(.bottom, 22)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

struct NativeCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    var onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    TextField("What is worth preserving?", text: $title)
                    TextField("Why does it matter?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Native by default") {
                    Label("Photos, location, notifications, widgets, and intents come next.", systemImage: "iphone")
                }
            }
            .navigationTitle("Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, note)
                        dismiss()
                    }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct NativeCapabilityRow: View {
    let capability: NativeCapability

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: capability.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SavyTheme.crimson)
                .frame(width: 34, height: 34)
                .background(SavyTheme.crimson.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .foregroundStyle(SavyTheme.ink)

                Text(capability.description)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundStyle(.black.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NativeCapability: Identifiable {
    let id: String
    let title: String
    let description: String
    let symbol: String

    static let initial: [NativeCapability] = [
        NativeCapability(
            id: "capture",
            title: "Native Capture",
            description: "SwiftUI form, keyboard, sheet, and state.",
            symbol: "square.and.pencil"
        ),
        NativeCapability(
            id: "notifications",
            title: "Notifications",
            description: "Local notifications and actions.",
            symbol: "bell.badge"
        ),
        NativeCapability(
            id: "context",
            title: "Context",
            description: "Photos, location, widgets, intents, and device-first features.",
            symbol: "sparkles"
        )
    ]
}

enum SavyTheme {
    static let crimson = Color(red: 230 / 255, green: 14 / 255, blue: 68 / 255)
    static let green = Color(red: 42 / 255, green: 184 / 255, blue: 96 / 255)
    static let paper = Color(red: 248 / 255, green: 244 / 255, blue: 237 / 255)
    static let paperAccent = Color(red: 239 / 255, green: 235 / 255, blue: 228 / 255)
    static let sectionBand = Color(red: 244 / 255, green: 239 / 255, blue: 231 / 255)
    static let ink = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
}

#Preview {
    RootView()
}
