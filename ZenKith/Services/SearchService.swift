import Foundation

/// 免费联网搜索服务：DuckDuckGo Instant Answer API + HTML 回退，无需 API Key
@MainActor
final class SearchService {

    struct SearchResult: Identifiable {
        public var id: String { url.absoluteString }
        public let title: String
        public let snippet: String
        public let url: URL
    }

    // MARK: - 搜索接口

    func search(query: String) async throws -> (text: String, results: [SearchResult]) {
        let results = await performSearch(query: query)
        let text = formatResults(results, query: query)
        return (text, results)
    }

    // MARK: - 两阶段搜索

    private func performSearch(query: String) async -> [SearchResult] {
        let apiResults = await searchInstantAnswer(query: query)
        if !apiResults.isEmpty { return apiResults }
        return await searchHTML(query: query)
    }

    // MARK: - DuckDuckGo Instant Answer API

    private func searchInstantAnswer(query: String) async -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&no_redirect=1&t=ZenKith") else {
            return []
        }

        guard let (data, _) = try? await directSession.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [SearchResult] = []

        // 主摘要
        if let abstract = json["Abstract"] as? String, !abstract.isEmpty,
           let absURLStr = json["AbstractURL"] as? String,
           let absURL = URL(string: absURLStr) {
            let title = (json["Heading"] as? String) ?? query
            results.append(SearchResult(title: title, snippet: String(abstract.prefix(400)), url: absURL))
        }

        // 相关话题
        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            for topic in topics.prefix(5) {
                if let text = topic["Text"] as? String, !text.isEmpty,
                   let firstURLStr = topic["FirstURL"] as? String,
                   let firstURL = URL(string: firstURLStr) {
                    let parts = text.components(separatedBy: " - ")
                    let title = parts.first ?? "相关结果"
                    let snippet = parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : text
                    results.append(SearchResult(title: title, snippet: String(snippet.prefix(400)), url: firstURL))
                }
            }
        }

        return Array(results.prefix(6))
    }

    // MARK: - DuckDuckGo HTML 回退

    private func searchHTML(query: String) async -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        guard let (data, _) = try? await directSession.data(from: url),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }

        var results: [SearchResult] = []

        // 正则提取标题、链接和摘要
        let linkPattern = #"class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)</a>"#
        let snippetPattern = #"class="result__snippet"[^>]*>([^<]*)</"#

        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern) else {
            return []
        }

        let links = linkRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        let snippets = snippetRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for i in 0..<min(links.count, snippets.count, 6) {
            let linkMatch = links[i]
            let snippetMatch = snippets[i]

            guard let linkRange = Range(linkMatch.range(at: 1), in: html),
                  let titleRange = Range(linkMatch.range(at: 2), in: html),
                  let snippetRange = Range(snippetMatch.range(at: 1), in: html),
                  let url = URL(string: String(html[linkRange]).unescapedHTML()) else {
                continue
            }

            let title = String(html[titleRange]).unescapedHTML().trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = String(html[snippetRange]).unescapedHTML().trimmingCharacters(in: .whitespacesAndNewlines)

            if !title.isEmpty || !snippet.isEmpty {
                results.append(SearchResult(title: title, snippet: String(snippet.prefix(400)), url: url))
            }
        }

        return results
    }

    // MARK: - 格式化

    private func formatResults(_ results: [SearchResult], query: String) -> String {
        guard !results.isEmpty else {
            return "搜索结果：未找到与「\(query)」相关的内容。"
        }

        var output = "以下是「\(query)」的搜索结果摘要：\n\n"
        for (index, result) in results.enumerated() {
            let snippet = result.snippet.count > 300
                ? String(result.snippet.prefix(300)) + "…"
                : result.snippet
            output += "\(index + 1). **\(result.title)**\n"
            output += "   \(snippet)\n"
            output += "   来源：\(result.url.absoluteString)\n\n"
        }
        output += "请基于以上搜索结果简要回答用户问题。"
        return output
    }

    // MARK: - URLSession (直连，不走代理)

    private let directSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
}

// MARK: - HTML 实体解码

private extension String {
    func unescapedHTML() -> String {
        self.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }
}
