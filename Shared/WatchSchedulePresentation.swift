import Foundation

nonisolated enum WatchClassStatus: Equatable, Sendable {
    case ongoing(WatchLesson)
    case upcoming(WatchLesson)
    case semesterEnded
    case noUpcomingClasses
    case noSemester
}

nonisolated struct WatchAgenda: Equatable, Sendable {
    let date: Date
    let lessons: [WatchLesson]
    let isTomorrow: Bool
}

extension WatchSnapshot {
    func classStatus(at now: Date) -> WatchClassStatus {
        guard semester != nil, let end = termEnd else { return .noSemester }
        if now >= end { return .semesterEnded }
        if let current = lessons(on: now).first(where: { $0.start <= now && now < $0.end }) {
            return .ongoing(current)
        }
        if let next = nextLesson(after: now) { return .upcoming(next) }
        return .noUpcomingClasses
    }

    /// Empty days remain visible, including weekends. Only a day that actually had
    /// classes advances to tomorrow once its last class has finished.
    func agenda(at now: Date) -> WatchAgenda {
        let today = calendar.startOfDay(for: now)
        let classes = lessons(on: today)
        if let lastEnd = classes.map(\.end).max(), now >= lastEnd,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            return WatchAgenda(date: tomorrow, lessons: lessons(on: tomorrow), isTomorrow: true)
        }
        return WatchAgenda(date: today, lessons: classes, isTomorrow: false)
    }
}
