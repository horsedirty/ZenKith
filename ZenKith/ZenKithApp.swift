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
        CommandGroup(after: .newItem) {
            Button(String(localized: "new_note")) {
                manager.createNote(language: settings.editorLanguage)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button(String(localized: "new_folder")) {
                manager.createFolder()
            }

            Divider()

            Button(String(localized: "pdf_translation")) {
                NotificationCenter.default.post(name: .openPDFTranslation, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "switch_work_dir")) {
                manager.selectDirectoryPanel()
            }
        }

        CommandMenu(String(localized: "view")) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    settings.viewMode = mode
                }
            }

            Divider()

            Button(String(localized: "toggle_sidebar")) {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "toggle_ai")) {
                NotificationCenter.default.post(name: .toggleAIDrawer, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu(String(localized: "export")) {
            exportButton("PDF", format: .pdf, shortcut: "1")
            exportButton("Word (.docx)", format: .docx, shortcut: "2")
            exportButton("纯文本 (.txt)", format: .txt, shortcut: "3")
            exportButton("Markdown (.md)", format: .markdown, shortcut: "4")
        }

        CommandGroup(replacing: .help) {
            Button(String(localized: "check_updates")) {
                if let url = URL(string: "https://github.com/horsedirty/ZenKith/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func exportButton(_ title: String, format: ExportService.ExportFormat, shortcut: String) -> some View {
        Button(String(format: String(localized: "export_as"), title)) {
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
