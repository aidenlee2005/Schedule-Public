import Foundation
import Observation

@MainActor
@Observable
final class TeachingStore {
    static let shared = TeachingStore()
    private let client = TeachingClient()
    private(set) var snapshot = TeachingSnapshot()
    private(set) var accountID: String?
    private(set) var isSignedIn = false
    private(set) var isRefreshing = false
    private(set) var progress = ""
    var message: String?
    private var generation = UUID()

    init() {
        do {
            if let credentials = try TeachingVault.load() {
                accountID = credentials.accountID
                client.setCookies(credentials.cookies.compactMap(\.cookie))
                isSignedIn = !(client.cookies.cookies ?? []).isEmpty
                try loadCache()
            }
        } catch { message = error.localizedDescription }
    }

    var unreadCount: Int { snapshot.items.filter { $0.kind == .announcement && !snapshot.readKeys.contains($0.readKey) }.count }

    func connect(cookies: [HTTPCookie]) async throws {
        let candidate = TeachingClient()
        candidate.setCookies(cookies)
        let id = try await candidate.accountID()
        let credentials = TeachingCredentials(accountID: id, cookies: (candidate.cookies.cookies ?? []).map(TeachingCookie.init))
        try TeachingVault.save(credentials)
        generation = UUID()
        accountID = id
        client.setCookies(candidate.cookies.cookies ?? [])
        snapshot = TeachingSnapshot()
        try loadCache()
        isSignedIn = true
        message = nil
    }

    func signOut() {
        do {
            try TeachingVault.clear()
            generation = UUID()
            client.clearCookies(); accountID = nil; snapshot = TeachingSnapshot(); isSignedIn = false
        } catch { message = error.localizedDescription }
    }

    func refreshIfNeeded() async {
        guard isSignedIn else { return }
        if let date = snapshot.fetchedAt, Date().timeIntervalSince(date) < 300 { return }
        await refresh()
    }

    func refresh() async {
        guard isSignedIn, !isRefreshing else { return }
        let requestGeneration = generation
        isRefreshing = true; progress = "Loading courses…"; message = nil
        defer { isRefreshing = false; progress = "" }
        do {
            let courses = try TeachingParser.courses(await client.html(TeachingURLs.home)).filter(\.isCurrent)
            let chosen = courses
            var replacement = snapshot.items
            var warnings: [String] = []
            var successfulCourses = 0
            for (index, course) in chosen.enumerated() {
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                progress = "\(index + 1)/\(chosen.count) · \(course.title)"
                do {
                    let items = try await fetchCourse(course)
                    replacement.removeAll { $0.courseID == course.id }
                    replacement.append(contentsOf: items)
                    successfulCourses += 1
                } catch TeachingError.loginRequired { throw TeachingError.loginRequired }
                catch is CancellationError { throw CancellationError() }
                catch { warnings.append("\(course.title): \(error.localizedDescription)") }
            }
            guard generation == requestGeneration else { return }
            let allowed = Set(courses.map(\.id))
            snapshot.courses = courses
            snapshot.items = replacement.filter { allowed.contains($0.courseID) }
            if successfulCourses > 0 || chosen.isEmpty { snapshot.fetchedAt = Date() }
            try saveCache()
            if let accountID { try TeachingVault.save(TeachingCredentials(accountID: accountID, cookies: (client.cookies.cookies ?? []).map(TeachingCookie.init))) }
            if !warnings.isEmpty { message = "Some courses could not be refreshed; their saved items were kept.\n" + warnings.joined(separator: "\n") }
        } catch is CancellationError { }
        catch TeachingError.loginRequired { isSignedIn = false; message = TeachingError.loginRequired.localizedDescription }
        catch { message = error.localizedDescription }
    }

    private func fetchCourse(_ course: TeachingCourse) async throws -> [TeachingItem] {
        let html = try await client.html(TeachingURLs.course(course.id))
        var result = try TeachingParser.announcements(html, course: course)
        if let metadata = try await client.announcementMetadata(courseID: course.id) {
            result = try TeachingParser.apiAnnouncements(metadata, course: course)
        }
        let dates = try await client.publicationDates(courseID: course.id)
        var queue = try TeachingParser.roots(html)
        var visited: Set<String> = []; var ids = Set(result.map(\.id))
        while !queue.isEmpty {
            try Task.checkCancellation()
            let id = queue.removeFirst()
            guard visited.insert(id).inserted else { continue }
            guard visited.count <= 150 else { throw TeachingError.unexpectedPage }
            let page = try TeachingParser.contents(await client.html(TeachingURLs.content(course: course.id, id: id)), course: course)
            queue.append(contentsOf: page.folders.filter { !visited.contains($0) })
            for var item in page.items where ids.insert(item.id).inserted {
                item.publishedAt = dates[item.contentID] ?? item.publishedAt
                if item.kind == .assignment {
                    let metadata = try TeachingParser.deadline(await client.html(TeachingURLs.assignment(course: course.id, id: item.contentID)))
                    item.dueDate = metadata.date; item.dueDateText = metadata.raw
                }
                result.append(item)
            }
        }
        return result
    }

    func markRead(_ item: TeachingItem) {
        snapshot.readKeys.insert(item.readKey)
        persist()
    }

    func link(courseID: String, to localCourseID: UUID?, termID: UUID) {
        snapshot.courseLinks[termID.uuidString, default: [:]][courseID] = localCourseID?.uuidString ?? ""
        persist()
    }

    func mappedCourse(_ courseID: String, termID: UUID) -> String? { snapshot.courseLinks[termID.uuidString]?[courseID] }

    struct DownloadResult {
        var files: [URL] = []
        var failures: [String] = []
    }

    func download(_ item: TeachingItem) async throws -> DownloadResult {
        guard isSignedIn, let accountID else { throw TeachingError.loginRequired }
        let folder = try directory(accountID).appendingPathComponent("Attachments").appendingPathComponent(TeachingURLs.digest(item.id))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var result = DownloadResult()
        for attachment in item.attachments {
            try Task.checkCancellation()
            do {
                let (temporary, filename) = try await client.download(attachment)
                let attachmentFolder = folder.appendingPathComponent(TeachingURLs.digest(attachment.id))
                try FileManager.default.createDirectory(at: attachmentFolder, withIntermediateDirectories: true)
                let target = attachmentFolder.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: temporary, to: target)
                result.files.append(target)
            } catch is CancellationError { throw CancellationError() }
            catch { result.failures.append("\(attachment.name): \(error.localizedDescription)") }
        }
        return result
    }

    private func persist() { do { try saveCache() } catch { message = error.localizedDescription } }
    private func directory(_ account: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("TeachingNetwork").appendingPathComponent(TeachingURLs.digest(account))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private func loadCache() throws {
        guard let accountID else { return }
        let file = try directory(accountID).appendingPathComponent("snapshot.json")
        if FileManager.default.fileExists(atPath: file.path) {
            snapshot = try JSONDecoder().decode(TeachingSnapshot.self, from: Data(contentsOf: file))
            snapshot.courses = snapshot.courses.filter(\.isCurrent)
            let currentIDs = Set(snapshot.courses.map(\.id))
            snapshot.items = snapshot.items.filter { currentIDs.contains($0.courseID) }.map { item in
                var cleaned = item
                cleaned.attachments = item.attachments.filter { !$0.url.path.isEmpty && $0.url.path != "/" }
                return cleaned
            }
        }
    }
    private func saveCache() throws {
        guard let accountID else { return }
        let file = try directory(accountID).appendingPathComponent("snapshot.json")
        try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
