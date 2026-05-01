import Foundation
import Combine
import SwiftUI

/// 三种视图模式
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

/// 编辑器编写语言
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

/// LaTeX 编译器选项
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

/// 全局持久化设置（使用 UserDefaults）
@MainActor
class AppSettings: ObservableObject {
    @Published var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: PersistenceKeys.fontSize)
        }
    }

    @Published var defaultDirectoryURL: URL? {
        didSet {
            if let url = defaultDirectoryURL {
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                    UserDefaults.standard.set(bookmark, forKey: PersistenceKeys.directoryBookmark)
                }
                UserDefaults.standard.set(url.path, forKey: PersistenceKeys.directoryPath)
            }
        }
    }

    @Published var viewMode: ViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: PersistenceKeys.viewMode)
        }
    }

    @Published var editorLanguage: EditorLanguage {
        didSet {
            UserDefaults.standard.set(editorLanguage.rawValue, forKey: PersistenceKeys.editorLanguage)
        }
    }

    @Published var latexCompiler: LatexCompiler {
        didSet {
            UserDefaults.standard.set(latexCompiler.rawValue, forKey: PersistenceKeys.latexCompiler)
        }
    }

    init() {
        let savedFont = UserDefaults.standard.double(forKey: PersistenceKeys.fontSize)
        self.fontSize = (savedFont >= 12 && savedFont <= 32) ? savedFont : 16

        let savedMode = UserDefaults.standard.integer(forKey: PersistenceKeys.viewMode)
        self.viewMode = ViewMode(rawValue: savedMode) ?? .split

        let savedLang = UserDefaults.standard.integer(forKey: PersistenceKeys.editorLanguage)
        self.editorLanguage = EditorLanguage(rawValue: savedLang) ?? .markdown

        let savedCompiler = UserDefaults.standard.string(forKey: PersistenceKeys.latexCompiler)
        self.latexCompiler = LatexCompiler(rawValue: savedCompiler ?? "") ?? .pdflatex

        if let bookmark = UserDefaults.standard.data(forKey: PersistenceKeys.directoryBookmark) {
            var isStale = false
            self.defaultDirectoryURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
        } else {
            self.defaultDirectoryURL = nil
        }
    }

    /// 获取有效的笔记目录，默认 ~/Documents/MarkFlow
    var effectiveDirectory: URL {
        if let url = defaultDirectoryURL {
            return url
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("MarkFlow")
    }
}
