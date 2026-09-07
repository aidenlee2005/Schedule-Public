import Foundation
import SwiftData

@MainActor
enum WatchSnapshotBuilder {
    static func make(context: ModelContext, activeTermID: String, sourceID: UUID, revision: Int,
                     now: Date = Date(), timeZone: TimeZone = .current) throws -> WatchSnapshot {
        let terms = try context.fetch(FetchDescriptor<Setting>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        let term = terms.first { $0.id.uuidString == activeTermID } ?? terms.first
        var result = WatchSnapshot(sourceID: sourceID, revision: revision, generatedAt: now,
            timeZoneIdentifier: timeZone.identifier, semester: nil, courses: [], assignments: [], exams: [])
        guard let term else { return result }
        // Keep period indexes intact if a legacy value is malformed; an invalid period is skipped below.
        let periods = term.periodTimeStrings.map { WatchPeriod.parse($0) ?? WatchPeriod(startMinute: 0, endMinute: 1) }
        result.semester = WatchSemester(id: term.id, name: term.displayName, startDate: term.termStartDate,
                                       totalWeeks: term.totalWeeks, periods: periods)
        let termID = term.id
        let courses = try context.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.termID == termID }))
        func validPeriods(_ start: Int, _ end: Int) -> Bool {
            guard start >= 1, end >= start, end <= term.periodTimeStrings.count else { return false }
            return WatchPeriod.parse(term.periodTimeStrings[start - 1]) != nil
                && WatchPeriod.parse(term.periodTimeStrings[end - 1]) != nil
        }
        func parity(_ pattern: WeekPattern) -> Int { pattern == .all ? 0 : pattern == .odd ? 1 : 2 }
        result.courses = courses.map { course in
            let meetings: [WatchMeeting]
            if course.meetings.isEmpty {
                meetings = validPeriods(course.startPeriod, course.endPeriod)
                    ? [WatchMeeting(id: course.id, weekday: course.weekday, startPeriod: course.startPeriod,
                                    endPeriod: course.endPeriod, parity: parity(course.weekPattern))] : []
            } else {
                meetings = course.meetings.filter { validPeriods($0.startPeriod, $0.endPeriod) }.map {
                    WatchMeeting(id: $0.id, weekday: $0.weekday, startPeriod: $0.startPeriod,
                                 endPeriod: $0.endPeriod, parity: parity($0.weekPattern))
                }.sorted { $0.id.uuidString < $1.id.uuidString }
            }
            return WatchCourse(id: course.id, name: String(course.name.prefix(160)),
                classroom: String(course.classroom.prefix(120)), teacher: String(course.teacher.prefix(80)), meetings: meetings)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        result.assignments = try context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate {
            $0.termID == termID && !$0.isCompleted
        })).map { WatchAssignment(id: $0.id, title: String($0.content.prefix(240)),
                                 courseName: String(($0.course?.name ?? "").prefix(160)), dueDate: $0.dueDate) }
        result.exams = try context.fetch(FetchDescriptor<Exam>(predicate: #Predicate {
            $0.termID == termID && $0.date >= now
        })).map { WatchExam(id: $0.id, title: String($0.subject.prefix(160)),
                           courseName: String(($0.course?.name ?? "").prefix(160)),
                           detail: String($0.detail.prefix(240)), date: $0.date) }
        return result
    }
}
