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

    private static let extractionScript = """
    (function() {
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
