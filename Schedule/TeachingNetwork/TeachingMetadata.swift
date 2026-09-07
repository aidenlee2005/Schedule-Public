import Foundation

struct TeachingMetadataPage: Decodable {
    struct Paging: Decodable { let nextPage: String? }
    let results: [TeachingContentMetadata]
    let paging: Paging?
}

struct TeachingContentMetadata: Decodable {
    let id: String
    let title: String?
    let body: String?
    let created: String?
    let modified: String?
    let hasChildren: Bool?

    var publishedAt: Date? { created.flatMap { TeachingParser.parseDate($0) } }
}

extension TeachingClient {
    /// Prefer the source's creation date; never substitute refresh or download time.
    func publicationDates(courseID: String) async throws -> [String: Date] {
        var queue = [TeachingURLs.make("/learn/api/public/v1/courses/\(courseID)/contents", ["limit": "100"])]
        var seen: Set<URL> = []
        var result: [String: Date] = [:]
        while !queue.isEmpty {
            try Task.checkCancellation()
            let url = queue.removeFirst()
            guard seen.insert(url).inserted else { continue }
            guard seen.count <= 150 else { break }
            guard let page = try await metadataPage(url) else { continue }
            for item in page.results {
                if let date = item.publishedAt { result[item.id] = date }
                if item.hasChildren == true {
                    queue.append(TeachingURLs.make("/learn/api/public/v1/courses/\(courseID)/contents/\(item.id)/children", ["limit": "100"]))
                }
            }
            if let next = page.paging?.nextPage, let url = TeachingURLs.resolve(next) { queue.append(url) }
        }
        return result
    }

    func announcementMetadata(courseID: String) async throws -> [TeachingContentMetadata]? {
        var next: URL? = TeachingURLs.make("/learn/api/public/v1/courses/\(courseID)/announcements", ["limit": "100"])
        var result: [TeachingContentMetadata] = []
        var seen: Set<URL> = []
        while let url = next, seen.insert(url).inserted, seen.count <= 100 {
            guard let page = try await metadataPage(url) else { return nil }
            result.append(contentsOf: page.results)
            next = page.paging?.nextPage.flatMap { TeachingURLs.resolve($0) }
        }
        return result
    }

    private func metadataPage(_ url: URL) async throws -> TeachingMetadataPage? {
        guard TeachingURLs.trusted(url) else { throw TeachingError.untrustedURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 { throw TeachingError.loginRequired }
        // Some installations restrict metadata APIs even when HTML course access is allowed.
        guard http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(TeachingMetadataPage.self, from: data)
    }
}
