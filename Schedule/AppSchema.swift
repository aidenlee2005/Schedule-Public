import SwiftData

/// The model set used by the persistent store.
enum AppSchema {
    static var schema: Schema {
        Schema([Course.self, CourseMeeting.self, Assignment.self, Exam.self, Setting.self,
                FlexiblePlan.self, PlanStep.self])
    }
}
