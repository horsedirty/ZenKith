import Foundation
import KeychainAccess

/// AI 流式对话服务，支持 OpenAI 兼容 API 的 SSE 流式响应，含思考过程（reasoning_content）
/// 使用 URLSessionDataDelegate 实现真正的 token-by-token 流式输出
@MainActor
final class AIService {

    // MARK: - 消息模型

    struct ChatMessage: Identifiable, Codable {
        let id: UUID
        let role: Role
        let content: String
        let reasoningContent: String?
        let timestamp: Date
        let attachments: [Attachment]?
        var searchResults: [SearchResultItem]?

        init(role: Role, content: String, reasoningContent: String? = nil,
             timestamp: Date = Date(), attachments: [Attachment]? = nil,
             searchResults: [SearchResultItem]? = nil) {
            self.id = UUID()
            self.role = role
            self.content = content
            self.reasoningContent = reasoningContent
            self.timestamp = timestamp
            self.attachments = attachments
            self.searchResults = searchResults
        }

        struct SearchResultItem: Identifiable, Codable {
            public var id: Int
            public let title: String
            public let url: String
        }

        enum Role: String, Codable {
            case system, user, assistant
        }

        struct Attachment: Identifiable, Codable {
            let id: UUID
            let fileName: String
            let fileExtension: String
            let data: Data
            let mimeType: String

            var displayName: String { "\(fileName).\(fileExtension)" }

            init(id: UUID = UUID(), fileName: String, fileExtension: String,
                 data: Data, mimeType: String) {
                self.id = id
                self.fileName = fileName
                self.fileExtension = fileExtension
                self.data = data
                self.mimeType = mimeType
            }
        }
    }

    // MARK: - Keychain 管理

    private let keychain = Keychain(service: PersistenceKeys.keychainService).synchronizable(false)
    private var currentTask: URLSessionDataTask?

    func cancelStream() {
        currentTask?.cancel()
        currentTask = nil
    }

    func getAPIKey(forIdentifier identifier: String) -> String? {
        try? keychain.getString(identifier)
    }

    func setAPIKey(_ key: String, forIdentifier identifier: String) {
        try? keychain.set(key, key: identifier)
    }

    func deleteAPIKey(forIdentifier identifier: String) {
        try? keychain.remove(identifier)
    }

    // MARK: - 流式对话（真正 SSE 流式）

    func streamChat(
        messages: [ChatMessage],
        config: AIConfig,
        systemPrompt: String? = nil,
        onReasoningChunk: @escaping @MainActor (String) -> Void,
        onChunk: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (String, String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        let apiKey = getAPIKey(forIdentifier: config.apiKeyIdentifier) ?? ""

        var requestMessages: [[String: String]] = []
        if let prompt = systemPrompt, !prompt.isEmpty {
            requestMessages.append(["role": "system", "content": prompt])
        }
        for msg in messages {
            requestMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": config.effectiveModel,
            "messages": requestMessages,
            "stream": true
        ]

        guard let requestURL = URL(string: config.effectiveEndpoint),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            onError(AIError.invalidURL)
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody
        request.timeoutInterval = 120
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // 使用 delegate 实现真正流式接收
        let delegate = SSEDelegate(
            onReasoningChunk: onReasoningChunk,
            onChunk: onChunk,
            onComplete: onComplete,
            onError: onError
        )

        // delegate 强引用保存在 session 上，session 结束前不会释放
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        currentTask = task
        objc_setAssociatedObject(task, "sseDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        task.resume()
    }
}

// MARK: - SSE 流式代理（非 MainActor，在 URLSession 后台线程接收数据）

private final class SSEDelegate: NSObject, URLSessionDataDelegate {
    let onReasoningChunk: @MainActor (String) -> Void
    let onChunk: @MainActor (String) -> Void
    let onComplete: @MainActor (String, String) -> Void
    let onError: @MainActor (Error) -> Void

    // 流式缓冲
    private var fullContent = ""
    private var fullReasoning = ""
    private var buffer = ""
    private var hasReceivedData = false
    private var isErrorResponse = false
    private var isCompleted = false
    private var httpErrorBody = ""
    private var httpErrorStatusCode = 0

    // 节流：DispatchWorkItem 方式，可靠触发于主队列
    private var pendingReasoningChunk = ""
    private var pendingContentChunk = ""
    private var flushWorkItem: DispatchWorkItem?

    init(
        onReasoningChunk: @escaping @MainActor (String) -> Void,
        onChunk: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (String, String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.onReasoningChunk = onReasoningChunk
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    // MARK: - 增量数据接收（核心：真正流式）
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        processBuffer()
    }

    // MARK: - HTTP 响应处理
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            Task { @MainActor in onError(AIError.invalidResponse) }
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // 非 200：标记错误，收集 body
            isErrorResponse = true
            httpErrorStatusCode = httpResponse.statusCode
            httpErrorBody = ""
            completionHandler(.allow)
            return
        }

        hasReceivedData = false
        isErrorResponse = false
        completionHandler(.allow)
    }

    // MARK: - 完成/错误
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        if let error = error {
            Task { @MainActor in onError(error) }
            session.invalidateAndCancel()
            return
        }

        if isErrorResponse {
            // 非 200 响应：读取原始 buffer（API 返回 JSON 而非 SSE）
            let rawBody = buffer.isEmpty ? httpErrorBody : buffer
            let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let statusMsg: String
            if !body.isEmpty {
                // 尝试从 JSON 中提取 error.message
                if let data = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any],
                   let msg = errorObj["message"] as? String {
                    statusMsg = "HTTP \(httpErrorStatusCode): \(msg)"
                } else {
                    statusMsg = "HTTP \(httpErrorStatusCode): \(String(body.prefix(300)))"
                }
            } else {
                statusMsg = "HTTP \(httpErrorStatusCode): 请求被服务器拒绝"
            }
            Task { @MainActor in onError(AIError.httpError(httpErrorStatusCode, statusMsg)) }
            session.invalidateAndCancel()
            return
        }

        // 冲刷残留数据
        flushPending()

        // 仅在未通过 [DONE] 完成时调用 onComplete（防止重复）
        if !isCompleted {
            if buffer.trimmingCharacters(in: .whitespacesAndNewlines).contains("data:") {
                // 残留 buffer 中还有未处理的 SSE 行，注入 [DONE] 触发处理
                isCompleted = true
                buffer += "\ndata: [DONE]"
                processBuffer()
            } else if hasReceivedData {
                isCompleted = true
                Task { @MainActor in onComplete(fullContent, fullReasoning) }
            } else {
                Task { @MainActor in onError(AIError.decodeError) }
            }
        }

        session.invalidateAndCancel()
    }

    // MARK: - 数据缓冲处理（SSE 协议解析）
    private func processBuffer() {
        // 按行分割，保留最后一行不完整数据
        let lines = buffer.components(separatedBy: "\n")
        // 最后一行可能是未完成行，保留在 buffer 中
        buffer = lines.last ?? ""

        // 处理完整行
        for line in lines.dropLast() {
            processLine(line.trimmingCharacters(in: .whitespaces))
        }
    }

    private func processLine(_ line: String) {
        guard line.hasPrefix("data: ") else { return }
        let jsonStr = String(line.dropFirst(6))

        // 错误响应：收集 body 用于报告
        if isErrorResponse {
            httpErrorBody += line + "\n"
            if jsonStr == "[DONE]" {
                Task { @MainActor in onError(AIError.httpError(0, httpErrorBody)) }
            }
            return
        }

        if jsonStr == "[DONE]" {
            isCompleted = true
            flushPending()
            Task { @MainActor in onComplete(fullContent, fullReasoning) }
            return
        }

        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any] else {
            return
        }

        hasReceivedData = true

        // 推理内容
        if let reasoning = delta["reasoning_content"] as? String {
            fullReasoning += reasoning
            pendingReasoningChunk += reasoning
            scheduleFlush()
        }

        // 正文内容
        if let content = delta["content"] as? String {
            fullContent += content
            pendingContentChunk += content
            scheduleFlush()
        }
    }

    // MARK: - 批量节流刷新（DispatchQueue.main 可靠触发）
    private func scheduleFlush() {
        guard flushWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.flushPending()
        }
        flushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func flushPending() {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        let reasoning = pendingReasoningChunk
        let content = pendingContentChunk
        pendingReasoningChunk = ""
        pendingContentChunk = ""

        if !reasoning.isEmpty {
            let cb = onReasoningChunk
            DispatchQueue.main.async {
                Task { @MainActor in cb(reasoning) }
            }
        }
        if !content.isEmpty {
            let cb = onChunk
            DispatchQueue.main.async {
                Task { @MainActor in cb(content) }
            }
        }
    }
}

// MARK: - 错误类型

enum AIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case decodeError
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 API 地址"
        case .invalidResponse: return "服务器响应无效"
        case .httpError(let code, let body): return "API 错误 (\(code)): \(body.prefix(200))"
        case .decodeError: return "响应解析失败"
        case .noAPIKey: return "未配置 API 密钥"
        }
    }
}
