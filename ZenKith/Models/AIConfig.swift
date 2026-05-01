import Foundation

/// AI 服务商预设
enum AIProvider: String, Codable, CaseIterable {
    case deepseek = "DeepSeek"
    case siliconflow = "硅基流动"
    case custom = "自定义"

    var defaultEndpoint: String {
        switch self {
        case .deepseek:
            return "https://api.deepseek.com/v1/chat/completions"
        case .siliconflow:
            return "https://api.siliconflow.cn/v1/chat/completions"
        case .custom:
            return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek:
            return "deepseek-chat"
        case .siliconflow:
            return "deepseek-ai/DeepSeek-V3"
        case .custom:
            return ""
        }
    }
}

/// 搜索服务商
enum SearchProvider: String, Codable, CaseIterable {
    case serpapi = "SerpAPI"
    case bing = "Bing Search"
}

/// AI 配置模型
struct AIConfig: Codable {
    var provider: AIProvider = .deepseek
    var customEndpoint: String = ""
    var modelName: String = ""
    var apiKeyIdentifier: String = ""
    var searchProvider: SearchProvider = .serpapi
    var searchAPIKeyIdentifier: String = ""

    var effectiveEndpoint: String {
        if case .custom = provider, !customEndpoint.isEmpty {
            return customEndpoint
        }
        return provider.defaultEndpoint
    }

    var effectiveModel: String {
        if !modelName.isEmpty { return modelName }
        return provider.defaultModel
    }
}
