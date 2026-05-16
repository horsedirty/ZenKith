import Foundation

/// UserDefaults 键名常量
struct PersistenceKeys {
    static let fontSize = "com.markflow.fontSize"
    static let viewMode = "com.markflow.viewMode"
    static let editorLanguage = "com.markflow.editorLanguage"
    static let latexCompiler = "com.markflow.latexCompiler"
    static let directoryBookmark = "com.markflow.directoryBookmark"
    static let directoryPath = "com.markflow.directoryPath"
    static let aiConfig = "com.markflow.aiConfig"
    static let keychainService = "com.markflow.zenkith"
}

extension Notification.Name {
    static let scrollToLine = Notification.Name("ZenKith.scrollToLine")
    static let sendCompileErrorsToAI = Notification.Name("ZenKith.sendCompileErrorsToAI")
}
