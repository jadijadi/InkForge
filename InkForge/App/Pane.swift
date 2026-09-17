import Foundation

enum Pane: Int, CaseIterable {
    case terminal = 1, editor, preview

    var title: String {
        switch self {
        case .terminal: "Agent Terminal"
        case .editor: "Editor"
        case .preview: "Preview"
        }
    }
}

extension Notification.Name {
    /// Posted with a `Pane` as the object to move keyboard focus into that pane.
    static let inkForgeFocusPane = Notification.Name("dev.jadi.InkForge.focusPane")
}
