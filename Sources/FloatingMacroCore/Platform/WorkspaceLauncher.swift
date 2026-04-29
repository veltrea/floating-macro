import AppKit

public protocol WorkspaceLauncherProtocol {
    func open(url: URL) throws
    func openApplication(bundleIdentifier: String) throws
}

public final class SystemWorkspaceLauncher: WorkspaceLauncherProtocol {
    public static let shared = SystemWorkspaceLauncher()

    private var workspace: NSWorkspace { NSWorkspace.shared }

    public func open(url: URL) throws {
        if !workspace.open(url) {
            if url.isFileURL {
                throw ActionError.launchTargetNotFound(url.path)
            } else {
                throw ActionError.urlSchemeUnhandled(url.absoluteString)
            }
        }
    }

    public func openApplication(bundleIdentifier: String) throws {
        let config = NSWorkspace.OpenConfiguration()
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?

        workspace.openApplication(
            at: workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
                ?? URL(fileURLWithPath: "/dev/null"),
            configuration: config
        ) { _, error in
            launchError = error
            semaphore.signal()
        }

        semaphore.wait()
        if launchError != nil {
            throw ActionError.launchTargetNotFound(bundleIdentifier)
        }
    }
}
