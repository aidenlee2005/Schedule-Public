import Foundation
import SwiftData

@MainActor
enum TermManager {
    /// Assign legacy records once, preserving every existing term and course relationship.
    static func prepare(in context: ModelContext) throws {
        do {
            var terms = try context.fetch(FetchDescriptor<Setting>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            if terms.isEmpty {
                let initial = Setting.defaultSetting()
                context.insert(initial)
                terms = [initial]
            }
            guard let legacyTerm = terms.first else { return }
            for term in terms where term.name.trimmed.isEmpty {
                term.name = term.displayName
            }
            for course in try context.fetch(FetchDescriptor<Course>()) where course.termID == nil {
                course.termID = legacyTerm.id
            }
            for assignment in try context.fetch(FetchDescriptor<Assignment>()) where assignment.termID == nil {
                assignment.termID = assignment.course?.termID ?? legacyTerm.id
            }
            for exam in try context.fetch(FetchDescriptor<Exam>()) where exam.termID == nil {
                exam.termID = exam.course?.termID ?? legacyTerm.id
            }
            try CourseMeetingMigrator.migrateIfNeeded(in: context)
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }

    static func clearData(for term: Setting, in context: ModelContext) throws {
        let id = term.id
        for plan in try context.fetch(FetchDescriptor<FlexiblePlan>(predicate: #Predicate { $0.termID == id })) {
            context.delete(plan)
        }
        for item in try context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate { $0.termID == id })) {
            context.delete(item)
        }
        for item in try context.fetch(FetchDescriptor<Exam>(predicate: #Predicate { $0.termID == id })) {
            context.delete(item)
        }
        for course in try context.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.termID == id })) {
            context.delete(course)
        }
    }

    static func delete(_ term: Setting, in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Setting>()) > 1 else {
            throw TermError.lastTerm
        }
        try clearData(for: term, in: context)
        context.delete(term)
    }

    enum TermError: LocalizedError {
        case lastTerm
        var errorDescription: String? { "Keep at least one semester. Create another semester before deleting this one." }
    }
}

struct TermDraft {
    var name: String
    var startDate: Date
    var totalWeeks: Int
    var grade: String
    var season: TermSeason
    var showWeekends: Bool

    init(term: Setting) {
        name = term.displayName
        startDate = term.termStartDate
        totalWeeks = term.totalWeeks
        grade = term.grade
        season = term.termSeason
        showWeekends = term.showWeekends
    }

    init() {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        season = calendar.component(.month, from: now) >= 7 ? .fall : .spring
        name = "\(year) \(season.displayName)"
        startDate = CalendarManager.monday(onOrBefore: now)
        totalWeeks = 20
        grade = ""
        showWeekends = true
    }

    func apply(to term: Setting) {
        term.name = name.trimmed
        term.termStartDate = CalendarManager.monday(onOrBefore: startDate)
        term.totalWeeks = totalWeeks
        term.grade = grade.trimmed
        term.termSeason = season
        term.showWeekends = showWeekends
    }

    func makeTerm() -> Setting {
        let term = Setting.defaultSetting()
        apply(to: term)
        return term
    }
}
