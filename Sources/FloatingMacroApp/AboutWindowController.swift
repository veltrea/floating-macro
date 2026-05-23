import AppKit
import SwiftUI

final class AboutWindowController: NSWindowController {

    static let shared = AboutWindowController()

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: AboutView())
            let w = SettingsWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = L("FloatingMacro_About")
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false
            w.center()
            self.window = w
        }

        let win = window
        DispatchQueue.main.async {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            win?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct AboutView: View {
    private let version: String = {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }()

    private let minimumOS: String = {
        Bundle.main.infoDictionary?["LSMinimumSystemVersion"] as? String ?? "13.0"
    }()

    private let commitLabel: String = {
        let hash = BuildInfo.gitHash
        let dirty = BuildInfo.gitDirty ? "+" : ""
        return "\(hash)\(dirty)"
    }()

    private let sourceLabel: String = {
        let path = BuildInfo.sourceDir
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }()

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("FloatingMacro")
                .font(.title2.bold())

            Text("Version \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("macOS \(minimumOS)+")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("Build")
                        .foregroundStyle(.tertiary)
                    Text(commitLabel)
                        .monospaced()
                    Text("(\(BuildInfo.gitBranch))")
                        .foregroundStyle(.tertiary)
                }
                Text(BuildInfo.buildDate)
                    .foregroundStyle(.tertiary)
                Text(sourceLabel)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .font(.caption2)

            Text("© 2025 veltrea")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
