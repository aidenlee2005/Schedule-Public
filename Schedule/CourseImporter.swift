import Foundation
import SwiftData

@MainActor
enum CourseImporter {
    struct Summary {
        var courses = 0
        var sessions = 0
        var duplicates = 0
        var rejectedRows: [Int] = []

        var message: String {
            var text = "Added \(courses) courses and \(sessions) sessions. Skipped \(duplicates) duplicate sessions."
            if !rejectedRows.isEmpty {
                let rows = rejectedRows.prefix(12).map(String.init).joined(separator: ", ")
                text += "\nInvalid rows skipped: \(rows)\(rejectedRows.count > 12 ? "…" : ""). Use a course name, weekday 1–7 and periods 1–12 with start ≤ end."
            }
            return text
        }
    }

    private struct CourseKey: Hashable {
        let name: String
        let teacher: String
        let classroom: String
        init(_ name: String, _ teacher: String, _ classroom: String) {
            self.name = name.trimmed.lowercased()
            self.teacher = teacher.trimmed.lowercased()
            self.classroom = classroom.trimmed.lowercased()
        }
    }

    enum ImportError: LocalizedError {
        case noValidRows([Int])
        case encoding
        var errorDescription: String? {
            switch self {
            case .encoding: return "Save the CSV as UTF-8 and try again."
            case .noValidRows(let rows):
                return "No valid courses were found. Check the CSV headers, names and period ranges." +
                    (rows.isEmpty ? "" : " Invalid rows: \(rows.prefix(12).map(String.init).joined(separator: ", ")).")
            }
        }
    }

    static func importCSV(_ csv: String, into term: Setting, context: ModelContext) throws -> Summary {
        let preview = CalendarManager.inspectCSV(csv)
        guard !preview.courses.isEmpty else { throw ImportError.noValidRows(preview.rejectedRows) }
        let id = term.id
        do {
            let existing = try context.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.termID == id }))
            var courseMap: [CourseKey: Course] = [:]
            for course in existing {
                let key = CourseKey(course.name, course.teacher, course.classroom)
                if courseMap[key] == nil { courseMap[key] = course }
            }
            var result = Summary(rejectedRows: preview.rejectedRows)
            for seed in preview.courses {
                let key = CourseKey(seed.name, seed.teacher, seed.classroom)
                let course: Course
                if let match = courseMap[key] {
                    course = match
                } else {
                    course = Course(termID: id, name: seed.name, teacher: seed.teacher, classroom: seed.classroom,
                        weekday: seed.weekday, startPeriod: seed.startPeriod, endPeriod: seed.endPeriod,
                        weekPattern: seed.weekPattern)
                    context.insert(course)
                    courseMap[key] = course
                    result.courses += 1
                }
                if course.meetings.contains(where: {
                    $0.weekday == seed.weekday && $0.startPeriod == seed.startPeriod &&
                    $0.endPeriod == seed.endPeriod && $0.weekPattern == seed.weekPattern
                }) {
                    result.duplicates += 1
                    continue
                }
                let meeting = CourseMeeting(weekday: seed.weekday, startPeriod: seed.startPeriod,
                    endPeriod: seed.endPeriod, weekPattern: seed.weekPattern, course: course)
                context.insert(meeting)
                course.meetings.append(meeting)
                result.sessions += 1
            }
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
