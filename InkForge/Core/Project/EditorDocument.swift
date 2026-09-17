import Foundation

/// The file currently loaded in the editor and what we know about its state on disk.
struct EditorDocument: Equatable {
    let url: URL
    var text: String
    /// Content as last read from or written to disk. `text != savedText` means unsaved edits.
    var savedText: String
    /// Modification date observed when `savedText` was read/written; used to tell our own
    /// writes apart from external ones when the file watcher fires.
    var knownModificationDate: Date?
    /// Bumped whenever `text` is replaced from outside the editor so the text view knows to reload.
    var reloadToken: Int = 0

    var isDirty: Bool { text != savedText }
}

enum FileConflict: Equatable {
    /// The file changed on disk while there were unsaved edits in the editor.
    case modifiedOnDisk(diskText: String, modificationDate: Date?)
    /// The file disappeared from disk.
    case deletedOnDisk
}
