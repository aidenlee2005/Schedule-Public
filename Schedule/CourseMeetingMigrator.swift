//
//  CourseMeetingMigrator.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftData

struct CourseMeetingMigrator {
    @MainActor
    @discardableResult
    static func migrateIfNeeded(in context: ModelContext) throws -> Bool {
        let fetch = FetchDescriptor<Course>()
        let courses = try context.fetch(fetch)

        var didChange = false
        for course in courses {
            if course.meetings.isEmpty {
                let meeting = CourseMeeting(
                    weekday: course.weekday,
                    startPeriod: course.startPeriod,
                    endPeriod: course.endPeriod,
                    weekPattern: course.weekPattern,
                    course: course
                )
                course.meetings.append(meeting)
                context.insert(meeting)
                didChange = true
            }
        }

        return didChange
    }
}
