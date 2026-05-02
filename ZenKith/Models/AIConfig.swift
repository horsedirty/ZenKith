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
            return "deepseek-v4-flash"
        case .siliconflow:
            return "deepseek-ai/DeepSeek-V3"
        case .custom:
            return ""
        }
    }

    /// 已知的可用模型列表
    var knownModels: [String] {
        switch self {
        case .deepseek:
            return ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .siliconflow:
            return [
                "deepseek-ai/DeepSeek-V3",
                "deepseek-ai/DeepSeek-R1",
                "deepseek-ai/DeepSeek-V2.5",
                "Pro/deepseek-ai/DeepSeek-V3",
                "Pro/deepseek-ai/DeepSeek-R1",
                "Qwen/Qwen2.5-72B-Instruct",
                "Qwen/Qwen2.5-32B-Instruct",
                "Qwen/Qwen2.5-7B-Instruct",
                "meta-llama/Llama-3.3-70B-Instruct",
                "meta-llama/Llama-3.1-405B-Instruct",
            ]
        case .custom:
            return []
        }
    }
}

/// AI 配置模型
struct AIConfig: Codable {
    var provider: AIProvider = .deepseek
    var customEndpoint: String = ""
    var modelName: String = ""
    var apiKeyIdentifier: String = ""

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
