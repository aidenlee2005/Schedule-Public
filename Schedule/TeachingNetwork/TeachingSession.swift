import Foundation
import Security

struct TeachingCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let secure: Bool
    let httpOnly: Bool

    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        expires = cookie.expiresDate; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
    }

    var cookie: HTTPCookie? {
        if let expires, expires < Date() { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

struct TeachingCredentials: Codable {
    let accountID: String
    let cookies: [TeachingCookie]
}

enum TeachingVault {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Schedule") + ".teaching-network",
         kSecAttrAccount as String: "session"]
    }

    static func load() throws -> TeachingCredentials? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw vaultError(status) }
        return try JSONDecoder().decode(TeachingCredentials.self, from: data)
    }

    static func save(_ credentials: TeachingCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(request as CFDictionary, nil)
            if added != errSecSuccess { throw vaultError(added) }
        } else if status != errSecSuccess { throw vaultError(status) }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw vaultError(status) }
    }

    private static func vaultError(_ code: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey:
            code == errSecInteractionNotAllowed
                ? "Unlock your device, then try connecting again."
                : "Secure session storage is unavailable. Please install the latest build and try again."])
    }
}

/// Redirects stay on HTTPS PKU hosts; cookies retain Foundation's domain/path scoping.
final class TeachingRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, let host = url.host?.lowercased(),
              host == "pku.edu.cn" || host.hasSuffix(".pku.edu.cn"), url.user == nil, url.password == nil else { completionHandler(nil); return }
        var next = request
        if url.scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            parts.scheme = "https"
            next.url = parts.url
        }
        guard next.url?.scheme == "https" else { completionHandler(nil); return }
        completionHandler(next)
    }
}

@MainActor
final class TeachingClient {
    let session: URLSession
    let cookies: HTTPCookieStorage
    private let redirectDelegate = TeachingRedirectDelegate()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 180
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 Schedule/1.0", "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.5"]
        cookies = configuration.httpCookieStorage!
        session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
    }

    func setCookies(_ newCookies: [HTTPCookie]) {
        clearCookies()
        for cookie in newCookies {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if host == "pku.edu.cn" || host.hasSuffix(".pku.edu.cn") { cookies.setCookie(cookie) }
        }
    }

    func clearCookies() { for cookie in cookies.cookies ?? [] { cookies.deleteCookie(cookie) } }

    func accountID() async throws -> String {
        let (data, _) = try await get(TeachingURLs.me)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? String else {
            throw TeachingError.loginRequired
        }
        return id
    }

    func html(_ url: URL) async throws -> String {
        let (data, _) = try await get(url)
        guard let html = String(data: data, encoding: .utf8) else { throw TeachingError.unexpectedPage }
        if TeachingParser.isLogin(html) { throw TeachingError.loginRequired }
        return html
    }

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        guard TeachingURLs.trusted(url) else { throw TeachingError.untrustedURL }
        let (data, response) = try await session.data(from: url)
        let http = try checked(response)
        return (data, http)
    }

    func download(_ attachment: TeachingAttachment) async throws -> (URL, String) {
        guard TeachingURLs.trusted(attachment.url) else { throw TeachingError.untrustedURL }
        let (temporary, response) = try await session.download(from: attachment.url)
        _ = try checked(response)
        if response.url?.path.contains("/webapps/portal/") == true || response.url?.path.contains("/execute/announcement") == true {
            throw TeachingError.fileUnavailable
        }
        if response.mimeType?.contains("html") == true {
            let sample = try FileHandle(forReadingFrom: temporary)
            defer { try? sample.close() }
            let data = try sample.read(upToCount: 32768) ?? Data()
            if TeachingParser.isLogin(String(decoding: data, as: UTF8.self)) { throw TeachingError.loginRequired }
        }
        let suggested = response.suggestedFilename ?? attachment.name
        return (temporary, TeachingURLs.filename(suggested.isEmpty ? attachment.name : suggested))
    }

    private func checked(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else { throw TeachingError.unexpectedPage }
        if response.statusCode == 401 || response.statusCode == 403 || response.url?.host == "iaaa.pku.edu.cn" || response.url?.path.contains("/webapps/login") == true { throw TeachingError.loginRequired }
        guard (200..<300).contains(response.statusCode) else { throw TeachingError.http(response.statusCode) }
        return response
    }
}
