import Foundation
import WidgetKit

/// The launcher has no changing data, permissions, file access or network work.
struct WatchLauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchLauncherEntry {
        WatchLauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchLauncherEntry) -> Void) {
        completion(WatchLauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchLauncherEntry>) -> Void) {
        completion(Timeline(entries: [WatchLauncherEntry(date: .now)], policy: .never))
    }
}
