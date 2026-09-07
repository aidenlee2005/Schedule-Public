import Foundation
import SwiftData

@MainActor
enum TeachingImporter {
    @discardableResult
    static func apply(_ item: TeachingItem, accountID: String, term: Setting, course: Course?,
                      chosenDate: Date? = nil, context: ModelContext) throws -> Assignment {
        let sourceID = item.id; let termID = term.id
        let existing = try context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate {
            $0.sourceID == sourceID && $0.sourceAccountID == accountID && $0.termID == termID
        })).first
        guard item.kind == .assignment else { throw TeachingError.unexpectedPage }
        if let course, course.termID != term.id { throw TeachingError.missingCourseLink }
        do {
            let assignment: Assignment
            if let existing {
                assignment = existing
                // Respect local edits and local completion state on every repeated import.
                if assignment.content == assignment.importedTitle { assignment.content = item.title }
                if assignment.detail == assignment.importedDetail { assignment.detail = item.body }
                if assignment.dueDate == assignment.importedDueDate, let date = item.dueDate { assignment.dueDate = date }
            } else {
                guard let dueDate = item.dueDate ?? chosenDate else { throw TeachingError.noDeadline }
                assignment = Assignment(termID: term.id, content: item.title, dueDate: dueDate, submitMethod: "PKU Blackboard", course: course)
                assignment.detail = item.body
                assignment.sourceID = item.id; assignment.sourceAccountID = accountID
                context.insert(assignment)
            }
            assignment.sourceURL = item.sourceURL.absoluteString
            assignment.importedTitle = item.title; assignment.importedDetail = item.body
            assignment.importedDueDate = item.dueDate ?? chosenDate ?? assignment.importedDueDate
            try context.save()
            return assignment
        } catch { context.rollback(); throw error }
    }
}
