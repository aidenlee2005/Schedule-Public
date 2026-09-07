//
//  HomeView.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    let term: Setting
    @Query private var courses: [Course]

    init(term: Setting) {
        self.term = term
        let id = term.id
        _courses = Query(filter: #Predicate<Course> { $0.termID == id }, sort: \Course.createdAt)
    }

    @State private var selectedWeek: Int = 1
    @State private var didSetInitialWeek = false
    @State private var activeSheet: HomeSheet?
    @State private var scrollTargetWeek: Int?

    private enum HomeSheet: Identifiable {
        case settings
        case newCourse
        case course(Course)

        var id: String {
            switch self {
            case .settings:
                return "settings"
            case .newCourse:
                return "newCourse"
            case .course(let course):
                return "course-\(course.id.uuidString)"
            }
        }
    }

    private var setting: Setting {
        term
    }

    private var totalWeeks: Int {
        max(setting.totalWeeks, 1)
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                weekPager
            }
            .padding(.horizontal, AppTheme.Spacing.page)
            .padding(.top, 4)
        }
        .onAppear {
            if !didSetInitialWeek {
                selectedWeek = currentWeekIndex(using: setting)
                scrollTargetWeek = selectedWeek
                didSetInitialWeek = true
            }
        }
        .onChange(of: term.totalWeeks) { _, _ in
            selectedWeek = min(selectedWeek, totalWeeks)
        }
        .onChange(of: term.termStartDate) { _, _ in
            selectedWeek = currentWeekIndex(using: term)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView(term: term)
            case .newCourse:
                NewCourseSheet(term: term)
            case .course(let course):
                CourseDetailSheet(course: course)
            }
        }
    }

    private var background: some View {
        AppTheme.background
    }

    private var topBar: some View {
        PageHeader(title: "Schedule", subtitle: "\(term.displayName) · Week \(selectedWeek) of \(totalWeeks)") {
            HStack(spacing: 8) {
                HeaderActionButton(title: "Add Course", systemImage: "plus") { activeSheet = .newCourse }
                    .accessibilityIdentifier("addCourse")
                HeaderActionButton(title: "Settings", systemImage: "slider.horizontal.3") { activeSheet = .settings }
                    .accessibilityIdentifier("settings")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var weekPager: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(1...totalWeeks, id: \.self) { week in
                WeekPageView(
                    week: week,
                    setting: setting,
                    courses: courses,
                    onCourseTap: { course in
                        activeSheet = .course(course)
                    }
                )
                        .frame(width: geo.size.width)
                        .id(week)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollTargetWeek)
            .onChange(of: scrollTargetWeek) { _, newValue in
                if let week = newValue {
                    selectedWeek = week
                }
            }
            .onChange(of: selectedWeek) { _, newValue in
                scrollTargetWeek = newValue
            }
        }
    }

    private func currentWeekIndex(using setting: Setting) -> Int {
        CalendarManager.currentWeekIndex(
            termStartDate: setting.termStartDate,
            totalWeeks: setting.totalWeeks,
            calendar: Calendar.current
        )
    }
}

private struct WeekPageView: View {
    let week: Int
    @Bindable var setting: Setting
    let courses: [Course]
    let onCourseTap: (Course) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                WeekDateHeaderRow(week: week, setting: setting)
                WeekGridView(
                    week: week,
                    setting: setting,
                    courses: courses,
                    onCourseTap: onCourseTap
                )
            }
            .padding(.bottom, 80)
        }
    }
}

private struct WeekDateHeaderRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let week: Int
    @Bindable var setting: Setting

    var body: some View {
        let dates = weekDates
        return HStack(spacing: 0) {
            Text("P")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36)

            ForEach(dates.indices, id: \.self) { index in
                let isToday = isToday(dates[index])
                let todayColor: Color = colorScheme == .dark ? AppTheme.highlight : AppTheme.deepGreen
                VStack(spacing: 2) {
                    Text(weekdaySymbols[index])
                        .font(.caption.weight(isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? todayColor : .primary)
                    Text(dateString(for: dates[index]))
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? todayColor : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 4)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: (week - 1) * 7, to: CalendarManager.monday(onOrBefore: setting.termStartDate)) ?? setting.termStartDate
        let count = setting.showWeekends ? 7 : 5
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        let ordered = Array(symbols[1...6]) + [symbols[0]]
        return setting.showWeekends ? ordered : Array(ordered.prefix(5))
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

private struct WeekGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    let week: Int
    @Bindable var setting: Setting
    let courses: [Course]
    let onCourseTap: (Course) -> Void

    private let cellHeight: CGFloat = 56
    private let rowHeaderWidth: CGFloat = 36

    private var totalPeriods: Int {
        max(12, setting.periodTimeStrings.count)
    }

    private var visibleWeekdays: [Int] {
        setting.showWeekends ? [1, 2, 3, 4, 5, 6, 7] : [1, 2, 3, 4, 5]
    }

    var body: some View {
        GeometryReader { geo in
            let gridWidth = max(geo.size.width - rowHeaderWidth, 1)
            let cellWidth = max(gridWidth / CGFloat(visibleWeekdays.count), 1)
            let gridHeight = cellHeight * CGFloat(totalPeriods)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    periodColumn
                        .frame(width: rowHeaderWidth, height: gridHeight)

                    gridBackground(cellHeight: cellHeight, gridWidth: gridWidth)
                        .frame(width: gridWidth, height: gridHeight)
                }

                ForEach(courses, id: \.id) { course in
                    ForEach(course.meetings.filter { $0.isActive(inWeek: week) }, id: \.id) { meeting in
                        if let columnIndex = visibleWeekdays.firstIndex(of: meeting.weekday),
                           (1...totalPeriods).contains(meeting.startPeriod) {
                            let endPeriod = min(meeting.endPeriod, totalPeriods)
                            let span = max(1, endPeriod - meeting.startPeriod + 1)
                            let xOffset = rowHeaderWidth + CGFloat(columnIndex) * cellWidth + 2
                            let yOffset = CGFloat(meeting.startPeriod - 1) * cellHeight + 2
                            let blockWidth = max(cellWidth - 4, 12)
                            let blockHeight = max((cellHeight * CGFloat(span)) - 4, 12)

                            CourseBlock(course: course)
                                .frame(width: blockWidth, height: blockHeight)
                                .offset(x: xOffset, y: yOffset)
                                .onTapGesture {
                                    onCourseTap(course)
                                }
                        }
                    }
                }

            }
            .frame(height: gridHeight)
        }
        .frame(height: cellHeight * CGFloat(totalPeriods))
    }

    private var periodColumn: some View {
        let lineColor = colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
        return VStack(spacing: 0) {
            ForEach(1...totalPeriods, id: \.self) { period in
                Text("\(period)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: cellHeight)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.background)
                    .overlay(
                        Rectangle()
                            .stroke(lineColor, lineWidth: 0.5)
                    )
            }
        }
    }

    private func gridBackground(cellHeight: CGFloat, gridWidth: CGFloat) -> some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: visibleWeekdays.count)
        let lineColor = colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
        return LazyVGrid(columns: gridColumns, spacing: 0) {
            ForEach(0..<(visibleWeekdays.count * totalPeriods), id: \.self) { _ in
                Rectangle()
                    .fill(AppTheme.background)
                    .overlay(
                        Rectangle()
                            .stroke(lineColor, lineWidth: 0.5)
                    )
                    .frame(height: cellHeight)
            }
        }
        .frame(width: gridWidth)
    }

}

private struct CourseBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    let course: Course

    var body: some View {
        let baseColor = course.displayColor(for: colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(course.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(course.classroom)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(baseColor.opacity(colorScheme == .dark ? 0.95 : 0.85), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
    }
}

private struct CourseDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let course: Course

    @State private var name = ""
    @State private var teacher = ""
    @State private var classroom = ""
    @State private var courseColor: Color = AppTheme.highlight
    @State private var meetingDrafts: [MeetingDraft] = []
    @State private var didLoad = false
    @State private var showDeleteAlert = false
    @State private var isEditing = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    if isEditing {
                        TextField("Name", text: $name)
                        TextField("Teacher", text: $teacher)
                        TextField("Classroom", text: $classroom)
                    } else {
                        Text(name)
                        if !teacher.trimmed.isEmpty {
                            Text(teacher)
                                .foregroundStyle(.secondary)
                        }
                        if !classroom.trimmed.isEmpty {
                            Text(classroom)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Schedule") {
                    if isEditing {
                        ForEach($meetingDrafts) { $draft in
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Session")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if meetingDrafts.count > 1 {
                                        Button(role: .destructive) {
                                            removeMeetingDraft(id: draft.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Picker("Weekday", selection: $draft.weekday) {
                                    ForEach(1...7, id: \.self) { day in
                                        Text(weekdayLabel(for: day)).tag(day)
                                    }
                                }
                                .pickerStyle(.menu)

                                PeriodRangeEditor(
                                    startPeriod: $draft.startPeriod,
                                    endPeriod: $draft.endPeriod
                                )

                                Picker("Week Pattern", selection: $draft.weekPattern) {
                                    ForEach(WeekPattern.allCases, id: \.self) { pattern in
                                        Text(patternLabel(for: pattern)).tag(pattern)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.vertical, 12)
                        }

                        Button {
                            addMeetingDraft()
                        } label: {
                            Label("Add Session", systemImage: "plus")
                        }
                    } else {
                        ForEach(meetingDrafts) { draft in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sessionTitle(for: draft))
                                    .font(.body.weight(.semibold))
                                Text(sessionDetail(for: draft))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                Section("Appearance") {
                    if isEditing {
                        ColorPicker(
                            "Course Color",
                            selection: $courseColor,
                            supportsOpacity: false
                        )
                    } else {
                        HStack {
                            Text("Course Color")
                            Spacer()
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(courseColor)
                                .frame(width: 28, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Text("Delete Course")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Course")
            .appFormSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.automatic)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            applyChanges()
                            if Persistence.save(modelContext, error: &saveError) { dismiss() }
                        }
                        .disabled(name.trimmed.isEmpty || meetingDrafts.isEmpty || !meetingDrafts.allSatisfy(\.isValid))
                        .buttonStyle(.automatic)
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                        .buttonStyle(.automatic)
                    }
                }
            }
            .alert("Delete Course?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(course)
                    if Persistence.save(modelContext, error: &saveError) { dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the course and all related assignments and exams.")
            }
        }
        .persistenceAlert($saveError)
        .onAppear {
            loadDraftsIfNeeded()
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }

    private func loadDraftsIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        name = course.name
        teacher = course.teacher
        classroom = course.classroom
        courseColor = course.displayColor
        let existing = course.meetings
        if existing.isEmpty {
            meetingDrafts = [
                MeetingDraft(
                    id: UUID(),
                    weekday: course.weekday,
                    startPeriod: course.startPeriod,
                    endPeriod: course.endPeriod,
                    weekPattern: course.weekPattern
                )
            ]
        } else {
            meetingDrafts = existing.map {
                return MeetingDraft(
                    id: $0.id,
                    weekday: $0.weekday,
                    startPeriod: $0.startPeriod,
                    endPeriod: $0.endPeriod,
                    weekPattern: $0.weekPattern
                )
            }
        }
    }

    private func applyChanges() {
        course.name = name.trimmed
        course.teacher = teacher.trimmed
        course.classroom = classroom.trimmed
        course.colorHex = courseColor.toHex() ?? course.colorHex

        let existing = Dictionary(uniqueKeysWithValues: course.meetings.map { ($0.id, $0) })
        let draftIDs = Set(meetingDrafts.map { $0.id })

        for draft in meetingDrafts {
            if let meeting = existing[draft.id] {
                meeting.weekday = draft.weekday
                meeting.startPeriod = draft.startPeriod
                meeting.endPeriod = draft.endPeriod
                meeting.weekPattern = draft.weekPattern
            } else {
                let meeting = CourseMeeting(
                    id: draft.id,
                    weekday: draft.weekday,
                    startPeriod: draft.startPeriod,
                    endPeriod: draft.endPeriod,
                    weekPattern: draft.weekPattern,
                    course: course
                )
                course.meetings.append(meeting)
                modelContext.insert(meeting)
            }
        }

        for meeting in course.meetings where !draftIDs.contains(meeting.id) {
            modelContext.delete(meeting)
        }
    }

    private func addMeetingDraft() {
        meetingDrafts.append(MeetingDraft())
    }

    private func removeMeetingDraft(id: UUID) {
        meetingDrafts.removeAll { $0.id == id }
    }

    private func weekdayLabel(for day: Int) -> String {
        switch day {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        default: return "Sunday"
        }
    }

    private func patternLabel(for pattern: WeekPattern) -> String {
        switch pattern {
        case .all: return "All Weeks"
        case .odd: return "Odd Weeks"
        case .even: return "Even Weeks"
        }
    }

    private func sessionTitle(for draft: MeetingDraft) -> String {
        "\(weekdayLabel(for: draft.weekday)) · \(draft.startPeriod)-\(draft.endPeriod)"
    }

    private func sessionDetail(for draft: MeetingDraft) -> String {
        patternLabel(for: draft.weekPattern)
    }
}

private struct NewCourseSheet: View {
    let term: Setting
    @State private var saveError: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var teacher = ""
    @State private var classroom = ""
    @State private var courseColor: Color = AppTheme.highlight
    @State private var meetingDrafts: [MeetingDraft] = [MeetingDraft()]

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Name", text: $name)
                    TextField("Teacher", text: $teacher)
                    TextField("Classroom", text: $classroom)
                }

                Section("Schedule") {
                    ForEach($meetingDrafts) { $draft in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Session")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if meetingDrafts.count > 1 {
                                    Button(role: .destructive) {
                                        removeMeetingDraft(id: draft.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Picker("Weekday", selection: $draft.weekday) {
                                ForEach(1...7, id: \.self) { day in
                                    Text(weekdayLabel(for: day)).tag(day)
                                }
                            }
                            .pickerStyle(.menu)

                            PeriodRangeEditor(
                                startPeriod: $draft.startPeriod,
                                endPeriod: $draft.endPeriod
                            )

                            Picker("Week Pattern", selection: $draft.weekPattern) {
                                ForEach(WeekPattern.allCases, id: \.self) { pattern in
                                    Text(patternLabel(for: pattern)).tag(pattern)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 12)
                    }

                    Button {
                        meetingDrafts.append(MeetingDraft())
                    } label: {
                        Label("Add Session", systemImage: "plus")
                    }
                }

                Section("Appearance") {
                    ColorPicker("Course Color", selection: $courseColor, supportsOpacity: false)
                }
            }
            .navigationTitle("New Course")
            .appFormSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.automatic)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        let course = Course(
                            termID: term.id,
                            name: name.trimmed,
                            teacher: teacher.trimmed,
                            classroom: classroom.trimmed,
                            weekday: meetingDrafts.first?.weekday ?? 1,
                            startPeriod: meetingDrafts.first?.startPeriod ?? 1,
                            endPeriod: meetingDrafts.first?.endPeriod ?? 2,
                            weekPattern: meetingDrafts.first?.weekPattern ?? .all,
                            colorHex: courseColor.toHex() ?? ""
                        )
                        modelContext.insert(course)
                        for draft in meetingDrafts {
                            let meeting = CourseMeeting(
                                id: draft.id,
                                weekday: draft.weekday,
                                startPeriod: draft.startPeriod,
                                endPeriod: draft.endPeriod,
                                weekPattern: draft.weekPattern,
                                course: course
                            )
                            course.meetings.append(meeting)
                            modelContext.insert(meeting)
                        }
                        if Persistence.save(modelContext, error: &saveError) { dismiss() }
                    }
                    .disabled(name.trimmed.isEmpty || meetingDrafts.isEmpty || !meetingDrafts.allSatisfy(\.isValid))
                    .buttonStyle(.automatic)
                }
            }
        }
        .persistenceAlert($saveError)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }

    private func removeMeetingDraft(id: UUID) {
        meetingDrafts.removeAll { $0.id == id }
    }

    private func weekdayLabel(for day: Int) -> String {
        switch day {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        default: return "Sunday"
        }
    }

    private func patternLabel(for pattern: WeekPattern) -> String {
        switch pattern {
        case .all: return "All Weeks"
        case .odd: return "Odd Weeks"
        case .even: return "Even Weeks"
        }
    }
}

private struct MeetingDraft: Identifiable {
    var isValid: Bool { (1...7).contains(weekday) && (1...12).contains(startPeriod) && endPeriod >= startPeriod && endPeriod <= 12 }
    var id: UUID = UUID()
    var weekday: Int = 1
    var startPeriod: Int = 1
    var endPeriod: Int = 2
    var weekPattern: WeekPattern = .all
}

private struct PeriodRangeEditor: View {
    @Binding var startPeriod: Int
    @Binding var endPeriod: Int

    struct Option: Identifiable {
        let id: String
        let start: Int
        let end: Int
    }

    static let options: [Option] = [
        Option(id: "1-2", start: 1, end: 2),
        Option(id: "3-4", start: 3, end: 4),
        Option(id: "5-6", start: 5, end: 6),
        Option(id: "7-8", start: 7, end: 8),
        Option(id: "7-9", start: 7, end: 9),
        Option(id: "10-11", start: 10, end: 11),
        Option(id: "10-12", start: 10, end: 12)
    ]

    private var availableOptions: [Option] {
        if Self.options.contains(where: { $0.start == startPeriod && $0.end == endPeriod }) { return Self.options }
        return Self.options + [Option(id: "\(startPeriod)-\(endPeriod)", start: startPeriod, end: endPeriod)]
    }

    private var selection: Binding<String> {
        Binding(get: { "\(startPeriod)-\(endPeriod)" }, set: { id in
            guard let option = availableOptions.first(where: { $0.id == id }) else { return }
            startPeriod = option.start
            endPeriod = option.end
        })
    }

    var body: some View {
        Picker("Period Range", selection: selection) {
            ForEach(availableOptions) { option in Text(option.id).tag(option.id) }
        }
        .pickerStyle(.menu)
        DisclosureGroup("Custom Period Range") {
            Stepper("Start: \(startPeriod)", value: $startPeriod, in: 1...12)
                .onChange(of: startPeriod) { _, new in if endPeriod < new { endPeriod = new } }
            Stepper("End: \(endPeriod)", value: $endPeriod, in: min(max(startPeriod, 1), 12)...12)
        }
    }
}
