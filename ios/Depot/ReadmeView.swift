import SwiftUI
import WebKit

struct ReadmeBlock: View {
    let source: String
    let owner: String
    let repo: String
    let branch: String
    @State private var height: CGFloat = 120

    var body: some View {
        ReadmeWeb(
            html: MarkdownHTML.page(markdown: source, owner: owner, repo: repo, branch: branch),
            height: $height
        )
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 80))
    }
}

private struct ReadmeWeb: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let page = WKWebpagePreferences()
        page.allowsContentJavaScript = false
        config.defaultWebpagePreferences = page
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        context.coordinator.observe(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.observe(web)
        if context.coordinator.loaded != html {
            context.coordinator.loaded = html
            web.loadHTMLString(html, baseURL: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.stop(web)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loaded = ""
        private weak var scroll: UIScrollView?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func observe(_ web: WKWebView) {
            guard scroll !== web.scrollView else { return }
            scroll?.removeObserver(self, forKeyPath: "contentSize")
            web.scrollView.addObserver(self, forKeyPath: "contentSize", options: [.new], context: nil)
            scroll = web.scrollView
        }

        func stop(_ web: WKWebView) {
            if scroll === web.scrollView {
                web.scrollView.removeObserver(self, forKeyPath: "contentSize")
                scroll = nil
            }
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard keyPath == "contentSize", let scroll = object as? UIScrollView else { return }
            let next = scroll.contentSize.height
            guard next > 1, abs(height.wrappedValue - next) > 2 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.height.wrappedValue = next
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
