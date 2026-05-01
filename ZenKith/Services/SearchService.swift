import Foundation

/// 联网搜索服务，支持 SerpAPI 和 Bing Search
@MainActor
final class SearchService {

    /// 搜索结果
    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let snippet: String
        let url: String
    }

    // MARK: - 搜索接口

    /// 执行联网搜索，获取 top 3 结果摘要
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - config: AI 配置（含搜索提供商和 API Key 标识）
    ///   - keyProvider: Keychain Key 读取闭包
    /// - Returns: 搜索摘要文本，可直接作为 AI 对话上下文
    func search(
        query: String,
        config: AIConfig,
        apiKey: String?
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw SearchError.noAPIKey
        }

        switch config.searchProvider {
        case .serpapi:
            let results = try await searchSerpAPI(query: query, apiKey: key)
            return formatResults(results, query: query)
        case .bing:
            let results = try await searchBing(query: query, apiKey: key)
            return formatResults(results, query: query)
        }
    }

    // MARK: - SerpAPI

    private func searchSerpAPI(query: String, apiKey: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://serpapi.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "engine", value: "google"),
            URLQueryItem(name: "num", value: "3"),
            URLQueryItem(name: "hl", value: "zh-CN")
        ]

        guard let url = components.url else {
            throw SearchError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SearchError.httpError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let organic = json?["organic_results"] as? [[String: Any]] ?? []

        return organic.prefix(3).compactMap { item in
            guard let title = item["title"] as? String,
                  let snippet = item["snippet"] as? String,
                  let link = item["link"] as? String else {
                return nil
            }
            return SearchResult(title: title, snippet: snippet, url: link)
        }
    }

    // MARK: - Bing Search

    private func searchBing(query: String, apiKey: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://api.bing.microsoft.com/v7.0/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "3"),
            URLQueryItem(name: "mkt", value: "zh-CN")
        ]

        guard let url = components.url else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SearchError.httpError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pages = json?["webPages"] as? [String: Any]
        let values = pages?["value"] as? [[String: Any]] ?? []

        return values.prefix(3).compactMap { item in
            guard let title = item["name"] as? String,
                  let snippet = item["snippet"] as? String,
                  let link = item["url"] as? String else {
                return nil
            }
            return SearchResult(title: title, snippet: snippet, url: link)
        }
    }

    // MARK: - 格式化

    /// 将搜索结果格式化为可嵌入 AI 对话的上下文文本
    private func formatResults(_ results: [SearchResult], query: String) -> String {
        guard !results.isEmpty else {
            return "搜索结果：未找到与「\(query)」相关的内容。"
        }

        var output = "以下是「\(query)」的搜索结果摘要：\n\n"
        for (index, result) in results.enumerated() {
            output += "\(index + 1). **\(result.title)**\n"
            output += "   \(result.snippet)\n"
            output += "   来源：\(result.url)\n\n"
        }
        output += "请基于以上搜索结果回答用户问题，并在回答中引用相关来源。"
        return output
    }
}

// MARK: - 搜索错误

enum SearchError: LocalizedError {
    case noAPIKey
    case invalidURL
    case httpError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "未配置搜索 API 密钥"
        case .invalidURL:
            return "无效的搜索 API 地址"
        case .httpError:
            return "搜索服务请求失败"
        }
    }
}
