import Foundation
import SwiftData

enum PlanWindow: String, Codable, CaseIterable {
    case thisWeek, soon, anytime
    var title: String {
        switch self { case .thisWeek: return "This Week"; case .soon: return "Soon"; case .anytime: return "Anytime" }
    }
}

enum PlanStatus: String, Codable, CaseIterable {
    case active, paused, completed
    var title: String { rawValue.capitalized }
}

@Model
final class FlexiblePlan {
    var id: UUID
    var title: String
    var nextStep: String
    var completionGoal: String
    var notes: String
    var window: PlanWindow
    var weekAnchor: Date?
    var status: PlanStatus
    /// nil means personal, and remains visible when the selected semester changes.
    var termID: UUID?
    var courseID: UUID?
    var createdAt: Date
    var completedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \PlanStep.plan)
    var steps: [PlanStep]

    init(id: UUID = UUID(), title: String, nextStep: String = "", completionGoal: String = "",
         notes: String = "", window: PlanWindow = .soon, status: PlanStatus = .active,
         termID: UUID? = nil, courseID: UUID? = nil, weekAnchor: Date? = nil) {
        self.id = id
        self.title = title
        self.nextStep = nextStep
        self.completionGoal = completionGoal
        self.notes = notes
        self.window = window
        self.status = status
        self.termID = termID
        self.courseID = courseID
        self.weekAnchor = window == .thisWeek ? (weekAnchor ?? CalendarManager.monday(onOrBefore: Date())) : nil
        createdAt = Date()
        steps = []
    }

    func needsReview(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard window == .thisWeek, status == .active, let weekAnchor,
              let end = calendar.date(byAdding: .day, value: 7, to: weekAnchor) else { return false }
        return calendar.startOfDay(for: date) >= end
    }

    func rescheduleToThisWeek(on date: Date = Date()) {
        window = .thisWeek
        weekAnchor = CalendarManager.monday(onOrBefore: date)
        status = .active
        completedAt = nil
    }

    func setCompleted(_ completed: Bool) {
        status = completed ? .completed : .active
        completedAt = completed ? Date() : nil
    }
}

@Model
final class PlanStep {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var position: Int
    var plan: FlexiblePlan?

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, position: Int = 0, plan: FlexiblePlan? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.position = position
        self.plan = plan
    }
}

/// Edits only the visible title, preserving data from earlier app versions.
struct PlanTitleDraft {
    var title: String

    init(plan: FlexiblePlan) { title = plan.title }

    func apply(to plan: FlexiblePlan) { plan.title = title.trimmed }
}
