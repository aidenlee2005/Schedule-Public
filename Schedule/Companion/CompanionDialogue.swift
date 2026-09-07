import Foundation

/// Local templates only. No networking, language model, or persistent pet state.
enum CompanionDialogue {
    static func lines(events: [UpcomingEvent], nextStep: String?, now: Date = Date()) -> [String] {
        var lines = ["今天也可以先迈出很小的一步。", "我在这里陪你。累了就伸个懒腰吧。", "不用一下做完所有事，慢慢来也很好。"]
        if let event = events.first {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: event.date)).day ?? 0
            let name = String(event.title.prefix(45))
            let reminder: String
            if event.date < now {
                reminder = "「\(name)」已经到期了，看看是否还需要处理吧。"
            } else if days == 0 {
                reminder = "「\(name)」就在今天 \(event.date.formatted(date: .omitted, time: .shortened))，我帮你记着呢。"
            } else {
                reminder = "「\(name)」还有 \(days) 天\(event.isExam ? "就要考试" : "到期")，可以先看一眼。"
            }
            lines.insert(reminder, at: 0)
        }
        if let nextStep, !nextStep.trimmed.isEmpty { lines.append("有空可以先做这一小步：\(String(nextStep.prefix(60)))") }
        return lines
    }

    static func canSpeak(lastSpoken: Date?, now: Date = Date()) -> Bool {
        lastSpoken.map { now.timeIntervalSince($0) >= 25 } ?? true
    }
}
