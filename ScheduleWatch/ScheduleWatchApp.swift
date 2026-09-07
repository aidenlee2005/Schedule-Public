import SwiftUI

@main
struct ScheduleWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            TimelineView(.everyMinute) { timeline in
                WatchDashboard(store: store, now: timeline.date)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.requestLatest() }
            }
        }
    }
}
