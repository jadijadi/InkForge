import SwiftUI
import AppKit

/// Lazy filesystem tree backed by NSOutlineView. Expansion state is autosaved per root.
struct FileOutlineView: NSViewRepresentable {
    let rootURL: URL
    /// A location to expand to and select (project folder or current file), when it changes.
    let revealURL: URL?
    /// Bumped when the tree should be re-read from disk.
    let treeVersion: Int
    let onSelect: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.floatsGroupRows = false
        outline.indentationPerLevel = 12
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = true
        outline.usesAutomaticRowHeights = false
        outline.rowHeight = 22
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.menu = context.coordinator.makeContextMenu()

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.outline = outline
        context.coordinator.setRoot(rootURL)
        context.coordinator.reveal(revealURL)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        if coordinator.root?.url != rootURL.standardizedFileURL {
            coordinator.setRoot(rootURL)
        } else if coordinator.treeVersion != treeVersion {
            coordinator.refresh()
        }
        coordinator.treeVersion = treeVersion
        if coordinator.lastRevealed != revealURL {
            coordinator.lastRevealed = revealURL
            coordinator.reveal(revealURL)
        }
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var onSelect: (URL) -> Void
        weak var outline: NSOutlineView?
        private(set) var root: FileNode?
        var treeVersion = 0
        var lastRevealed: URL?
        private var isProgrammaticSelection = false

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func setRoot(_ url: URL) {
            root = FileTree.root(url)
            outline?.autosaveExpandedItems = false
            outline?.autosaveName = "InkForge.FileBrowser." + url.standardizedFileURL.path
            outline?.autosaveExpandedItems = true
            outline?.reloadData()
        }

        /// Re-reads listings while keeping expansion and selection.
        func refresh() {
            guard let outline, let root else { return }
            let selected = (outline.item(atRow: outline.selectedRow) as? FileNode)?.url
            let expanded = expandedURLs(under: root)
            root.invalidate(recursively: true)
            outline.reloadData()
            for url in expanded {
                if let node = root.descendant(at: url) { outline.expandItem(node) }
            }
            if let selected, let node = root.descendant(at: selected) {
                selectSilently(node)
            }
        }

        private func expandedURLs(under node: FileNode) -> [URL] {
            guard let outline, node.hasLoadedChildren else { return [] }
            var result: [URL] = []
            for child in node.children where child.isDirectory && outline.isItemExpanded(child) {
                result.append(child.url)
                result.append(contentsOf: expandedURLs(under: child))
            }
            return result
        }

        func reveal(_ url: URL?) {
            guard let url, let outline, let root else { return }
            let target = url.standardizedFileURL
            guard target.path.hasPrefix(root.url.path == "/" ? "/" : root.url.path + "/") else { return }
            // Expand every ancestor between the root and the target.
            var ancestors: [URL] = []
            var cursor = target.deletingLastPathComponent()
            while cursor.path.count > root.url.path.count {
                ancestors.append(cursor)
                cursor = cursor.deletingLastPathComponent()
            }
            for ancestor in ancestors.reversed() {
                if let node = root.descendant(at: ancestor) { outline.expandItem(node) }
            }
            if let node = root.descendant(at: target) {
                selectSilently(node)
                outline.scrollRowToVisible(outline.row(forItem: node))
            }
        }

        private func selectSilently(_ node: FileNode) {
            guard let outline else { return }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return }
            isProgrammaticSelection = true
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isProgrammaticSelection = false
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            ((item as? FileNode) ?? root)?.children.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? FileNode) ?? root)!.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.isDirectory ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
            (item as? FileNode)?.url.path
        }

        func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
            guard let path = object as? String else { return nil }
            return root?.descendant(at: URL(fileURLWithPath: path))
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("FileCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView) ?? Self.makeCell(identifier)
            cell.textField?.stringValue = node.name
            cell.imageView?.image = NSImage(systemSymbolName: Self.symbol(for: node), accessibilityDescription: nil)
            cell.imageView?.contentTintColor = node.isDirectory ? .controlAccentColor : (node.isMarkdown ? .labelColor : .secondaryLabelColor)
            return cell
        }

        private static func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
            text.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(image)
            cell.addSubview(text)
            cell.imageView = image
            cell.textField = text
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private static func symbol(for node: FileNode) -> String {
            if node.isDirectory { return "folder" }
            if node.isMarkdown { return "doc.text" }
            if node.isImage { return "photo" }
            switch node.url.pathExtension.lowercased() {
            case "epub": return "book.closed"
            case "json", "yaml", "yml", "toml": return "curlybraces"
            default: return "doc"
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isProgrammaticSelection, let outline,
                  let node = outline.item(atRow: outline.selectedRow) as? FileNode else { return }
            onSelect(node.url)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let outline, let node = outline.item(atRow: outline.clickedRow) as? FileNode, node.isDirectory else { return }
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        }

        // MARK: Context menu

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, let node = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
            func add(_ title: String, _ action: @escaping () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = MenuAction(run: action)
                menu.addItem(item)
            }
            if node.isDirectory {
                add("Go Here in Terminal") { [weak self] in self?.onSelect(node.url) }
            } else {
                add("Open with Default App") { NSWorkspace.shared.open(node.url) }
            }
            add("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            menu.addItem(.separator())
            add("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }

        private final class MenuAction { let run: () -> Void; init(run: @escaping () -> Void) { self.run = run } }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuAction)?.run()
        }
    }
}
