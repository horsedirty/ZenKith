import SwiftUI

struct BibEntryRow: View {
    let entry: BibEntry
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(entry.key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                Spacer()
                Text(entry.type)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .tertiarySystemFill))
                    .cornerRadius(3)
            }
            Text(entry.title)
                .font(.system(size: 11))
                .lineLimit(2)
                .foregroundColor(.primary)
            HStack(spacing: 4) {
                Text(entry.author)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !entry.year.isEmpty {
                    Text("(\(entry.year))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if !entry.journal.isEmpty {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Text(entry.journal)
                        .font(.system(size: 10, design: .serif).italic())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onSelect(entry.key) }
    }
}

struct BibManagerView: View {
    @ObservedObject var bibManager: BibManager
    var onSelectCiteKey: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索参考文献...", text: $bibManager.searchQuery)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !bibManager.searchQuery.isEmpty {
                    Button(action: { bibManager.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            .padding(6).background(Color(nsColor: .controlBackgroundColor))
            Divider()

            if bibManager.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed").font(.system(size: 24)).foregroundColor(.secondary)
                    Text("未找到参考文献").font(.system(size: 11)).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(bibManager.filteredEntries) { entry in
                    BibEntryRow(entry: entry, onSelect: onSelectCiteKey)
                }
                .listStyle(.plain)
            }

            if !bibManager.duplicateKeys.isEmpty {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundColor(.orange)
                    Text("重复键: \(bibManager.duplicateKeys.joined(separator: ", "))").font(.system(size: 9)).foregroundColor(.orange).lineLimit(2)
                }.padding(6)
            }
        }
    }
}
