import SwiftUI
import AppKit

/// NSSplitView 的 SwiftUI 桥接，支持左右两端内容、可拖拽分割线
struct SplitHSView<Leading: View, Trailing: View>: NSViewRepresentable {
    let leading: Leading
    let trailing: Trailing

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let leadingHost = NSHostingView(rootView: AnyView(leading))
        let trailingHost = NSHostingView(rootView: AnyView(trailing))

        leadingHost.translatesAutoresizingMaskIntoConstraints = true
        trailingHost.translatesAutoresizingMaskIntoConstraints = true

        splitView.addArrangedSubview(leadingHost)
        splitView.addArrangedSubview(trailingHost)

        // 默认 50/50 分割
        let halfWidth = splitView.bounds.width / 2
        if halfWidth > 0 {
            splitView.setPosition(halfWidth, ofDividerAt: 0)
        } else {
            splitView.setPosition(400, ofDividerAt: 0)
        }

        context.coordinator.leadingHost = leadingHost
        context.coordinator.trailingHost = trailingHost

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        if let leadingHost = context.coordinator.leadingHost {
            leadingHost.rootView = AnyView(leading)
        }
        if let trailingHost = context.coordinator.trailingHost {
            trailingHost.rootView = AnyView(trailing)
        }
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        weak var leadingHost: NSHostingView<AnyView>?
        weak var trailingHost: NSHostingView<AnyView>?

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 260
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.frame.width - 260
        }
    }
}
