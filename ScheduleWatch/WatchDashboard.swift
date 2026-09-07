import SwiftUI

private enum WatchPalette {
    static let accent = Color(red: 0.48, green: 0.82, blue: 0.65)
    static let secondary = Color(red: 0.66, green: 0.74, blue: 0.69)
    static let pine = Color(red: 0.06, green: 0.18, blue: 0.12)
    static let canvas = LinearGradient(colors: [Color(red: 0.025, green: 0.075, blue: 0.05), pine],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let plain = LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
}

/// Read-only pages. Dates and the highlighted lesson follow time automatically.
struct WatchDashboard: View {
    @ObservedObject var store: WatchStore
    let now: Date
    @State private var page = 0

    private var snapshot: WatchSnapshot? { store.snapshot }
    private var calendar: Calendar { snapshot?.calendar ?? .current }
    private var agenda: WatchAgenda? { snapshot?.agenda(at: now) }
    private var agendaHeading: String {
        let date = agenda?.date ?? now
        return "\(agenda?.isTomorrow == true ? "明天" : "今天") \(formatted(date, "M/d"))"
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                heroPage.tag(0).containerBackground(WatchPalette.canvas, for: .tabView)
                dayPage.tag(1).containerBackground(.black, for: .tabView)
                assignmentPage.tag(2).containerBackground(.black, for: .tabView)
                examPage.tag(3).containerBackground(.black, for: .tabView)
            }
            .tabViewStyle(.verticalPage(transitionStyle: .blur))
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if page == 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(agendaHeading).font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchPalette.accent).fixedSize()
                    }
                }
            }
            .containerBackground(page == 0 ? WatchPalette.canvas : WatchPalette.plain, for: .navigation)
            .overlay(alignment: .bottom) {
                if let snapshot, store.syncIssue || now.timeIntervalSince(snapshot.generatedAt) > 24 * 60 * 60 {
                    Text("请打开手机更新数据").font(.system(size: 10))
                        .foregroundStyle(WatchPalette.secondary).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.8), in: Capsule()).padding(.bottom, 2)
                }
            }
        }
        .tint(WatchPalette.accent)
    }

    private var heroPage: some View {
        Group {
            if let snapshot {
                switch snapshot.classStatus(at: now) {
                case .ongoing(let lesson): lessonHero(lesson, ongoing: true)
                case .upcoming(let lesson): lessonHero(lesson, ongoing: false)
                case .semesterEnded:
                    statusHero("学期已结束！", symbol: "flag.checkered", detail: "在手机切换学期")
                case .noUpcomingClasses:
                    statusHero("暂时没有课", symbol: "calendar", detail: "暂无后续课程安排")
                case .noSemester:
                    statusHero("等待同步", symbol: "iphone", detail: "在手机设置当前学期")
                }
            } else {
                statusHero("等待同步", symbol: "iphone", detail: "打开手机上的 Schedule")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
        .accessibilityIdentifier("watch-next")
    }

    private func lessonHero(_ lesson: WatchLesson, ongoing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ongoing ? "进行中" : "下一节课")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.accent)
                .lineLimit(1).minimumScaleFactor(0.85)
            VStack(alignment: .leading, spacing: 7) {
                Text(lesson.name).font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                if !lesson.classroom.isEmpty {
                    Label(lesson.classroom, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(WatchPalette.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if !calendar.isDate(lesson.start, inSameDayAs: now) {
                        Text(day(lesson.start)).font(.system(size: 11)).foregroundStyle(WatchPalette.secondary)
                    }
                    Text("\(time(lesson.start))–\(time(lesson.end))")
                        .font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                }
                if ongoing {
                    let progress = min(max(now.timeIntervalSince(lesson.start) / lesson.end.timeIntervalSince(lesson.start), 0), 1)
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: progress).progressViewStyle(.linear).controlSize(.mini)
                            .tint(WatchPalette.accent).accessibilityLabel("本节课进度")
                    }.padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.07), lineWidth: 0.5))
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusHero(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.accent).lineLimit(1).minimumScaleFactor(0.85)
            emptyState(symbol, title: detail)
        }
    }

    private var dayPage: some View {
        Group {
            if let agenda {
                if agenda.lessons.isEmpty {
                    let weekday = calendar.component(.weekday, from: agenda.date)
                    let weekend = weekday == 1 || weekday == 7
                    emptyState(weekend ? "sun.max" : "calendar", title: agenda.isTomorrow ? "明天暂无课程" : "今天暂无课程")
                } else {
                    fittingList {
                        ForEach(agenda.lessons) { lesson in
                            lessonRow(lesson)
                        }
                    }
                }
            } else { emptyState("iphone", title: "打开手机同步课表") }
        }
        .padding(.horizontal, 8).padding(.bottom, 2)
        .accessibilityIdentifier("watch-day")
    }

    private func lessonRow(_ lesson: WatchLesson) -> some View {
        let ongoing = lesson.start <= now && now < lesson.end
        let past = lesson.end <= now
        return timelineRow(time: time(lesson.start), secondaryTime: time(lesson.end),
                           title: lesson.name, subtitle: lesson.classroom,
                           ongoing: ongoing, past: past)
    }

    /// Shared rhythm for courses, assignments and exams: when on the left,
    /// what and where on the right. Long content grows instead of shrinking.
    private func timelineRow(time: String, secondaryTime: String, title: String,
                             subtitle: String, detail: String = "",
                             ongoing: Bool = false, past: Bool = false) -> some View {
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(time)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(past ? WatchPalette.secondary : WatchPalette.accent)
                    .frame(width: 36, alignment: .leading)
                Text(title).font(.system(size: 14, weight: .semibold))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(past ? WatchPalette.secondary : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(secondaryTime).font(.system(size: 10, design: .rounded)).monospacedDigit()
                    .frame(width: 36, alignment: .leading)
                Text(subtitle.isEmpty ? " " : subtitle)
                    .font(.system(size: 11)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(WatchPalette.secondary)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(WatchPalette.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 48)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(ongoing ? WatchPalette.pine : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            if ongoing {
                Capsule().fill(WatchPalette.accent).frame(width: 2).padding(.vertical, 9)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var assignmentPage: some View {
        Group {
            if let snapshot {
                let items = snapshot.pendingAssignments(at: now)
                if items.isEmpty { emptyState("checklist", title: "暂无待完成作业") }
                else {
                    fittingList {
                        ForEach(items) { item in
                            timelineRow(time: item.dueDate < now ? "已逾期" : shortDay(item.dueDate),
                                        secondaryTime: item.dueDate < now ? formatted(item.dueDate, "M/d") : time(item.dueDate),
                                        title: item.title,
                                        subtitle: item.title.contains(item.courseName) ? "" : item.courseName)
                                .accessibilityLabel("\(item.title)，\(item.courseName)，\(item.dueDate < now ? "已逾期，" : "")截止 \(formatted(item.dueDate, "M月d日 HH:mm"))")
                        }
                    }
                }
            } else { emptyState("iphone", title: "打开手机同步作业") }
        }
        .padding(.horizontal, 8).padding(.bottom, 2)
        .accessibilityIdentifier("watch-assignments")
    }

    private var examPage: some View {
        Group {
            if let snapshot {
                let items = snapshot.upcomingExams(at: now)
                if items.isEmpty { emptyState("calendar", title: "未来5天暂无考试") }
                else {
                    fittingList {
                        ForEach(items) { item in
                            timelineRow(time: shortDay(item.date), secondaryTime: time(item.date),
                                        title: item.courseName.isEmpty ? item.title : item.courseName,
                                        subtitle: item.courseName.isEmpty || item.title == item.courseName ? "" : item.title,
                                        detail: item.detail)
                        }
                    }
                }
            } else { emptyState("iphone", title: "打开手机同步考试") }
        }
        .padding(.horizontal, 8).padding(.bottom, 2)
        .accessibilityIdentifier("watch-exams")
    }

    private func fittingList<Content: View>(spacing: CGFloat = 6, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyState(_ symbol: String, title: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 33, weight: .regular)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(WatchPalette.accent)
                .frame(width: 70, height: 70)
                .background(WatchPalette.accent.opacity(0.075), in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .medium))
                .foregroundStyle(WatchPalette.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatted(_ value: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: value)
    }
    private func time(_ value: Date) -> String { formatted(value, "HH:mm") }
    private func shortDay(_ value: Date) -> String {
        if calendar.isDate(value, inSameDayAs: now) { return "今天" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(value, inSameDayAs: tomorrow) {
            return "明天"
        }
        return formatted(value, "M/d")
    }
    private func day(_ value: Date) -> String {
        let short = shortDay(value)
        return short == "今天" || short == "明天" ? short : formatted(value, "M/d EEE")
    }
}
