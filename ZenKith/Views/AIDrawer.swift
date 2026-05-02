import SwiftUI
import UniformTypeIdentifiers
import Textual

/// 右侧 AI 抽屉面板：聊天气泡 + 流式输出 + 思考过程 + Markdown 渲染 + 会话管理 + 文件附件
struct AIDrawer: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var expandedReasoning: Set<UUID> = []
    @State private var isImportingFile = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            messageListView
            Divider()
            attachmentChipsView
            optionsView
            Divider()
            inputView
        }
        .frame(minWidth: 280, idealWidth: 360)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $viewModel.showConfigPanel) { configPanelView }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.plainText, .pdf, .image, .json, .data, .sourceCode,
                                  UTType(filenameExtension: "md") ?? .plainText,
                                  UTType(filenameExtension: "swift") ?? .plainText,
                                  UTType(filenameExtension: "py") ?? .plainText,
                                  UTType(filenameExtension: "js") ?? .plainText,
                                  UTType(filenameExtension: "html") ?? .plainText,
                                  UTType(filenameExtension: "css") ?? .plainText,
                                  UTType(filenameExtension: "csv") ?? .plainText,
                                  UTType(filenameExtension: "xml") ?? .plainText,
            ].compactMap { $0 },
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    viewModel.addAttachment(from: url)
                }
            }
        }
    }

    // MARK: - 标题栏

    private var headerView: some View {
        HStack(spacing: 6) {
            // 会话选择器
            Menu {
                if viewModel.sessions.isEmpty {
                    Text("暂无历史会话").foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.sessions) { session in
                        Button(action: { viewModel.selectedSessionId = session.id }) {
                            HStack {
                                Text(session.title)
                                    .lineLimit(1)
                                if viewModel.selectedSessionId == session.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    ForEach(viewModel.sessions) { session in
                        Button(role: .destructive, action: { viewModel.deleteSession(id: session.id) }) {
                            Label("删除「\(session.title)」", systemImage: "trash")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Label(currentSessionTitle, systemImage: "sparkles")
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 180)
            .help("切换或管理历史会话")

            Spacer()

            // 模型快速切换
            modelSwitcher

            // 新建对话
            Button(action: { viewModel.createNewSession() }) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("新建对话")

            if viewModel.isStreaming {
                ProgressView().scaleEffect(0.7).padding(.trailing, 2)
            }

            Button(action: { viewModel.showConfigPanel.toggle() }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless).help("配置 API 设置")

            Button(action: { viewModel.clearChat() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless).help("清空当前对话")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var modelSwitcher: some View {
        Menu {
            // 服务商切换
            Section("服务商") {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Button(action: {
                        viewModel.config.provider = provider
                        viewModel.config.modelName = provider.defaultModel
                    }) {
                        HStack {
                            Text(provider.rawValue)
                            if viewModel.config.provider == provider {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            // 模型切换
            let models = viewModel.config.provider.knownModels
            if !models.isEmpty {
                Section("模型") {
                    ForEach(models, id: \.self) { model in
                        Button(action: { viewModel.config.modelName = model }) {
                            HStack {
                                Text(modelShortName(model))
                                    .lineLimit(1)
                                if viewModel.config.effectiveModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Button(action: { viewModel.showConfigPanel = true }) {
                Label("高级配置…", systemImage: "gearshape")
            }
        } label: {
            Text(currentModelLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 120)
        .help("切换 AI 模型 / 服务商")
    }

    private var currentModelLabel: String {
        let model = viewModel.config.effectiveModel
        if model.isEmpty { return "选择模型" }
        return modelShortName(model)
    }

    private func modelShortName(_ model: String) -> String {
        // 截取模型名最后一段，如 "deepseek-ai/DeepSeek-V3" → "DeepSeek-V3"
        if let lastSlash = model.lastIndex(of: "/") {
            return String(model[model.index(after: lastSlash)...])
        }
        if let lastDot = model.lastIndex(of: "-") {
            let suffix = String(model[model.index(after: lastDot)...])
            if suffix.count <= 12 { return suffix }
        }
        if model.count > 16 {
            return String(model.prefix(14)) + "…"
        }
        return model
    }

    private var currentSessionTitle: String {
        if let id = viewModel.selectedSessionId,
           let session = viewModel.sessions.first(where: { $0.id == id }) {
            return session.title
        }
        return "AI 助手"
    }

    // MARK: - 消息列表

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                    }
                    if viewModel.isStreaming, !viewModel.streamingText.isEmpty || !viewModel.streamingReasoning.isEmpty {
                        streamingBubble
                    }
                    Color.clear.frame(height: 4).id("bottomAnchor")
                }
                .padding(12)
            }
            .onChange(of: viewModel.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.streamingText) { _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.streamingReasoning) { _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
    }

    // MARK: - 消息气泡

    @ViewBuilder
    private func messageBubble(_ message: AIService.ChatMessage) -> some View {
        let isUser = message.role == .user
        let hasAttachments = message.attachments != nil && !(message.attachments?.isEmpty ?? true)

        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor.opacity(0.1)))
            } else {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                // 思考过程（可折叠）
                if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                    reasoningSection(id: message.id, reasoning: reasoning)
                }

                // 文件附件（在用户气泡中显示图标+文件名）
                if isUser, hasAttachments {
                    attachmentBubbleContent(message.attachments!)
                }

                // 消息正文
                if !message.content.isEmpty {
                    if isUser {
                        let displayText = userDisplayContent(message)
                        Text(displayText)
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .textSelection(.enabled)
                    } else {
                        assistantMarkdownBubble(message.content)
                    }
                }

                // 搜索引用来源
                if !isUser, let results = message.searchResults, !results.isEmpty {
                    searchSourcesView(results)
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            }
        }
    }

    /// 用户消息中只展示用户可见的内容，过滤掉文件上下文注入
    private func userDisplayContent(_ message: AIService.ChatMessage) -> String {
        let content = message.content
        // 如果包含笔记上下文注入，提取用户问题部分
        if content.contains("以下是我当前笔记") {
            if let range = content.range(of: "我的问题是：") {
                return String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 过滤掉文件上下文注入标识
        if content.hasPrefix("请分析以下文件内容:") {
            if message.attachments != nil {
                return "[已发送文件]"
            }
            return content
        }
        // 文件内容注入标记去除
        if content.contains("\n[文件:") {
            if let firstNewline = content.firstIndex(of: "\n") {
                let userText = String(content[..<firstNewline])
                if !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return userText
                }
            }
            return "[已发送 \(message.attachments?.count ?? 0) 个文件]"
        }
        return content
    }

    @ViewBuilder
    private func attachmentBubbleContent(_ attachments: [AIService.ChatMessage.Attachment]) -> some View {
        ForEach(attachments) { att in
            HStack(spacing: 6) {
                Image(systemName: fileIconName(for: att.fileExtension))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                Text(att.displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func fileIconName(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "swift", "py", "js", "html", "css", "json", "xml", "csv": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }

    // MARK: - AI 消息气泡（WebView + MathJax）

    private func assistantMarkdownBubble(_ content: String) -> some View {
        MessageMarkdownView(
            markdown: content,
            baseURL: FileManager.default.temporaryDirectory,
            isStreaming: false
        )
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(nsColor: .controlColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 搜索引用来源

    @ViewBuilder
    private func searchSourcesView(_ results: [AIService.ChatMessage.SearchResultItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .padding(.vertical, 2)
            Text("📎 引用来源")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            ForEach(results) { item in
                HStack(alignment: .top, spacing: 4) {
                    Text("[\(item.id)]")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Text(item.url)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 流式输出气泡

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.1)))

            VStack(alignment: .leading, spacing: 4) {
                // 流式思考
                if !viewModel.streamingReasoning.isEmpty {
                    streamingReasoningSection
                }

                // 流式正文 - 使用 WebView 增量渲染 Markdown + LaTeX
                if !viewModel.streamingText.isEmpty {
                    MessageMarkdownView(
                        markdown: viewModel.streamingText,
                        baseURL: FileManager.default.temporaryDirectory,
                        isStreaming: true
                    )
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(nsColor: .controlColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    )
                } else if viewModel.isStreaming && !viewModel.streamingReasoning.isEmpty {
                    // 仅有思考还没有正文
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("生成中…").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 思考过程（已完成消息）

    private func reasoningSection(id: UUID, reasoning: String) -> some View {
        let isExpanded = expandedReasoning.contains(id)
        return VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                if isExpanded { expandedReasoning.remove(id) }
                else { expandedReasoning.insert(id) }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption2)
                    Text("思考过程").font(.caption2)
                    Text(isExpanded ? "▲" : "▼").font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView(.vertical) {
                    InlineText(markdown: reasoning)
                        .textual.textSelection(.enabled)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color(nsColor: .controlColor).opacity(0.4))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 流式思考过程

    private var streamingReasoningSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5)
                Text("深度思考中…").font(.caption2).foregroundColor(.secondary)
            }
            ScrollView(.vertical) {
                Text(viewModel.streamingReasoning)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .background(Color(nsColor: .controlColor).opacity(0.4))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - 附件碎片显示（待发送）

    @ViewBuilder
    private var attachmentChipsView: some View {
        if !viewModel.pendingAttachments.isEmpty {
            VStack(spacing: 0) {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.pendingAttachments) { att in
                            HStack(spacing: 4) {
                                Image(systemName: fileIconName(for: att.fileExtension))
                                    .font(.caption2)
                                Text(att.displayName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Button(action: { viewModel.removeAttachment(id: att.id) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(nsColor: .controlColor))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - 选项区

    private var optionsView: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $viewModel.includeNoteContent) {
                Label("包含笔记", systemImage: "doc.text").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .help("将当前笔记内容作为上下文发送给 AI")

            Toggle(isOn: $viewModel.enableWebSearch) {
                Label("联网搜索", systemImage: "globe").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .help("启用联网搜索（需配置搜索 API）")

            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - 输入区

    private var inputView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 文件选择按钮
            Button(action: { isImportingFile = true }) {
                Image(systemName: "paperclip")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help("附加文件 (图片、代码、PDF 等)")

            TextField("输入消息...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            Button(action: {
                if viewModel.isStreaming {
                    viewModel.cancelStreaming()
                } else {
                    Task {
                        if viewModel.enableWebSearch {
                            await viewModel.sendMessageWithSearch()
                        } else {
                            viewModel.sendMessage()
                        }
                    }
                }
            }) {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && viewModel.pendingAttachments.isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("发送 (Cmd+Return)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - 配置面板

    private var configPanelView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI 配置").font(.headline)

            Picker("服务商", selection: $viewModel.config.provider) {
                ForEach(AIProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            if case .custom = viewModel.config.provider {
                TextField("API 端点 URL", text: $viewModel.config.customEndpoint)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("模型名称（留空使用默认）", text: $viewModel.config.modelName)
                .textFieldStyle(.roundedBorder)

            Divider()
            Text("API 密钥管理").font(.subheadline).foregroundColor(.secondary)
            SecureField("API Key", text: Binding(
                get: { viewModel.getAPIKey() }, set: { viewModel.setAPIKey($0) }
            )).textFieldStyle(.roundedBorder)
            Text("密钥安全存储在系统钥匙串中").font(.caption).foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("完成") { viewModel.showConfigPanel = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 400)
    }
}
