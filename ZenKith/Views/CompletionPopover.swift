import SwiftUI
import AppKit

// MARK: - Completion Popover (NSPanel-based)

final class CompletionPopover {

    private let panel: NSPanel
    private let hostingController: NSHostingController<CompletionListView>
    private let engine: LatexCompletionEngine

    init(engine: LatexCompletionEngine) {
        self.engine = engine

        let listView = CompletionListView(engine: engine)

        hostingController = NSHostingController(rootView: listView)
        hostingController.sizingOptions = [.preferredContentSize]
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.contentView = hostingController.view
    }

    func show(near rect: NSRect, in textView: NSTextView) {
        guard let window = textView.window else { return }
        let screenRect = window.convertToScreen(rect)

        let size = hostingController.view.fittingSize
        let panelWidth = max(240, size.width)
        let panelHeight = min(340, max(40, size.height))
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        let originX = screenRect.minX
        // setFrameTopLeftPoint 设置面板顶边在屏幕坐标中的位置（Y 轴向上）。
        // screenRect.minY 是字符矩形的底边，面板顶边紧贴其下方 4pt。
        let originY = screenRect.minY - 4
        panel.setFrameTopLeftPoint(NSPoint(x: originX, y: originY))
        panel.orderFront(nil)

        window.addChildWindow(panel, ordered: .above)
    }

    func hide() {
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        hostingController.view.frame = .zero
    }

    func updateSize() {
        let size = hostingController.view.fittingSize
        let newSize = NSSize(width: max(240, size.width), height: min(340, max(40, size.height)))
        panel.setContentSize(newSize)
    }
}

// MARK: - SwiftUI Completion List View

struct CompletionListView: View {
    @ObservedObject var engine: LatexCompletionEngine

    var body: some View {
        let items = engine.suggestions
        let dark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark

        Group {
            if items.isEmpty {
                emptyView
            } else {
                ScrollViewReader { proxy in
                    List(items) { item in
                        CompletionRow(
                            item: item,
                            isSelected: item == engine.selectedItem,
                            dark: dark
                        )
                        .id(item.id)
                        .onTapGesture {
                            engine.state = .navigating(
                                prefix: engine.state.prefix ?? "",
                                range: engine.state.range ?? NSRange(location: 0, length: 0),
                                selectedIndex: items.firstIndex(of: item) ?? 0
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: engine.selectedItem?.id) { _ in
                        if let id = engine.selectedItem?.id {
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    .frame(minHeight: 80)
                }
            }
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
        .background(
            VisualEffectView(material: .menu, blendingMode: .behindWindow)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(separatorColor(dark), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(dark ? 0.3 : 0.1), radius: 8, x: 0, y: 2)
    }

    private var emptyView: some View {
        Text("无匹配命令")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private func separatorColor(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
}

// MARK: - Completion Row

private struct CompletionRow: View {
    let item: LatexCompletion
    let isSelected: Bool
    let dark: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(item.category.rawValue)
                .font(.system(size: 9))
                .foregroundColor(categoryColor(item.category))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(categoryColor(item.category).opacity(0.12))
                )

            Text(item.displayName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(dark ? .white : .primary)

            Spacer()

            Text(item.detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected
                    ? (dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    : Color.clear)
        )
    }

    private func categoryColor(_ cat: LatexCompletion.Category) -> Color {
        switch cat {
        case .documentStructure: return .orange
        case .section:          return .blue
        case .textFormatting:   return .green
        case .mathSymbol:       return .purple
        case .mathFunction:     return .pink
        case .environment:      return .teal
        case .reference:        return .indigo
        case .package:          return .brown
        case .other:            return .secondary
        }
    }
}

// MARK: - Visual Effect View (NSVisualEffectView bridge)

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
