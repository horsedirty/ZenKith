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

    func loadBibContent(_ content: String) {
        entries = parseBibtex(content)
        detectDuplicateKeys()
    }

    private func parseBibtex(_ content: String) -> [BibEntry] {
        var entries: [BibEntry] = []
        let text = content as NSString
        var searchRange = NSRange(location: 0, length: text.length)
        guard let atRegex = try? NSRegularExpression(pattern: "@(\\w+)\\s*\\{\\s*") else { return entries }

        while true {
            guard
                  let atMatch = atRegex.firstMatch(in: content, options: [], range: searchRange),
                  atMatch.numberOfRanges >= 2,
                  let typeRange = Range(atMatch.range(at: 1), in: content) else { break }

            let type = String(content[typeRange])

            let afterBrace = atMatch.range(at: 0).location + atMatch.range(at: 0).length
            guard afterBrace < text.length else { break }

            let remaining = text.substring(from: afterBrace)
            guard let firstComma = remaining.firstIndex(of: ",") else { break }

            let key = String(remaining[..<firstComma]).trimmingCharacters(in: .whitespaces)

            let fieldsStart = afterBrace + remaining.distance(from: remaining.startIndex, to: remaining.index(after: firstComma))
            guard fieldsStart < text.length else { break }

            let fieldsString = text.substring(from: fieldsStart)
            guard let closingBrace = findMatchingBrace(in: fieldsString, startOffset: 0) else { break }

            let fieldsContent = (fieldsString as NSString).substring(to: closingBrace)
            let fields = parseFields(fieldsContent)

            entries.append(BibEntry(
                key: key, type: type,
                author: fields["author"] ?? "",
                title: fields["title"] ?? "",
                journal: fields["journal"] ?? fields["booktitle"] ?? "",
                year: fields["year"] ?? ""
            ))

            let matchEnd = fieldsStart + closingBrace + 1
            searchRange = NSRange(location: matchEnd, length: text.length - matchEnd)
            if searchRange.length <= 0 { break }
        }
        return entries
    }

    private func findMatchingBrace(in text: String, startOffset: Int) -> Int? {
        var depth = 0
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if i < startOffset { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                if depth == 0 { return i }
                depth -= 1
            }
        }
        return nil
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
