//
//  Models.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import Foundation
import SwiftData
import SwiftUI

enum WeekPattern: String, CaseIterable, Codable {
    case all
    case odd
    case even
}

enum TermSeason: String, CaseIterable, Codable {
    case spring
    case fall

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .fall: return "Fall"
        }
    }
}

@Model
final class Course {
    var id: UUID
    /// Optional for lightweight migration of existing stores.
    var termID: UUID?
    var name: String
    var teacher: String
    var classroom: String
    /// 1 = Monday ... 7 = Sunday
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var weekPattern: WeekPattern
    /// Hex color string like "#AABBCC"
    var colorHex: String
    /// Seed for default color selection when no custom color is set.
    var colorSeed: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CourseMeeting.course)
    var meetings: [CourseMeeting]

    @Relationship(deleteRule: .cascade, inverse: \Assignment.course)
    var assignments: [Assignment]

    @Relationship(deleteRule: .cascade, inverse: \Exam.course)
    var exams: [Exam]

    init(
        id: UUID = UUID(),
        termID: UUID? = nil,
        name: String,
        teacher: String,
        classroom: String,
        weekday: Int,
        startPeriod: Int,
        endPeriod: Int,
        weekPattern: WeekPattern = .all,
        colorHex: String = "",
        colorSeed: Int = Int.random(in: 1...1_000_000),
        createdAt: Date = Date(),
        meetings: [CourseMeeting] = [],
        assignments: [Assignment] = [],
        exams: [Exam] = []
    ) {
        self.id = id
        self.termID = termID
        self.name = name
        self.teacher = teacher
        self.classroom = classroom
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weekPattern = weekPattern
        self.colorHex = colorHex
        self.colorSeed = colorSeed
        self.createdAt = createdAt
        self.meetings = meetings
        self.assignments = assignments
        self.exams = exams
    }
}

@Model
final class CourseMeeting {
    var id: UUID
    /// 1 = Monday ... 7 = Sunday
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var weekPattern: WeekPattern
    var createdAt: Date

    @Relationship
    var course: Course?

    init(
        id: UUID = UUID(),
        weekday: Int,
        startPeriod: Int,
        endPeriod: Int,
        weekPattern: WeekPattern = .all,
        createdAt: Date = Date(),
        course: Course? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weekPattern = weekPattern
        self.createdAt = createdAt
        self.course = course
    }
}

@Model
final class Assignment {
    var id: UUID
    var termID: UUID?
    var detail: String = ""
    var sourceID: String?
    var sourceAccountID: String?
    var sourceURL: String?
    var importedTitle: String?
    var importedDueDate: Date?
    var importedDetail: String?
    var content: String
    var dueDate: Date
    var submitMethod: String
    var isCompleted: Bool
    var createdAt: Date

    @Relationship
    var course: Course?

    init(
        id: UUID = UUID(),
        termID: UUID? = nil,
        content: String,
        dueDate: Date,
        submitMethod: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        course: Course? = nil
    ) {
        self.id = id
        self.termID = termID ?? course?.termID
        self.content = content
        self.dueDate = dueDate
        self.submitMethod = submitMethod
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.course = course
    }
}

@Model
final class Exam {
    var id: UUID
    var termID: UUID?
    var subject: String
    var detail: String
    var date: Date
    var createdAt: Date

    @Relationship
    var course: Course?

    init(
        id: UUID = UUID(),
        termID: UUID? = nil,
        subject: String,
        detail: String,
        date: Date,
        createdAt: Date = Date(),
        course: Course? = nil
    ) {
        self.id = id
        self.termID = termID ?? course?.termID
        self.subject = subject
        self.detail = detail
        self.date = date
        self.createdAt = createdAt
        self.course = course
    }
}

@Model
final class Setting {
    var id: UUID
    // Keep the persisted model name so pre-semester stores can migrate in place.
    var name: String = ""
    /// Term start date (start of week 1).
    var termStartDate: Date
    /// Total weeks in the term.
    var totalWeeks: Int
    /// Grade label for the current term.
    var grade: String
    /// Term season (Spring/Fall).
    var termSeason: TermSeason
    /// Show Saturday/Sunday in schedule view.
    var showWeekends: Bool
    /// "08:00-08:45" format for each period, index 0 == period 1.
    var periodTimeStrings: [String]
    /// true if week starts on Monday.
    var weekStartsOnMonday: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        termStartDate: Date,
        totalWeeks: Int,
        grade: String = "",
        termSeason: TermSeason = .spring,
        showWeekends: Bool = true,
        periodTimeStrings: [String],
        weekStartsOnMonday: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.termStartDate = termStartDate
        self.totalWeeks = totalWeeks
        self.grade = grade
        self.termSeason = termSeason
        self.showWeekends = showWeekends
        self.periodTimeStrings = periodTimeStrings
        self.weekStartsOnMonday = weekStartsOnMonday
        self.createdAt = createdAt
    }
}

extension Setting {
    var displayName: String {
        name.trimmed.isEmpty
            ? "\(Calendar.current.component(.year, from: termStartDate)) \(termSeason.displayName)"
            : name
    }

    static func defaultSetting() -> Setting {
        let calendar = Calendar.current
        let today = Date()
        let year = calendar.component(.year, from: today)
        let season: TermSeason = calendar.component(.month, from: today) >= 7 ? .fall : .spring
        let start = calendar.date(from: DateComponents(year: year, month: season == .fall ? 9 : 3, day: 1)) ?? today
        let defaultStart = CalendarManager.monday(onOrBefore: start)

        let periodTimes = [
            "08:00-08:50",
            "09:00-09:50",
            "10:10-11:00",
            "11:10-12:00",
            "13:00-13:50",
            "14:00-14:50",
            "15:10-16:00",
            "16:10-17:00",
            "17:10-18:00",
            "18:40-19:30",
            "19:40-20:30",
            "20:40-21:30"
        ]

        return Setting(
            termStartDate: defaultStart,
            totalWeeks: 20,
            grade: "",
            termSeason: season,
            showWeekends: true,
            periodTimeStrings: periodTimes,
            weekStartsOnMonday: true
        )
    }
}

extension Course {
    func isActive(inWeek week: Int) -> Bool {
        switch weekPattern {
        case .all:
            return true
        case .odd:
            return week % 2 == 1
        case .even:
            return week % 2 == 0
        }
    }
}

extension CourseMeeting {
    func isActive(inWeek week: Int) -> Bool {
        switch weekPattern {
        case .all:
            return true
        case .odd:
            return week % 2 == 1
        case .even:
            return week % 2 == 0
        }
    }
}

extension Course {
    var displayColor: Color {
        displayColor(for: .light)
    }

    func displayColor(for scheme: ColorScheme) -> Color {
        if let color = Color(hex: colorHex) {
            return color
        }
        let lightPalette: [Color] = [
            Color(red: 0.86, green: 0.96, blue: 0.90),
            Color(red: 0.80, green: 0.92, blue: 0.86),
            Color(red: 0.90, green: 0.98, blue: 0.94),
            Color(red: 0.78, green: 0.90, blue: 0.80),
            Color(red: 0.92, green: 0.96, blue: 0.88),
            Color(red: 0.84, green: 0.94, blue: 0.92)
        ]
        let darkPalette: [Color] = [
            Color(red: 0.10, green: 0.24, blue: 0.18),
            Color(red: 0.12, green: 0.28, blue: 0.20),
            Color(red: 0.08, green: 0.22, blue: 0.16),
            Color(red: 0.14, green: 0.30, blue: 0.22),
            Color(red: 0.09, green: 0.20, blue: 0.15),
            Color(red: 0.13, green: 0.26, blue: 0.19)
        ]
        let palette = scheme == .dark ? darkPalette : lightPalette
        let index = colorSeed == 0
            ? stableIndex(for: id.uuidString, count: palette.count)
            : abs(colorSeed) % max(palette.count, 1)
        return palette[index]
    }

    private func stableIndex(for value: String, count: Int) -> Int {
        var hash = 0
        for scalar in value.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        return abs(hash) % max(count, 1)
    }
}
