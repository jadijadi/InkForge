import SwiftUI
import AppKit

/// Terminal | Editor | Preview in an NSSplitViewController.
/// AppKit is used here for real draggable dividers with autosaved pane sizes.
struct ThreePaneSplitView: NSViewControllerRepresentable {
    @EnvironmentObject private var app: AppState
    let isPreviewVisible: Bool

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.splitView.autosaveName = "InkForge.MainSplitView"

        let terminal = NSSplitViewItem(viewController: host(TerminalPane(terminal: app.terminal)))
        terminal.minimumThickness = 280
        terminal.holdingPriority = .defaultLow + 2
        terminal.canCollapse = false

        let editor = NSSplitViewItem(viewController: host(EditorPane()))
        editor.minimumThickness = 320
        editor.holdingPriority = .defaultLow

        let preview = NSSplitViewItem(viewController: host(PreviewPane()))
        preview.minimumThickness = 280
        preview.holdingPriority = .defaultLow + 1
        preview.canCollapse = true
        preview.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        preview.isCollapsed = !isPreviewVisible

        controller.addSplitViewItem(terminal)
        controller.addSplitViewItem(editor)
        controller.addSplitViewItem(preview)
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        guard let preview = controller.splitViewItems.last else { return }
        if preview.isCollapsed == isPreviewVisible {
            preview.animator().isCollapsed = !isPreviewVisible
        }
    }

    private func host<V: View>(_ view: V) -> NSViewController {
        let controller = NSHostingController(rootView: view.environmentObject(app))
        controller.sizingOptions = []
        return controller
    }
}
