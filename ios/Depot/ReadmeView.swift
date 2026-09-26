import SwiftUI
import Translation
import WebKit

struct TranslatedReadme: View {
    let source: String
    let owner: String
    let repo: String
    let branch: String

    private var guess: ReadmeLanguage.Guess { ReadmeLanguage.guess(source) }

    var body: some View {
        if #available(iOS 18.0, *), !guess.english {
            ReadmeTranslation(source: source, owner: owner, repo: repo, branch: branch, guess: guess)
        } else {
            ReadmeBlock(source: source, owner: owner, repo: repo, branch: branch)
        }
    }
}

@available(iOS 18.0, *)
private struct ReadmeTranslation: View {
    let source: String
    let owner: String
    let repo: String
    let branch: String
    let guess: ReadmeLanguage.Guess

    @State private var english: String?
    @State private var showOriginal = false
    @State private var failed = false
    @State private var partial = false
    @State private var started = false

    private var displayed: String {
        if let english, !showOriginal, !failed { return english }
        return source
    }

    private var status: String {
        if failed {
            return "This README is in \(guess.language). Translation isn't available right now."
        }
        if english == nil {
            return "Translating from \(guess.language)…"
        }
        if showOriginal {
            return "This README is in \(guess.language)."
        }
        var line = "Translated from \(guess.language)"
        if partial {
            line += ". Only the beginning of this long README was translated."
        }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(status)
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(DepotColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if english != nil {
                    Button(showOriginal ? "Read in English" : "Show original") {
                        showOriginal.toggle()
                    }
                    .font(.custom("Avenir Next", size: 13).weight(.medium))
                    .foregroundStyle(DepotColor.fg)
                    .buttonStyle(.plain)
                }
            }
            ReadmeBlock(source: displayed, owner: owner, repo: repo, branch: branch)
        }
        .translationTask(source: guess.apple, target: Locale.Language(identifier: "en")) { session in
            guard !started else { return }
            started = true
            await translate(session)
        }
    }

    private func translate(_ session: TranslationSession) async {
        let limit = 12_000
        let clipped = source.count > limit
        let body = clipped ? String(source.prefix(limit)) : source
        var out = ""
        do {
            for segment in ReadmeLanguage.segments(body) {
                switch segment {
                case .raw(let text):
                    out += text
                case .prose(let text):
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        out += text
                        continue
                    }
                    for chunk in ReadmeLanguage.chunks(text, limit: 900) {
                        let response = try await session.translate(chunk)
                        out += response.targetText
                    }
                }
            }
            if clipped {
                out += String(source.dropFirst(limit))
            }
            english = out
            partial = clipped
        } catch {
            failed = true
        }
    }
}

enum ReadmeLanguage {
    struct Guess {
        var english: Bool
        var language: String
        var apple: Locale.Language?
    }

    enum Segment {
        case raw(String)
        case prose(String)
    }

    private static let latin: [(String, String, [String])] = [
        ("Spanish", "es", ["también", "está", "este", "esta", "para", "porque", "como", "más", "qué", "cómo", "una", "los", "las", "del", "por", "proyecto", "instalación", "repositorio", "puedes", "tiene", "sobre", "cuando"]),
        ("French", "fr", ["avec", "pour", "dans", "une", "les", "des", "est", "pas", "vous", "cette", "projet", "sont", "nous", "aux", "être", "sur", "dépôt"]),
        ("German", "de", ["und", "nicht", "eine", "für", "mit", "auf", "das", "der", "die", "ist", "ein", "von", "werden", "oder", "auch", "sich", "projekt", "dokumentation"]),
        ("Portuguese", "pt", ["não", "para", "com", "uma", "você", "como", "mais", "dos", "das", "pelo", "pela", "também", "projeto", "instalação", "repositório", "quando"]),
        ("Italian", "it", ["che", "non", "per", "una", "con", "del", "della", "questo", "questa", "sono", "come", "anche", "progetto", "installazione", "dalla", "degli", "più"]),
        ("Dutch", "nl", ["het", "een", "van", "niet", "voor", "met", "zijn", "ook", "naar", "deze", "wordt"]),
    ]

    private static let englishWords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "from", "your", "you", "are", "not", "have",
        "can", "will", "about", "into", "using", "which", "when", "was", "install", "project",
    ]

    static func guess(_ markdown: String) -> Guess {
        let text = prose(markdown)
        if scriptCount(text, in: 0x3040...0x30FF) >= 6 { return script("Japanese", "ja") }
        if scriptCount(text, in: 0xAC00...0xD7AF) >= 6 { return script("Korean", "ko") }
        if scriptCount(text, in: 0x4E00...0x9FFF) >= 8 { return script("Chinese", "zh") }
        if scriptCount(text, in: 0x0600...0x06FF) >= 8 { return script("Arabic", "ar") }
        if scriptCount(text, in: 0x0590...0x05FF) >= 8 { return script("Hebrew", "he") }
        if scriptCount(text, in: 0x0400...0x04FF) >= 8 { return script("Russian", "ru") }
        if scriptCount(text, in: 0x0E00...0x0E7F) >= 8 { return script("Thai", "th") }
        if scriptCount(text, in: 0x0900...0x097F) >= 8 { return script("Hindi", "hi") }
        if scriptCount(text, in: 0x0370...0x03FF) >= 8 { return script("Greek", "el") }

        let words = words(in: text)
        if words.count < 8 { return Guess(english: true, language: "English", apple: nil) }
        let english = score(words, vocab: englishWords)
        var bestName = "English"
        var bestCode = "en"
        var best = 0
        for row in latin {
            let n = score(words, vocab: Set(row.2))
            if n > best {
                best = n
                bestName = row.0
                bestCode = row.1
            }
        }
        if (best >= 4 && best > english) || (best >= 3 && english == 0) {
            return Guess(english: false, language: bestName, apple: Locale.Language(identifier: bestCode))
        }
        return Guess(english: true, language: "English", apple: nil)
    }

    static func segments(_ markdown: String) -> [Segment] {
        var result: [Segment] = []
        var rest = markdown[...]
        var prose = ""
        func flush() {
            if !prose.isEmpty {
                result.append(.prose(prose))
                prose = ""
            }
        }
        while !rest.isEmpty {
            if rest.hasPrefix("```") {
                flush()
                let search = rest.index(rest.startIndex, offsetBy: 3)
                if let range = rest[search...].range(of: "```") {
                    result.append(.raw(String(rest[..<range.upperBound])))
                    rest = rest[range.upperBound...]
                } else {
                    result.append(.raw(String(rest)))
                    break
                }
                continue
            }
            if rest.hasPrefix("`"), let end = rest.dropFirst().firstIndex(of: "`"), !rest[rest.index(after: rest.startIndex)..<end].contains("\n") {
                flush()
                let close = rest.index(after: end)
                result.append(.raw(String(rest[..<close])))
                rest = rest[close...]
                continue
            }
            prose.append(rest.removeFirst())
        }
        flush()
        return result
    }

    static func chunks(_ text: String, limit: Int) -> [String] {
        if text.count <= limit { return [text] }
        var parts: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let next = current.isEmpty ? String(line) : current + "\n" + line
            if next.count > limit, !current.isEmpty {
                parts.append(current)
                current = String(line)
            } else {
                current = next
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    private static func script(_ name: String, _ code: String) -> Guess {
        Guess(english: false, language: name, apple: Locale.Language(identifier: code))
    }

    private static func prose(_ markdown: String) -> String {
        var text = markdown
        let patterns = [
            "```[\\s\\S]*?```",
            "`[^`\\n]+`",
            "!\\[[^\\]]*\\]\\([^)]*\\)",
            "\\[[^\\]]*\\]\\([^)]*\\)",
            "https?://\\S+",
            "<!--[\\s\\S]*?-->",
            "<[^>]+>",
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text
    }

    private static func scriptCount(_ text: String, in range: ClosedRange<UInt32>) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            range.contains(scalar.value) ? count + 1 : count
        }
    }

    private static func words(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[a-zA-Zà-ÿ']{2,}") else { return [] }
        let ns = text.lowercased() as NSString
        return regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    private static func score(_ words: [String], vocab: Set<String>) -> Int {
        var seen: [String: Int] = [:]
        var n = 0
        for word in words where vocab.contains(word) {
            let used = seen[word] ?? 0
            if used >= 3 { continue }
            seen[word] = used + 1
            n += 1
        }
        return n
    }
}

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
