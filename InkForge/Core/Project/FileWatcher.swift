import Foundation
import CoreServices

/// Recursive directory watcher built on FSEvents.
///
/// FSEvents (rather than a kqueue on a single file) is used deliberately: agents such as
/// Claude Code frequently write via temp-file-and-rename, which changes the inode of the
/// watched file and silently breaks per-file descriptors. Watching the project root
/// catches renames, new chapters and deletions alike.
final class FileWatcher {
    typealias Handler = (_ changedPaths: [String]) -> Void

    private let directory: URL
    private let latency: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "dev.jadi.InkForge.FileWatcher")
    private var stream: FSEventStreamRef?

    init(directory: URL, latency: TimeInterval = 0.15, handler: @escaping Handler) {
        self.directory = directory
        self.latency = latency
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            watcher.handler(Array(paths.prefix(numEvents)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                               [directory.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
