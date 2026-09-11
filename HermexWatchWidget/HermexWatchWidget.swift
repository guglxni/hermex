import SwiftUI
import WidgetKit

struct HermexWatchWidget: Widget {
    let kind = "HermexWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermexWatchTimelineProvider()) { entry in
            HermexWatchWidgetView(entry: entry)
        }
        .configurationDisplayName("Hermex")
        .description("Shows whether Hermex is ready on Apple Watch.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct HermexWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HermexWatchEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "iphone.and.arrow.forward")
                    .widgetLabel("Set up")
            case .accessoryInline:
                Label("Set up on iPhone", systemImage: "iphone")
            default:
                VStack(alignment: .leading) {
                    Text("Hermex")
                        .font(.headline)
                    Text("Set up on iPhone")
                        .font(.caption)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
