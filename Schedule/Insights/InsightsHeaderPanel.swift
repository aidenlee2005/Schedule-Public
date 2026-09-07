import SwiftUI

/// Only this slot depends on the removable Companion module.
struct InsightsHeaderPanel: View {
    let events: [UpcomingEvent]
    let nextStep: String?
    let onSelect: (UpcomingEvent) -> Void
    @State private var showingCompanion = !ProcessInfo.processInfo.arguments.contains("--disable-companion")

    var body: some View {
        #if DISABLE_COMPANION
        fallback
        #else
        if showingCompanion {
            CompanionCard(events: events, nextStep: nextStep, onSelect: onSelect) { showingCompanion = false }
        } else {
            VStack(spacing: 12) {
                fallback
                Button("Show Companion") { showingCompanion = true }.font(.footnote)
            }
        }
        #endif
    }

    private var fallback: some View {
        UpcomingSummary(events: events, onSelect: onSelect)
            .padding(18).cardBackground(cornerRadius: 22)
    }
}
