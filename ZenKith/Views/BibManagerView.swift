import SwiftUI

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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.key).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.accentColor)
                        Text(entry.title).font(.system(size: 11)).lineLimit(2)
                        HStack {
                            Text(entry.author).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                            if !entry.year.isEmpty {
                                Text("(\(entry.year))").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(entry.type).font(.system(size: 9)).foregroundColor(.secondary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(3)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onSelectCiteKey(entry.key) }
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
