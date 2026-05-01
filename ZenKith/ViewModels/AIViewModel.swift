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

    // MARK: - 依赖

    private let aiService = AIService()
    private let searchService = SearchService()
    private var currentNoteProvider: (() -> (content: String, title: String)?)?

    init() {
        self.config = AIViewModel.loadConfig()
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

    func getSearchAPIKey() -> String {
        aiService.getAPIKey(forIdentifier: config.searchAPIKeyIdentifier) ?? ""
    }

    func setSearchAPIKey(_ key: String) {
        aiService.setAPIKey(key, forIdentifier: config.searchAPIKeyIdentifier)
    }

    // MARK: - 发送消息

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        var finalInput = trimmed
        if includeNoteContent, let note = currentNoteProvider?() {
            finalInput = "以下是我当前笔记「\(note.title)」的完整内容：\n\n```markdown\n\(note.content)\n```\n\n我的问题是：\(trimmed)"
        }

        let userMessage = AIService.ChatMessage(role: .user, content: finalInput)
        messages.append(userMessage)
        inputText = ""

        isStreaming = true
        streamingText = ""
        streamingReasoning = ""

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
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                let msg = AIService.ChatMessage(role: .assistant, content: "错误：\(error.localizedDescription)")
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
            }
        )
    }

    func sendMessageWithSearch() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = AIService.ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        inputText = ""

        var finalInput = trimmed

        if enableWebSearch {
            let searchKey = getSearchAPIKey()
            do {
                let searchContext = try await searchService.search(query: trimmed, config: config, apiKey: searchKey)
                messages[messages.count - 1] = AIService.ChatMessage(
                    role: .user, content: "\(trimmed)\n\n[联网搜索结果]\n\(searchContext)"
                )
                finalInput = "\(trimmed)\n\n[联网搜索结果]\n\(searchContext)"
            } catch {
                let msg = AIService.ChatMessage(role: .assistant, content: "联网搜索失败：\(error.localizedDescription)")
                messages.append(msg)
                isStreaming = false
                return
            }
        }

        if includeNoteContent, let note = currentNoteProvider?() {
            finalInput = "以下是我当前笔记「\(note.title)」的完整内容：\n\n```markdown\n\(note.content)\n```\n\n我的问题是：\(trimmed)"
            if !messages.isEmpty {
                messages[messages.count - 1] = AIService.ChatMessage(role: .user, content: finalInput)
            }
        }

        isStreaming = true
        streamingText = ""
        streamingReasoning = ""

        let contextMessages = messages

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
                let msg = AIService.ChatMessage(
                    role: .assistant,
                    content: content,
                    reasoningContent: reasoning.isEmpty ? nil : reasoning
                )
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                let msg = AIService.ChatMessage(role: .assistant, content: "错误：\(error.localizedDescription)")
                self.messages.append(msg)
                self.streamingText = ""
                self.streamingReasoning = ""
                self.isStreaming = false
            }
        )
    }

    func clearChat() {
        messages.removeAll()
        streamingText = ""
        streamingReasoning = ""
    }

    private static func loadConfig() -> AIConfig {
        guard let data = UserDefaults.standard.data(forKey: PersistenceKeys.aiConfig),
              let config = try? JSONDecoder().decode(AIConfig.self, from: data) else {
            return AIConfig()
        }
        return config
    }
}
