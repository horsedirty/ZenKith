import SwiftUI

/// 右侧 AI 抽屉面板：聊天气泡 + 流式输出 + 思考过程 + Markdown 渲染
struct AIDrawer: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var expandedReasoning: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            messageListView
            Divider()
            optionsView
            Divider()
            inputView
        }
        .frame(minWidth: 280, idealWidth: 360)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $viewModel.showConfigPanel) { configPanelView }
    }

    // MARK: - 标题栏
    private var headerView: some View {
        HStack {
            Label("AI 助手", systemImage: "sparkles").font(.headline)
            Spacer()
            if viewModel.isStreaming {
                ProgressView().scaleEffect(0.7).padding(.trailing, 4)
            }
            Button(action: { viewModel.showConfigPanel.toggle() }) {
                Image(systemName: "gearshape")
            }.buttonStyle(.borderless).help("配置 API 设置")
            Button(action: { viewModel.clearChat() }) {
                Image(systemName: "trash")
            }.buttonStyle(.borderless).help("清空对话")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
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

                // 消息正文
                if !message.content.isEmpty {
                    markdownText(message.content)
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            isUser
                                ? Color.accentColor
                                : Color(nsColor: .controlColor)
                        )
                        .foregroundColor(isUser ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .textSelection(.enabled)
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

                // 流式正文
                if !viewModel.streamingText.isEmpty {
                    markdownText(viewModel.streamingText)
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(nsColor: .controlColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                        )
                        .textSelection(.enabled)
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

    // MARK: - Markdown 文本渲染
    private func markdownText(_ content: String) -> Text {
        if let data = content.data(using: .utf8),
           let att = try? AttributedString(markdown: data,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
            return Text(att)
        }
        return Text(content)
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
                    Text(reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .textSelection(.enabled)
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

    // MARK: - 选项区
    private var optionsView: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $viewModel.includeNoteContent) {
                Label("包含笔记", systemImage: "doc.text").labelStyle(.iconOnly)
            }.toggleStyle(.button)
            .help("将当前笔记内容作为上下文发送给 AI")

            Toggle(isOn: $viewModel.enableWebSearch) {
                Label("联网搜索", systemImage: "globe").labelStyle(.iconOnly)
            }.toggleStyle(.button)
            .help("启用联网搜索（需配置搜索 API）")

            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - 输入区
    private var inputView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入消息...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            Button(action: {
                Task {
                    if viewModel.enableWebSearch {
                        await viewModel.sendMessageWithSearch()
                    } else {
                        viewModel.sendMessage()
                    }
                }
            }) {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

            Divider()
            Text("联网搜索配置").font(.subheadline).foregroundColor(.secondary)
            Picker("搜索引擎", selection: $viewModel.config.searchProvider) {
                ForEach(SearchProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            SecureField("搜索 API Key", text: Binding(
                get: { viewModel.getSearchAPIKey() }, set: { viewModel.setSearchAPIKey($0) }
            )).textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("完成") { viewModel.showConfigPanel = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 400)
    }
}
