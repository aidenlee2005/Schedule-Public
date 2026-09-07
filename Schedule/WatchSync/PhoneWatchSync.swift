import Foundation
import SwiftData
import WatchConnectivity

/// The only message accepted from the watch asks for a fresh display snapshot.
/// This service never inserts, edits, deletes, or saves SwiftData models.
@MainActor
final class PhoneWatchSync: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSync()
    private var container: ModelContainer?
    private var defaults: UserDefaults = .standard
    private var session: WCSession?
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    func configure(container: ModelContainer, defaults: UserDefaults) {
        guard WCSession.isSupported() else { return }
        self.container = container
        self.defaults = defaults
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: Persistence.didSave,
                object: nil, queue: .main) { [weak self] _ in
                    guard let coordinator = self else { return }
                    Task { @MainActor in coordinator.refresh() }
                }
        }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func refresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            _ = self?.publish()
        }
    }

    private func publish() -> [String: Any] {
        guard let session, session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled, let container else { return [:] }
        do {
            let sourceID = UUID(uuidString: defaults.string(forKey: "watchSnapshotSource") ?? "") ?? UUID()
            let previous = defaults.integer(forKey: "watchSnapshotRevision")
            let revision = previous < Int.max ? previous + 1 : 1
            defaults.set(sourceID.uuidString, forKey: "watchSnapshotSource")
            defaults.set(revision, forKey: "watchSnapshotRevision")
            let snapshot = try WatchSnapshotBuilder.make(context: container.mainContext,
                activeTermID: defaults.string(forKey: "activeTermID") ?? "", sourceID: sourceID, revision: revision)
            let data = try snapshot.encoded()
            if data.count < 60_000 {
                let packet: [String: Any] = [WatchSnapshot.contextKey: data]
                try session.updateApplicationContext(packet)
                return packet
            }
            // Large semesters use the file channel, not an oversized context/message.
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WatchTransfer", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID()).json")
            try data.write(to: url, options: .atomic)
            for old in session.outstandingFileTransfers {
                guard old.file.metadata?["scheduleSnapshot"] as? Bool == true else { continue }
                old.cancel()
                try? FileManager.default.removeItem(at: old.file.fileURL)
            }
            session.transferFile(url, metadata: ["scheduleSnapshot": true])
            try session.updateApplicationContext(["scheduleSnapshotPending": true])
            return ["scheduleSnapshotPending": true]
        } catch {
            // The watch keeps the last valid copy and shows its original sync date.
            return ["scheduleSnapshotUnavailable": true]
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in if state == .activated { self.refresh() } }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard message.count == 1, message[WatchSnapshot.requestKey] as? Bool == true else {
            replyHandler([:]); return
        }
        Task { @MainActor in replyHandler(self.publish()) }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer,
                             error: Error?) {
        guard fileTransfer.file.metadata?["scheduleSnapshot"] as? Bool == true else { return }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
}
