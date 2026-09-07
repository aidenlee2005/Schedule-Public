import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Setting.createdAt, order: .reverse) private var terms: [Setting]
    @AppStorage("activeTermID", store: AppPreferences.defaults) private var activeTermID = ""
    @State private var selectedTab = 0

    private var activeTerm: Setting? {
        terms.first { $0.id.uuidString == activeTermID } ?? terms.first
    }

    var body: some View {
        Group {
            if let term = activeTerm {
                TabView(selection: $selectedTab) {
                    HomeView(term: term)
                        .tabItem { Label("Schedule", systemImage: "rectangle.grid.3x2") }.tag(0)
                    CalendarView(term: term)
                        .tabItem { Label("Calendar", systemImage: "calendar") }.tag(1)
                    TasksView(term: term)
                        .tabItem { Label("Tasks", systemImage: "checkmark.circle") }.tag(2)
                    InsightsView(term: term)
                        .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }.tag(3)
                }
                .id(term.id)
                .onAppear { activeTermID = term.id.uuidString }
            } else {
                ProgressView("Loading semester…")
            }
        }
    }
}
