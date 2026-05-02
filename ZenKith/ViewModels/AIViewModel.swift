import Foundation
import Combine
import SwiftUI

/// AI 对话面板 ViewModel，管理聊天历史、网络搜索、消息流转、思考过程
@MainActor
final class AIViewModel: ObservableObject {

    // MARK: - 发布属性

    @Published var messages: [AIService.ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var streamingText: String = ""
    @Published var streamingReasoning: String = ""
    @Published var includeNoteContent: Bool = false
    @Published var enableWebSearch: Bool = false
    @Published var config: AIConfig { didSet { saveConfig() } }
    @Published var showConfigPanel: Bool = false

    // 会话管理
    @Published var sessions: [ChatSession] = []
    @Published var selectedSessionId: UUID? {
        didSet { switchToSession(selectedSessionId) }
    }

    // 文件附件
    @Published var pendingAttachments: [AIService.ChatMessage.Attachment] = []

    // 最近一次搜索的结果引用
    private var lastSearchResults: [AIService.ChatMessage.SearchResultItem] = []

    // MARK: - 依赖

    private let aiService = AIService()
    private let searchService = SearchService()
    private var currentNoteProvider: (() -> (content: String, title: String)?)?

    private static let sessionsFileURL: URL = {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = supportDir.appendingPathComponent("ZenKith")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chatSessions.json")
    }()

    init() {
        self.config = AIViewModel.loadConfig()
        loadSessions()
    }

    // MARK: - 会话管理

    func createNewSession() {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        selectedSessionId = session.id
        saveSessions()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
        }
        saveSessions()
    }

    func switchToSession(_ id: UUID?) {
        guard let id = id, let session = sessions.first(where: { $0.id == id }) else {
            messages = []
            return
        }
        messages = session.messages
    }

    func renameSession(id: UUID, title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = title
        saveSessions()
    }

    private func saveCurrentSession() {
        guard let sessionId = selectedSessionId,
              let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].messages = messages
        sessions[idx].lastModified = Date()
        // 自动标题：取第一条 user 消息的前 30 字
        if sessions[idx].title == "新对话",
           let firstUserMsg = messages.first(where: { $0.role == .user })?.content {
            let title = String(firstUserMsg.prefix(30)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { sessions[idx].title = title }
        }
        saveSessions()
    }

    private func saveSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: Self.sessionsFileURL, options: .atomic)
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: Self.sessionsFileURL),
              let loaded = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        sessions = loaded
    }

    func setNoteContentProvider(_ provider: @escaping () -> (content: String, title: String)?) {
        currentNoteProvider = provider
    }

    // MARK: - 配置持久化

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: PersistenceKeys.aiConfig)
        }
    }

    // MARK: - Keychain 操作

    func getAPIKey() -> String {
        aiService.getAPIKey(forIdentifier: config.apiKeyIdentifier) ?? ""
    }

    func setAPIKey(_ key: String) {
        aiService.setAPIKey(key, forIdentifier: config.apiKeyIdentifier)
    }

    // MARK: - 发送消息

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty, !isStreaming else { return }

        let hasAttachments = !pendingAttachments.isEmpty
        var finalInput = trimmed

        // 构建发送给 AI 的完整内容（含附件）
        var displayContent = trimmed
        if hasAttachments {
            var attachmentContext = ""
            for att in pendingAttachments {
                if att.mimeType.hasPrefix("image/") {
                    let base64 = att.data.base64EncodedString()
                    attachmentContext += "\n[文件: \(att.displayName) (图片, base64编码)]"
                    // 图片用 base64 加入消息
                    if !finalInput.isEmpty { finalInput += "\n" }
                } else {
                    if let text = String(data: att.data, encoding: .utf8) {
                        attachmentContext += "\n[文件: \(att.displayName)]\n```\n\(text)\n```"
                    } else {
                        attachmentContext += "\n[文件: \(att.displayName), 大小: \(att.data.count) 字节]"
                    }
                }
            }
            if !finalInput.isEmpty {
                finalInput += attachmentContext
            } else {
                finalInput = "请分析以下文件内容:" + attachmentContext
            }
            displayContent = trimmed.isEmpty ? "[已发送 \(pendingAttachments.count) 个文件]" : trimmed
        }

        if includeNoteContent, let note = currentNoteProvider?() {
            finalInput = "以下是我当前笔记「\(note.title)」的完整内容：\n\n```markdown\n\(note.content)\n```\n\n我的问题是：\(finalInput)"
        }

        // 创建新会话
        if selectedSessionId == nil { createNewSession() }

        let userMessage = AIService.ChatMessage(
            role: .user,
            content: displayContent,
            attachments: hasAttachments ? pendingAttachments : nil
        )
        messages.append(userMessage)
        // 更新发送给 AI 的消息内容（为会话上下文用）
        messages[messages.count - 1] = AIService.ChatMessage(
            role: .user,
            content: finalInput,
            attachments: hasAttachments ? pendingAttachments : nil
        )
        inputText = ""
        pendingAttachments = []

        isStreaming = true
        streamingText = ""
        streamingReasoning = ""

        saveCurrentSession()

        aiService.streamChat(
            messages: messages,
            config: config,
            systemPrompt: "你是一个专业的写作助手，帮助用户改进 Markdown 笔记、提供写作建议和知识解答。请使用中文回复。",
            onReasoningChunk: { [weak self] chunk in
                self?.streamingReasoning += chunk
            },
            onChunk: { [weak self] chunk in
                self?.streamingText += chunk
            },
            onComplete: { [weak self] content, reasoning in
                guard let self = self else { return }
                let msg = AIService.ChatMessage(
                    role: .assistant,
                    content: content,
                    reasoningContent: reasoning.isEmpty ? nil : reasoning
                )
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
                self.saveCurrentSession()
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                let msg = AIService.ChatMessage(role: .assistant, content: "错误：\(error.localizedDescription)")
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
                self.saveCurrentSession()
            }
        )
    }

    func sendMessageWithSearch() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty, !isStreaming else { return }

        let hasAttachments = !pendingAttachments.isEmpty
        let displayContent: String
        if hasAttachments {
            displayContent = trimmed.isEmpty ? "[已发送 \(pendingAttachments.count) 个文件]" : trimmed
        } else if trimmed.isEmpty {
            displayContent = "请分析以下文件"
        } else {
            displayContent = trimmed
        }

        // 创建新会话
        if selectedSessionId == nil { createNewSession() }

        // 用户气泡：只显示用户输入 + 搜索/附件标记
        let userBubbleContent = enableWebSearch ? trimmed + "\n🔍 已联网搜索" : displayContent
        let userMessage = AIService.ChatMessage(
            role: .user,
            content: userBubbleContent,
            attachments: hasAttachments ? pendingAttachments : nil
        )
        messages.append(userMessage)
        inputText = ""

        var finalInput = trimmed

        // 文件内容（只发给 AI，不显示在气泡）
        if hasAttachments {
            var attachmentContext = ""
            for att in pendingAttachments {
                if let text = String(data: att.data, encoding: .utf8) {
                    attachmentContext += "\n[文件: \(att.displayName)]\n```\n\(text)\n```"
                } else {
                    attachmentContext += "\n[文件: \(att.displayName), 大小: \(att.data.count) 字节]"
                }
            }
            finalInput += attachmentContext
        }

        let attachmentsToSend = pendingAttachments
        pendingAttachments = []

        // 联网搜索（只发给 AI，不显示在气泡）
        var searchContext = ""
        if enableWebSearch {
            do {
                let (text, rawResults) = try await searchService.search(query: trimmed)
                searchContext = text
                lastSearchResults = rawResults.enumerated().map { idx, r in
                    AIService.ChatMessage.SearchResultItem(id: idx + 1, title: r.title, url: r.url.absoluteString)
                }
                finalInput = "\(finalInput)\n\n[联网搜索结果]\n\(searchContext)"
                // 在 AI 上下文末尾提醒引用编号
                finalInput += "\n\n请在回答中引用搜索来源时使用 [1]、[2] 等编号标记。"
            } catch {
                let msg = AIService.ChatMessage(role: .assistant, content: "联网搜索失败：\(error.localizedDescription)")
                messages.append(msg)
                isStreaming = false
                saveCurrentSession()
                return
            }
        }

        if includeNoteContent, let note = currentNoteProvider?() {
            finalInput = "以下是我当前笔记「\(note.title)」的完整内容：\n\n```markdown\n\(note.content)\n```\n\n我的问题是：\(finalInput)"
        }

        // 发给 AI 的消息包含搜索/文件上下文（不修改用户气泡显示）
        var aiMessages = messages
        aiMessages[aiMessages.count - 1] = AIService.ChatMessage(
            role: .user,
            content: finalInput,
            attachments: attachmentsToSend.isEmpty ? nil : attachmentsToSend
        )

        isStreaming = true
        streamingText = ""
        streamingReasoning = ""

        saveCurrentSession()

        let contextMessages = aiMessages

        aiService.streamChat(
            messages: contextMessages,
            config: config,
            systemPrompt: "你是一个专业的写作助手，帮助用户改进 Markdown 笔记、提供写作建议和知识解答。请使用中文回复。如果提供了联网搜索结果，请基于搜索内容进行回答并引用来源。",
            onReasoningChunk: { [weak self] chunk in
                self?.streamingReasoning += chunk
            },
            onChunk: { [weak self] chunk in
                self?.streamingText += chunk
            },
            onComplete: { [weak self] content, reasoning in
                guard let self = self else { return }
                let results = self.lastSearchResults.isEmpty ? nil : self.lastSearchResults
                let msg = AIService.ChatMessage(
                    role: .assistant,
                    content: content,
                    reasoningContent: reasoning.isEmpty ? nil : reasoning,
                    searchResults: results
                )
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
                self.lastSearchResults = []
                self.saveCurrentSession()
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                let msg = AIService.ChatMessage(role: .assistant, content: "错误：\(error.localizedDescription)")
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
                self.saveCurrentSession()
            }
        )
    }

    func clearChat() {
        messages.removeAll()
        streamingText = ""
        streamingReasoning = ""
        pendingAttachments = []
        saveCurrentSession()
    }

    func cancelStreaming() {
        aiService.cancelStream()
        let msg = AIService.ChatMessage(role: .assistant, content: "[已中止]")
        messages.append(msg)
        streamingText = ""
        streamingReasoning = ""
        isStreaming = false
        saveCurrentSession()
    }

    // MARK: - 文件附件

    func addAttachment(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let fileName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        let mimeType = Self.mimeType(for: ext)
        let attachment = AIService.ChatMessage.Attachment(
            fileName: fileName,
            fileExtension: ext,
            data: data,
            mimeType: mimeType
        )
        pendingAttachments.append(attachment)
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "swift": return "text/x-swift"
        case "py": return "text/x-python"
        case "js": return "text/javascript"
        case "html": return "text/html"
        case "css": return "text/css"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "csv": return "text/csv"
        default: return "application/octet-stream"
        }
    }

    private static func loadConfig() -> AIConfig {
        guard let data = UserDefaults.standard.data(forKey: PersistenceKeys.aiConfig),
              let config = try? JSONDecoder().decode(AIConfig.self, from: data) else {
            return AIConfig()
        }
        return config
    }
}
