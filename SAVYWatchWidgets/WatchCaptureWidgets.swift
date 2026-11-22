import SwiftUI
import WidgetKit

// Watch capture kit: the same in every app that uses it.
// A watch face complication and Smart Stack entry. A tap opens the app on its doors.
// The face never changes, so the timeline holds one entry.

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
                .widgetLabel(WatchCaptureConfig.appName)
        case .accessoryInline:
            Label(WatchCaptureConfig.appName, systemImage: "mic.fill")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label(WatchCaptureConfig.appName, systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.accentOnDark)
                    .widgetAccentable()
                HStack(spacing: 10) {
                    ForEach(WatchCaptureKind.allCases) { kind in
                        Image(systemName: kind.symbol)
                    }
                }
                .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct WatchCaptureWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchCaptureConfig.appName + "CaptureDoor", provider: CaptureDoorProvider()) { _ in
            CaptureDoorView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WatchCaptureConfig.appName + " Capture")
        .description("Opens " + WatchCaptureConfig.appName + " on "
                     + ListFormatter.localizedString(byJoining: WatchCaptureKind.allCases.map(\.label)) + ".")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
