import Foundation

enum MarkdownHTML {
    static func page(markdown: String, owner: String, repo: String, branch: String) -> String {
        let body = render(String(markdown.prefix(80_000)), owner: owner, repo: repo, branch: branch)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        \(css)
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static let css = """
    :root { color-scheme: dark; }
    html, body { margin: 0; padding: 0; background: transparent; }
    body {
      padding: 2px 2px 28px;
      color: #e8e2d6;
      font: 17px/1.65 "Avenir Next", -apple-system, BlinkMacSystemFont, sans-serif;
      letter-spacing: 0.01em;
      overflow-wrap: break-word;
      -webkit-text-size-adjust: 100%;
    }
    h1, h2, h3, h4 { font-weight: 560; letter-spacing: -0.03em; line-height: 1.2; color: #e8e2d6; }
    h1 { font-size: 28px; margin: 4px 0 14px; padding-bottom: 10px; border-bottom: 1px solid #2c2b28; }
    h2 { font-size: 22px; margin: 28px 0 10px; padding-bottom: 6px; border-bottom: 1px solid #2c2b28; }
    h3 { font-size: 18px; margin: 22px 0 8px; }
    h4 { font-size: 16px; margin: 18px 0 6px; color: #a39e94; }
    p { margin: 12px 0; }
    a { color: #e8e2d6; text-underline-offset: 3px; }
    ul, ol { margin: 12px 0; padding-left: 1.25rem; }
    li { margin: 5px 0; }
    li > p { margin: 2px 0; }
    hr { border: 0; border-top: 1px solid #2c2b28; margin: 22px 0; }
    blockquote {
      margin: 14px 0;
      padding: 2px 0 2px 14px;
      border-left: 2px solid #e8e2d6;
      color: #a39e94;
    }
    code {
      font-family: ui-monospace, "SF Mono", Menlo, monospace;
      font-size: 0.86em;
    }
    p code, li code, h1 code, h2 code, h3 code, td code {
      background: #101113;
      border: 1px solid #2c2b28;
      border-radius: 6px;
      padding: 0.08em 0.38em;
    }
    .code {
      margin: 14px 0;
      background: #101113;
      border: 1px solid #2c2b28;
      border-radius: 14px;
      overflow: hidden;
    }
    .code .lang {
      padding: 7px 12px 0;
      color: #6f6a62;
      font: 11px/1.2 ui-monospace, "SF Mono", Menlo, monospace;
      letter-spacing: 0.04em;
      text-transform: lowercase;
    }
    pre { margin: 0; padding: 12px 14px 14px; overflow-x: auto; -webkit-overflow-scrolling: touch; }
    pre code { font-size: 13px; line-height: 1.55; color: #e8e2d6; }
    img { max-width: 100%; height: auto; }
    p > img:only-child, p > a:only-child > img {
      display: block;
      margin: 16px auto;
      border-radius: 12px;
      max-height: 420px;
      object-fit: contain;
    }
    p > img, a > img {
      display: inline-block;
      vertical-align: middle;
      margin: 3px 6px 3px 0;
      border-radius: 4px;
    }
    table { width: 100%; border-collapse: collapse; margin: 14px 0; font-size: 15px; display: block; overflow-x: auto; }
    th, td { border-bottom: 1px solid #2c2b28; padding: 8px 10px; text-align: left; vertical-align: top; }
    th { color: #a39e94; font-weight: 560; }
    [align="center"] { text-align: center; }
    [align="right"] { text-align: right; }
    kbd {
      font-family: ui-monospace, Menlo, monospace;
      font-size: 0.84em;
      border: 1px solid #2c2b28;
      border-bottom-width: 2px;
      border-radius: 6px;
      padding: 0.05em 0.4em;
      background: #16171a;
    }
    input[type="checkbox"] { accent-color: #e8e2d6; margin-right: 6px; }
    """

    static func render(_ markdown: String, owner: String, repo: String, branch: String) -> String {
        let ctx = Ctx(owner: owner, repo: repo, branch: branch.isEmpty ? "main" : branch)
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var i = 0
        var html = ""
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("<!--") {
                while i < lines.count && !lines[i].contains("-->") { i += 1 }
                if i < lines.count { i += 1 }
                continue
            }
            if isFence(lines[i]) {
                let open = lines[i].trimmingCharacters(in: .whitespaces)
                let lang = String(open.dropFirst(3)).trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
                i += 1
                var code = ""
                while i < lines.count && !isFence(lines[i]) {
                    if !code.isEmpty { code += "\n" }
                    code += lines[i]
                    i += 1
                }
                if i < lines.count { i += 1 }
                html += codeBlock(code, lang: lang)
                continue
            }
            if isRule(lines[i]) {
                html += "<hr>"
                i += 1
                continue
            }
            if let heading = heading(lines[i]) {
                html += "<h\(heading.0)>\(inline(heading.1, ctx: ctx))</h\(heading.0)>"
                i += 1
                continue
            }
            if i + 1 < lines.count && isTableRow(lines[i]) && isTableRule(lines[i + 1]) {
                let header = cells(lines[i])
                let align = cells(lines[i + 1]).map(columnAlign)
                i += 2
                var rows: [[String]] = []
                while i < lines.count && isTableRow(lines[i]) && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[i]))
                    i += 1
                }
                html += table(header: header, align: align, rows: rows, ctx: ctx)
                continue
            }
            if isQuote(lines[i]) {
                var chunk: [String] = []
                while i < lines.count && (isQuote(lines[i]) || (chunk.isEmpty == false && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !isBlockStart(lines[i]))) {
                    chunk.append(unquote(lines[i]))
                    i += 1
                }
                html += "<blockquote>\(render(chunk.joined(separator: "\n"), owner: owner, repo: repo, branch: branch))</blockquote>"
                continue
            }
            if listMarker(lines[i]) != nil {
                let ordered = listMarker(lines[i])?.ordered == true
                html += ordered ? "<ol>" : "<ul>"
                while i < lines.count, let item = listMarker(lines[i]) {
                    var text = item.text
                    i += 1
                    while i < lines.count {
                        let next = lines[i]
                        if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                        if listMarker(next) != nil || isBlockStart(next) { break }
                        text += " " + next.trimmingCharacters(in: .whitespaces)
                        i += 1
                    }
                    if let box = item.checked {
                        let mark = box ? " checked" : ""
                        html += "<li><input type=\"checkbox\" disabled\(mark)> \(inline(text, ctx: ctx))</li>"
                    } else {
                        html += "<li>\(inline(text, ctx: ctx))</li>"
                    }
                }
                html += ordered ? "</ol>" : "</ul>"
                continue
            }
            if htmlTagName(lines[i]) != nil {
                let name = htmlTagName(lines[i]) ?? ""
                var chunk = [lines[i]]
                i += 1
                if !voidTags.contains(name) {
                    while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        chunk.append(lines[i])
                        let joined = chunk.joined(separator: "\n").lowercased()
                        i += 1
                        if joined.contains("</\(name)") { break }
                    }
                }
                html += sanitize(rewrite(chunk.joined(separator: "\n"), ctx: ctx))
                continue
            }
            var para = [lines[i]]
            i += 1
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !isBlockStart(lines[i]) && listMarker(lines[i]) == nil {
                para.append(lines[i])
                i += 1
            }
            html += "<p>\(inline(para.joined(separator: " "), ctx: ctx))</p>"
        }
        return html
    }

    private struct Ctx {
        let owner: String
        let repo: String
        let branch: String
    }

    private struct ListItem {
        let ordered: Bool
        let checked: Bool?
        let text: String
    }

    private static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func isRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        let chars = Set(t)
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }

    private static func isQuote(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix(">")
    }

    private static func unquote(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix(">") { t.removeFirst() }
        if t.hasPrefix(" ") { t.removeFirst() }
        return t
    }

    private static func heading(_ line: String) -> (Int, String)? {
        var i = line.startIndex
        var spaces = 0
        while i < line.endIndex && line[i] == " " && spaces < 3 {
            spaces += 1
            i = line.index(after: i)
        }
        var level = 0
        while i < line.endIndex && line[i] == "#" && level < 6 {
            level += 1
            i = line.index(after: i)
        }
        guard level > 0, i < line.endIndex, line[i] == " " else { return nil }
        i = line.index(after: i)
        var text = String(line[i...]).trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isTableRule(_ line: String) -> Bool {
        let parts = cells(line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { cell in
            let t = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return t.count >= 3 && t.allSatisfy { $0 == "-" }
        }
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func columnAlign(_ cell: String) -> String {
        let left = cell.hasPrefix(":")
        let right = cell.hasSuffix(":")
        if left && right { return "center" }
        if right { return "right" }
        return "left"
    }

    private static func listMarker(_ line: String) -> ListItem? {
        let pattern = #"^(\s*)([-*+]|\d+\.)\s+(.*)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return nil }
        let ns = line as NSString
        let marker = ns.substring(with: match.range(at: 2))
        var text = ns.substring(with: match.range(at: 3))
        var checked: Bool?
        if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            checked = text.hasPrefix("[x] ") || text.hasPrefix("[X] ")
            text = String(text.dropFirst(4))
        }
        return ListItem(ordered: marker.contains("."), checked: checked, text: text)
    }

    private static func isBlockStart(_ line: String) -> Bool {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if isFence(line) || isRule(line) || isQuote(line) || heading(line) != nil { return true }
        if htmlTagName(line) != nil { return true }
        return false
    }

    private static func htmlTagName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("<"), t.count > 2 else { return nil }
        var i = t.index(after: t.startIndex)
        if t[i] == "/" { i = t.index(after: i) }
        var name = ""
        while i < t.endIndex {
            let c = t[i]
            if c.isLetter || c.isNumber || c == "-" || c == ":" {
                name.append(c)
                i = t.index(after: i)
            } else {
                break
            }
        }
        guard !name.isEmpty else { return nil }
        let next = i < t.endIndex ? t[i] : ">"
        guard next == ">" || next == " " || next == "/" || next == "\n" else { return nil }
        return name.lowercased()
    }

    private static func codeBlock(_ code: String, lang: String) -> String {
        let label = lang.isEmpty ? "" : "<div class=\"lang\">\(escape(lang))</div>"
        return "<div class=\"code\">\(label)<pre><code>\(escape(code))</code></pre></div>"
    }

    private static func table(header: [String], align: [String], rows: [[String]], ctx: Ctx) -> String {
        func cell(_ text: String, index: Int, head: Bool) -> String {
            let alignValue = index < align.count ? align[index] : "left"
            let tag = head ? "th" : "td"
            return "<\(tag) align=\"\(alignValue)\">\(inline(text, ctx: ctx))</\(tag)>"
        }
        var html = "<table><thead><tr>"
        for (index, item) in header.enumerated() {
            html += cell(item, index: index, head: true)
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            html += "<tr>"
            for (index, item) in row.enumerated() {
                html += cell(item, index: index, head: false)
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }

    private static func inline(_ raw: String, ctx: Ctx) -> String {
        var codes: [String] = []
        var text = pull(raw, pattern: #"`([^`]+)`"#) { code in
            codes.append("<code>\(escape(code))</code>")
            return "\u{0}C\(codes.count - 1)\u{0}"
        }
        text = escape(text)
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "<br>", options: .regularExpression)
        text = replaceMatches(text, pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^&]*")?\)"#) { _, groups in
            let alt = groups[0]
            let url = absURL(unescape(groups[1]), ctx: ctx, image: true)
            return "<img alt=\"\(alt)\" src=\"\(escape(url))\">"
        }
        text = replaceMatches(text, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) { _, groups in
            let url = absURL(unescape(groups[1]), ctx: ctx, image: false)
            return "<a href=\"\(escape(url))\">\(groups[0])</a>"
        }
        text = pull(text, pattern: #"~~([^~]+)~~"#) { inner in "<del>\(inner)</del>" }
        text = replaceMatches(text, pattern: #"\*\*([^*]+)\*\*|__([^_]+)__"#) { _, groups in
            let inner = groups.first(where: { !$0.isEmpty }) ?? ""
            return "<strong>\(inner)</strong>"
        }
        text = replaceMatches(text, pattern: #"(^|[^\w*])\*([^*\n]+)\*(?!\*)"#) { _, groups in
            return "\(groups[0])<em>\(groups.count > 1 ? groups[1] : "")</em>"
        }
        text = pull(text, pattern: #"(?<![="'>])(https?://[^\s<&]+)"#) { url in
            let clean = unescape(url).trimmingCharacters(in: CharacterSet(charactersIn: ".,);"))
            return "<a href=\"\(escape(clean))\">\(escape(clean))</a>"
        }
        for (index, code) in codes.enumerated() {
            text = text.replacingOccurrences(of: "\u{0}C\(index)\u{0}", with: code)
        }
        return text
    }

    private static func pull(_ source: String, pattern: String, _ transform: (String) -> String) -> String {
        replaceMatches(source, pattern: pattern) { full, groups in
            transform(groups.first ?? full)
        }
    }

    private static func replaceMatches(
        _ source: String,
        pattern: String,
        _ transform: (String, [String]) -> String
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return source }
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        var out = ""
        var last = 0
        re.enumerateMatches(in: source, range: full) { match, _, _ in
            guard let match else { return }
            let range = match.range
            if range.location < last { return }
            if range.location > last {
                out += ns.substring(with: NSRange(location: last, length: range.location - last))
            }
            var groups: [String] = []
            if match.numberOfRanges > 1 {
                for index in 1..<match.numberOfRanges {
                    let part = match.range(at: index)
                    if part.location != NSNotFound {
                        groups.append(ns.substring(with: part))
                    } else {
                        groups.append("")
                    }
                }
            }
            out += transform(ns.substring(with: range), groups)
            last = range.location + range.length
        }
        if last < ns.length {
            out += ns.substring(from: last)
        }
        return out
    }

    private static func absURL(_ raw: String, ctx: Ctx, image: Bool) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") || value.hasPrefix("mailto:") { return value }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        let path = value.replacingOccurrences(of: "./", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if image {
            return "https://raw.githubusercontent.com/\(ctx.owner)/\(ctx.repo)/\(ctx.branch)/\(path)"
        }
        return "https://github.com/\(ctx.owner)/\(ctx.repo)/blob/\(ctx.branch)/\(path)"
    }

    private static func rewrite(_ html: String, ctx: Ctx) -> String {
        replaceMatches(html, pattern: #"(src|href)\s*=\s*(["'])(.*?)\2"#) { _, groups in
            let attr = groups[0]
            let quote = groups[1]
            let url = absURL(unescape(groups[2]), ctx: ctx, image: attr == "src")
            return "\(attr)=\(quote)\(escape(url))\(quote)"
        }
    }

    private static func sanitize(_ html: String) -> String {
        var s = html
        let patterns = [
            "(?is)<script\\b[^>]*>.*?</script>",
            "(?is)<style\\b[^>]*>.*?</style>",
            "(?is)<iframe\\b[^>]*>.*?</iframe>",
            "(?is)<object\\b[^>]*>.*?</object>",
            "(?is)<embed\\b[^>]*>.*?</embed>",
            "(?i)\\son\\w+\\s*=\\s*\"[^\"]*\"",
            "(?i)\\son\\w+\\s*=\\s*'[^']*'",
            "(?i)javascript:",
        ]
        for pattern in patterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return s
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&")
            .replacingOccurrences(of: "<", with: "<")
            .replacingOccurrences(of: ">", with: ">")
            .replacingOccurrences(of: "\"", with: """)
    }

    private static func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: """, with: "\"")
            .replacingOccurrences(of: ">", with: ">")
            .replacingOccurrences(of: "<", with: "<")
            .replacingOccurrences(of: "&", with: "&")
    }
}
