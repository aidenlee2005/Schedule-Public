import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var isReachable = false
    @Published private(set) var syncIssue = false
    private var session: WCSession?
    private var lastRequest = Date.distantPast
    private let cacheURL: URL

    override init() {
        cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchSnapshot.json")
        super.init()
        if let data = try? Data(contentsOf: cacheURL) { snapshot = try? WatchSnapshot.decode(data) }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func requestLatest() {
        guard let session, session.activationState == .activated else { return }
        isReachable = session.isReachable
        if let data = session.receivedApplicationContext[WatchSnapshot.contextKey] as? Data { receive(data) }
        guard session.isReachable, Date().timeIntervalSince(lastRequest) > 10 else { return }
        lastRequest = Date()
        session.sendMessage([WatchSnapshot.requestKey: true], replyHandler: { [weak self] message in
            let data = message[WatchSnapshot.contextKey] as? Data
            let failed = message["scheduleSnapshotUnavailable"] as? Bool == true
            Task { @MainActor in
                if let data { self?.receive(data) }
                else if failed { self?.syncIssue = true }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.syncIssue = true }
        })
    }

    private func receive(_ data: Data) {
        do {
            let incoming = try WatchSnapshot.decode(data)
            guard incoming.isNewer(than: snapshot) else { return }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            snapshot = incoming
            syncIssue = false
        } catch { syncIssue = true }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.requestLatest() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.requestLatest() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context[WatchSnapshot.contextKey] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["scheduleSnapshot"] as? Bool == true,
              let size = try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= WatchSnapshot.maximumBytes,
              let data = try? Data(contentsOf: file.fileURL) else { return }
        // Read during the callback; WatchConnectivity removes the temporary file afterwards.
        Task { @MainActor in self.receive(data) }
    }
}
