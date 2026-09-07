import SwiftUI
import SwiftData

enum PlanListFilter: String, CaseIterable {
    case all, active, paused, completed
    var title: String { rawValue.capitalized }
}

struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [FlexiblePlan]
    let filter: PlanListFilter
    let onOpen: (FlexiblePlan) -> Void
    let onDelete: (FlexiblePlan) -> Void
    @State private var saveError: String?

    init(term: Setting, filter: PlanListFilter, onOpen: @escaping (FlexiblePlan) -> Void,
         onDelete: @escaping (FlexiblePlan) -> Void) {
        self.filter = filter
        self.onOpen = onOpen
        self.onDelete = onDelete
        let id = term.id
        _plans = Query(filter: #Predicate<FlexiblePlan> { $0.termID == nil || $0.termID == id },
                       sort: \FlexiblePlan.createdAt, order: .reverse)
    }

    private var visiblePlans: [FlexiblePlan] {
        plans.filter { filter == .all || $0.status.rawValue == filter.rawValue }
            .sorted {
                if $0.status != $1.status { return rank($0.status) < rank($1.status) }
                if $0.status == .completed {
                    return ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
                }
                return $0.createdAt > $1.createdAt
            }
    }

    private func rank(_ status: PlanStatus) -> Int {
        switch status { case .active: 0; case .paused: 1; case .completed: 2 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.row) {
                if visiblePlans.isEmpty {
                    AppEmptyState(title: emptyTitle, message: emptyMessage, systemImage: "leaf")
                        .accessibilityIdentifier("plansEmptyState")
                }
                ForEach(visiblePlans) { plan in
                    TaskRowCard(title: plan.title, onOpen: { onOpen(plan) }, onDelete: { onDelete(plan) }) {
                        CompletionButton(isCompleted: plan.status == .completed, title: plan.title) {
                            plan.setCompleted(plan.status != .completed)
                            _ = Persistence.save(context, error: &saveError)
                        }
                    } content: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.title)
                                .font(AppTheme.Typography.rowTitle)
                                .foregroundStyle(plan.status == .completed ? .secondary : .primary)
                                .strikethrough(plan.status == .completed)
                                .lineLimit(3)
                            if plan.status == .paused {
                                Text("Paused").font(AppTheme.Typography.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .persistenceAlert($saveError)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No plans yet."
        case .active: "No active plans."
        case .paused: "No paused plans."
        case .completed: "No completed plans."
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all, .active: "Tap + to add a plan. Just a title is enough."
        case .paused: "Paused plans will appear here."
        case .completed: "Completed plans will appear here."
        }
    }
}

struct PlanEditor: View {
    let onSave: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("planTitle")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Plan")
            .appFormSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.buttonStyle(.automatic)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save", action: save)
                        .buttonStyle(.automatic).disabled(title.trimmed.isEmpty)
                        .accessibilityIdentifier("savePlan")
                }
            }
        }
        .persistenceAlert($saveError)
        .task { titleFocused = true }
    }

    private func save() {
        guard !title.trimmed.isEmpty else { return }
        context.insert(FlexiblePlan(title: title.trimmed, window: .anytime))
        if Persistence.save(context, error: &saveError) { onSave(); dismiss() }
    }
}

struct PlanDetailView: View {
    let plan: FlexiblePlan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var draft: PlanTitleDraft
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    init(plan: FlexiblePlan) {
        self.plan = plan
        _draft = State(initialValue: PlanTitleDraft(plan: plan))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    if isEditing {
                        TextField("Title", text: $draft.title)
                            .focused($titleFocused)
                            .accessibilityIdentifier("editPlanTitle")
                    } else {
                        Text(plan.title).textSelection(.enabled)
                    }
                }
                Section("Status") { Text(plan.status.title) }
                if !isEditing && plan.status != .completed {
                    Section {
                        Button(plan.status == .paused ? "Resume Plan" : "Pause Plan") {
                            plan.status = plan.status == .paused ? .active : .paused
                            if Persistence.save(context, error: &saveError) { dismiss() }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Plan")
            .appFormSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.buttonStyle(.automatic)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            draft.apply(to: plan)
                            if Persistence.save(context, error: &saveError) { dismiss() }
                        }
                        .buttonStyle(.automatic).disabled(draft.title.trimmed.isEmpty)
                        .accessibilityIdentifier("savePlanTitle")
                    } else {
                        Button("Edit") {
                            draft = PlanTitleDraft(plan: plan)
                            isEditing = true
                            titleFocused = true
                        }.buttonStyle(.automatic)
                    }
                }
            }
        }
        .persistenceAlert($saveError)
    }
}
