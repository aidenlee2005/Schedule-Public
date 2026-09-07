import SwiftUI
import UIKit

enum CompanionCharacter: String, CaseIterable, Identifiable {
    case lulu = "Lulu"
    case nai = "Nai"

    var id: String { rawValue }

    static var available: [Self] {
        allCases.filter { character in
            CompanionPose.allCases.allSatisfy { UIImage(named: character.asset(for: $0)) != nil }
        }
    }

    func asset(for pose: CompanionPose) -> String {
        "companion-\(rawValue.lowercased())-\(pose.rawValue)"
    }
}

enum CompanionPose: String, CaseIterable {
    case idle, blink, pat, laugh, rest, cheer
}

enum CompanionReaction {
    case idle, pat, tickle, rest, wake

    var pose: CompanionPose {
        switch self {
        case .idle: .idle
        case .pat: .pat
        case .tickle: .laugh
        case .rest: .rest
        case .wake: .cheer
        }
    }
}

/// Generated pose sprites share a canvas and ground line. Native motion adds
/// breathing and touch feedback without a video, network service, or pet model.
struct CompanionArtwork: View {
    static let canvasSize: CGFloat = 224
    let character: CompanionCharacter
    let pose: CompanionPose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var appearedAt = Date()

    private var animates: Bool {
        isVisible && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animates)) { timeline in
            let time = animates ? max(0, timeline.date.timeIntervalSince(appearedAt)) : 0
            let breath = sin(time * .pi / (pose == .rest ? 2.5 : 1.8))
            let blink = pose == .idle && time.truncatingRemainder(dividingBy: 4.7) > 4.53
            Image(character.asset(for: blink ? .blink : pose))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(x: 1 - breath * 0.004, y: 1 + breath * 0.008, anchor: .bottom)
                .rotationEffect(.degrees(pose == .rest ? 0 : sin(time * .pi / 3.6) * 0.65), anchor: .bottom)
        }
        .frame(width: Self.canvasSize, height: Self.canvasSize)
        .onAppear { appearedAt = Date(); isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityHidden(true)
    }
}
