import WidgetKit

struct HermexWatchEntry: TimelineEntry {
    let date: Date
}

struct HermexWatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HermexWatchEntry {
        HermexWatchEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (HermexWatchEntry) -> Void) {
        completion(HermexWatchEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HermexWatchEntry>) -> Void) {
        completion(Timeline(entries: [HermexWatchEntry(date: Date())], policy: .never))
    }
}
