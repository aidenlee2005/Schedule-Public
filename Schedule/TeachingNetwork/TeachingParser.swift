import Foundation
import SwiftSoup

/// Selectors and endpoints adapted from sshwy/pku3b (MIT). See ThirdPartyNotices.txt.
enum TeachingParser {
    struct ContentPage {
        var items: [TeachingItem] = []
        var folders: [String] = []
    }

    static func isLogin(_ html: String) -> Bool {
        html.contains("id=\"loginForm\"") || html.contains("name=\"password\"") || html.contains("id=\"password\"") || html.contains("iaaa.pku.edu.cn/iaaa/oauth.jsp")
    }

    static func courses(_ html: String) throws -> [TeachingCourse] {
        let doc = try SwiftSoup.parse(html)
        if isLogin(html) { throw TeachingError.loginRequired }
        var result: [TeachingCourse] = []
        var seen: Set<String> = []
        let portlets = try doc.select("div.portlet")
        for portlet in portlets {
            let title = try portlet.select("span.moduleTitle").text()
            let current = title.contains("当前") || title.localizedCaseInsensitiveContains("current semester")
            for link in try portlet.select("ul.courseListing li a") {
                let href = try link.attr("href")
                guard let id = capture(#"key=([\d_]+)"#, in: href) ?? TeachingURLs.resolve(href)?.queryValue("course_id"), seen.insert(id).inserted else { continue }
                result.append(TeachingCourse(id: id, title: try link.text(), isCurrent: current))
            }
        }
        let containers = try doc.select("ul.courseListing, #courseMenuPalette_contents")
        if result.isEmpty && containers.isEmpty() {
            throw TeachingError.unexpectedPage
        }
        return result
    }

    static func roots(_ html: String) throws -> [String] {
        let doc = try SwiftSoup.parse(html)
        if isLogin(html) { throw TeachingError.loginRequired }
        let links = try doc.select("#courseMenuPalette_contents > li > a")
        return Array(Set(try links.compactMap { link in
            guard let url = TeachingURLs.resolve(try link.attr("href")), url.path.hasSuffix("listContent.jsp") else { return nil }
            return url.queryValue("content_id")
        })).sorted()
    }

    static func contents(_ html: String, course: TeachingCourse) throws -> ContentPage {
        let doc = try SwiftSoup.parse(html)
        if isLogin(html) { throw TeachingError.loginRequired }
        let contentContainers = try doc.select("#content_listContainer, .noItems, #emptyListMsg")
        guard !contentContainers.isEmpty() else { throw TeachingError.unexpectedPage }
        var result = ContentPage()
        for row in try doc.select("#content_listContainer > li") {
            let children = row.children().array()
            guard children.count >= 2 else { continue }
            let image = try row.select("img").first()
            let alt = try image?.attr("alt").lowercased() ?? ""
            let titleElement = try row.select(".item, h3").first() ?? children[1]
            let title = try titleElement.text().trimmed
            let titleLink = try titleElement.select("a").first()
            let url = try titleLink.flatMap { TeachingURLs.resolve(try $0.attr("href")) }
            let headerID = try titleElement.attr("id")
            let rowID = try row.attr("id")
            let id = url?.queryValue("content_id") ?? (headerID.isEmpty ? rowID : headerID)
            guard !id.isEmpty, !title.isEmpty else { continue }
            let isFolder = alt.contains("文件夹") || alt.contains("folder") || url?.path.hasSuffix("listContent.jsp") == true
            if isFolder {
                result.folders.append(url?.queryValue("content_id") ?? id)
                continue
            }
            let assignment = alt.contains("作业") || alt.contains("assignment") || url?.path.contains("uploadAssignment") == true
            let detail = children.count > 2 ? children[2] : row
            let body = try detail.select(".vtbegenerated").text()
            var attachments = try attachmentLinks(in: detail)
            if alt == "文件" || alt == "file" {
                let file = TeachingURLs.make("/webapps/blackboard/execute/content/file", ["course_id": course.id, "content_id": id, "mode": "view"])
                attachments.insert(TeachingAttachment(name: title, url: file), at: 0)
            }
            if !assignment && attachments.isEmpty && (url?.path.contains("bbcswebdav") == true) {
                attachments.append(TeachingAttachment(name: title, url: url!))
            }
            result.items.append(TeachingItem(id: "\(course.id):\(id)", courseID: course.id, courseTitle: course.title,
                contentID: id, kind: assignment ? .assignment : .material, title: title, body: body,
                publishedText: nil, sourceURL: assignment ? TeachingURLs.assignment(course: course.id, id: id) : (url ?? TeachingURLs.content(course: course.id, id: id)), attachments: attachments))
        }
        return result
    }

    static func announcements(_ html: String, course: TeachingCourse) throws -> [TeachingItem] {
        let doc = try SwiftSoup.parse(html)
        if isLogin(html) { throw TeachingError.loginRequired }
        var result: [TeachingItem] = []; var seen: Set<String> = []
        for heading in try doc.select("#announcementList h3, #content_listContainer h3, .announcement h3, .vtbegenerated h3") {
            let title = try heading.text().trimmed
            guard !title.isEmpty, title != "公告", title != "Announcements" else { continue }
            let parent = heading.parent() ?? heading
            var content = ""; var published = ""
            var next = try heading.nextElementSibling(); var count = 0
            while let element = next, element.tagName() != "h3", count < 20 {
                let text = try element.text().trimmed
                if text.contains("发布") || text.localizedCaseInsensitiveContains("posted on") { published = text }
                else if !text.isEmpty { content += (content.isEmpty ? "" : "\n") + text }
                next = try element.nextElementSibling(); count += 1
            }
            if content.isEmpty { content = try parent.select(".vtbegenerated, .details").text() }
            let rawID = try heading.attr("id").isEmpty ? (parent.tagName() == "li" ? parent.attr("id") : "") : heading.attr("id")
            let id = rawID.isEmpty ? TeachingURLs.digest(title + published) : rawID
            guard seen.insert(id).inserted else { continue }
            result.append(TeachingItem(id: "\(course.id):notice:\(id)", courseID: course.id, courseTitle: course.title,
                contentID: id, kind: .announcement, title: title, body: content,
                publishedText: published.isEmpty ? nil : published, publishedAt: parseDate(published), sourceURL: TeachingURLs.course(course.id), attachments: try attachmentLinks(in: parent)))
        }
        return result
    }

    static func apiAnnouncements(_ rows: [TeachingContentMetadata], course: TeachingCourse) throws -> [TeachingItem] {
        try rows.compactMap { row in
            guard let title = row.title, !title.trimmed.isEmpty else { return nil }
            let body = try SwiftSoup.parse(row.body ?? "")
            return TeachingItem(id: "\(course.id):notice:\(row.id)", courseID: course.id,
                courseTitle: course.title, contentID: row.id, kind: .announcement, title: title,
                body: try body.text(), publishedText: row.created, publishedAt: row.publishedAt,
                sourceURL: TeachingURLs.course(course.id), attachments: try attachmentLinks(in: body))
        }
    }

    static func deadline(_ html: String) throws -> (date: Date?, raw: String?) {
        if isLogin(html) { throw TeachingError.loginRequired }
        let doc = try SwiftSoup.parse(html)
        let text = try doc.select("#assignMeta2 + div").first()?.text()
        return (text.flatMap { parseDate($0) }, text)
    }

    static func parseDate(_ text: String) -> Date? {
        let normalized = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        let pattern = #"(\d{4})年(\d{1,2})月(\d{1,2})日\s*(?:星期\S\s*)?(上午|下午)?\s*(\d{1,2}):(\d{2})"#
        if let match = normalized.range(of: pattern, options: .regularExpression) {
            let raw = String(normalized[match])
            let regex = try! NSRegularExpression(pattern: pattern)
            if let m = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                func value(_ i: Int) -> String { Range(m.range(at: i), in: raw).map { String(raw[$0]) } ?? "" }
                var hour = Int(value(5)) ?? 0
                if value(4) == "下午" && hour < 12 { hour += 12 }
                if value(4) == "上午" && hour == 12 { hour = 0 }
                guard (0...23).contains(hour), let minute = Int(value(6)), (0...59).contains(minute) else { return nil }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                let components = DateComponents(year: Int(value(1)), month: Int(value(2)), day: Int(value(3)), hour: hour, minute: Int(value(6)))
                guard let date = calendar.date(from: components), calendar.component(.day, from: date) == components.day else { return nil }
                return date
            }
        }
        for format in ["yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm", "EEEE, MMMM d, yyyy h:mm a", "MMMM d, yyyy h:mm a", "MMM d, yyyy h:mm a"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = format; formatter.isLenient = false
            if let date = formatter.date(from: normalized.trimmed) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: normalized) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: normalized) { return date }
        if let dateText = capture(#"(\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:[ ]\d{1,2}:\d{2})?)"#, in: normalized) {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.isLenient = false
            for format in ["yyyy-M-d HH:mm", "yyyy/M/d HH:mm", "yyyy-M-d", "yyyy/M/d"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: dateText) { return date }
            }
        }
        return nil
    }

    private static func attachmentLinks(in element: Element) throws -> [TeachingAttachment] {
        var seen: Set<String> = []
        return try element.select("ul.attachments a, audio + ul a, a[href*='bbcswebdav']").compactMap { a in
            guard let url = TeachingURLs.resolve(try a.attr("href")), !url.path.isEmpty, url.path != "/", seen.insert(url.absoluteString).inserted else { return nil }
            let name = try a.text().trimmed
            return TeachingAttachment(name: name.isEmpty ? url.lastPathComponent : name, url: url)
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)?.queryItems?.first { $0.name == name }?.value
    }
}
