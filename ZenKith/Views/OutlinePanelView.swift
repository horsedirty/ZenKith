import SwiftUI

struct OutlinePanelView: NSViewRepresentable {
    var items: [OutlineItem]
    var onSelectLine: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.indentationPerLevel = 12
        outlineView.rowSizeStyle = .small

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        col.width = 200
        col.resizingMask = .autoresizingMask
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        context.coordinator.outlineView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.items = items
        (scrollView.documentView as? NSOutlineView)?.reloadData()
        guard let ov = scrollView.documentView as? NSOutlineView else { return }
        ov.expandItem(nil, expandChildren: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectLine: onSelectLine)
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var items: [OutlineItem] = []
        var onSelectLine: (Int) -> Void
        weak var outlineView: NSOutlineView?

        init(onSelectLine: @escaping (Int) -> Void) {
            self.onSelectLine = onSelectLine
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? OutlineItem else { return items.count }
            return item.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? OutlineItem else { return items[index] }
            return item.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            return !item.children.isEmpty
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? OutlineItem else { return nil }
            let id = NSUserInterfaceItemIdentifier("OutlineCell")
            let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? NSTextField()
            cell.identifier = id
            cell.isBordered = false
            cell.drawsBackground = false
            cell.isEditable = false
            cell.font = .systemFont(ofSize: 12)
            cell.lineBreakMode = .byTruncatingTail
            cell.stringValue = item.title
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let ov = outlineView,
                  let item = ov.item(atRow: ov.selectedRow) as? OutlineItem else { return }
            onSelectLine(item.lineNumber)
        }
    }
}
