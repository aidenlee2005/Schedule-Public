import Foundation

/// A display-only copy. It deliberately contains no account credentials or mutation commands.
nonisolated struct WatchSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let contextKey = "schedule.snapshot.v1"
    static let requestKey = "schedule.requestSnapshot"
    static let maximumBytes = 2_000_000

    var version = currentVersion
    var sourceID: UUID
    var revision: Int
    var generatedAt: Date
    var timeZoneIdentifier: String
    var semester: WatchSemester?
    var courses: [WatchCourse]
    var assignments: [WatchAssignment]
    var exams: [WatchExam]

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw SnapshotError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw SnapshotError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == currentVersion, value.revision >= 0,
              TimeZone(identifier: value.timeZoneIdentifier) != nil else { throw SnapshotError.invalid }
        if let term = value.semester {
            guard (1...104).contains(term.totalWeeks), term.periods.count <= 24,
                  term.periods.allSatisfy({ (0..<1440).contains($0.startMinute)
                      && (1...1440).contains($0.endMinute) && $0.endMinute > $0.startMinute })
            else { throw SnapshotError.invalid }
        }
        return value
    }

    func isNewer(than previous: Self?) -> Bool {
        guard let previous else { return true }
        return sourceID != previous.sourceID || revision > previous.revision
    }

    enum SnapshotError: Error { case tooLarge, invalid }
}

nonisolated struct WatchSemester: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var startDate: Date
    var totalWeeks: Int
    var periods: [WatchPeriod]
}

nonisolated struct WatchPeriod: Codable, Equatable, Sendable {
    var startMinute: Int
    var endMinute: Int

    static func parse(_ text: String) -> Self? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        func minutes(_ text: Substring) -> Int? {
            let values = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard values.count == 2, let hour = Int(values[0]), let minute = Int(values[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        guard parts.count == 2, let start = minutes(parts[0]), let end = minutes(parts[1]), end > start
        else { return nil }
        return Self(startMinute: start, endMinute: end)
    }
}

nonisolated struct WatchCourse: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var classroom: String
    var teacher: String
    var meetings: [WatchMeeting]
}

nonisolated struct WatchMeeting: Codable, Equatable, Sendable {
    var id: UUID
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    /// 0 = every week, 1 = odd weeks, 2 = even weeks.
    var parity: Int
}

nonisolated struct WatchAssignment: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var courseName: String
    var dueDate: Date
}

nonisolated struct WatchExam: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var courseName: String
    var detail: String
    var date: Date
}

nonisolated struct WatchLesson: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var classroom: String
    var teacher: String
    var start: Date
    var end: Date
    var startPeriod: Int
    var endPeriod: Int
}

extension WatchSnapshot {
    var termStart: Date? {
        guard let semester else { return nil }
        let start = calendar.startOfDay(for: semester.startDate)
        return calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start)
    }

    var termEnd: Date? {
        guard let semester, let start = termStart else { return nil }
        return calendar.date(byAdding: .day, value: semester.totalWeeks * 7, to: start)
    }

    func lessons(on date: Date) -> [WatchLesson] {
        guard let semester, let start = termStart, let end = termEnd else { return [] }
        let day = calendar.startOfDay(for: date)
        guard day >= start, day < end else { return [] }
        let week = (calendar.dateComponents([.day], from: start, to: day).day ?? 0) / 7 + 1
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
        func time(_ minute: Int) -> Date? {
            if minute == 1440 { return calendar.date(byAdding: .day, value: 1, to: day) }
            return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
        }
        return courses.flatMap { course in
            course.meetings.compactMap { meeting -> WatchLesson? in
                guard meeting.weekday == weekday, (0...2).contains(meeting.parity),
                      meeting.parity == 0 || meeting.parity == (week % 2 == 1 ? 1 : 2),
                      meeting.startPeriod >= 1, meeting.endPeriod >= meeting.startPeriod,
                      meeting.endPeriod <= semester.periods.count,
                      let begins = time(semester.periods[meeting.startPeriod - 1].startMinute),
                      let ends = time(semester.periods[meeting.endPeriod - 1].endMinute), ends > begins
                else { return nil }
                return WatchLesson(id: "\(meeting.id)-\(day.timeIntervalSince1970)", name: course.name,
                    classroom: course.classroom, teacher: course.teacher, start: begins, end: ends,
                    startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod)
            }
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    func nextLesson(after now: Date) -> WatchLesson? {
        guard !courses.isEmpty, let start = termStart, let end = termEnd else { return nil }
        var day = max(calendar.startOfDay(for: now), start)
        while day < end {
            if let next = lessons(on: day).first(where: { $0.start >= now }) { return next }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day), tomorrow > day else { break }
            day = tomorrow
        }
        return nil
    }

    /// The phone sends only unfinished items. Keep nearby overdue items visible too.
    func pendingAssignments(at now: Date) -> [WatchAssignment] {
        Array(assignments.sorted {
            let left = abs($0.dueDate.timeIntervalSince(now))
            let right = abs($1.dueDate.timeIntervalSince(now))
            if left != right { return left < right }
            return $0.dueDate == $1.dueDate ? $0.id.uuidString < $1.id.uuidString : $0.dueDate < $1.dueDate
        }.prefix(3))
    }

    func upcomingExams(at now: Date) -> [WatchExam] {
        guard let end = calendar.date(byAdding: .day, value: 5, to: now) else { return [] }
        return exams.filter { $0.date >= now && $0.date <= end }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
}
