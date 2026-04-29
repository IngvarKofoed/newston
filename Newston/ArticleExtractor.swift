import Foundation
import WebKit

@MainActor
protocol ArticleExtracting: AnyObject {
    func extractBody(from url: URL) async throws -> String
}

enum ArticleExtractionError: LocalizedError {
    case alreadyExtracting
    case loadFailed(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .alreadyExtracting: return "Another article is already being extracted."
        case .loadFailed(let message): return "Could not load article: \(message)"
        case .noContent: return "No article content found on the page."
        }
    }
}

@MainActor
final class ArticleExtractor: NSObject, ArticleExtracting {
    private var webView: WKWebView?
    private var pendingContinuation: CheckedContinuation<String, Error>?

    private static let readabilityScript: String = {
        guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return source
    }()

    // Readability mutates the document it's given, so clone first. We use
    // innerText (not Readability's textContent) on the parsed HTML so block
    // boundaries become real newlines — textContent runs paragraphs together.
    // Falls back to the raw page if Readability can't parse it.
    private static let extractionScript = """
    (function() {
        function readableInnerText(html) {
            var host = document.createElement('div');
            host.style.cssText = 'position:absolute;left:-99999px;top:0;width:1024px;';
            host.innerHTML = html;
            document.body.appendChild(host);
            var text = host.innerText || host.textContent || '';
            document.body.removeChild(host);
            return text;
        }
        try {
            var clone = document.cloneNode(true);
            var article = new Readability(clone).parse();
            if (article && article.content) {
                var text = readableInnerText(article.content);
                if (text && text.trim().length > 0) { return text; }
            }
        } catch (e) {}
        var el = document.querySelector('article')
              || document.querySelector('main')
              || document.body;
        if (!el) { return ''; }
        return el.innerText || el.textContent || '';
    })()
    """

    func extractBody(from url: URL) async throws -> String {
        if pendingContinuation != nil {
            throw ArticleExtractionError.alreadyExtracting
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            wv.load(URLRequest(url: url))
            self.webView = wv
        }
    }

    private func completeWithText(_ text: String) {
        let cont = pendingContinuation
        pendingContinuation = nil
        webView = nil
        cont?.resume(returning: text)
    }

    private func completeWithError(_ error: Error) {
        let cont = pendingContinuation
        pendingContinuation = nil
        webView = nil
        cont?.resume(throwing: error)
    }
}

extension ArticleExtractor: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                if !Self.readabilityScript.isEmpty {
                    _ = try await webView.evaluateJavaScript(Self.readabilityScript)
                }
                let result = try await webView.evaluateJavaScript(Self.extractionScript)
                let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty {
                    completeWithError(ArticleExtractionError.noContent)
                } else {
                    completeWithText(text)
                }
            } catch {
                completeWithError(ArticleExtractionError.loadFailed(error.localizedDescription))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            completeWithError(ArticleExtractionError.loadFailed(error.localizedDescription))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            completeWithError(ArticleExtractionError.loadFailed(error.localizedDescription))
        }
    }
}
