import SwiftUI

struct UpcomingEvent: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let isExam: Bool

    static func collect(assignments: [Assignment], exams: [Exam], now: Date = Date()) -> [UpcomingEvent] {
        let tasks = assignments.filter { !$0.isCompleted }.map {
            UpcomingEvent(id: $0.id, title: $0.content, date: $0.dueDate, isExam: false)
        }
        let tests = exams.filter { $0.date >= now }.map {
            UpcomingEvent(id: $0.id, title: $0.subject, date: $0.date, isExam: true)
        }
        return (tasks + tests).sorted { $0.date < $1.date }
    }

    func relativeTime(now: Date = Date(), calendar: Calendar = .current) -> String {
        if date < now { return "Past due" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today · \(date.formatted(date: .omitted, time: .shortened))" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }
}

struct UpcomingSummary: View {
    let events: [UpcomingEvent]
    let onSelect: (UpcomingEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming Up").font(.subheadline.weight(.semibold))
            if events.isEmpty {
                Text("No upcoming deadlines. A little breathing room.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(events.prefix(2)) { event in
                Button { onSelect(event) } label: {
                    HStack(alignment: .center, spacing: AppTheme.Spacing.row) {
                        Image(systemName: event.isExam ? "pencil.and.list.clipboard" : "checklist")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(event.relativeTime()).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, height: 20)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityIdentifier("upcoming-\(event.title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
