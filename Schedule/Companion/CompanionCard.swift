import SwiftUI

struct CompanionCard: View {
    let events: [UpcomingEvent]
    let nextStep: String?
    let onSelect: (UpcomingEvent) -> Void
    let onHide: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var speech = "今天也可以先迈出很小的一步。"
    @State private var lastSpoken: Date?
    @State private var character = CompanionCharacter.lulu
    @State private var reaction = CompanionReaction.idle
    @State private var isResting = false
    @State private var touchSequence = 0
    @State private var lastTouch = Date.distantPast
    private let stageHeight: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pawprint.fill").foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(character.rawValue)’s Corner").font(.headline)
                    Text("A little company, at your pace").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Picker("Companion", selection: $character) {
                        ForEach(CompanionCharacter.available) { character in
                            Text(character.rawValue).tag(character)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Hide Companion", action: onHide)
                } label: { Image(systemName: "ellipsis").padding(8).contentShape(Rectangle()) }
                .accessibilityLabel("Companion Options")
            }
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [AppTheme.highlight.opacity(scheme == .dark ? 0.10 : 0.45), AppTheme.accent.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse().fill(AppTheme.accent.opacity(0.12)).frame(width: 220, height: 44).offset(y: 4)
                Image(systemName: "sparkle").font(.system(size: 16)).foregroundStyle(AppTheme.accent.opacity(0.55)).offset(x: -100, y: -168)
                Image(systemName: "leaf.fill").font(.system(size: 18)).foregroundStyle(AppTheme.accent.opacity(0.45)).rotationEffect(.degrees(24)).offset(x: 116, y: -36)
                CompanionArtwork(character: character, pose: isResting ? .rest : reaction.pose)
                    .id(character)
                    .phaseAnimator([0, 1, 2, 3, 4], trigger: touchSequence) { artwork, phase in
                        artwork
                            .offset(y: reduceMotion ? 0 : bounceOffset(phase))
                            .rotationEffect(.degrees(reduceMotion ? 0 : swayAngle(phase)), anchor: .bottom)
                            .scaleEffect(x: reduceMotion ? 1 : (phase == 1 ? 1.035 : 1),
                                         y: reduceMotion ? 1 : (phase == 1 ? 0.965 : 1), anchor: .bottom)
                    } animation: { _ in .easeInOut(duration: 0.12) }
                    .padding(.bottom, 2)
            }
            .frame(height: stageHeight)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.45, maximumDistance: 12)
                    .exclusively(before: SpatialTapGesture())
                    .onEnded { touch in
                        switch touch {
                        case .first(true): interact(isResting ? .wake : .rest)
                        case .second(let tap):
                            let headBoundary = stageHeight - CompanionArtwork.canvasSize * 0.43
                            interact(isResting ? .wake : (tap.location.y < headBoundary ? .pat : .tickle))
                        default: break
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(character.rawValue)
            .accessibilityValue(isResting ? "Resting" : "Awake")
            .accessibilityAction { interact(isResting ? .wake : .pat) }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("companionStage")

            Text(speech)
                .font(.subheadline).lineSpacing(4)
                .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                .padding(13)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("companionSpeech")
            Divider().opacity(0.5)
            UpcomingSummary(events: events, onSelect: onSelect)
        }
        .padding(18)
        .cardBackground(cornerRadius: 26)
        .onAppear { speak(random: false) }
        .onChange(of: character) {
            isResting = false
            reaction = .wake
            touchSequence += 1
            speech = "我是 \(character.rawValue)，今天也一起慢慢来。"
            lastSpoken = Date()
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(35)) } catch { return }
                if scenePhase == .active && !isResting && CompanionDialogue.canSpeak(lastSpoken: lastSpoken) { speak(random: true) }
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: touchSequence)
        .task(id: touchSequence) {
            guard reaction != .idle else { return }
            do { try await Task.sleep(for: .seconds(1.8)) } catch { return }
            reaction = .idle
        }
    }

    private func interact(_ action: CompanionReaction) {
        let now = Date()
        guard now.timeIntervalSince(lastTouch) >= 0.18 else { return }
        lastTouch = now
        isResting = action == .rest
        reaction = action
        touchSequence += 1
        switch action {
        case .tickle: speech = "哈哈，好痒！稍微休息一下也很好。"
        case .rest: speech = "靠着你休息一小会儿，真舒服。"
        case .wake: speech = "醒啦，我继续陪着你。"
        default:
            if touchSequence.isMultiple(of: 3) { speak(random: true) }
            else { speech = "收到摸摸，陪你慢慢把事情做好。" }
        }
        lastSpoken = now
    }

    private func bounceOffset(_ phase: Int) -> CGFloat {
        if reaction == .rest { return phase == 1 ? 3 : 0 }
        switch phase {
        case 1: return reaction == .wake ? -12 : -8
        case 3: return -3
        default: return 0
        }
    }

    private func swayAngle(_ phase: Int) -> Double {
        guard reaction != .rest else { return 0 }
        let amount = reaction == .tickle ? 5.0 : 2.0
        switch phase {
        case 1: return -amount
        case 2: return amount
        case 3: return -amount * 0.45
        default: return 0
        }
    }

    private func speak(random: Bool) {
        let lines = CompanionDialogue.lines(events: events, nextStep: nextStep)
        let alternatives = lines.filter { $0 != speech }
        speech = random ? (alternatives.randomElement() ?? lines[0]) : lines[0]
        lastSpoken = Date()
    }
}
