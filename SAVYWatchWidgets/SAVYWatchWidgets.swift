import SwiftUI
import WidgetKit

// Screen one of Adam's plan: a watch face complication and Smart Stack entry. A tap opens
// SAVY on the four doors. The face never changes, so the timeline holds one entry.

struct CaptureDoorEntry: TimelineEntry {
    let date: Date
}

struct CaptureDoorProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureDoorEntry {
        CaptureDoorEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CaptureDoorEntry) -> Void) {
        completion(CaptureDoorEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CaptureDoorEntry>) -> Void) {
        completion(Timeline(entries: [CaptureDoorEntry(date: Date())], policy: .never))
    }
}

private enum ComplicationTheme {
    static let crimson = Color(red: 230 / 255, green: 14 / 255, blue: 68 / 255)
}

struct CaptureDoorView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel("SAVY")
        case .accessoryInline:
            Label("SAVY", systemImage: "mic.fill")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("SAVY", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(ComplicationTheme.crimson)
                    .widgetAccentable()
                HStack(spacing: 10) {
                    ForEach(["bolt", "bell", "calendar", "text.bubble"], id: \.self) { symbol in
                        Image(systemName: symbol)
                    }
                }
                .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct SAVYWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SAVYCaptureDoor", provider: CaptureDoorProvider()) { _ in
            CaptureDoorView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SAVY Capture")
        .description("Opens SAVY on Action, Reminder, Calendar and Social.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
