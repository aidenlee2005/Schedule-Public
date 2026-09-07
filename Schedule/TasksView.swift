//
//  TasksView.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var assignments: [Assignment]
    @Query private var exams: [Exam]
    @Query private var courses: [Course]
    let term: Setting
    @State private var saveError: String?

    init(term: Setting) {
        self.term = term
        let id = term.id
        _assignments = Query(filter: #Predicate<Assignment> { $0.termID == id }, sort: \Assignment.dueDate)
        _exams = Query(filter: #Predicate<Exam> { $0.termID == id }, sort: \Exam.date)
        _courses = Query(filter: #Predicate<Course> { $0.termID == id }, sort: \Course.name)
    }

    @State private var selection: TaskSection = .assignments
    @State private var activeSheet: TaskSheet?
    @State private var detailSheet: TaskDetailSheet?
    @State private var deletingTask: TaskDetailSheet?
    @State private var planFilter: PlanListFilter = .all
    @State private var assignmentFilter: AssignmentFilter = .all
    @State private var examFilter: ExamFilter = .all

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    PageHeader(title: "Tasks", subtitle: nil) {
                        HStack(spacing: 10) {
                            filterMenu
                            HeaderActionButton(title: "Add Task", systemImage: "plus") {
                                switch selection {
                                case .plans: activeSheet = .newPlan
                                case .assignments: activeSheet = .newAssignment
                                case .exams: activeSheet = .newExam
                                }
                            }
                            .accessibilityIdentifier("addTask")
                        }
                    }

                    AppSegmentedPicker(label: "Section", selection: $selection,
                        options: TaskSection.allCases, title: { $0.title })

                    if selection == .plans {
                        PlansView(term: term, filter: planFilter,
                                  onOpen: { detailSheet = .plan($0) },
                                  onDelete: { deletingTask = .plan($0) })
                    } else {
                        ScrollView {
                            LazyVStack(spacing: AppTheme.Spacing.row) {
                                if selection == .assignments {
                                    if sortedAssignments.isEmpty {
                                        AppEmptyState(title: assignmentFilter == .all ? "No assignments yet." : "No \(assignmentFilter.title.lowercased()) assignments.",
                                                      message: "Tap + to add an assignment.", systemImage: "checklist")
                                    }
                                    ForEach(sortedAssignments, id: \.id) { item in
                                        AssignmentRow(item: item, isDueSoon: isAssignmentDueSoon(item),
                                            onToggleComplete: {
                                                item.isCompleted.toggle()
                                                _ = Persistence.save(modelContext, error: &saveError)
                                            }, onOpen: { detailSheet = .assignment(item) },
                                            onDelete: { deletingTask = .assignment(item) })
                                    }
                                } else {
                                    if sortedExams.isEmpty {
                                        AppEmptyState(title: examFilter == .all ? "No exams yet." : "No \(examFilter.title.lowercased()) exams.",
                                                      message: "Tap + to add an exam.", systemImage: "calendar")
                                    }
                                    ForEach(sortedExams, id: \.id) { item in
                                        ExamRow(item: item, daysUntil: daysUntilExam(item),
                                                onOpen: { detailSheet = .exam(item) },
                                                onDelete: { deletingTask = .exam(item) })
                                    }
                                }
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .toolbar(.hidden, for: .navigationBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .alert("Delete this task?", isPresented: Binding(
            get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }
        )) {
            Button("Delete", role: .destructive, action: deleteSelectedTask)
            Button("Cancel", role: .cancel) { deletingTask = nil }
        } message: { Text(deletingTask?.title ?? "") }
        .persistenceAlert($saveError)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newPlan:
                PlanEditor { planFilter = .all }
            case .newAssignment:
                AssignmentEditor(courses: courses, termID: term.id) { assignmentFilter = .all }
            case .newExam:
                ExamEditor(courses: courses, termID: term.id) { examFilter = .all }
            }
        }
        .sheet(item: $detailSheet) { sheet in
            switch sheet {
            case .plan(let plan):
                PlanDetailView(plan: plan)
            case .assignment(let item):
                AssignmentDetailView(item: item)
            case .exam(let item):
                ExamDetailView(item: item)
            }
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        switch selection {
        case .plans:
            TaskFilterMenu(label: "Filter Plans", selection: $planFilter, options: PlanListFilter.allCases,
                           optionTitle: { $0.title }, isFiltered: planFilter != .all)
        case .assignments:
            TaskFilterMenu(label: "Filter Assignments", selection: $assignmentFilter, options: AssignmentFilter.allCases,
                           optionTitle: { $0.title }, isFiltered: assignmentFilter != .all)
        case .exams:
            TaskFilterMenu(label: "Filter Exams", selection: $examFilter, options: ExamFilter.allCases,
                           optionTitle: { $0.title }, isFiltered: examFilter != .all)
        }
    }

    private func deleteSelectedTask() {
        guard let task = deletingTask else { return }
        switch task {
        case .plan(let item): modelContext.delete(item)
        case .assignment(let item): modelContext.delete(item)
        case .exam(let item): modelContext.delete(item)
        }
        _ = Persistence.save(modelContext, error: &saveError)
        deletingTask = nil
    }

    private var sortedAssignments: [Assignment] {
        assignments.filter {
            switch assignmentFilter {
            case .all: true
            case .pending: !$0.isCompleted
            case .completed: $0.isCompleted
            }
        }.sorted {
            if $0.isCompleted != $1.isCompleted {
                return !$0.isCompleted && $1.isCompleted
            }
            if $0.isCompleted {
                return $0.dueDate > $1.dueDate
            }
            return $0.dueDate < $1.dueDate
        }
    }

    private var sortedExams: [Exam] {
        let now = Date()
        return exams.filter {
            switch examFilter {
            case .all: true
            case .upcoming: $0.date >= now
            case .past: $0.date < now
            }
        }.sorted { examFilter == .past ? $0.date > $1.date : $0.date < $1.date }
    }

    private func isAssignmentDueSoon(_ item: Assignment) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let due = calendar.startOfDay(for: item.dueDate)
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 999
        return days >= 0 && days <= 3
    }

    private func daysUntilExam(_ item: Exam) -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let exam = calendar.startOfDay(for: item.date)
        let days = calendar.dateComponents([.day], from: today, to: exam).day ?? -1
        return (0...7).contains(days) ? days : nil
    }
}

private enum AssignmentFilter: String, CaseIterable {
    case all, pending, completed
    var title: String { rawValue.capitalized }
}

private enum ExamFilter: String, CaseIterable {
    case all, upcoming, past
    var title: String { rawValue.capitalized }
}

private enum TaskSection: CaseIterable {
    case plans
    case assignments
    case exams

    var title: String {
        switch self {
        case .plans: return "Plans"
        case .assignments: return "Assignments"
        case .exams: return "Exams"
        }
    }
}

private enum TaskSheet: Identifiable {
    case newPlan
    case newAssignment
    case newExam

    var id: String {
        switch self {
        case .newPlan: return "plan"
        case .newAssignment: return "assignment"
        case .newExam: return "exam"
        }
    }
}

private enum TaskDetailSheet: Identifiable {
    case plan(FlexiblePlan)
    case assignment(Assignment)
    case exam(Exam)

    var id: String {
        switch self {
        case .plan(let item):
            return "plan-\(item.id.uuidString)"
        case .assignment(let item):
            return "assignment-\(item.id.uuidString)"
        case .exam(let item):
            return "exam-\(item.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .plan(let item): item.title
        case .assignment(let item): item.content
        case .exam(let item): item.subject
        }
    }
}

private struct AssignmentRow: View {
    let item: Assignment
    let isDueSoon: Bool
    let onToggleComplete: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        TaskRowCard(title: item.content, onOpen: onOpen, onDelete: onDelete) {
            CompletionButton(isCompleted: item.isCompleted, title: item.content, action: onToggleComplete)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.content)
                        .font(AppTheme.Typography.rowTitle)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    if isDueSoon && !item.isCompleted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.dueDate, style: .date)
                    if let courseName = item.course?.name { Text(courseName).lineLimit(1) }
                }
                .font(AppTheme.Typography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExamRow: View {
    let item: Exam
    let daysUntil: Int?
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        TaskRowCard(title: item.subject, onOpen: onOpen, onDelete: onDelete) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(AppTheme.accent)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.subject).font(AppTheme.Typography.rowTitle)
                    if let daysUntil, daysUntil >= 0 {
                        Text("D-\(daysUntil)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                if !item.detail.trimmed.isEmpty {
                    Text(item.detail).font(AppTheme.Typography.caption).foregroundStyle(.secondary)
                }
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTheme.Typography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct AssignmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let item: Assignment
    @State private var isEditing = false
    @State private var saveError: String?
    @State private var content: String = ""
    @State private var detail = ""
    @State private var submitMethod: String = ""
    @State private var dueDate: Date = Date()
    @State private var isCompleted: Bool = false


    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    if isEditing {
                        TextField("Content", text: $content)
                        TextField("Submit Method", text: $submitMethod)
                    } else {
                        Text(item.content)
                        if !item.submitMethod.trimmed.isEmpty {
                            Text(item.submitMethod)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if isEditing || !item.detail.isEmpty {
                    Section("Details") {
                        if isEditing { TextField("Details", text: $detail, axis: .vertical) }
                        else { Text(item.detail).textSelection(.enabled) }
                    }
                }
                if let raw = item.sourceURL, let url = URL(string: raw), TeachingURLs.trusted(url) {
                    Section { Link("Open on Teaching Network", destination: url) }
                }
                Section("Due") {
                    if isEditing {
                        DatePicker("Deadline", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    } else {
                        Text(item.dueDate, style: .date)
                        Text(item.dueDate, style: .time)
                    }
                }
                if let course = item.course {
                    Section("Course") {
                        Text(course.name)
                    }
                }
                Section("Status") {
                    if isEditing {
                        Toggle("Completed", isOn: $isCompleted)
                    } else {
                        Text(item.isCompleted ? "Completed" : "Pending")
                    }
                }
            }
            .navigationTitle("Assignment")
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
                            item.detail = detail.trimmed
                            item.content = content.trimmed
                            item.submitMethod = submitMethod.trimmed
                            item.dueDate = dueDate
                            item.isCompleted = isCompleted
                            if Persistence.save(modelContext, error: &saveError) { dismiss() }
                        }
                        .disabled(content.trimmed.isEmpty)
                        .buttonStyle(.automatic)
                    } else {
                        Button("Edit") {
                            detail = item.detail
                            content = item.content
                            submitMethod = item.submitMethod
                            dueDate = item.dueDate
                            isCompleted = item.isCompleted
                            isEditing = true
                        }
                        .buttonStyle(.automatic)
                    }
                }
            }
        }
        .persistenceAlert($saveError)
    }
}

struct ExamDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let item: Exam
    @State private var isEditing = false
    @State private var saveError: String?
    @State private var subject: String = ""
    @State private var detail: String = ""
    @State private var date: Date = Date()


    var body: some View {
        NavigationStack {
            Form {
                Section("Exam") {
                    if isEditing {
                        TextField("Subject", text: $subject)
                        TextField("Detail", text: $detail)
                    } else {
                        Text(item.subject)
                        if !item.detail.trimmed.isEmpty {
                            Text(item.detail)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Date") {
                    if isEditing {
                        DatePicker("Exam Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    } else {
                        Text(item.date, style: .date)
                        Text(item.date, style: .time)
                    }
                }
                if let course = item.course {
                    Section("Course") {
                        Text(course.name)
                    }
                }
            }
            .navigationTitle("Exam")
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
                            item.subject = subject.trimmed
                            item.detail = detail.trimmed
                            item.date = date
                            if Persistence.save(modelContext, error: &saveError) { dismiss() }
                        }
                        .disabled(subject.trimmed.isEmpty)
                        .buttonStyle(.automatic)
                    } else {
                        Button("Edit") {
                            subject = item.subject
                            detail = item.detail
                            date = item.date
                            isEditing = true
                        }
                        .buttonStyle(.automatic)
                    }
                }
            }
        }
        .persistenceAlert($saveError)
    }
}

private struct AssignmentEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let courses: [Course]
    let termID: UUID
    let onSave: () -> Void
    @State private var saveError: String?
    @State private var content = ""
    @State private var dueDate = Calendar.current.date(
        bySettingHour: 23,
        minute: 59,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var submitMethod = ""
    @State private var selectedCourseID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    TextField("Content", text: $content)
                    TextField("Submit Method", text: $submitMethod)
                }
                Section("Due Date") {
                    DatePicker("Deadline", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }
                Section("Course") {
                    Picker("Course", selection: $selectedCourseID) {
                        Text("None").tag(UUID?.none)
                        ForEach(courses, id: \.id) { course in
                            Text(course.name).tag(course.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .navigationTitle("New Assignment")
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
                        let assignment = Assignment(
                            termID: termID,
                            content: content.trimmed,
                            dueDate: dueDate,
                            submitMethod: submitMethod.trimmed,
                            course: courses.first { $0.id == selectedCourseID }
                        )
                        modelContext.insert(assignment)
                        if Persistence.save(modelContext, error: &saveError) { onSave(); dismiss() }
                    }
                    .disabled(content.trimmed.isEmpty)
                    .buttonStyle(.automatic)
                }
            }
        }
        .persistenceAlert($saveError)
    }
}

private struct ExamEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let courses: [Course]
    let termID: UUID
    let onSave: () -> Void
    @State private var saveError: String?
    @State private var subject = ""
    @State private var detail = ""
    @State private var date = Date()
    @State private var selectedCourseID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Exam") {
                    TextField("Subject", text: $subject)
                    TextField("Detail", text: $detail)
                }
                Section("Date") {
                    DatePicker("Exam Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }
                Section("Course") {
                    Picker("Course", selection: $selectedCourseID) {
                        Text("None").tag(UUID?.none)
                        ForEach(courses, id: \.id) { course in
                            Text(course.name).tag(course.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .navigationTitle("New Exam")
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
                        let exam = Exam(
                            termID: termID,
                            subject: subject.trimmed,
                            detail: detail.trimmed,
                            date: date,
                            course: courses.first { $0.id == selectedCourseID }
                        )
                        modelContext.insert(exam)
                        if Persistence.save(modelContext, error: &saveError) { onSave(); dismiss() }
                    }
                    .disabled(subject.trimmed.isEmpty)
                    .buttonStyle(.automatic)
                }
            }
        }
        .persistenceAlert($saveError)
    }
}
