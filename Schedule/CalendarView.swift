//
//  CalendarView.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query private var assignments: [Assignment]
    @Query private var exams: [Exam]

    init(term: Setting) {
        let id = term.id
        _assignments = Query(filter: #Predicate<Assignment> { $0.termID == id }, sort: \Assignment.dueDate)
        _exams = Query(filter: #Predicate<Exam> { $0.termID == id }, sort: \Exam.date)
    }

    @State private var currentIndex: Int = 24
    @State private var scrollTargetIndex: Int? = 24
    @State private var selectedDate: Date? = nil
    private let monthIndices = Array(0..<49)
    private let baseIndex = 24
    private let monthRowHeight: CGFloat = 44
    private let monthRowSpacing: CGFloat = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PageHeader(title: "Calendar", subtitle: nil) {
                    EmptyView()
                }
                MonthHeader(
                    currentMonth: currentMonth,
                    onPrevious: { moveMonth(by: -1) },
                    onNext: { moveMonth(by: 1) }
                )
                WeekdayRow()
                MonthPager(
                    monthIndices: monthIndices,
                    baseIndex: baseIndex,
                    selectedDate: selectedDate,
                    assignments: assignments,
                    exams: exams,
                    scrollTargetIndex: $scrollTargetIndex,
                    rowHeight: monthRowHeight,
                    rowSpacing: monthRowSpacing,
                    onSelectDate: { day in
                        selectedDate = day
                    }
                )
                DayAgendaInlineView(
                    date: selectedDate,
                    assignments: assignments,
                    exams: exams
                )
            }
            .padding(.horizontal, AppTheme.Spacing.page)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: scrollTargetIndex) { _, newValue in
            if let newValue {
                currentIndex = newValue
            }
        }
        .onAppear {
            currentIndex = baseIndex
            scrollTargetIndex = baseIndex
        }
    }

    private var baseMonth: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var currentMonth: Date {
        let offset = currentIndex - baseIndex
        return Calendar.current.date(byAdding: .month, value: offset, to: baseMonth) ?? Date()
    }

    private func moveMonth(by delta: Int) {
        let newIndex = currentIndex + delta
        guard monthIndices.contains(newIndex) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            scrollTargetIndex = newIndex
        }
    }
}

private struct MonthHeader: View {
    let currentMonth: Date
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            HeaderActionButton(title: "Previous Month", systemImage: "chevron.left", action: onPrevious)
                .accessibilityIdentifier("previousMonth")

            Spacer()

            Text(monthTitle)
                .font(AppTheme.Typography.sectionTitle)

            Spacer()

            HeaderActionButton(title: "Next Month", systemImage: "chevron.right", action: onNext)
                .accessibilityIdentifier("nextMonth")
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
}

private struct WeekdayRow: View {
    private let titles = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct MonthPager: View {
    let monthIndices: [Int]
    let baseIndex: Int
    let selectedDate: Date?
    let assignments: [Assignment]
    let exams: [Exam]
    @Binding var scrollTargetIndex: Int?
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let onSelectDate: (Date) -> Void

    var body: some View {
        TabView(selection: Binding(
            get: { scrollTargetIndex ?? baseIndex },
            set: { scrollTargetIndex = $0 }
        )) {
            ForEach(monthIndices, id: \.self) { index in
                MonthGrid(
                    currentMonth: month(for: index),
                    weekStartsOnMonday: true,
                    selectedDate: selectedDate,
                    assignments: assignments,
                    exams: exams,
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    onSelect: onSelectDate
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: rowHeight * 6 + rowSpacing * 5)
    }

    private func month(for index: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let offset = index - baseIndex
        return calendar.date(byAdding: .month, value: offset, to: base) ?? base
    }
}

private struct MonthGrid: View {
    let currentMonth: Date
    let weekStartsOnMonday: Bool
    let selectedDate: Date?
    let assignments: [Assignment]
    let exams: [Exam]
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let onSelect: (Date) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: rowSpacing), count: 7)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(days, id: \.id) { day in
                DayCell(
                    day: day,
                    selectedDate: selectedDate,
                    assignments: assignments,
                    exams: exams,
                    rowHeight: rowHeight,
                    onSelect: onSelect
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var days: [MonthDay] {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsOnMonday ? 2 : 1

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let daysInMonth = range.count
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var result: [MonthDay] = []
        let totalCells = 42

        for index in 0..<totalCells {
            let offset = index - leading
            let date = calendar.date(byAdding: .day, value: offset, to: monthStart) ?? monthStart
            let inCurrentMonth = offset >= 0 && offset < daysInMonth
            let day = MonthDay(date: date, inCurrentMonth: inCurrentMonth)
            result.append(day)
        }

        return result
    }
}

private struct DayCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let day: MonthDay
    let selectedDate: Date?
    let assignments: [Assignment]
    let exams: [Exam]
    let rowHeight: CGFloat
    let onSelect: (Date) -> Void

    var body: some View {
        let isSelected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false
        let isToday = day.isToday

        return Button {
            onSelect(day.date)
        } label: {
            VStack(spacing: 6) {
                dateBadge(
                    text: day.numberString,
                    isToday: isToday,
                    isSelected: isSelected,
                    isInMonth: day.inCurrentMonth
                )

                DotsRow(
                    assignmentCount: assignmentCount,
                    examCount: examCount
                )
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(day.accessibilityID)
    }

    @ViewBuilder
    private func dateBadge(
        text: String,
        isToday: Bool,
        isSelected: Bool,
        isInMonth: Bool
    ) -> some View {
        let isDark = colorScheme == .dark
        let baseTextColor: Color = isInMonth ? .primary : .secondary
        let textColor: Color = isSelected
            ? .primary
            : (isToday ? AppTheme.deepGreen : baseTextColor)
        let fillColor: Color = isSelected
            ? (isDark ? Color.clear : Color.white)
            : (isToday ? AppTheme.highlight : Color.clear)
        let strokeColor: Color = isSelected
            ? AppTheme.deepGreen
            : (isToday ? AppTheme.deepGreen.opacity(0.4) : Color.clear)

        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1.2)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.06) : .clear, radius: 4, x: 0, y: 2)
    }

    private var assignmentCount: Int {
        let calendar = Calendar.current
        return assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: day.date) }.count
    }

    private var examCount: Int {
        let calendar = Calendar.current
        return exams.filter { calendar.isDate($0.date, inSameDayAs: day.date) }.count
    }
}

private struct DotsRow: View {
    let assignmentCount: Int
    let examCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(assignmentCount, 3), id: \.self) { _ in
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 5, height: 5)
            }
            ForEach(0..<min(examCount, 3), id: \.self) { _ in
                Circle()
                    .fill(Color.pink.opacity(0.85))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 8)
    }
}

private struct DayAgendaInlineView: View {
    let date: Date?
    let assignments: [Assignment]
    let exams: [Exam]

    @ViewBuilder
    var body: some View {
        if let date {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))

                let calendar = Calendar.current
                let dayAssignments = assignments.filter {
                    calendar.isDate($0.dueDate, inSameDayAs: date)
                }
                let dayExams = exams.filter {
                    calendar.isDate($0.date, inSameDayAs: date)
                }

                if dayAssignments.isEmpty && dayExams.isEmpty {
                    Text("No items")
                        .foregroundStyle(.secondary)
                } else {
                    if !dayAssignments.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(dayAssignments.indices, id: \.self) { index in
                                let item = dayAssignments[index]
                                AgendaRow(title: item.content, subtitle: item.submitMethod, dotColor: .blue)
                                if index < dayAssignments.count - 1 {
                                    Divider()
                                        .opacity(0.3)
                                }
                            }
                        }
                    }

                    if !dayExams.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(dayExams.indices, id: \.self) { index in
                                let item = dayExams[index]
                                AgendaRow(title: item.subject, subtitle: item.detail, dotColor: .pink)
                                if index < dayExams.count - 1 {
                                    Divider()
                                        .opacity(0.3)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.card)
            .cardBackground()
            .padding(.bottom, 8)
        }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date ?? Date())
    }
}

private struct MonthDay: Identifiable {
    var id: Date { date }
    let date: Date
    let inCurrentMonth: Bool

    var accessibilityID: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(inCurrentMonth ? "calendarDay" : "adjacentDay")-\(c.year!)-\(c.month!)-\(c.day!)"
    }

    var numberString: String {
        String(Calendar.current.component(.day, from: date))
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

private struct AgendaRow: View {
    let title: String
    let subtitle: String
    let dotColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Typography.rowTitle)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
