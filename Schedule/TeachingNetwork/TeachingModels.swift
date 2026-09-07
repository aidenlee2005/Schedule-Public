import Foundation
import CryptoKit

enum TeachingKind: String, Codable, CaseIterable {
    case announcement, assignment, material
    var title: String {
        switch self { case .announcement: return "Notices"; case .assignment: return "Assignments"; case .material: return "Materials" }
    }
}

struct TeachingCourse: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let isCurrent: Bool
    var displayTitle: String { Self.readableTitle(title) }

    static func readableTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"^\d{4,6}-[^:]+:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\(\d{2}-\d{2}学年第\d学期\)$"#, with: "", options: .regularExpression).trimmed
    }
}

struct TeachingAttachment: Identifiable, Codable, Hashable {
    let name: String
    let url: URL
    var id: String { url.absoluteString }
}

struct TeachingItem: Identifiable, Codable, Hashable {
    let id: String
    let courseID: String
    let courseTitle: String
    let contentID: String
    let kind: TeachingKind
    let title: String
    let body: String
    var dueDate: Date?
    var dueDateText: String?
    let publishedText: String?
    var publishedAt: Date?
    let sourceURL: URL
    var attachments: [TeachingAttachment]
    var revision: String { TeachingURLs.digest(title + body + (publishedText ?? "")) }
    var readKey: String { id + ":" + revision }
    var displayCourseTitle: String { TeachingCourse.readableTitle(courseTitle) }

    /// Unknown publication times retain source order, after entries with known times.
    static func newestFirst(_ items: [TeachingItem]) -> [TeachingItem] {
        items.enumerated().sorted { a, b in
            switch (a.element.publishedAt, b.element.publishedAt) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}

struct TeachingSnapshot: Codable {
    var courses: [TeachingCourse] = []
    var items: [TeachingItem] = []
    var fetchedAt: Date?
    var readKeys: Set<String> = []
    /// term UUID -> remote course ID -> local course UUID (empty string means no local course).
    var courseLinks: [String: [String: String]] = [:]
}

enum TeachingURLs {
    static let origin = URL(string: "https://course.pku.edu.cn")!
    static let login = URL(string: "https://course.pku.edu.cn/webapps/bb-sso-BBLEARN/login.html")!
    static let home = make("/webapps/portal/execute/tabs/tabAction", ["tab_tab_group_id": "_1_1"])
    static let me = make("/learn/api/public/v1/users/me")

    static func make(_ path: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: URL(string: path, relativeTo: origin)!.absoluteURL, resolvingAgainstBaseURL: true)!
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    static func course(_ id: String) -> URL {
        make("/webapps/blackboard/execute/announcement", ["method": "search", "context": "course_entry", "course_id": id, "handle": "announcements_entry", "mode": "view"])
    }

    static func content(course: String, id: String) -> URL {
        make("/webapps/blackboard/content/listContent.jsp", ["course_id": course, "content_id": id])
    }

    static func assignment(course: String, id: String) -> URL {
        make("/webapps/assignment/uploadAssignment", ["action": "newAttempt", "course_id": course, "content_id": id])
    }

    static func trusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return host == "pku.edu.cn" || host.hasSuffix(".pku.edu.cn")
    }

    static func resolve(_ href: String) -> URL? {
        let cleaned = href.trimmed.replacingOccurrences(of: "@X@EmbeddedFile.requestUrlStub@X@", with: "/")
        guard !cleaned.isEmpty, !cleaned.hasPrefix("#"),
              let absolute = URL(string: cleaned, relativeTo: origin)?.absoluteURL,
              var parts = URLComponents(url: absolute, resolvingAgainstBaseURL: true) else { return nil }
        if parts.scheme == "http", let host = parts.host, host == "pku.edu.cn" || host.hasSuffix(".pku.edu.cn") { parts.scheme = "https" }
        guard let url = parts.url, trusted(url) else { return nil }
        return url
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func filename(_ name: String) -> String {
        let stripped = name.components(separatedBy: CharacterSet(charactersIn: "/\\:\0")).joined(separator: "_").trimmed
        let usable = stripped.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return usable.isEmpty ? "attachment" : String(usable.prefix(150))
    }
}

enum TeachingError: LocalizedError {
    case loginRequired, untrustedURL, unexpectedPage, fileUnavailable, noDeadline, missingCourseLink, http(Int)
    var errorDescription: String? {
        switch self {
        case .loginRequired: return "Your teaching-network session has expired. Sign in again to refresh. Saved items remain available."
        case .untrustedURL: return "This link cannot be downloaded inside the app. Open the original course page instead."
        case .unexpectedPage: return "The teaching-network page format was not recognized. Your saved items have been kept."
        case .fileUnavailable: return "The teaching network returned a webpage instead of this file. Open the original item to check availability."
        case .noDeadline: return "No reliable deadline was provided. Choose a date before importing this assignment."
        case .missingCourseLink: return "Choose the semester and course for this assignment first."
        case .http(let status): return "The teaching network returned HTTP \(status). Please try again later."
        }
    }
}
