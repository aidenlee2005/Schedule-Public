import SwiftUI
import SwiftData
import QuickLook

struct TeachingNetworkCard: View {
    let term: Setting
    @State private var store = TeachingStore.shared
    @State private var showingHub = false

    var body: some View {
        Button { showingHub = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "building.columns").font(.title2).foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("PKU Teaching Network").font(.headline)
                    Text(store.isSignedIn ? "\(store.unreadCount) unread notices · assignments & materials" : "Connect notices, assignments and course files")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(AppTheme.Spacing.card).cardBackground()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("teachingNetwork")
        .sheet(isPresented: $showingHub) { TeachingHubView(term: term) }
        .task { await store.refreshIfNeeded() }
    }
}

struct TeachingHubView: View {
    let term: Setting
    @Environment(\.dismiss) private var dismiss
    @State private var store = TeachingStore.shared
    @State private var category: TeachingKind = .announcement
    @State private var courseFilter = ""
    @State private var showLogin = false
    @State private var selectedItem: TeachingItem?

    private var items: [TeachingItem] {
        TeachingItem.newestFirst(store.snapshot.items.filter {
            $0.kind == category && (courseFilter.isEmpty || $0.courseID == courseFilter)
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.isSignedIn ? "Connected to PKU" : "Connect your teaching network").font(.headline)
                            if let date = store.snapshot.fetchedAt {
                                Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !store.isSignedIn { Button("Sign In") { showLogin = true }.accessibilityIdentifier("teachingSignIn") }
                    }
                    if store.isRefreshing { ProgressView(store.progress).font(.caption) }
                    if let message = store.message { Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                    if store.isSignedIn {
                        Picker("Course", selection: $courseFilter) {
                            Text("All Courses").tag("")
                            ForEach(store.snapshot.courses) { Text($0.displayTitle).tag($0.id) }
                        }
                    }
                }
                AppSegmentedPicker(label: "Teaching Category", selection: $category,
                    options: TeachingKind.allCases, title: { $0.title })
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if items.isEmpty {
                    AppEmptyState(
                        title: store.isSignedIn ? "No \(category.title.lowercased()) yet" : "Your courses, in one place",
                        message: store.isSignedIn ? "Pull to refresh, or select another course." : "Sign in to read notices, import assignments and download your teachers’ files.",
                        systemImage: "building.columns"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(items) { item in
                    Button {
                        if item.kind == .announcement { store.markRead(item) }
                        selectedItem = item
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            if item.kind == .announcement && !store.snapshot.readKeys.contains(item.readKey) {
                                Circle().fill(AppTheme.accent).frame(width: 7, height: 7).padding(.top, 7)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(AppTheme.Typography.rowTitle).foregroundStyle(.primary)
                                Text(item.displayCourseTitle).font(.caption).foregroundStyle(.secondary)
                                if let published = item.publishedAt {
                                    Text(published.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                } else if let raw = item.publishedText, !raw.isEmpty {
                                    Text(raw).font(.caption).foregroundStyle(.secondary)
                                }
                                if let due = item.dueDate { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(AppTheme.accent) }
                                else if item.kind == .assignment { Text("No deadline provided").font(.caption).foregroundStyle(.secondary) }
                                if !item.attachments.isEmpty { Label("\(item.attachments.count) files", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(AppTheme.Spacing.card)
                        .cardBackground()
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Teaching Network")
            .appFormSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.buttonStyle(.automatic) }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Refresh") { Task { await store.refresh() } }.disabled(!store.isSignedIn || store.isRefreshing)
                        Button("Sign In Again") { showLogin = true }
                        Button("Sign Out", role: .destructive) { store.signOut() }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Teaching Network Options")
                }
            }
            .refreshable { await store.refresh() }
        }
        .sheet(isPresented: $showLogin) { TeachingSignInView(store: store) }
        .sheet(item: $selectedItem) { TeachingItemView(item: $0, term: term, store: store) }
        .task { await store.refreshIfNeeded() }
    }
}

private struct TeachingItemView: View {
    let item: TeachingItem
    let term: Setting
    let store: TeachingStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var courses: [Course]
    @State private var showingImport = false
    @State private var imported = false
    @State private var downloading = false
    @State private var files: [URL] = []
    @State private var preview: URL?
    @State private var error: String?

    init(item: TeachingItem, term: Setting, store: TeachingStore) {
        self.item = item; self.term = term; self.store = store
        let id = term.id
        _courses = Query(filter: #Predicate<Course> { $0.termID == id }, sort: \Course.name)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.title).font(AppTheme.Typography.sectionTitle)
                    Text(item.displayCourseTitle).font(.subheadline).foregroundStyle(.secondary)
                    if let dueDate = item.dueDate { Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar") }
                    else if let raw = item.dueDateText { Text("Deadline on source: \(raw)").font(.footnote) }
                    if !item.body.isEmpty { Text(item.body).textSelection(.enabled) }
                    Link("Open Original", destination: item.sourceURL)
                }
                if item.kind == .assignment {
                    Section {
                        Button(imported ? "Update Imported Assignment" : "Import Assignment", action: importAssignment)
                            .accessibilityIdentifier("importTeachingAssignment")
                        Text(imported ? "Added to \(term.displayName). Re-importing keeps your local edits and completion status." : "Import into \(term.displayName). The first import lets you link a local course.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !item.attachments.isEmpty {
                    Section("Course Files") {
                        ForEach(item.attachments) { attachment in Label(attachment.name, systemImage: "doc") }
                        Button {
                            Task {
                                downloading = true
                                defer { downloading = false }
                                do {
                                    let result = try await store.download(item)
                                    files = result.files
                                    if !result.failures.isEmpty { error = result.failures.joined(separator: "\n") }
                                    else if files.count == 1 { preview = files[0] }
                                }
                                catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            if downloading { ProgressView("Downloading…") }
                            else { Label("Download Files", systemImage: "arrow.down.circle") }
                        }
                        .disabled(downloading)
                        .accessibilityIdentifier("downloadTeachingFiles")
                    }
                }
                if !files.isEmpty {
                    Section("Downloaded") {
                        ForEach(files, id: \.self) { url in
                            HStack {
                                Button(url.lastPathComponent) { preview = url }
                                Spacer()
                                ShareLink(item: url)
                            }
                        }
                    }
                }
            }
            .navigationTitle(item.kind == .announcement ? "Notice" : (item.kind == .assignment ? "Assignment" : "Materials"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.buttonStyle(.automatic) } }
        }
        .quickLookPreview($preview)
        .sheet(isPresented: $showingImport) { TeachingImportSheet(item: item, term: term, store: store) { imported = true } }
        .persistenceAlert($error)
    }

    private func importAssignment() {
        guard let mapping = store.mappedCourse(item.courseID, termID: term.id), item.dueDate != nil,
              let accountID = store.accountID else { showingImport = true; return }
        let course = courses.first { $0.id.uuidString == mapping }
        if !mapping.isEmpty && course == nil { showingImport = true; return }
        do { try TeachingImporter.apply(item, accountID: accountID, term: term, course: course, context: context); imported = true }
        catch { self.error = error.localizedDescription }
    }
}

private struct TeachingImportSheet: View {
    let item: TeachingItem
    let term: Setting
    let store: TeachingStore
    let onImported: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var courses: [Course]
    @State private var selectedCourseID: UUID?
    @State private var chosenDate = Date()
    @State private var dateConfirmed = false
    @State private var error: String?

    init(item: TeachingItem, term: Setting, store: TeachingStore, onImported: @escaping () -> Void) {
        self.item = item; self.term = term; self.store = store; self.onImported = onImported
        let id = term.id
        _courses = Query(filter: #Predicate<Course> { $0.termID == id }, sort: \Course.name)
        _selectedCourseID = State(initialValue: store.mappedCourse(item.courseID, termID: term.id).flatMap(UUID.init(uuidString:)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Text(term.displayName)
                    Picker("Local Course", selection: $selectedCourseID) {
                        Text("No local course").tag(UUID?.none)
                        ForEach(courses) { Text($0.name).tag($0.id as UUID?) }
                    }
                    Text("This link is remembered for later imports from \(item.displayCourseTitle).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if item.dueDate == nil {
                    Section("Deadline") {
                        Text("The source did not provide a readable deadline. Choose one explicitly to create a dated assignment.")
                        DatePicker("Due Date", selection: $chosenDate)
                        Toggle("Use this date", isOn: $dateConfirmed)
                    }
                }
            }
            .navigationTitle("Import Assignment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        guard let accountID = store.accountID else { error = TeachingError.loginRequired.localizedDescription; return }
                        do {
                            try TeachingImporter.apply(item, accountID: accountID, term: term,
                                course: courses.first { $0.id == selectedCourseID }, chosenDate: item.dueDate == nil ? chosenDate : nil, context: context)
                            store.link(courseID: item.courseID, to: selectedCourseID, termID: term.id)
                            onImported(); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.automatic).disabled(item.dueDate == nil && !dateConfirmed)
                    .accessibilityIdentifier("confirmTeachingImport")
                }
            }
        }
        .persistenceAlert($error)
    }
}
