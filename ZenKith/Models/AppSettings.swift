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

    init() {
        let savedFont = UserDefaults.standard.double(forKey: PersistenceKeys.fontSize)
        self.fontSize = (savedFont >= 12 && savedFont <= 32) ? savedFont : 16

        let savedMode = UserDefaults.standard.integer(forKey: PersistenceKeys.viewMode)
        self.viewMode = ViewMode(rawValue: savedMode) ?? .split

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
