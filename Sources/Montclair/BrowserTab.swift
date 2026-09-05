import AppKit
import WebKit

@MainActor
final class BrowserTab: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private static let privateFaviconSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    let id = UUID()
    let isPrivate: Bool
    private let websiteDataStore: WKWebsiteDataStore
    private(set) var webView: WKWebView?
    private(set) var storedURL: URL?
    private(set) var title = "New Tab"
    private(set) var favicon: NSImage?
    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var lastActive = Date()

    var onChange: (() -> Void)?
    var onOpenNewTab: ((URL) -> Void)?
    var onNavigationResult: ((Bool, String) -> Void)?
    var onScrollDirection: ((Bool) -> Void)?
    var onVisit: ((String, String) -> Void)?
    var sessionAddress: String {
        let value = storedURL?.absoluteString ?? ""
        return BrowserLibrary.isWebURL(value) ? value : ""
    }

    var displayAddress: String {
        guard let url = webView?.url else { return "" }
        if url.isFileURL, let resources = Bundle.main.resourceURL, url.path.hasPrefix(resources.path) { return "" }
        return url.absoluteString == "about:blank" ? "" : url.absoluteString
    }

    init(url: URL? = nil, lazy: Bool = false, websiteDataStore: WKWebsiteDataStore? = nil, isPrivate: Bool = false) {
        storedURL = url
        self.websiteDataStore = websiteDataStore ?? .default()
        self.isPrivate = isPrivate
        super.init()
        if !lazy { restore() }
    }

    func restore() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.add(self, name: "montclairScroll")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
              let lastY = window.scrollY;
              let ticking = false;
              addEventListener('scroll', () => {
                if (ticking) return;
                ticking = true;
                requestAnimationFrame(() => {
                  const y = window.scrollY;
                  if (Math.abs(y - lastY) > 8) {
                    window.webkit.messageHandlers.montclairScroll.postMessage(y > lastY ? 'down' : 'up');
                    lastY = y;
                  }
                  ticking = false;
                });
              }, {passive:true});
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsMagnification = true
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        observe(view)
        if let storedURL {
            view.load(URLRequest(url: storedURL))
        } else {
            loadStartPage(in: view)
        }
        lastActive = Date()
    }

    func markActive() {
        lastActive = Date()
        restore()
    }

    func suspendIfIdle(for interval: TimeInterval = 10 * 60) {
        guard Date().timeIntervalSince(lastActive) >= interval else { return }
        if let url = webView?.url, BrowserLibrary.isWebURL(url.absoluteString) { storedURL = url }
        clearObservations()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "montclairScroll")
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    func dispose() {
        clearObservations()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "montclairScroll")
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    func load(_ input: String) {
        restore()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if let candidate = URL(string: trimmed), candidate.scheme != nil {
            url = candidate
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            url = URL(string: "https://\(trimmed)")
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://www.google.com/search?q=\(query)")
        }
        if let url { webView?.load(URLRequest(url: url)) }
    }

    private func loadStartPage(in view: WKWebView) {
        let privateClass = isPrivate ? "private" : ""
        let privacyMark = isPrivate ? #"<div class="privacy">PRIVATE BROWSING</div>"# : ""
        let homepageLogo = isPrivate ? "MontclairHomepagePrivate.png" : "MontclairHomepageNormal.png"
        let html = #"""
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light">
        <style>
        :root{font-family:-apple-system,BlinkMacSystemFont,sans-serif;color:#211d19;background:#f3f0e9}*{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:radial-gradient(circle at 50% 34%,#fffdf8 0,#f4ede1 42%,#e9e1d5 100%)}
        body.private{color:#f5ead5;background:radial-gradient(circle at 50% 32%,#20242c 0,#11151c 48%,#080a0f 100%)}
        main{text-align:center;width:min(620px,80vw)}img{width:96px;height:96px;border-radius:24px;object-fit:contain;box-shadow:0 18px 44px #6d56352b}
        h1{font-family:Didot,"Bodoni 72",Georgia,serif;font-size:38px;font-weight:500;letter-spacing:6px;margin:17px 0 8px;color:#2a2119}.tag{font-size:10px;letter-spacing:3.5px;text-transform:uppercase;color:#927c5b;margin-bottom:30px}
        .private h1{color:#f1dfbd}.private .tag{color:#bca77e}.privacy{display:inline-block;margin:0 0 22px;padding:7px 12px;border:1px solid #d0b37855;border-radius:999px;color:#d8c08d;font-size:9px;font-weight:700;letter-spacing:2.2px}
        form{height:58px;display:flex;align-items:center;padding:0 10px 0 21px;border-radius:21px;background:#ffffffa8;border:1px solid #b89b6852;box-shadow:0 22px 58px #80694724,inset 0 1px #fff}
        .private form{background:#ffffff12;border-color:#d0b37855;box-shadow:0 22px 58px #0008,inset 0 1px #ffffff18}.private input{color:#f7f0e5}.private input::placeholder{color:#aaa49b}
        input{flex:1;border:0;outline:0;background:transparent;color:#211d19;font:500 15px -apple-system,sans-serif}input::placeholder{color:#8c8378}button{border:0;width:40px;height:40px;border-radius:14px;background:linear-gradient(145deg,#d8c08d,#aa8752);color:#211d19;font-size:18px;box-shadow:0 8px 18px #8b6b3838}
        </style></head><body class="\#(privateClass)"><main><img src="\#(homepageLogo)" alt="Montclair"><h1>MONTCLAIR</h1><div class="tag">A brighter way forward</div>\#(privacyMark)<form action="https://www.google.com/search"><input name="q" autofocus autocomplete="off" placeholder="\#(isPrivate ? "Search privately" : "Search the web")"><button aria-label="Search">⌕</button></form></main></body></html>
        """#
        view.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }

    private func observe(_ view: WKWebView) {
        progressObservation = view.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
        urlObservation = view.observe(\.url, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                if let url = view.url,
                   !(url.isFileURL && Bundle.main.resourceURL.map { url.path.hasPrefix($0.path) } == true) {
                    self?.storedURL = url
                }
                self?.onChange?()
            }
        }
        titleObservation = view.observe(\.title, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                self?.title = view.title?.isEmpty == false ? view.title! : "New Tab"
                self?.onChange?()
            }
        }
        loadingObservation = view.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    private func clearObservations() {
        progressObservation = nil
        urlObservation = nil
        titleObservation = nil
        loadingObservation = nil
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { onOpenNewTab?(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        onNavigationResult?(false, error.localizedDescription)
        showLoadError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        onNavigationResult?(false, error.localizedDescription)
        showLoadError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, BrowserLibrary.isWebURL(url.absoluteString) {
            storedURL = url
            onVisit?(webView.title ?? url.host ?? url.absoluteString, url.absoluteString)
        }
        refreshFavicon(in: webView)
        onNavigationResult?(true, webView.url?.absoluteString ?? "unknown")
    }

    private func refreshFavicon(in webView: WKWebView) {
        guard let pageURL = webView.url, !pageURL.isFileURL else { favicon = nil; onChange?(); return }
        let script = "document.querySelector('link[rel~=icon]')?.href || new URL('/favicon.ico', location.href).href"
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let string = value as? String, let url = URL(string: string) else { return }
            let session = self?.isPrivate == true ? Self.privateFaviconSession : URLSession.shared
            session.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                Task { @MainActor in self?.favicon = image; self?.onChange?() }
            }.resume()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let direction = message.body as? String else { return }
        onScrollDirection?(direction == "down")
    }

    private func showLoadError(_ error: Error, in view: WKWebView) {
        let message = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html><meta name="color-scheme" content="dark"><style>
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:#05070b;color:#edf4ff;font-family:-apple-system,sans-serif}
        main{max-width:520px;text-align:center;padding:40px}h1{font-size:26px}p{color:#8491a5;line-height:1.55}.code{margin-top:22px;padding:12px 16px;background:#0d1420;border-radius:12px;font-size:13px;color:#73a7ff}
        </style><main><h1>Page couldn’t be loaded</h1><p>Check your connection or the address, then try again.</p><div class="code">\(message)</div></main>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}
