//
//  CalendarManager.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import Foundation

struct CalendarManager {
    struct CourseSeed: Identifiable {
        let id = UUID()
        let name: String
        let teacher: String
        let classroom: String
        let weekday: Int
        let startPeriod: Int
        let endPeriod: Int
        let weekPattern: WeekPattern
    }

    static func monday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    static func currentWeekIndex(termStartDate: Date, totalWeeks: Int, calendar: Calendar = .current) -> Int {
        let start = monday(onOrBefore: termStartDate, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        let dayDiff = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let week = (dayDiff / 7) + 1
        return min(max(1, week), max(totalWeeks, 1))
    }

    struct ImportPreview {
        var courses: [CourseSeed] = []
        var rejectedRows: [Int] = []
    }

    static func parseCourses(fromCSV csv: String) -> [CourseSeed] {
        inspectCSV(csv).courses
    }

    static func inspectCSV(_ csv: String) -> ImportPreview {
        var cleaned = csv.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if cleaned.hasPrefix("\u{FEFF}") { cleaned.removeFirst() }
        let parsed = parseCSVRows(cleaned)
        guard !parsed.unterminatedQuotes else { return ImportPreview(rejectedRows: [parsed.rows.count + 1]) }
        let rows = parsed.rows
        guard let firstIndex = rows.firstIndex(where: { $0.contains(where: { !$0.trimmed.isEmpty }) }) else {
            return ImportPreview()
        }
        let headerMap = headerIndexMap(rows[firstIndex])
        let startIndex = headerMap.isEmpty ? firstIndex : firstIndex + 1
        var result = ImportPreview()
        for index in startIndex..<rows.count {
            let row = rows[index]
            if row.allSatisfy({ $0.trimmed.isEmpty }) { continue }
            guard let name = value(for: ["name", "课程", "课程名"], in: row, headerMap: headerMap),
                  !name.trimmed.isEmpty,
                  let teacher = value(for: ["teacher", "老师", "教师"], in: row, headerMap: headerMap),
                  let classroom = value(for: ["classroom", "教室", "地点"], in: row, headerMap: headerMap),
                  let weekdayString = value(for: ["weekday", "星期", "周", "星期几"], in: row, headerMap: headerMap),
                  let startString = value(for: ["startperiod", "开始节次", "起始节次", "开始节"], in: row, headerMap: headerMap),
                  let endString = value(for: ["endperiod", "结束节次", "终止节次", "结束节"], in: row, headerMap: headerMap),
                  let weekday = parseWeekday(weekdayString),
                  let start = Int(startString.trimmed), let end = Int(endString.trimmed),
                  (1...12).contains(start), (start...12).contains(end),
                  let pattern = parseWeekPattern(value(for: ["weekpattern", "单双周", "周次"], in: row, headerMap: headerMap) ?? "")
            else {
                result.rejectedRows.append(index + 1)
                continue
            }
            result.courses.append(CourseSeed(name: name.trimmed, teacher: teacher.trimmed,
                classroom: classroom.trimmed, weekday: weekday, startPeriod: start,
                endPeriod: end, weekPattern: pattern))
        }
        return result
    }

    private static func parseCSVRows(_ csv: String) -> (rows: [[String]], unterminatedQuotes: Bool) {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let chars = Array(csv)
        var index = 0

        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if inQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" {
                    index += 1
                }
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
            } else {
                currentField.append(char)
            }
            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return (rows, inQuotes)
    }

    private static func headerIndexMap(_ header: [String]) -> [String: Int] {
        let knownHeaders: Set<String> = [
            "name", "课程", "课程名",
            "teacher", "老师", "教师",
            "classroom", "教室", "地点",
            "weekday", "星期", "周", "星期几",
            "startperiod", "开始节次", "起始节次", "开始节",
            "endperiod", "结束节次", "终止节次", "结束节",
            "weekpattern", "单双周", "周次"
        ]

        var map: [String: Int] = [:]
        for (index, raw) in header.enumerated() {
            let key = raw.trimmed.lowercased()
            if !key.isEmpty {
                map[key] = index
            }
        }
        let hasHeader = header.contains { knownHeaders.contains($0.trimmed.lowercased()) }
        return hasHeader ? map : [:]
    }

    private static func value(for keys: [String], in row: [String], headerMap: [String: Int]) -> String? {
        if headerMap.isEmpty {
            guard let index = defaultIndex(for: keys), index < row.count else { return nil }
            return row[index]
        }

        for key in keys {
            let normalized = key.lowercased()
            if let index = headerMap[normalized], index < row.count {
                return row[index]
            }
        }

        return nil
    }

    private static func defaultIndex(for keys: [String]) -> Int? {
        let mapping: [String: Int] = [
            "name": 0,
            "课程": 0,
            "课程名": 0,
            "teacher": 1,
            "老师": 1,
            "教师": 1,
            "classroom": 2,
            "教室": 2,
            "地点": 2,
            "weekday": 3,
            "星期": 3,
            "周": 3,
            "startperiod": 4,
            "开始节次": 4,
            "起始节次": 4,
            "endperiod": 5,
            "结束节次": 5,
            "终止节次": 5,
            "weekpattern": 6,
            "单双周": 6,
            "周次": 6
        ]

        for key in keys {
            if let index = mapping[key.lowercased()] {
                return index
            }
        }
        return nil
    }

    private static func parseWeekday(_ raw: String) -> Int? {
        let value = raw.trimmed.lowercased()
        if let numeric = Int(value), (1...7).contains(numeric) {
            return numeric
        }

        let map: [String: Int] = [
            "mon": 1, "monday": 1, "周一": 1, "星期一": 1, "一": 1,
            "tue": 2, "tues": 2, "tuesday": 2, "周二": 2, "星期二": 2, "二": 2,
            "wed": 3, "weds": 3, "wednesday": 3, "周三": 3, "星期三": 3, "三": 3,
            "thu": 4, "thur": 4, "thurs": 4, "thursday": 4, "周四": 4, "星期四": 4, "四": 4,
            "fri": 5, "friday": 5, "周五": 5, "星期五": 5, "五": 5,
            "sat": 6, "saturday": 6, "周六": 6, "星期六": 6, "六": 6,
            "sun": 7, "sunday": 7, "周日": 7, "周天": 7, "星期日": 7, "日": 7
        ]

        return map[value]
    }

    private static func parseWeekPattern(_ raw: String) -> WeekPattern? {
        switch raw.trimmed.lowercased() {
        case "", "all", "全周", "全部", "每周": return .all
        case "odd", "单", "单周": return .odd
        case "even", "双", "双周": return .even
        default: return nil
        }
    }
}
