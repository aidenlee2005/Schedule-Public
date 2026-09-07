import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    let term: Setting
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Setting.termStartDate, order: .reverse) private var terms: [Setting]
    @AppStorage("activeTermID", store: AppPreferences.defaults) private var activeTermID = ""
    @State private var draft: TermDraft
    @State private var isImporterPresented = false
    @State private var termEditor: TermEditorRoute?
    @State private var pendingDeletion: Setting?
    @State private var showClearAlert = false
    @State private var showTeachingNetwork = false
    @State private var saveError: String?
    @State private var importMessage: String?

    init(term: Setting) {
        self.term = term
        _draft = State(initialValue: TermDraft(term: term))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Current Semester", selection: Binding(
                        get: { term.id.uuidString },
                        set: { value in switchTerm(to: value) }
                    )) {
                        ForEach(terms) { item in Text(item.displayName).tag(item.id.uuidString) }
                    }
                    .accessibilityIdentifier("semesterPicker")
                    Button { termEditor = .new } label: {
                        Label("Create Semester", systemImage: "plus")
                    }
                    .accessibilityIdentifier("createSemester")
                    NavigationLink("Manage Semesters") {
                        semesterList
                    }
                    .accessibilityIdentifier("manageSemesters")
                } header: {
                    Text("Semesters")
                } footer: {
                    Text("Courses, assignments, exams and settings are saved separately for each semester. Switching semesters discards unsaved settings below.")
                }

                SemesterDetailsSection(draft: $draft)
                Section("Schedule View") {
                    AppSegmentedPicker(label: "Show Weekends", selection: $draft.showWeekends,
                        options: [true, false], title: { $0 ? "Show Sat/Sun" : "Hide Sat/Sun" })
                }
                Section {
                    Button("Import CSV") { isImporterPresented = true }
                    Text("CSV columns: name, teacher, classroom, weekday, startPeriod, endPeriod, weekPattern.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Import into \(term.displayName)") }
                Section("Connections") {
                    Button("PKU Teaching Network") { showTeachingNetwork = true }
                        .accessibilityIdentifier("settingsTeachingNetwork")
                }
                Section("Appearance") {
                    Button("Randomize Course Colors", action: randomizeColors)
                }
                Section {
                    Button("Clear Current Semester Data", role: .destructive) { showClearAlert = true }
                } header: { Text("Data") } footer: {
                    Text("Importing, randomizing colors and clearing data take effect immediately. Other semesters are unaffected.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .appFormSurface()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        draft.apply(to: term)
                        if Persistence.save(modelContext, error: &saveError) { dismiss() }
                    }
                    .buttonStyle(.automatic)
                    .disabled(draft.name.trimmed.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showTeachingNetwork) { TeachingHubView(term: term) }
        .sheet(item: $termEditor) { route in
            TermEditor(term: route.term) { saved in
                if route.term == nil { switchTerm(to: saved.id.uuidString) }
                else if saved.id == term.id { draft = TermDraft(term: saved) }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard let csv = String(data: data, encoding: .utf8) else { throw CourseImporter.ImportError.encoding }
                let summary = try CourseImporter.importCSV(csv, into: term, context: modelContext)
                importMessage = summary.message
            } catch { saveError = error.localizedDescription }
        }
        .persistenceAlert($saveError)
        .alert("Import Complete", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .alert("Clear \(term.displayName)?", isPresented: $showClearAlert) {
            Button("Clear Data", role: .destructive) {
                do {
                    try TermManager.clearData(for: term, in: modelContext)
                    _ = Persistence.save(modelContext, error: &saveError)
                } catch { modelContext.rollback(); saveError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes this semester’s courses, assignments, exams and semester plans. Personal plans and the semester and its settings are kept.") }
        .alert("Delete Semester?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Delete", role: .destructive, action: deletePendingTerm)
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { Text("Delete \(pendingDeletion?.displayName ?? "") and its courses, assignments, exams and semester plans? Personal plans are kept. This cannot be undone.") }
    }

    private var semesterList: some View {
        List {
            ForEach(terms) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName).font(.body.weight(.semibold))
                        Text("\(item.termStartDate.formatted(date: .abbreviated, time: .omitted)) · \(item.totalWeeks) weeks")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.id == term.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
                    }
                    Menu {
                        Button("Load Semester") { switchTerm(to: item.id.uuidString) }
                        Button("Edit Semester") { termEditor = .edit(item) }
                        Button("Delete Semester", role: .destructive) { pendingDeletion = item }
                            .disabled(terms.count <= 1)
                    } label: {
                        Image(systemName: "ellipsis.circle").padding(8)
                    }
                    .accessibilityLabel("Manage \(item.displayName)")
                }
            }
            Button { termEditor = .new } label: { Label("Create Semester", systemImage: "plus") }
        }
        .navigationTitle("Semesters")
        .appFormSurface()
    }

    private func switchTerm(to id: String) {
        guard id != term.id.uuidString else { return }
        dismiss()
        activeTermID = id
    }

    private func randomizeColors() {
        do {
            let id = term.id
            for course in try modelContext.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.termID == id })) {
                course.colorHex = ""
                course.colorSeed = Int.random(in: 1...1_000_000)
            }
            _ = Persistence.save(modelContext, error: &saveError)
        } catch { modelContext.rollback(); saveError = error.localizedDescription }
    }

    private func deletePendingTerm() {
        guard let item = pendingDeletion else { return }
        let deletingCurrent = item.id == term.id
        let replacementID = terms.first { $0.id != item.id }?.id.uuidString
        do {
            try TermManager.delete(item, in: modelContext)
            if Persistence.save(modelContext, error: &saveError), deletingCurrent, let replacementID {
                dismiss()
                activeTermID = replacementID
            }
        } catch { modelContext.rollback(); saveError = error.localizedDescription }
        pendingDeletion = nil
    }
}

private enum TermEditorRoute: Identifiable {
    case new
    case edit(Setting)
    var term: Setting? { if case .edit(let term) = self { return term }; return nil }
    var id: String { term?.id.uuidString ?? "new" }
}

/// Current settings and semester creation/editing expose the same information.
private struct SemesterDetailsSection: View {
    @Binding var draft: TermDraft
    var nameIdentifier = "Semester Name"
    var isNewSemester = false

    var body: some View {
        Section {
            TextField("Semester Name", text: $draft.name)
                .accessibilityIdentifier(nameIdentifier)
            DatePicker("Week 1 Starts", selection: $draft.startDate, displayedComponents: [.date])
                .datePickerStyle(.compact)
            Stepper("Total Weeks: \(draft.totalWeeks)", value: $draft.totalWeeks, in: 1...52)
            TextField("Grade", text: $draft.grade)
            Picker("Season", selection: $draft.season) {
                ForEach(TermSeason.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Semester Details")
        } footer: {
            Text(isNewSemester
                 ? "Week 1 begins on the Monday of the selected week. A new semester starts with an empty course schedule and task list."
                 : "Week 1 begins on the Monday of the selected week.")
        }
    }
}

private struct TermEditor: View {
    let term: Setting?
    let onCreate: (Setting) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TermDraft
    @State private var saveError: String?

    init(term: Setting?, onCreate: @escaping (Setting) -> Void) {
        self.term = term
        self.onCreate = onCreate
        _draft = State(initialValue: term.map { TermDraft(term: $0) } ?? TermDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                SemesterDetailsSection(draft: $draft, nameIdentifier: "termName", isNewSemester: term == nil)
            }
            .navigationTitle(term == nil ? "New Semester" : "Edit Semester")
            .appFormSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(term == nil ? "Create" : "Save") {
                        let target = term ?? draft.makeTerm()
                        if term == nil { context.insert(target) } else { draft.apply(to: target) }
                        if Persistence.save(context, error: &saveError) {
                            dismiss()
                            onCreate(target)
                        }
                    }
                    .buttonStyle(.automatic)
                    .disabled(draft.name.trimmed.isEmpty)
                    .accessibilityIdentifier("saveSemester")
                }
            }
        }
        .persistenceAlert($saveError)
    }
}
