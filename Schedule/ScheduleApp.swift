import SwiftUI
import SwiftData

@main
struct ScheduleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var container: ModelContainer?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                } else if let startupError {
                    ContentUnavailableView {
                        Label("Unable to Open Schedule", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your saved data has not been deleted.\n\(startupError)")
                    } actions: {
                        Button("Try Again", action: openStore)
                    }
                } else {
                    ProgressView("Opening Schedule…")
                        .task { openStore() }
                }
            }
            .tint(AppTheme.accent)
            .onChange(of: scenePhase) { _, _ in PhoneWatchSync.shared.refresh() }
        }
    }

    private func openStore() {
        do {
            let schema = AppSchema.schema
            let config = ModelConfiguration("ScheduleStore_v2", schema: schema,
                isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            let opened = try ModelContainer(for: schema, configurations: [config])
            opened.mainContext.autosaveEnabled = false
            try TermManager.prepare(in: opened.mainContext)
            PhoneWatchSync.shared.configure(container: opened, defaults: AppPreferences.defaults)
            container = opened
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }
}
