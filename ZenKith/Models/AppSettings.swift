import SwiftUI
import Combine
import Security

// MARK: - Enums

enum AppTheme: String, CaseIterable {
    case system, light, dark
}

enum ViewMode: Int, Codable, CaseIterable {
    case split = 0
    case editor = 1
    case preview = 2

    var displayName: String {
        switch self {
        case .split: return "双栏"
        case .editor: return "纯编辑"
        case .preview: return "纯预览"
        }
    }

    var systemImage: String {
        switch self {
        case .split: return "rectangle.split.2x1"
        case .editor: return "rectangle.and.pencil.and.ellipsis"
        case .preview: return "eye"
        }
    }
}

enum EditorLanguage: Int, Codable, CaseIterable {
    case markdown = 0
    case latex = 1

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .latex: return "LaTeX"
        }
    }
}

enum LatexCompiler: String, CaseIterable {
    case pdflatex = "pdflatex"
    case xelatex  = "xelatex"
    case lualatex = "lualatex"

    var displayName: String {
        switch self {
        case .pdflatex: return "pdfLaTeX"
        case .xelatex:  return "XeLaTeX"
        case .lualatex: return "LuaLaTeX"
        }
    }
}

enum TranslationEngine: String, CaseIterable {
    case apple = "Apple 翻译"
    case tencent = "腾讯翻译"
}

// MARK: - AppSettings

class AppSettings: ObservableObject {
    // General
    @AppStorage("openLastFileOnLaunch") var openLastFileOnLaunch = true
    @AppStorage("autoSave") var autoSave = true
    @AppStorage("theme") var theme: AppTheme = .system

    // Editor mode
    @Published var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "com.markflow.viewMode") }
    }
    @Published var editorLanguage: EditorLanguage {
        didSet { UserDefaults.standard.set(editorLanguage.rawValue, forKey: "com.markflow.editorLanguage") }
    }
    @Published var latexCompiler: LatexCompiler {
        didSet { UserDefaults.standard.set(latexCompiler.rawValue, forKey: "com.markflow.latexCompiler") }
    }

    // Directory
    @Published var defaultDirectoryURL: URL? {
        didSet {
            if let url = defaultDirectoryURL {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                    UserDefaults.standard.set(bookmark, forKey: "com.markflow.directoryBookmark")
                }
                UserDefaults.standard.set(url.path, forKey: "com.markflow.directoryPath")
            }
        }
    }

    var effectiveDirectory: URL {
        if let url = defaultDirectoryURL { return url }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("MarkFlow")
    }

    // Editor display
    @AppStorage("showLineNumbers") var showLineNumbers = true
    @AppStorage("wordWrap") var wordWrap = true

    // AI
    @AppStorage("aiAPIKey") var aiAPIKey = ""
    @AppStorage("aiEndpoint") var aiEndpoint = "https://api.openai.com/v1"
    @AppStorage("aiModel") var aiModel = "claude-opus-4.6"

    // Translation
    @Published var translationEngine: TranslationEngine {
        didSet { UserDefaults.standard.set(translationEngine.rawValue, forKey: "com.markflow.translationEngine") }
    }
    @AppStorage("tencentSecretId") var tencentSecretId = ""
    @AppStorage("tencentSourceLanguage") var tencentSourceLanguage = "en"
    @AppStorage("tencentTargetLanguage") var tencentTargetLanguage = "zh"

    private let keychainService = "com.zenkith.translation"
    var tencentSecretKey: String {
        get { KeychainHelper.load(service: keychainService, account: "tencentSecretKey") ?? "" }
        set { KeychainHelper.save(newValue, service: keychainService, account: "tencentSecretKey") }
    }

    // MARK: - Init

    init() {
        // View mode
        let savedMode = UserDefaults.standard.integer(forKey: "com.markflow.viewMode")
        self.viewMode = ViewMode(rawValue: savedMode) ?? .split

        // Editor language
        let savedLang = UserDefaults.standard.integer(forKey: "com.markflow.editorLanguage")
        self.editorLanguage = EditorLanguage(rawValue: savedLang) ?? .markdown

        // Latex compiler
        let savedCompiler = UserDefaults.standard.string(forKey: "com.markflow.latexCompiler")
        self.latexCompiler = LatexCompiler(rawValue: savedCompiler ?? "") ?? .pdflatex

        // Directory bookmark
        if let bookmark = UserDefaults.standard.data(forKey: "com.markflow.directoryBookmark") {
            var isStale = false
            self.defaultDirectoryURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
        } else {
            self.defaultDirectoryURL = nil
        }

        // Translation engine
        let savedEngine = UserDefaults.standard.string(forKey: "com.markflow.translationEngine")
        self.translationEngine = TranslationEngine(rawValue: savedEngine ?? "") ?? .apple
    }
}

// MARK: - Keychain Helper

private struct KeychainHelper {
    static func save(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}
