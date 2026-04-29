import Foundation
import FloatingMacroCore

/// Watches the presets directory for filesystem changes and invokes a
/// callback so the UI can re-scan. Uses `DispatchSourceFileSystemObject`
/// on the directory file descriptor; any add / remove / rename inside
/// the directory triggers `.write`, which is enough for a coarse re-scan.
///
/// We deliberately don't try to identify which file changed — the
/// `PresetManager.refreshPresetEntries()` call is cheap enough for the
/// expected preset count.
final class PresetDirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        stop()
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            LoggerContext.shared.error("PresetWatcher",
                "open() failed", ["path": path, "errno": String(errno)])
            return
        }
        fileDescriptor = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        // Coalesce bursts: when a file is dropped in via Finder we may get
        // several events back to back; debounce so we re-scan once.
        var pending = false
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if pending { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                pending = false
                self?.onChange()
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        source = src
        LoggerContext.shared.info("PresetWatcher", "Started", ["path": path])
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}
