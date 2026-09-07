//
//  InsightsView.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query private var assignments: [Assignment]
    @Query private var exams: [Exam]
    @Query private var courses: [Course]
    @Query private var plans: [FlexiblePlan]
    let term: Setting
    @State private var selectedEvent: UpcomingEvent?

    init(term: Setting) {
        self.term = term
        let id = term.id
        _assignments = Query(filter: #Predicate<Assignment> { $0.termID == id }, sort: \Assignment.dueDate)
        _exams = Query(filter: #Predicate<Exam> { $0.termID == id }, sort: \Exam.date)
        _plans = Query(filter: #Predicate<FlexiblePlan> { $0.termID == nil || $0.termID == id }, sort: \FlexiblePlan.createdAt)
        _courses = Query(filter: #Predicate<Course> { $0.termID == id }, sort: \Course.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PageHeader(title: "Insights", subtitle: nil) {
                        EmptyView()
                    }
                    InsightsHeaderPanel(
                        events: UpcomingEvent.collect(assignments: assignments, exams: exams),
                        nextStep: plans.first { $0.status == .active && !$0.nextStep.isEmpty }?.nextStep,
                        onSelect: { selectedEvent = $0 }
                    )
                    TeachingNetworkCard(term: term)
                    MetricsRow(
                        coursesCount: courses.count,
                        assignmentsCompleted: completedAssignmentsCount,
                        assignmentsTotal: assignments.count,
                        examsCompleted: completedExamsCount,
                        examsTotal: exams.count
                    )

                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, 4)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedEvent) { event in
            if let assignment = assignments.first(where: { $0.id == event.id }) {
                AssignmentDetailView(item: assignment)
            } else if let exam = exams.first(where: { $0.id == event.id }) {
                ExamDetailView(item: exam)
            }
        }
    }

    private var completedAssignmentsCount: Int {
        assignments.filter { $0.isCompleted }.count
    }

    private var completedExamsCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return exams.filter { calendar.startOfDay(for: $0.date) < today }.count
    }
}

private struct MetricsRow: View {
    let coursesCount: Int
    let assignmentsCompleted: Int
    let assignmentsTotal: Int
    let examsCompleted: Int
    let examsTotal: Int

    var body: some View {
        HStack(spacing: 12) {
            MetricCard(title: "Courses", value: "\(coursesCount)")
            MetricCard(title: "Assignments", value: "\(assignmentsCompleted)/\(assignmentsTotal)")
            MetricCard(title: "Exams", value: "\(examsCompleted)/\(examsTotal)")
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(AppTheme.Typography.sectionTitle)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardBackground()
    }
}
