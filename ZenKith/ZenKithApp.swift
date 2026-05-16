import SwiftUI

/// MarkFlow Note 应用入口点
/// 支持三种视图模式、AI 辅助写作、多格式导出
@main
struct ZenKithApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var manager: NotesManager
    @StateObject private var aiViewModel = AIViewModel()

    init() {
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("MarkFlow")
        _manager = StateObject(wrappedValue: NotesManager(directory: defaultDir))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(aiViewModel)
                .frame(minWidth: 900, idealWidth: 1200, minHeight: 600, idealHeight: 800)
                .onAppear {
                    if let customURL = settings.defaultDirectoryURL {
                        manager.changeDirectory(to: customURL)
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            commandMenus
        }

        WindowGroup(id: "pdfTranslation") {
            TranslationWindowView()
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }

    // MARK: - 菜单栏命令

    @CommandsBuilder
    private var commandMenus: some Commands {
        // 文件菜单：新建笔记、新建文件夹、切换目录
        CommandGroup(after: .newItem) {
            Button("新建笔记") {
                manager.createNote(language: settings.editorLanguage)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("新建文件夹") {
                manager.createFolder()
            }

            Divider()

            Button("PDF 翻译...") {
                NotificationCenter.default.post(name: .openPDFTranslation, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("切换工作目录...") {
                manager.selectDirectoryPanel()
            }
        }

        // 显示菜单：视图模式切换 + AI 开关
        CommandMenu("显示") {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    settings.viewMode = mode
                }
            }

            Divider()

            Button("显示/隐藏 目录栏") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("显示/隐藏 AI 助手") {
                NotificationCenter.default.post(name: .toggleAIDrawer, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        // 导出菜单：四种格式
        CommandMenu("导出") {
            exportButton("PDF", format: .pdf, shortcut: "1")
            exportButton("Word (.docx)", format: .docx, shortcut: "2")
            exportButton("纯文本 (.txt)", format: .txt, shortcut: "3")
            exportButton("Markdown (.md)", format: .markdown, shortcut: "4")
        }

        CommandGroup(replacing: .help) {
            Button("检查更新...") {
                if let url = URL(string: "https://github.com/horsedirty/ZenKith/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func exportButton(_ title: String, format: ExportService.ExportFormat, shortcut: String) -> some View {
        Button("导出为 \(title)") {
            NotificationCenter.default.post(
                name: .exportNote,
                object: nil,
                userInfo: ["format": format]
            )
        }
        .keyboardShortcut(KeyEquivalent(shortcut.first!), modifiers: [.command, .shift])
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    static let toggleAIDrawer = Notification.Name("com.markflow.toggleAIDrawer")
    static let toggleSidebar = Notification.Name("com.markflow.toggleSidebar")
    static let exportNote = Notification.Name("com.markflow.exportNote")
    static let directoryDidChange = Notification.Name("com.markflow.directoryDidChange")
    static let openPDFTranslation = Notification.Name("com.markflow.openPDFTranslation")
}
