import Foundation

struct ChatSession: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var messages: [AIService.ChatMessage]
    var createdAt: Date
    var lastModified: Date

    init(title: String = "新对话", messages: [AIService.ChatMessage] = []) {
        self.id = UUID()
        self.title = title
        self.messages = messages
        let now = Date()
        self.createdAt = now
        self.lastModified = now
    }
}
