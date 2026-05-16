import Foundation
import Combine

struct BibEntry: Identifiable, Equatable, Codable {
    let id = UUID()
    let key: String
    let type: String
    var author: String
    var title: String
    var journal: String
    var year: String

    var citationSummary: String {
        let authorShort: String = {
            let parts = author.components(separatedBy: " and ")
            let first = parts.first?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? author
            if parts.count > 2 { return first + " et al." }
            if parts.count == 2 {
                let second = parts[1].components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? parts[1]
                return first + " & " + second
            }
            return first
        }()
        return "\(authorShort) (\(year)), \(title). *\(journal)*"
    }
}

@MainActor
final class BibManager: ObservableObject {
    @Published var entries: [BibEntry] = []
    @Published var searchQuery: String = ""
    @Published var duplicateKeys: [String] = []

    var filteredEntries: [BibEntry] {
        if searchQuery.isEmpty { return entries }
        let q = searchQuery.lowercased()
        return entries.filter {
            $0.key.lowercased().contains(q) ||
            $0.title.lowercased().contains(q) ||
            $0.author.lowercased().contains(q)
        }
    }

    var allKeys: [String] { entries.map(\.key) }

    func loadBibFiles(from directory: URL?) {
        var allEntries: [BibEntry] = []
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "bib" {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                allEntries.append(contentsOf: parseBibtex(content))
            }
        }
        entries = allEntries
        detectDuplicateKeys()
    }

    func citeKeys(for prefix: String) -> [String] {
        let lower = prefix.lowercased()
        return entries.map(\.key).filter { $0.lowercased().contains(lower) }
    }

    func findMissingCitations(texContent: String) -> [String] {
        var missing: [String] = []
        let pattern = try? NSRegularExpression(pattern: "\\\\cite\\{([^}]*)\\}", options: [])
        let nsText = texContent as NSString
        pattern?.enumerateMatches(in: texContent, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let keysRange = Range(match.range(at: 1), in: texContent) else { return }
            let keysStr = String(texContent[keysRange])
            let keys = keysStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for key in keys {
                if !entries.contains(where: { $0.key == key }) && !missing.contains(key) {
                    missing.append(key)
                }
            }
        }
        return missing
    }

    private func parseBibtex(_ content: String) -> [BibEntry] {
        var entries: [BibEntry] = []
        let pattern = try? NSRegularExpression(pattern: "@(\\w+)\\s*\\{\\s*(\\S+)\\s*,\\s*([^@]*?)\\}\\s*$", options: [.dotMatchesLineSeparators])
        guard let regex = pattern else { return [] }

        regex.enumerateMatches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3,
                  let typeRange = Range(match.range(at: 1), in: content),
                  let keyRange = Range(match.range(at: 2), in: content) else { return }
            let type = String(content[typeRange]).trimmingCharacters(in: .whitespaces)
            let key = String(content[keyRange]).trimmingCharacters(in: .whitespaces)

            var fieldsContent = ""
            if match.numberOfRanges >= 4, let fieldsRange = Range(match.range(at: 3), in: content) {
                fieldsContent = String(content[fieldsRange])
            }
            let fields = parseFields(fieldsContent)

            entries.append(BibEntry(
                key: key, type: type,
                author: fields["author"] ?? "",
                title: fields["title"] ?? "",
                journal: fields["journal"] ?? fields["booktitle"] ?? "",
                year: fields["year"] ?? ""
            ))
        }
        return entries
    }

    private func parseFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let fieldName = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let afterEq = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            let value: String
            if afterEq.hasPrefix("{"), let close = afterEq.lastIndex(of: "}") {
                let start = afterEq.index(after: afterEq.startIndex)
                value = String(afterEq[start..<close]).trimmingCharacters(in: .whitespaces)
            } else if afterEq.hasPrefix("\"") {
                let afterQuote = afterEq.dropFirst()
                if let close = afterQuote.firstIndex(of: "\"") {
                    value = String(afterQuote[..<close]).trimmingCharacters(in: .whitespaces)
                } else {
                    value = afterEq
                }
            } else {
                value = afterEq
            }
            if !fieldName.isEmpty && !value.isEmpty {
                fields[fieldName.lowercased()] = value
            }
        }
        return fields
    }

    private func detectDuplicateKeys() {
        let allKeys = entries.map(\.key)
        var seen: Set<String> = []
        var dupes: Set<String> = []
        for k in allKeys {
            if seen.contains(k) { dupes.insert(k) } else { seen.insert(k) }
        }
        duplicateKeys = Array(dupes)
    }
}
