import SwiftUI
import WebKit

struct TeachingSignInView: View {
    let store: TeachingStore
    @Environment(\.dismiss) private var dismiss
    @State private var browser = LoginBrowser()
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Sign in on PKU’s website. Only the login session is saved in Keychain; the app does not store your password.")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
                if let error = error ?? browser.error {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(10)
                }
                LoginWebView(browser: browser)
                if checking { ProgressView("Checking your session…").padding() }
            }
            .navigationTitle("PKU Sign In").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(.automatic) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { Task { await connect() } }.disabled(checking).buttonStyle(.automatic)
                        .accessibilityIdentifier("finishPKULogin")
                }
            }
            .onChange(of: browser.reachedPortal) { _, ready in if ready { Task { await connect() } } }
        }
    }

    private func connect() async {
        guard !checking else { return }
        checking = true; error = nil
        defer { checking = false }
        do {
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                browser.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            try await store.connect(cookies: cookies)
            dismiss()
            Task { await store.refresh() }
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
@Observable
final class LoginBrowser: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var error: String?
    var reachedPortal = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: TeachingURLs.login))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.host == "course.pku.edu.cn", webView.url?.path.contains("/portal/") == true { reachedPortal = true }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme?.lowercased() == "http", let secureURL = TeachingURLs.resolve(url.absoluteString) {
            // PKU's registered OAuth callback still names HTTP; upgrade before sending the token.
            var secureRequest = navigationAction.request
            secureRequest.url = secureURL
            error = nil
            decisionHandler(.cancel)
            webView.load(secureRequest)
        } else if url.absoluteString == "about:blank" || TeachingURLs.trusted(url) {
            error = nil
            decisionHandler(.allow)
        }
        else { error = "This sign-in link is not an HTTPS PKU page."; decisionHandler(.cancel) }
    }
}

private struct LoginWebView: UIViewRepresentable {
    let browser: LoginBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
